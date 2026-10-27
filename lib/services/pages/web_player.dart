import 'dart:async';
import 'dart:convert';

import 'package:app_web_ui/services/pages/embed_frame.dart';
import 'package:app_web_ui/services/pages/webview.dart';
import 'package:app_web_ui/services/server_vote_service.dart';
import 'package:app_web_ui/services/stream_servers.dart';
import 'package:app_web_ui/services/web_subtitles.dart';
import 'package:app_web_ui/stores/history_store.dart';
import 'package:flutter/material.dart';

const _accent = Color(0xFFEF0003);

/// Sources offered on the web: only those our custom player can drive
/// without a click ever reaching the provider. 111Movies takes seek commands
/// and responds to the keyboard; the others need clicks on their own,
/// ad-laden controls. The mobile app still offers every source.
const _customServers = {'111Movies'};
final List<StreamServer> _webServers =
    streamServers.where((s) => _customServers.contains(s.name)).toList();

/// Height of our bottom control bar.
const double _barHeight = 104;

/// The web build's player — [MyWidget] uses this state when running in a
/// browser. Browsers can't run the Android headless extractor (no request
/// interception, and CORS blocks reading the embed pages), so the provider's
/// own player plays in an iframe.
///
/// With the ad shield on, the iframe is fully covered and no click ever
/// reaches the provider, so its ad scripts never get the click they need to
/// open a tab. Instead:
/// * seek and ±10s are sent to the player as postMessage commands;
/// * play/pause and sound can't be commanded, and a page can't fake key
///   presses into another site's frame, so the player keeps keyboard focus
///   and the user's own Space / M keys drive it (keys don't trigger its ads);
///   our play and volume buttons say which key to press;
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

  // Ad shield: blocks clicks into the embed so its ads can't open tabs. The
  // player is then driven by keys, so it's on wherever there's a keyboard
  // (see [_shieldFor]); there's no toggle.
  bool _shield = true;
  bool _fullscreen = false;
  // The site's own full screen: just the player and an exit button. Mobile
  // web starts in it; on iPhone, which can't fullscreen a page, the
  // fullscreen button uses it too.
  bool _pseudoFullscreen = false;
  bool get _isFullscreen => _fullscreen || _pseudoFullscreen;
  bool get _canFullscreen => appFullscreenSupported || isIPhone;
  StreamSubscription<Object?>? _fullscreenSub;

  final EmbedFrameController _frame = EmbedFrameController();

  // Playback clock, rebuilt from the player's progress events (about one a
  // second) and advanced locally in between.
  bool _playing = false;
  double _baseTime = 0;
  DateTime _baseAt = DateTime.now();
  double? _duration;
  bool _resumeSent = false;
  double _lastReportedTime = -1;
  Object? _lastEvent;
  Timer? _tick;
  // No player event for a while after loading: the provider is erroring or
  // stuck (its own error dialog can't be clicked through the shield).
  bool _stalled = false;
  Timer? _stallTimer;
  int _reloads = 0;
  // Safari watchdog: 111Movies' stream has a stretch near the start that
  // Safari can't decode, and the video just freezes there ("Media failed to
  // decode"; its own player does the same outside our site). When time
  // stops moving while it should be playing, reload and jump past it.
  DateTime _lastProgressAt = DateTime.now();
  double? _recoverTo;
  int _recoverSeeks = 0;
  double? _lastRecoveryAt;
  int _recoveries = 0;
  static const _maxRecoveries = 5;
  bool _eventSinceLoad = false;
  // While dragging the seek bar.
  double? _scrubTo;

  bool _controlsVisible = true;
  Timer? _hideTimer;
  // "Press Space…" hints shown above the bar.
  String? _keyHint;
  Timer? _keyHintTimer;
  bool _soundHintShown = false;

  // Subtitles.
  bool _subsOpen = false;
  bool _serversOpen = false;
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
    _shield = webHasKeyboardPointer;
    // Mobile web opens the player in the site's own full screen (just the
    // player and an exit button), not the system fullscreen.
    _pseudoFullscreen = !webHasKeyboardPointer;
    // Fallback progress saving for providers that don't post player events.
    _elapsedTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _saveElapsed(),
    );
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (_playing) setState(() {});
      _checkFrozen();
    });
    _pickInitialServer();
    _poke();
  }

  /// Start on the globally best-voted source for this title, falling back to
  /// the first configured one.
  Future<void> _pickInitialServer() async {
    var server = widget.url == null ? null : streamServerForUrl(widget.url!);
    if (!_webServers.contains(server)) server = null;
    if (server == null && _hasTitle) {
      // Don't hold the player on a slow backend (cold start): after 1.5s
      // just start on the default source.
      final best = await ServerVoteService.instance
          .bestServerName(tmdbId: widget.tmdbId!, mediaType: widget.mediaType!)
          .timeout(const Duration(milliseconds: 1500), onTimeout: () => null);
      server = _webServers.where((s) => s.name == best).firstOrNull;
    }
    if (!mounted) return;
    setState(() {
      _server = server ?? _webServers.first;
      _shield = _shieldFor(_server!);
    });
    _watchForStall();
  }

  void _watchForStall() {
    _stallTimer?.cancel();
    _stalled = false;
    _eventSinceLoad = false;
    _stallTimer = Timer(const Duration(seconds: 15), () {
      // Only 111Movies autoplays; the others wait for a click.
      if (mounted && !_eventSinceLoad && _supportsCommands) {
        setState(() => _stalled = true);
      }
    });
  }

  /// Reloads the current source from scratch.
  void _checkFrozen() {
    if (!isSafariEngine || !_playing) return;
    if (_recoveries >= _maxRecoveries) return;
    if (DateTime.now().difference(_lastProgressAt).inSeconds < 5) return;
    // Skip 2s past the freeze; further if the same spot froze again.
    final frozeAt = _lastReportedTime < 0 ? 0.0 : _lastReportedTime;
    final again =
        _lastRecoveryAt != null && (frozeAt - _lastRecoveryAt!).abs() < 6;
    final target = frozeAt + (again ? 8 : 2);
    _recoveries++;
    _lastRecoveryAt = target;
    _recoverTo = target;
    _recoverSeeks = 0;
    _lastProgressAt = DateTime.now();
    setState(() {
      _reloads++;
      _playing = false;
      // The recovery seek replaces the usual resume.
      _resumeSent = true;
      _lastReportedTime = -1;
      _lastEvent = null;
    });
    _watchForStall();
  }

  void _reload() {
    setState(() {
      _reloads++;
      _playing = false;
      _resumeSent = false;
    });
    _watchForStall();
  }

  void _nextSource() {
    final i = _webServers.indexOf(_server!);
    _switchServer(_webServers[(i + 1) % _webServers.length]);
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

  /// Our ad-free player is driven by keys, so it needs a keyboard.
  bool _shieldFor(StreamServer server) => webHasKeyboardPointer;

  void _switchServer(StreamServer server) {
    if (server == _server) return;
    _saveElapsed();
    setState(() {
      _server = server;
      _shield = _shieldFor(server);
      _serversOpen = false;
      // The new source starts from scratch, so restart the elapsed-time
      // fallback from wherever we last got to.
      _gotPlayerEvent = false;
      _watchStart = DateTime.now();
      if (_lastSavedSeconds > _elapsedBaseline) {
        _elapsedBaseline = _lastSavedSeconds;
      }
      _playing = false;
      _resumeSent = false;
      _lastReportedTime = -1;
      _lastEvent = null;
      _soundHintShown = false;
      _recoverTo = null;
      _lastRecoveryAt = null;
      _recoveries = 0;
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
    _keyHintTimer?.cancel();
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
    if (timestamp is! num || !timestamp.isFinite) return;
    // Players report NaN/Infinity before the video's metadata has loaded,
    // and round() throws on those.
    final rawDuration = payload['duration'];
    final duration =
        rawDuration is num && rawDuration.isFinite && rawDuration > 0
            ? rawDuration
            : null;
    _updateClock(
      payload['event'] as Object?,
      timestamp.toDouble(),
      duration?.toDouble(),
    );
    _handleProgress(
      timestamp.round(),
      duration?.round(),
      season: payload['season'],
      episode: payload['episode'],
    );
  }

  void _updateClock(Object? event, double time, double? duration) {
    if (!mounted) return;
    _eventSinceLoad = true;
    if (_stalled) _stalled = false;
    if ((event == 'timeupdate' && time > _lastReportedTime) ||
        event == 'seeked' ||
        event == 'play') {
      _lastProgressAt = DateTime.now();
    }
    final wasPlaying = _playing;
    setState(() {
      switch (event) {
        case 'play':
        case 'playing':
          _playing = true;
        // Some players (Vidlink) also send timeupdate while paused, e.g.
        // after a seek; only time moving forward across two updates in a
        // row means it's playing.
        case 'timeupdate':
          if (_lastEvent == 'timeupdate' && time > _lastReportedTime) {
            _playing = true;
          }
        case 'pause':
        case 'ended':
          _playing = false;
      }
      _lastReportedTime = time;
      _lastEvent = event;
      // A 'play' event reports where playback was, not where it is now.
      if (event != 'play') {
        _baseTime = time;
        _baseAt = DateTime.now();
      }
      if (duration != null && duration > 0) _duration = duration;
    });
    if (wasPlaying != _playing) _poke();
    if (_playing && !_soundHintShown && _shield) {
      _soundHintShown = true;
      _showKeyHint('Sound starts off. Press M to turn it on.');
    }
    // After a watchdog reload, jump past the spot that froze. The player
    // also restores its own last position on load, which can land after our
    // seek and put it back on the bad spot, so keep re-sending until it's
    // actually past it.
    final recoverTo = _recoverTo;
    if (recoverTo != null && (event == 'play' || event == 'timeupdate')) {
      if (event == 'timeupdate' && time >= recoverTo - 1) {
        _recoverTo = null;
      } else if (_recoverSeeks < 8) {
        _recoverSeeks++;
        _seekTo(recoverTo);
      } else {
        _recoverTo = null;
      }
    }
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

  /// Providers whose players post progress events once they're playing.
  bool get _reportsProgress =>
      _server?.name == '111Movies' || _server?.name == 'Vidlink';

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
    // These players report progress while playing, so silence means it
    // isn't playing; counting wall-clock time would push the resume point
    // forward.
    if (_reportsProgress) return;

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
    if (!mounted ||
        !_playing ||
        _subsOpen ||
        _serversOpen ||
        _scrubTo != null) {
      return;
    }
    setState(() => _controlsVisible = false);
  }

  void _toggleFullscreen() {
    if (_pseudoFullscreen) {
      setState(() => _pseudoFullscreen = false);
    } else if (appFullscreenSupported) {
      _fullscreen ? exitAppFullscreen() : requestAppFullscreen();
    } else if (isIPhone) {
      setState(() => _pseudoFullscreen = !_pseudoFullscreen);
    }
    _poke();
  }

  void _showKeyHint(String hint) {
    _keyHintTimer?.cancel();
    setState(() => _keyHint = hint);
    _poke();
    _keyHintTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _keyHint = null);
    });
  }

  // ---------------------------------------------------------------------------
  // Subtitles

  Future<void> _toggleSubtitles() async {
    setState(() {
      _subsOpen = !_subsOpen;
      _serversOpen = false;
    });
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
      body:
          _shield && _customServers.contains(_server?.name)
              ? _buildCustom(url)
              : _buildPlain(context, url),
    );
  }

  /// Provider's own player under a plain top bar (other sources, phones, or
  /// ad shield off).
  Widget _buildPlain(BuildContext context, String url) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            // Fullscreen is the whole app, so drop the bar; Esc brings it
            // back. On iPhone only the player is left, plus the ✕ below.
            if (!_isFullscreen) _buildTopBar(context),
            Expanded(
              key: const ValueKey('player'),
              child: EmbedFrame(
                key: ValueKey('$url#$_reloads'),
                url: url,
                shield: _shield,
                controller: _frame,
              ),
            ),
          ],
        ),
        if (_pseudoFullscreen)
          Positioned(
            top: 10,
            left: 10,
            child: TapCatcher(
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Exit full screen',
                  icon: const Icon(
                    Icons.fullscreen_exit_rounded,
                    color: Colors.white,
                  ),
                  onPressed: _toggleFullscreen,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCustom(String url) {
    final visible = _controlsVisible;
    final cue = _cues.isEmpty ? null : cueAt(_cues, _now + _subOffset);
    return MouseRegion(
      cursor: visible ? MouseCursor.defer : SystemMouseCursors.none,
      onHover: (_) => _poke(),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Clicks on the video (not on a control) toggle the controls.
        onTap: () {
          if (_subsOpen || _serversOpen) {
            setState(() {
              _subsOpen = false;
              _serversOpen = false;
            });
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
                bottom: visible ? _barHeight + 12 : 48,
                child: IgnorePointer(child: _SubtitleText(cue.text)),
              ),
            if (_keyHint != null)
              Positioned(
                left: 16,
                bottom: _barHeight + 8,
                child: IgnorePointer(child: _HintPill(_keyHint!)),
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
                    _buildBottomOverlay(),
                    if (_subsOpen) _buildSubtitlePanel(),
                    if (_serversOpen) _buildServerPanel(),
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
        // Unmute pill.
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
            if (_hasTitle && _webServers.length > 1)
              Flexible(
                flex: 2,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final s in _webServers) ...[
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
          ],
        ),
      ),
    );
  }

  Widget _buildBottomOverlay() {
    final duration = _duration;
    final now = _scrubTo ?? _now;
    final wide = MediaQuery.of(context).size.width >= 900;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: _barHeight + 40,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, 0.4, 1],
            colors: [Color(0x00000000), Color(0xD9000000), Color(0xF2000000)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                height: 28,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.5,
                    activeTrackColor: _accent,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: _accent,
                    overlayShape: SliderComponentShape.noOverlay,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6.5,
                    ),
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
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    _ControlButton(
                      icon: Icons.replay_10_rounded,
                      tooltip: 'Back 10 seconds',
                      onTap: () => _seekTo(_now - 10),
                    ),
                    // Play/pause and sound can only be driven by the user's
                    // own keys (see the class comment), so these say which.
                    _ControlButton(
                      icon:
                          _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                      size: 34,
                      keyLabel: 'Space',
                      onTap:
                          () => _showKeyHint('Press Space to play or pause.'),
                    ),
                    _ControlButton(
                      icon: Icons.forward_10_rounded,
                      tooltip: 'Forward 10 seconds',
                      onTap: () => _seekTo(_now + 10),
                    ),
                    _ControlButton(
                      icon: Icons.volume_up_rounded,
                      keyLabel: 'M',
                      onTap:
                          () =>
                              _showKeyHint('Press M to turn sound on or off.'),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${_formatTime(now)} / '
                      '${duration == null ? '--:--' : _formatTime(duration)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Spacer(),
                    if (wide)
                      const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: Text(
                          'Space play/pause  ·  M sound  ·  ← → 10s',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ),
                    if (_webServers.length > 1)
                      _ControlButton(
                        icon: Icons.dns_rounded,
                        tooltip: 'Server',
                        highlighted: _serversOpen,
                        onTap: () {
                          setState(() {
                            _serversOpen = !_serversOpen;
                            _subsOpen = false;
                          });
                          _poke();
                        },
                      ),
                    _ControlButton(
                      icon:
                          _track != null
                              ? Icons.closed_caption_rounded
                              : Icons.closed_caption_off_outlined,
                      tooltip: 'Subtitles',
                      highlighted: _track != null,
                      onTap: _toggleSubtitles,
                    ),
                    if (_canFullscreen)
                      _ControlButton(
                        icon:
                            _isFullscreen
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                        tooltip:
                            _isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
                        onTap: _toggleFullscreen,
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

  Widget _buildServerPanel() {
    return Positioned(
      right: 16,
      bottom: _barHeight + 8,
      width: 340,
      child: Material(
        color: const Color(0xF21F1E26),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text(
                  'Server',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final s in _webServers)
                _TrackTile(
                  title: s.name,
                  subtitle: 'Ad-free controls',
                  selected: s == _server,
                  onTap: () => _switchServer(s),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitlePanel() {
    final tracks = _tracks;
    const muted = TextStyle(color: Colors.white54, fontSize: 12.5);
    return Positioned(
      right: 16,
      bottom: _barHeight + 8,
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
    final showSources = _hasTitle && _webServers.length > 1;
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
                      for (final s in _webServers) ...[
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
          if (_canFullscreen)
            IconButton(
              tooltip: 'Fullscreen',
              icon: const Icon(Icons.fullscreen_rounded, color: Colors.white),
              onPressed: _toggleFullscreen,
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

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    this.onTap,
    this.tooltip,
    this.size = 28,
    this.highlighted = false,
    this.keyLabel,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final bool highlighted;

  /// The keyboard key that does this, shown as a small key cap.
  final String? keyLabel;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(
      icon,
      size: size,
      color: highlighted ? _accent : Colors.white,
    );
    final button = Material(
      color: Colors.transparent,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: SizedBox(
            height: 44,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 34, child: Center(child: iconWidget)),
                if (keyLabel != null) _KeyCap(keyLabel!),
              ],
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white38),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A short instruction shown above the control bar.
class _HintPill extends StatelessWidget {
  const _HintPill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xF21F1E26),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x59F7BB0D)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.keyboard_rounded,
            color: Color(0xFFF7BB0D),
            size: 18,
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
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
