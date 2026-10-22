import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;
import 'package:app_web_ui/services/config.dart';
import 'package:app_web_ui/services/pages/native_player.dart';
import 'package:app_web_ui/services/pages/web_player.dart';
import 'package:app_web_ui/services/stream_extractor.dart';
import 'package:app_web_ui/services/stream_servers.dart';
import 'package:app_web_ui/shared/squeeze_button.dart';
import 'package:app_web_ui/stores/download_store.dart';
import 'package:app_web_ui/stores/history_store.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class MyWidget extends StatefulWidget {
  final String? url;
  final int? tmdbId;
  final String? mediaType; // 'movie' | 'tv'
  final int? seasonNumber;
  final int? episodeNumber;
  final int? durationSeconds;
  final int initialProgressSeconds;
  final String? title;
  final String? posterPath;
  final String? backdropPath;
  // IMDb id (from the TMDB detail response) — used for YIFY subtitles in the
  // native player without a second TMDB request.
  final String? imdbId;

  /// When true, extraction kicks off a background download via
  /// DownloadStore.start(...) instead of opening the native player. The
  /// route pops back to the caller as soon as the URL is captured.
  final bool downloadMode;

  /// When true, skip headless extraction entirely and just show the embed
  /// in a visible webview (the iframe). This is the fallback for titles
  /// whose extracted stream errors in ExoPlayer but plays fine in the
  /// browser/iframe.
  final bool iframePlayback;

  const MyWidget({
    super.key,
    this.url,
    this.tmdbId,
    this.mediaType,
    this.seasonNumber,
    this.episodeNumber,
    this.durationSeconds,
    this.initialProgressSeconds = 0,
    this.title,
    this.posterPath,
    this.backdropPath,
    this.imdbId,
    this.downloadMode = false,
    this.iframePlayback = false,
  });

  // Browsers can't run the headless stream extractor, so the web build plays
  // the provider's embed in an iframe instead. kIsWeb is a compile-time
  // constant, so each build only ever uses one of the two states.
  @override
  State<MyWidget> createState() =>
      // ignore: no_logic_in_create_state
      kIsWeb ? WebPlayerState() : _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  late String _currentUrl;

  DateTime _lastSavedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastSavedSeconds = -1;

  // Fallback elapsed-time tracker for when Videasy postMessage doesn't reach us.
  Timer? _elapsedTimer;
  DateTime? _watchStart;
  int _elapsedBaseline = 0;
  bool _gotPlayerEvent = false;
  int? _knownDuration;

  final InAppWebViewSettings _wvSettings = InAppWebViewSettings(
    isInspectable: true,
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: false,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    iframeAllowFullscreen: true,
    useShouldInterceptRequest: true,
  );

  // Headless webview — runs entirely off-screen so it doesn't fight the
  // Flutter UI thread for frame budget. Without this the platform-view
  // texture for a visible InAppWebView starves the loading spinner.
  HeadlessInAppWebView? _headless;

  // Captured stream info from the iframe.
  String? _streamUrl;
  String? _subtitleUrl;
  final List<String> _subtitleUrls = []; // every .vtt/.srt URL seen
  final Map<String, String> _streamHeaders = {};
  bool _handedOff = false;
  Timer? _handoffTimer;

  // Race state: every provider is extracted simultaneously; the first to
  // return a stream wins and the rest are cancelled. `_allFailed` flips true
  // only if every provider fails or times out.
  bool _allFailed = false;
  bool _racing = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url ?? serverurl;
    _elapsedBaseline = widget.initialProgressSeconds;
    _knownDuration = widget.durationSeconds;
    _watchStart = DateTime.now();
    WakelockPlus.enable();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Fallback: save approximate progress every 15s based on elapsed time.
    // If the player posts messages we use that instead (more accurate).
    _elapsedTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _saveElapsed(),
    );

    // iframe-playback mode shows the embed directly in a visible webview —
    // no extraction, no native handoff.
    if (!widget.iframePlayback) {
      // Prefer racing every provider at once (needs tmdbId + mediaType to
      // build all the URLs). Fall back to single-URL extraction otherwise.
      if (widget.tmdbId != null && widget.mediaType != null) {
        _startRace();
      } else {
        _startHeadlessExtractor();
      }
    }
  }

  /// Extract from every provider simultaneously; first to return a stream
  /// wins and the rest are torn down. No manual server picking.
  Future<void> _startRace() async {
    setState(() {
      _racing = true;
      _allFailed = false;
    });
    final raced = await raceServersForStream(
      tmdbId: widget.tmdbId!,
      mediaType: widget.mediaType!,
      seasonNumber: widget.seasonNumber,
      episodeNumber: widget.episodeNumber,
    );
    if (!mounted || _handedOff) return;
    if (raced == null) {
      setState(() {
        _racing = false;
        _allFailed = true;
      });
      return;
    }
    // Adopt the winner's stream + the embed URL it came from (the latter is
    // used as `sourceUrl` so the native player records a vote for it).
    _currentUrl = raced.embedUrl;
    _streamUrl = raced.stream.videoUrl;
    _streamHeaders
      ..clear()
      ..addAll(raced.stream.headers);
    _subtitleUrl = raced.stream.subtitleUrl;
    _subtitleUrls
      ..clear()
      ..addAll(raced.stream.subtitleUrls);
    _openNativePlayer();
  }

  /// Re-run the race (from the all-failed state).
  void _retryRace() {
    if (widget.tmdbId != null && widget.mediaType != null) {
      _startRace();
    }
  }

  /// Last-resort fallback: open the winning-or-first provider's embed in a
  /// visible webview so the user can watch in the page itself.
  void _watchInBrowser() {
    final fallback = streamServers.first.buildUrl(
      widget.tmdbId!,
      widget.mediaType!,
      widget.seasonNumber,
      widget.episodeNumber,
    );
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        pageBuilder:
            (_, __, ___) => MyWidget(
              url: fallback,
              tmdbId: widget.tmdbId,
              mediaType: widget.mediaType,
              seasonNumber: widget.seasonNumber,
              episodeNumber: widget.episodeNumber,
              durationSeconds: widget.durationSeconds,
              initialProgressSeconds: widget.initialProgressSeconds,
              title: widget.title,
              posterPath: widget.posterPath,
              backdropPath: widget.backdropPath,
              iframePlayback: true,
            ),
      ),
    );
  }

  Future<void> _startHeadlessExtractor() async {
    _headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(_currentUrl)),
      // Give the headless page a realistic viewport so elementFromPoint()
      // in the auto-clicker resolves to actual elements rather than null.
      initialSize: const Size(1280, 720),
      initialSettings: _wvSettings,
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: "sessionStorage.setItem('ads-enabled-session', 'false');",
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        UserScript(
          source: r"""
            (function() {
              function forward(raw) {
                try {
                  var data = typeof raw === 'string' ? JSON.parse(raw) : raw;
                  if (data && typeof data === 'object' &&
                      ('timestamp' in data || 'progress' in data)) {
                    window.flutter_inappwebview.callHandler('progress', data);
                  }
                } catch (e) {}
              }
              window.addEventListener('message', function(e) { forward(e.data); }, false);
              var origPost = window.postMessage;
              window.postMessage = function(data) {
                try { forward(data); } catch (e) {}
                return origPost.apply(window, arguments);
              };
            })();
          """,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        // Aggressive auto-clicker. Same as before — synthesises a full
        // pointer/mouse/click sequence at viewport centre + offsets, plus
        // common play-button selectors, plus video.play().
        _autoClickUserScript(),
      ]),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'progress',
          callback: (args) {
            if (args.isNotEmpty && args.first is Map) {
              _handleProgress(Map<String, dynamic>.from(args.first));
            }
          },
        );
      },
      shouldInterceptRequest:
          Platform.isAndroid
              ? (controller, req) async {
                try {
                  final url = req.url;
                  final headers = <String, String>{};
                  req.headers?.forEach((k, v) => headers[k] = v);
                  _captureRequest(Uri.parse(url.toString()), headers);
                } catch (_) {}
                return null;
              }
              : null,
    );
    await _headless!.run();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _handoffTimer?.cancel();
    _headless?.dispose();
    // Final save when the user closes the player.
    _saveElapsed();
    // Only restore portrait + system UI if the user backed out of the
    // webview directly. If we handed off to the native player, leave its
    // landscape + immersive setup alone — pushReplacement disposes this
    // page AFTER the native player's initState runs, so any restore here
    // would clobber the player.
    if (!_handedOff) {
      WakelockPlus.disable();
      // Restore free rotation (matches the global default from main.dart),
      // not portrait-only — so tablets keep landscape after closing the player.
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    }
    super.dispose();
  }

  void _saveElapsed() {
    // Skip if the player already reported real progress recently.
    if (_gotPlayerEvent) return;
    if (widget.tmdbId == null || widget.mediaType == null) return;
    if (_watchStart == null) return;

    final elapsedSecs = DateTime.now().difference(_watchStart!).inSeconds;
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

  // Intercepted from the iframe's HTTP requests. We watch for HLS/MP4
  // playlists and WebVTT subtitle files, plus the headers (especially
  // Referer/Origin) the underlying stream expects.
  void _captureRequest(Uri uri, Map<String, String> headers) {
    final fullLower = uri.toString().toLowerCase();
    final isVideo =
        fullLower.contains('.m3u8') ||
        fullLower.contains('.mp4') ||
        fullLower.contains('.mpd') ||
        fullLower.contains('/manifest') ||
        fullLower.contains('/playlist') ||
        fullLower.contains('master.txt');
    // Skip HLS segments (.ts) — we want the manifest, not chunks.
    final isSegment =
        fullLower.contains('.ts?') ||
        fullLower.endsWith('.ts') ||
        fullLower.contains('.m4s');
    final isSubtitle =
        fullLower.contains('.vtt') ||
        fullLower.contains('.srt') ||
        fullLower.contains('/subtitle') ||
        fullLower.contains('/caption');
    if ((!isVideo || isSegment) && !isSubtitle) return;

    // For HLS, segment URLs (.ts) and variant playlists also show up; prefer
    // the first .m3u8 we see — usually the master — and ignore subsequent ones.
    if (isVideo && !isSegment && _streamUrl == null) {
      _streamUrl = uri.toString();
      _streamHeaders.clear();
      headers.forEach((k, v) {
        final lk = k.toLowerCase();
        if (lk == 'referer' ||
            lk == 'origin' ||
            lk == 'user-agent' ||
            lk == 'cookie' ||
            lk.startsWith('sec-')) {
          _streamHeaders[k] = v;
        }
      });
      // Fall back to the iframe origin as Referer if not set.
      _streamHeaders.putIfAbsent(
        'Referer',
        () => '${uri.scheme}://${uri.host}/',
      );
      // Give subtitles a brief moment to also be captured before handing off.
      _handoffTimer?.cancel();
      _handoffTimer = Timer(
        const Duration(milliseconds: 1200),
        _openNativePlayer,
      );
      if (mounted) setState(() {});
    }
    if (isSubtitle) {
      final s = uri.toString();
      if (!_subtitleUrls.contains(s)) {
        _subtitleUrls.add(s);
        _subtitleUrl ??= s; // first one becomes the default
        if (mounted) setState(() {});
      }
    }
  }

  void _openNativePlayer() {
    if (!mounted) return;
    final url = _streamUrl;
    if (url == null || _handedOff) return;
    _handedOff = true;

    // Download mode — kick off the background download and pop back instead
    // of opening the player. The DownloadStore handles progress + completion;
    // the user can monitor it from the Downloads page.
    if (widget.downloadMode) {
      if (widget.tmdbId != null && widget.mediaType != null) {
        downloadStore.start(
          tmdbId: widget.tmdbId!,
          mediaType: widget.mediaType!,
          url: url,
          headers: Map<String, String>.from(_streamHeaders),
          seasonNumber: widget.seasonNumber,
          episodeNumber: widget.episodeNumber,
          title: widget.title,
          posterPath: widget.posterPath,
          backdropPath: widget.backdropPath,
        );
      }
      Navigator.of(context).pop();
      return;
    }

    // Zero-duration transition. The default MaterialPageRoute slide-up
    // animates both old + new pages live for ~300ms, which contends with
    // the video controller's initialize() on the main thread and makes
    // the loading spinner look janky. Snapping instantly avoids that.
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder:
            (_, __, ___) => NativePlayerPage(
              videoUrl: url,
              httpHeaders: Map<String, String>.from(_streamHeaders),
              subtitleUrl: _subtitleUrl,
              subtitleUrls: List<String>.from(_subtitleUrls),
              sourceUrl: _currentUrl,
              imdbId: widget.imdbId,
              title: widget.title,
              tmdbId: widget.tmdbId,
              mediaType: widget.mediaType,
              seasonNumber: widget.seasonNumber,
              episodeNumber: widget.episodeNumber,
              initialProgressSeconds:
                  _lastSavedSeconds >= 0
                      ? _lastSavedSeconds
                      : widget.initialProgressSeconds,
              posterPath: widget.posterPath,
              backdropPath: widget.backdropPath,
            ),
      ),
    );
  }

  // Save progress at most every 10s OR when the playback position jumps >15s.
  Future<void> _handleProgress(Map<String, dynamic> data) async {
    if (widget.tmdbId == null || widget.mediaType == null) return;

    final timestamp = (data['timestamp'] as num?)?.round();
    final duration = (data['duration'] as num?)?.round();
    if (timestamp == null) return;

    _gotPlayerEvent = true;
    if (duration != null && duration > 0) _knownDuration = duration;

    final now = DateTime.now();
    final timeDelta = now.difference(_lastSavedAt).inSeconds;
    final seekDelta = (_lastSavedSeconds - timestamp).abs();
    if (timeDelta < 10 && seekDelta < 15) return;

    _lastSavedAt = now;
    _lastSavedSeconds = timestamp;

    final season = (data['season'] as num?)?.toInt() ?? widget.seasonNumber;
    final episode = (data['episode'] as num?)?.toInt() ?? widget.episodeNumber;

    historyStore.record(
      tmdbId: widget.tmdbId!,
      mediaType: widget.mediaType!,
      seasonNumber: widget.mediaType == 'tv' ? season : null,
      episodeNumber: widget.mediaType == 'tv' ? episode : null,
      progressSeconds: timestamp,
      durationSeconds: _knownDuration,
      title: widget.title,
      posterPath: widget.posterPath,
      backdropPath: widget.backdropPath,
    );
  }

  // Aggressive auto-clicker: synthesises a full pointer/mouse/click sequence
  // at the viewport centre (+ offsets), clicks common play-button selectors,
  // and calls video.play() with a muted-autoplay fallback. Runs in every
  // frame so it reaches nested provider iframes. Shared by the headless
  // extractor and the visible iframe-playback fallback.
  UserScript _autoClickUserScript() {
    return UserScript(
      source: r"""
        (function() {
          var attempts = 0;
          var maxAttempts = 120;
          var selectors = [
            'button[aria-label*="play" i]',
            'button[title*="play" i]',
            '[role="button"][aria-label*="play" i]',
            '[class*="play" i][class*="button" i]',
            '[class*="bigPlay" i]',
            '[class*="big-play" i]',
            '[class*="playButton" i]',
            '.plyr__control--overlaid',
            '.vjs-big-play-button',
            '.jw-display-icon-container',
            '.jw-icon-display',
            'svg[class*="play" i]',
            'div[class*="play" i]'
          ];
          function fakeClick(el, x, y) {
            if (!el) return;
            try {
              ['pointerdown','mousedown','pointerup','mouseup','click'].forEach(function(type) {
                var ev;
                if (type.indexOf('pointer') === 0) {
                  ev = new PointerEvent(type, {bubbles: true, cancelable: true, clientX: x, clientY: y, button: 0, pointerType: 'mouse'});
                } else {
                  ev = new MouseEvent(type, {bubbles: true, cancelable: true, view: window, clientX: x, clientY: y, button: 0});
                }
                el.dispatchEvent(ev);
              });
              try { el.click(); } catch (e) {}
            } catch (e) {}
          }
          function clickAt(x, y) {
            var el = document.elementFromPoint(x, y);
            fakeClick(el, x, y);
          }
          var timer = setInterval(function() {
            attempts++;
            if (attempts > maxAttempts) { clearInterval(timer); return; }
            try {
              var cx = (window.innerWidth || document.documentElement.clientWidth) / 2;
              var cy = (window.innerHeight || document.documentElement.clientHeight) / 2;
              clickAt(cx, cy);
              clickAt(cx, cy - 40);
              clickAt(cx, cy + 40);
              clickAt(cx - 40, cy);
              clickAt(cx + 40, cy);
              for (var s = 0; s < selectors.length; s++) {
                var els = document.querySelectorAll(selectors[s]);
                for (var j = 0; j < els.length; j++) {
                  try { els[j].click(); } catch (e) {}
                }
              }
              var videos = document.querySelectorAll('video');
              for (var i = 0; i < videos.length; i++) {
                var v = videos[i];
                try {
                  var p = v.play();
                  if (p && p.catch) p.catch(function() {
                    try { v.muted = true; v.play(); } catch (e) {}
                  });
                } catch (e) {}
              }
              for (var k = 0; k < videos.length; k++) {
                if (!videos[k].paused && videos[k].currentTime > 0) {
                  clearInterval(timer);
                  return;
                }
              }
            } catch (e) {}
          }, 500);
        })();
      """,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // iframe-playback fallback: show the embed in a visible webview and let
    // the user watch in the page itself (used when native extraction errors
    // but the iframe plays fine).
    if (widget.iframePlayback) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_currentUrl)),
              initialSettings: _wvSettings,
              initialUserScripts: UnmodifiableListView<UserScript>([
                UserScript(
                  source:
                      "sessionStorage.setItem('ads-enabled-session', 'false');",
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
                _autoClickUserScript(),
              ]),
              onWebViewCreated: (controller) {
                controller.addJavaScriptHandler(
                  handlerName: 'progress',
                  callback: (args) {
                    if (args.isNotEmpty && args.first is Map) {
                      _handleProgress(Map<String, dynamic>.from(args.first));
                    }
                  },
                );
              },
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      );
    }

    // No platform view in the tree — the headless extractors run in the
    // background. This keeps the Flutter UI thread free so the loading
    // indicator animates smoothly.
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: RepaintBoundary(
                child: _allFailed ? _buildFailed() : _buildLoading(),
              ),
            ),
            // Back chevron — escape hatch if everything hangs.
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            color: Color(0xFFEF0003),
            strokeWidth: 2.5,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _streamUrl != null
              ? 'Preparing player…'
              : (_racing ? 'Finding the best source…' : 'Loading stream…'),
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildFailed() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFEF0003),
            size: 48,
          ),
          const SizedBox(height: 16),
          const Text(
            'No source returned a stream.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Every provider failed or timed out. Try again, or watch in the browser.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SqueezeButton(
                onTap: _retryRace,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF0003),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.refresh_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Try again',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SqueezeButton(
                onTap: _watchInBrowser,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 1.2,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.public_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Watch in browser',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
