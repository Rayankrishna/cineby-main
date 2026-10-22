import 'dart:async';
import 'dart:convert';
import 'dart:ui' show lerpDouble;

import 'package:app_web_ui/services/pages/embed_frame.dart';
import 'package:app_web_ui/services/pages/webview.dart';
import 'package:app_web_ui/services/server_vote_service.dart';
import 'package:app_web_ui/services/stream_servers.dart';
import 'package:app_web_ui/services/web_subtitles.dart';
import 'package:app_web_ui/stores/history_store.dart';
import 'package:flutter/material.dart';

const _accent = Color(0xFFEF0003);

/// The web build's player — [MyWidget] uses this state when running in a
/// browser. Browsers can't run the Android headless extractor (no request
/// interception, and CORS blocks reading the embed pages), so the provider's
/// own player plays in an iframe.
///
/// With the ad shield on and a provider whose player we know (111Movies), the
/// iframe is covered by our own controls:
/// * seek and ±10s are sent to the player as postMessage commands;
/// * play/pause and volume can't be commanded, so the shield has holes over
///   the provider's own buttons and our icons are drawn on top: the click
///   lands on the real button underneath;
/// * subtitles come from OpenSubtitles (through the backend) and are drawn
///   by us, timed from the player's progress events.
class WebPlayerState extends State<MyWidget> {
  StreamServer? _server;

  StreamSubscription<Object?>? _messages;
  Timer? _elapsedTimer;

  DateTime _lastSavedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastSavedSeconds = -1;
  DateTime _watchStart = DateTime.now();
  int _elapsedBaseline = 0;
  bool _gotPlayerEvent = false;
  int? _knownDuration;
  // Server we already sent a success vote for, so we vote once per source.
  String? _votedFor;

  // Ad shield: blocks clicks into the embed so its ads can't open tabs.
  bool _shield = true;
  bool _fullscreen = false;
  StreamSubscription<Object?>? _fullscreenSub;
  StreamSubscription<Object?>? _frameFocusSub;

  final EmbedFrameController _frame = EmbedFrameController();

  // Playback clock, rebuilt from the player's progress events (about one a
  // second) and advanced locally in between.
  bool _playing = false;
  double _baseTime = 0;
  DateTime _baseAt = DateTime.now();
  double? _duration;
  bool _resumeSent = false;
  Timer? _tick;
  // No player event for a while after loading: the provider is erroring or
  // stuck (its own error dialog can't be clicked through the shield).
  bool _stalled = false;
  Timer? _stallTimer;
  int _reloads = 0;
  bool _eventSinceLoad = false;
  // While dragging the seek bar.
  double? _scrubTo;

  bool _controlsVisible = true;
  Timer? _hideTimer;
  Offset? _pointer;
  _ProviderLayout? _layout;

  // Subtitles.
  bool _subsOpen = false;
  bool _subsLoading = false;
  String? _subsError;
  List<WebSubtitleTrack>? _tracks;
  WebSubtitleTrack? _track;
  List<SubtitleCue> _cues = const [];
  double _subOffset = 0;

  bool get _hasTitle => widget.tmdbId != null && widget.mediaType != null;

