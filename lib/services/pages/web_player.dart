import 'dart:async';
import 'dart:convert';

import 'package:app_web_ui/services/pages/embed_frame.dart';
import 'package:app_web_ui/services/pages/webview.dart';
import 'package:app_web_ui/services/server_vote_service.dart';
import 'package:app_web_ui/services/stream_servers.dart';
import 'package:app_web_ui/stores/history_store.dart';
import 'package:flutter/material.dart';

/// The web build's player — [MyWidget] uses this state when running in a
/// browser. Browsers can't run the Android headless extractor (no request
/// interception, and CORS blocks reading the embed pages), so the provider's
/// own player plays in an iframe and the user can switch sources from the
/// top bar.
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
  // player is driven by keyboard instead, so it's only on by default where
  // there is one.
  bool _shield = false;
  bool _fullscreen = false;
  StreamSubscription<Object?>? _fullscreenSub;

  bool get _hasTitle => widget.tmdbId != null && widget.mediaType != null;

  @override
  void initState() {
    super.initState();
    _elapsedBaseline = widget.initialProgressSeconds;
    _knownDuration = widget.durationSeconds;
    _messages = listenToWindowMessages(_onMessage);
    _shield = webHasKeyboardPointer;
    _fullscreenSub = listenToFullscreenChange(() {
      if (mounted) setState(() => _fullscreen = appIsFullscreen());
    });
    // Fallback progress saving for providers that don't post player events.
    _elapsedTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _saveElapsed(),
    );
    _pickInitialServer();
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
    });
  }

  @override
  void dispose() {
    _messages?.cancel();
    _elapsedTimer?.cancel();
    _fullscreenSub?.cancel();
    exitAppFullscreen();
    // Final save when the user closes the player.
    _saveElapsed();
    super.dispose();
  }

  // Embeds post progress either flat ({timestamp, duration}) or wrapped as
  // {type: 'PLAYER_EVENT', data: {currentTime, duration, ...}}, sometimes as
  // a JSON string.
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
    _handleProgress(
      timestamp.round(),
      duration is num ? duration.round() : null,
      season: payload['season'],
      episode: payload['episode'],
    );
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

  @override
  Widget build(BuildContext context) {
    final url = _embedUrl;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Fullscreen is the whole app, so drop the bar; Esc brings it back.
          if (!_fullscreen) _buildTopBar(context),
          Expanded(
            child:
                url == null
                    ? const Center(
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          color: Color(0xFFEF0003),
                          strokeWidth: 2.5,
                        ),
                      ),
                    )
                    : EmbedFrame(key: ValueKey(url), url: url, shield: _shield),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final episodeLabel =
        widget.mediaType == 'tv' && widget.seasonNumber != null
            ? 'S${widget.seasonNumber} · E${widget.episodeNumber}'
            : null;
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
                    child: Text(
                      [
                        if (widget.title != null) widget.title!,
                        if (episodeLabel != null) episodeLabel,
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
                  _shield
                      ? 'Clicks on the video are blocked so ads can\'t open tabs. '
                          'Keys: Space play/pause · ← → seek · M mute. '
                          'Turn off for the player\'s own menus.'
                      : 'Clicks reach the player, so its ads may open tabs.',
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
