import 'dart:async';
import 'dart:collection';
import 'package:app_web_ui/services/config.dart';
import 'package:app_web_ui/stores/history_store.dart';

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
  });

  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  late String _currentUrl;
  final Key _webViewKey = UniqueKey();
  bool _isLoading = true;

  DateTime _lastSavedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastSavedSeconds = -1;

  // Fallback elapsed-time tracker for when Videasy postMessage doesn't reach us.
  Timer? _elapsedTimer;
  DateTime? _watchStart;
  int _elapsedBaseline = 0;
  bool _gotPlayerEvent = false;
  int? _knownDuration;

  final InAppWebViewSettings settings = InAppWebViewSettings(
    isInspectable: true,
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: false,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    iframeAllowFullscreen: true,
  );

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
  }



  @override
  void dispose() {
    _elapsedTimer?.cancel();
    // Final save when the user closes the player.
    _saveElapsed();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              key: _webViewKey,
              initialUrlRequest: URLRequest(url: WebUri(_currentUrl)),
              initialSettings: settings,
              initialUserScripts: UnmodifiableListView<UserScript>([
                UserScript(
                  source:
                      "sessionStorage.setItem('ads-enabled-session', 'false');",
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
                        } catch (e) { /* ignore */ }
                      }
                      window.addEventListener('message', function(e) {
                        forward(e.data);
                      }, false);
                      var origPost = window.postMessage;
                      window.postMessage = function(data) {
                        try { forward(data); } catch (e) {}
                        return origPost.apply(window, arguments);
                      };
                    })();
                  """,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                ),
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

              onLoadStart: (controller, url) {
                setState(() {
                  _isLoading = true;
                });
              },
              onLoadStop: (controller, url) {
                setState(() {
                  _isLoading = false;
                });
              },
            ),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(color: Color(0xFFEF0003)),
              ),
          ],
        ),
      ),
    );
  }
}