  @override
  void initState() {
    super.initState();
    _elapsedBaseline = widget.initialProgressSeconds;
    _knownDuration = widget.durationSeconds;
    _duration = widget.durationSeconds?.toDouble();
    _baseTime = widget.initialProgressSeconds.toDouble();
    _messages = listenToWindowMessages(_onMessage);
    _fullscreenSub = listenToFullscreenChange(() {
      if (mounted) setState(() => _fullscreen = appIsFullscreen());
    });
    // A click went through a hole onto the player's own button.
    _frameFocusSub = listenToFrameFocus(_poke);
    // Fallback progress saving for providers that don't post player events.
    _elapsedTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _saveElapsed(),
    );
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && _playing) setState(() {});
    });
    _pickInitialServer();
    _poke();
  }

  /// Start on the globally best-voted source for this title, falling back to
  /// the first configured one.
  Future<void> _pickInitialServer() async {
    var server = widget.url == null ? null : streamServerForUrl(widget.url!);
    if (server == null && _hasTitle) {
      final best = await ServerVoteService.instance.bestServerName(
        tmdbId: widget.tmdbId!,
        mediaType: widget.mediaType!,
      );
      server = streamServers.where((s) => s.name == best).firstOrNull;
    }
    if (!mounted) return;
    setState(() => _server = server ?? streamServers.first);
    _watchForStall();
  }

  void _watchForStall() {
    _stallTimer?.cancel();
    _stalled = false;
    _eventSinceLoad = false;
    _stallTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && !_eventSinceLoad) setState(() => _stalled = true);
    });
  }

  /// Reloads the current source from scratch.
  void _reload() {
    setState(() {
      _reloads++;
      _playing = false;
      _resumeSent = false;
    });
    _watchForStall();
  }

  void _nextSource() {
    final i = streamServers.indexOf(_server!);
    _switchServer(streamServers[(i + 1) % streamServers.length]);
  }

  String? get _embedUrl {
    final server = _server;
    if (server == null) return null;
    if (!_hasTitle) return widget.url;
    return server.buildUrl(
      widget.tmdbId!,
      widget.mediaType!,
      widget.seasonNumber,
      widget.episodeNumber,
    );
  }

  void _switchServer(StreamServer server) {
    if (server == _server) return;
    _saveElapsed();
    setState(() {
      _server = server;
      // The new source starts from scratch, so restart the elapsed-time
      // fallback from wherever we last got to.
      _gotPlayerEvent = false;
      _watchStart = DateTime.now();
      if (_lastSavedSeconds > _elapsedBaseline) {
        _elapsedBaseline = _lastSavedSeconds;
      }
      _playing = false;
      _resumeSent = false;
      _baseTime = _elapsedBaseline.toDouble();
      _baseAt = DateTime.now();
    });
    _watchForStall();
  }

  @override
  void dispose() {
    _messages?.cancel();
    _elapsedTimer?.cancel();
    _fullscreenSub?.cancel();
    _frameFocusSub?.cancel();
    _tick?.cancel();
    _hideTimer?.cancel();
    _stallTimer?.cancel();
    exitAppFullscreen();
    // Final save when the user closes the player.
    _saveElapsed();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Player events

  // Embeds post progress either flat ({timestamp, duration}) or wrapped as
  // {type: 'PLAYER_EVENT', data: {event, currentTime, duration, ...}},
  // sometimes as a JSON string.
  void _onMessage(Object? raw) {
    var data = raw;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        return;
      }
    }
    if (data is! Map) return;
    final inner = data['data'];
    final payload = inner is Map ? inner : data;
    // Ignore events that name a different title (e.g. a stale iframe).
    final eventTmdbId = payload['tmdbId'];
    if (eventTmdbId is num && eventTmdbId.toInt() != widget.tmdbId) return;
    final timestamp =
        (payload['timestamp'] ?? payload['currentTime']) as Object?;
    if (timestamp is! num) return;
    final duration = payload['duration'];
    _updateClock(
      payload['event'] as Object?,
      timestamp.toDouble(),
      duration is num ? duration.toDouble() : null,
    );
    _handleProgress(
      timestamp.round(),
      duration is num ? duration.round() : null,
      season: payload['season'],
      episode: payload['episode'],
    );
  }

  void _updateClock(Object? event, double time, double? duration) {
    if (!mounted) return;
    _eventSinceLoad = true;
    if (_stalled) _stalled = false;
    final wasPlaying = _playing;
    setState(() {
      switch (event) {
        case 'play':
        case 'playing':
        case 'timeupdate':
          _playing = true;
        case 'pause':
        case 'ended':
          _playing = false;
      }
      // A 'play' event reports where playback was, not where it is now.
      if (event != 'play') {
        _baseTime = time;
        _baseAt = DateTime.now();
      }
      if (duration != null && duration > 0) _duration = duration;
    });
    if (wasPlaying != _playing) _poke();
    _maybeResume(time);
  }

  /// Pick up where the user left off, once the player has started.
  void _maybeResume(double time) {
    if (_resumeSent || !_supportsCommands) return;
    final duration = _duration;
    if (duration == null || duration <= 0) return;
    _resumeSent = true;
    final target = widget.initialProgressSeconds;
    if (target < 30 || target > duration - 60 || (time - target).abs() < 15) {
      return;
    }
    _seekTo(target.toDouble());
  }

  double get _now {
    var t = _baseTime;
    if (_playing) {
      t += DateTime.now().difference(_baseAt).inMilliseconds / 1000;
    }
    final d = _duration;
    if (d != null && t > d) t = d;
    return t < 0 ? 0 : t;
  }

  /// Whether the current provider takes postMessage seek commands and has a
  /// control layout we can line our buttons up with.
  bool get _supportsCommands => _server?.name == '111Movies';

  void _seekTo(double seconds) {
    final d = _duration;
    var t = seconds < 0 ? 0.0 : seconds;
    if (d != null && t > d - 1) t = d - 1;
    _frame.post({'type': 'seek', 'time': t});
    setState(() {
      _baseTime = t;
      _baseAt = DateTime.now();
    });
    _poke();
  }

  // Save progress at most every 10s OR when the playback position jumps >15s.
  void _handleProgress(
    int timestamp,
    int? duration, {
    Object? season,
    Object? episode,
  }) {
    if (!_hasTitle) return;
    _gotPlayerEvent = true;
    if (duration != null && duration > 0) _knownDuration = duration;
    _voteForCurrentServer(timestamp);

    final now = DateTime.now();
    final timeDelta = now.difference(_lastSavedAt).inSeconds;
    final seekDelta = (_lastSavedSeconds - timestamp).abs();
    if (timeDelta < 10 && seekDelta < 15) return;

    _lastSavedAt = now;
    _lastSavedSeconds = timestamp;

    final isTv = widget.mediaType == 'tv';
    historyStore.record(
      tmdbId: widget.tmdbId!,
      mediaType: widget.mediaType!,
      seasonNumber:
          isTv ? (season is num ? season.toInt() : widget.seasonNumber) : null,
      episodeNumber:
          isTv
              ? (episode is num ? episode.toInt() : widget.episodeNumber)
              : null,
      progressSeconds: timestamp,
      durationSeconds: _knownDuration,
      title: widget.title,
      posterPath: widget.posterPath,
      backdropPath: widget.backdropPath,
    );
  }

  /// A source that reports real playback is working — count it so it becomes
  /// the default for the next viewer of this title.
  void _voteForCurrentServer(int timestamp) {
    final server = _server;
    if (server == null || timestamp <= 0 || _votedFor == server.name) return;
    _votedFor = server.name;
    ServerVoteService.instance.recordSuccess(
      tmdbId: widget.tmdbId!,
      mediaType: widget.mediaType!,
      serverName: server.name,
    );
  }

  void _saveElapsed() {
    // Skip if the player already reported real progress.
    if (_gotPlayerEvent || !_hasTitle) return;
    // 111Movies always reports progress, so silence means it isn't playing;
    // counting wall-clock time would push the resume point forward.
    if (_supportsCommands) return;

    final elapsedSecs = DateTime.now().difference(_watchStart).inSeconds;
    final progress = _elapsedBaseline + elapsedSecs;
    if (progress <= _lastSavedSeconds) return;

    _lastSavedAt = DateTime.now();
    _lastSavedSeconds = progress;

    historyStore.record(
      tmdbId: widget.tmdbId!,
      mediaType: widget.mediaType!,
      seasonNumber: widget.seasonNumber,
      episodeNumber: widget.episodeNumber,
      progressSeconds: progress,
      durationSeconds: _knownDuration,
      title: widget.title,
      posterPath: widget.posterPath,
      backdropPath: widget.backdropPath,
    );
  }

  // ---------------------------------------------------------------------------
  // Controls visibility

  /// Shows the controls and restarts the auto-hide timer.
  void _poke() {
    if (!mounted) return;
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), _maybeHide);
  }

  void _maybeHide() {
    if (!mounted || !_playing || _subsOpen || _scrubTo != null) return;
    // The pointer may be inside a hole, where we get no hover events; hiding
    // would close the hole under it.
    final p = _pointer;
    final layout = _layout;
    if (p != null &&
        layout != null &&
        layout.holes.any((h) => h.inflate(24).contains(p))) {
      _poke();
      return;
    }
    setState(() => _controlsVisible = false);
  }

  // ---------------------------------------------------------------------------
  // Subtitles

  Future<void> _toggleSubtitles() async {
    setState(() => _subsOpen = !_subsOpen);
    _poke();
    if (!_subsOpen || _tracks != null || _subsLoading || !_hasTitle) return;
    setState(() {
      _subsLoading = true;
      _subsError = null;
    });
    try {
      final tracks = await WebSubtitles.instance.search(
        tmdbId: widget.tmdbId!,
        mediaType: widget.mediaType!,
        season: widget.seasonNumber,
        episode: widget.episodeNumber,
      );
      if (!mounted) return;
      setState(() => _tracks = tracks);
    } catch (_) {
      if (!mounted) return;
      setState(() => _subsError = 'Couldn\'t load subtitles.');
    } finally {
      if (mounted) setState(() => _subsLoading = false);
    }
  }

  Future<void> _pickTrack(WebSubtitleTrack? track) async {
    if (track == null) {
      setState(() {
        _track = null;
        _cues = const [];
      });
      return;
    }
    setState(() {
      _track = track;
      _subsLoading = true;
      _subsError = null;
    });
    try {
      final cues = await WebSubtitles.instance.cuesFor(track);
      if (!mounted || _track != track) return;
      setState(() {
        _cues = cues;
        _subsOpen = false;
      });
    } catch (e) {
      if (!mounted) return;
      final quota = e.toString().contains('429');
      setState(() {
        _track = null;
        _cues = const [];
        _subsError =
            quota
                ? 'Daily subtitle limit reached. Try again tomorrow.'
                : 'Couldn\'t download that subtitle. Try another.';
      });
    } finally {
      if (mounted) setState(() => _subsLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build

  @override
  Widget build(BuildContext context) {
    final url = _embedUrl;
    if (url == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(color: _accent, strokeWidth: 2.5),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final custom =
              _shield &&
              _supportsCommands &&
              _ProviderLayout.keyFor(size) >= _ProviderLayout.minKey;
          return custom ? _buildCustom(url, size) : _buildPlain(context, url);
        },
      ),
    );
  }

  /// Provider's own player under a plain top bar (other sources, phones, or
  /// ad shield off).
  Widget _buildPlain(BuildContext context, String url) {
    _layout = null;
    return Column(
      children: [
        // Fullscreen is the whole app, so drop the bar; Esc brings it back.
        if (!_fullscreen) _buildTopBar(context),
        Expanded(
          child: EmbedFrame(
            key: ValueKey('$url#$_reloads'),
            url: url,
            shield: _shield,
            controller: _frame,
          ),
        ),
      ],
    );
  }

  Widget _buildCustom(String url, Size size) {
    final layout = _ProviderLayout.forSize(size);
    _layout = layout;
    final visible = _controlsVisible;
    final cue = _cues.isEmpty ? null : cueAt(_cues, _now + _subOffset);
    return MouseRegion(
      cursor: visible ? MouseCursor.defer : SystemMouseCursors.none,
      onHover: (e) {
        _pointer = e.localPosition;
        _poke();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Clicks on the video (not on a control) toggle the controls.
        onTap: () {
          if (_subsOpen) {
            setState(() => _subsOpen = false);
            _poke();
          } else if (_controlsVisible && _playing) {
            _hideTimer?.cancel();
            setState(() => _controlsVisible = false);
          } else {
            _poke();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            EmbedFrame(
              key: ValueKey('$url#$_reloads'),
              url: url,
              shield: true,
              controller: _frame,
              holes: visible ? layout.holes : const [],
            ),
            // Scrim hides the provider's own error dialog behind our card.
            if (_stalled)
              ColoredBox(
                color: const Color(0xF2000000),
                child: Center(child: _buildStallCard()),
              ),
            if (cue != null)
              Positioned(
                left: 24,
                right: 24,
                bottom: visible ? layout.barHeight + 12 : 48,
                child: IgnorePointer(child: _SubtitleText(cue.text)),
              ),
            IgnorePointer(
              ignoring: !visible,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildTopOverlay(),
                    ..._buildBottomOverlay(layout, size),
                    if (_subsOpen) _buildSubtitlePanel(layout),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopOverlay() {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: Container(
        // Tall enough to cover the provider's own title, Sources button and
        // Unmute pill, which it shows while the pointer is in a hole.
        padding: const EdgeInsets.fromLTRB(8, 10, 16, 90),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, 0.78, 1],
            colors: [Color(0xFF000000), Color(0xF2000000), Color(0x00000000)],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 4),
            Flexible(child: _titleText(17)),
            const SizedBox(width: 16),
            if (_hasTitle && streamServers.length > 1)
              Flexible(
                flex: 2,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final s in streamServers) ...[
                        _SourcePill(
                          label: s.name,
                          selected: s == _server,
                          onTap: () => _switchServer(s),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ),
            const Spacer(),
            Tooltip(
              message:
                  'On: clicks can\'t reach the player\'s ads. '
                  'Off: use the player\'s own controls.',
              child: _SourcePill(
                label: 'Ad shield on',
                selected: true,
                onTap: () => setState(() => _shield = false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBottomOverlay(_ProviderLayout l, Size size) {
    final duration = _duration;
    final now = _scrubTo ?? _now;
    final rowCenter = l.rowTop + l.size / 2;
    final backdropTop = size.height - l.barHeight - 40;
    Widget at(Rect r, Widget child) =>
        Positioned.fromRect(rect: r, child: child);
    return [
      // Backdrop. It hides the provider's own bar (shown while the pointer is
      // in a hole), except over its volume slider, which shows through.
      Positioned(
        left: 0,
        right: 0,
        top: backdropTop,
        bottom: 0,
        child: IgnorePointer(
          child: ClipPath(
            clipper: _HoleClipper(l.sliderWindow.translate(0, -backdropTop)),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  // Fully opaque from the seek bar down, so none of the
                  // provider's own bar shows through.
                  stops: [0, 0.3, 0.45, 1],
                  colors: [
                    Color(0x00000000),
                    Color(0xE6000000),
                    Color(0xFF000000),
                    Color(0xFF000000),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      // Seek bar.
      Positioned(
        left: l.left,
        right: l.left,
        top: l.rowTop - 34,
        height: 28,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3.5,
            activeTrackColor: _accent,
            inactiveTrackColor: Colors.white24,
            thumbColor: _accent,
            overlayShape: SliderComponentShape.noOverlay,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
          ),
          child: Slider(
            min: 0,
            max: duration ?? 1,
            value: duration == null ? 0 : now.clamp(0, duration),
            onChanged:
                duration == null
                    ? null
                    : (v) {
                      setState(() => _scrubTo = v);
                      _poke();
                    },
            onChangeEnd:
                duration == null
                    ? null
                    : (v) {
                      setState(() => _scrubTo = null);
                      _seekTo(v);
                    },
          ),
        ),
      ),
      at(
        l.button(0),
        _ControlButton(
          icon: Icons.replay_10_rounded,
          tooltip: 'Back 10 seconds',
          onTap: () => _seekTo(_now - 10),
        ),
      ),
      // Drawn only: clicks here go through the hole to the provider's own
      // play/pause button.
      at(
        l.button(1),
        IgnorePointer(
          child: _ControlButton(
            icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 34,
          ),
        ),
      ),
      at(
        l.button(2),
        _ControlButton(
          icon: Icons.forward_10_rounded,
          tooltip: 'Forward 10 seconds',
          onTap: () => _seekTo(_now + 10),
        ),
      ),
      // Same for the volume button; its slider shows through next to it.
      at(
        l.button(3),
        const IgnorePointer(
          child: _ControlButton(icon: Icons.volume_up_rounded),
        ),
      ),
      Positioned(
        left: l.sliderWindow.right + 14,
        top: rowCenter - 10,
        child: IgnorePointer(
          child: Text(
            '${_formatTime(now)} / '
            '${duration == null ? '--:--' : _formatTime(duration)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
      Positioned(
        right: l.left,
        top: l.rowTop,
        height: l.size,
        child: Row(
          children: [
            SizedBox.square(
              dimension: l.size,
              child: _ControlButton(
                icon:
                    _track != null
                        ? Icons.closed_caption_rounded
                        : Icons.closed_caption_off_outlined,
                tooltip: 'Subtitles',
                highlighted: _track != null,
                onTap: _toggleSubtitles,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox.square(
              dimension: l.size,
              child: _ControlButton(
                icon:
                    _fullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                tooltip: _fullscreen ? 'Exit fullscreen' : 'Fullscreen',
                onTap: () {
                  _fullscreen ? exitAppFullscreen() : requestAppFullscreen();
                  _poke();
                },
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildSubtitlePanel(_ProviderLayout l) {
    final tracks = _tracks;
    const muted = TextStyle(color: Colors.white54, fontSize: 12.5);
    return Positioned(
      right: l.left,
      bottom: l.barHeight + 8,
      width: 340,
      child: Material(
        color: const Color(0xF21F1E26),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Subtitles · English',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (_track != null) ...[
                      _OffsetButton(
                        label: '−0.5s',
                        onTap: () => setState(() => _subOffset -= 0.5),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${_subOffset >= 0 ? '+' : ''}'
                          '${_subOffset.toStringAsFixed(1)}s',
                          textAlign: TextAlign.center,
                          style: muted,
                        ),
                      ),
                      _OffsetButton(
                        label: '+0.5s',
                        onTap: () => setState(() => _subOffset += 0.5),
                      ),
                    ],
                  ],
                ),
              ),
              if (_subsError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    _subsError!,
                    style: const TextStyle(
                      color: Color(0xFFFF8A80),
                      fontSize: 12.5,
                    ),
                  ),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    _TrackTile(
                      title: 'Off',
                      selected: _track == null,
                      onTap: () => _pickTrack(null),
                    ),
                    if (_subsLoading && tracks == null)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: _accent,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      ),
                    if (tracks != null && tracks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Text(
                          'No subtitles found for this title.',
                          style: muted,
                        ),
                      ),
                    for (final t in tracks ?? const <WebSubtitleTrack>[])
                      _TrackTile(
                        title: t.release,
                        subtitle:
                            '${t.downloads} downloads'
                            '${t.hearingImpaired ? ' · SDH' : ''}',
                        selected: _track?.fileId == t.fileId,
                        loading: _subsLoading && _track?.fileId == t.fileId,
                        onTap: () => _pickTrack(t),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStallCard() {
    return Container(
      width: 420,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1E26),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_server?.name ?? 'This source'} isn\'t playing this title',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'It may be unavailable right now. Try again or switch source.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                ),
                onPressed: _reload,
                child: const Text('Try again'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                ),
                onPressed: _nextSource,
                child: const Text('Next source'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _titleText(double fontSize) {
    final episodeLabel =
        widget.mediaType == 'tv' && widget.seasonNumber != null
            ? 'S${widget.seasonNumber} · E${widget.episodeNumber}'
            : null;
    return Text(
      [
        if (widget.title != null) widget.title!,
        if (episodeLabel != null) episodeLabel,
      ].join('  ·  '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final showSources = _hasTitle && streamServers.length > 1;
    const hint = TextStyle(color: Colors.white38, fontSize: 12);
    return Container(
      width: double.infinity,
      color: const Color(0xFF18181A),
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: _titleText(15),
                  ),
                ],
              ),
              if (showSources)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 12, right: 8),
                        child: Text(
                          'Source',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      for (final s in streamServers) ...[
                        _SourcePill(
                          label: s.name,
                          selected: s == _server,
                          onTap: () => _switchServer(s),
                        ),
                        const SizedBox(width: 6),
                      ],
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Text(
                          'Not playing? Try another source.',
                          style: hint,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          // The ad shield gets its own line so the toggle stays put when the
          // hint text changes length.
          Row(
            children: [
              _SourcePill(
                label: _shield ? 'Ad shield on' : 'Ad shield off',
                selected: _shield,
                onTap: () => setState(() => _shield = !_shield),
              ),
              IconButton(
                tooltip: 'Fullscreen',
                icon: const Icon(Icons.fullscreen_rounded, color: Colors.white),
                onPressed: requestAppFullscreen,
              ),
              Expanded(
                child: Text(
                  !_shield
                      ? 'Clicks reach the player, so its ads may open tabs.'
                      : 'Clicks on the video are blocked so ads can\'t open '
                          'tabs. Keys: Space play/pause · ← → seek · M mute. '
                          'Full controls work on 111Movies.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: hint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatTime(double seconds) {
  final s = seconds.floor();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}

/// Where the 111Movies player puts its bottom-left controls. Measured in its
/// own frame at many sizes; the layout scales with the width of the 16:9
/// picture that fits the frame, so we interpolate on that. The buttons are,
/// left to right: back 10s, play/pause, forward 10s, volume, then the volume
/// slider (96x24, 8px right of the volume button, centred 10px lower).
class _ProviderLayout {
  _ProviderLayout._(this.frame, this.size, this.left, this.step, this.rowTop);

  static const _keys = [
    760.0, 800.0, 900.0, 1024.0, 1280.0, 1365.0, 1440.0, //
    1536.0, 1600.0, 1680.0, 1742.0, 1920.0, 2560.0,
  ];
  static const _sizes = [
    37.0, 38.0, 39.0, 40.0, 42.0, 43.0, 44.0, //
    45.0, 45.0, 46.0, 46.0, 48.0, 53.0,
  ];
  static const _lefts = [
    5.0, 6.0, 6.0, 7.0, 9.0, 9.0, 9.0, //
    9.0, 9.0, 9.0, 9.0, 8.0, 7.0,
  ];
  static const _steps = [
    44.0, 45.0, 46.0, 48.0, 51.0, 53.0, 54.0, //
    55.0, 55.0, 56.0, 56.0, 58.0, 63.0,
  ];
  static const _bottomPads = [
    14.0, 15.0, 16.0, 17.0, 19.0, 19.0, 20.0, //
    20.0, 20.0, 20.0, 20.0, 20.0, 20.0,
  ];

  /// Smallest frame we've measured; below it we fall back to the plain
  /// player rather than guess.
  static const minKey = 760.0;

  static double keyFor(Size frame) =>
      frame.width < frame.height * 16 / 9 ? frame.width : frame.height * 16 / 9;

  final Size frame;
  final double size;
  final double left;
  final double step;
  final double rowTop;

  static double _at(List<double> ys, double k) {
    if (k <= _keys.first) return ys.first;
    for (var i = 1; i < _keys.length; i++) {
      if (k <= _keys[i]) {
        final t = (k - _keys[i - 1]) / (_keys[i] - _keys[i - 1]);
        return lerpDouble(ys[i - 1], ys[i], t)!;
      }
    }
    return ys.last;
  }

  factory _ProviderLayout.forSize(Size frame) {
    final k = keyFor(frame);
    final size = _at(_sizes, k);
    return _ProviderLayout._(
      frame,
      size,
      _at(_lefts, k),
      _at(_steps, k),
      frame.height - _at(_bottomPads, k) - size,
    );
  }

  Rect button(int i) => Rect.fromLTWH(left + i * step, rowTop, size, size);

  /// The volume slider, with a little margin.
  Rect get sliderWindow {
    final volume = button(3);
    return Rect.fromCenter(
      center: Offset(volume.right + 8 + 48, volume.center.dy + 10),
      width: 96 + 8,
      height: 24 + 8,
    );
  }

  /// Height of our bottom bar, from the frame's bottom edge.
  double get barHeight => frame.height - rowTop + 44;

  /// Shield cut-outs: play/pause, and the volume button plus its slider.
  List<Rect> get holes => [
    button(1).inflate(2),
    button(3).inflate(2).expandToInclude(sliderWindow),
  ];
}

/// Clips [hole] out of the painted area.
class _HoleClipper extends CustomClipper<Path> {
  _HoleClipper(this.hole);

  final Rect hole;

  @override
  Path getClip(Size size) =>
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(8)));

  @override
  bool shouldReclip(_HoleClipper oldClipper) => oldClipper.hole != hole;
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    this.onTap,
    this.tooltip,
    this.size = 28,
    this.highlighted = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    // Opaque disc so the provider's own icon underneath never shows.
    final button = Material(
      color: Colors.black,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            size: size,
            color: highlighted ? _accent : Colors.white,
          ),
        ),
      ),
    );
    final sized = FittedBox(child: button);
    return tooltip == null ? sized : Tooltip(message: tooltip!, child: sized);
  }
}

class _SubtitleText extends StatelessWidget {
  const _SubtitleText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: (width / 48).clamp(16, 30),
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.loading = false,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child:
                  loading
                      ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          color: _accent,
                          strokeWidth: 2,
                        ),
                      )
                      : selected
                      ? const Icon(
                        Icons.check_rounded,
                        color: _accent,
                        size: 18,
                      )
                      : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11.5,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OffsetButton extends StatelessWidget {
  const _OffsetButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ),
    );
  }
}

class _SourcePill extends StatelessWidget {
  const _SourcePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
