import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// What `extractStream` resolves to once the headless webview has captured
/// a stream URL from the videasy / vidlink / vidsrc / 2embed / 111movies
/// embed page.
class ExtractedStream {
  final String videoUrl;
  final String? subtitleUrl;
  final Map<String, String> headers;
  const ExtractedStream({
    required this.videoUrl,
    required this.subtitleUrl,
    required this.headers,
  });
}

/// Runs the same auto-clicker + `shouldInterceptRequest` capture pipeline as
/// the player's headless extractor, but as a one-shot function that:
///   • does NOT modify orientation / status bar / wakelock
///   • does NOT mount any visible widget
///   • disposes the headless webview as soon as a stream URL is captured
///
/// Use this for "silent" flows like downloads where the user should never
/// see a loading screen or have their device flipped to landscape.
///
/// Android only — falls through to `null` on other platforms because
/// `shouldInterceptRequest` doesn't exist there. Times out after [timeout]
/// (default 45 s) and resolves to `null` if no stream URL is captured.
Future<ExtractedStream?> extractStream({
  required String embedUrl,
  Duration timeout = const Duration(seconds: 45),
  Duration subtitleGrace = const Duration(milliseconds: 800),
}) async {
  if (kIsWeb || !Platform.isAndroid) return null;

  final completer = Completer<ExtractedStream?>();
  HeadlessInAppWebView? headless;
  Timer? subtitleTimer;
  Timer? timeoutTimer;

  String? streamUrl;
  String? subtitleUrl;
  final headers = <String, String>{};

  Future<void> dispose() async {
    subtitleTimer?.cancel();
    timeoutTimer?.cancel();
    try {
      await headless?.dispose();
    } catch (_) {}
  }

  void resolveWithStream() {
    if (completer.isCompleted) return;
    if (streamUrl == null) return;
    completer.complete(ExtractedStream(
      videoUrl: streamUrl!,
      subtitleUrl: subtitleUrl,
      headers: Map<String, String>.from(headers),
    ));
    dispose();
  }

  void resolveNull() {
    if (completer.isCompleted) return;
    completer.complete(null);
    dispose();
  }

  void capture(Uri uri, Map<String, String> reqHeaders) {
    final fullLower = uri.toString().toLowerCase();
    final isVideo = fullLower.contains('.m3u8') ||
        fullLower.contains('.mp4') ||
        fullLower.contains('.mpd') ||
        fullLower.contains('/manifest') ||
        fullLower.contains('/playlist');
    final isSegment = fullLower.contains('.ts?') ||
        fullLower.endsWith('.ts') ||
        fullLower.contains('.m4s');
    final isSubtitle = fullLower.contains('.vtt') ||
        fullLower.contains('.srt') ||
        fullLower.contains('/subtitle') ||
        fullLower.contains('/caption');

    if (isVideo && !isSegment && streamUrl == null) {
      streamUrl = uri.toString();
      reqHeaders.forEach((k, v) {
        final lk = k.toLowerCase();
        if (lk == 'referer' ||
            lk == 'origin' ||
            lk == 'user-agent' ||
            lk == 'cookie' ||
            lk.startsWith('sec-')) {
          headers[k] = v;
        }
      });
      headers.putIfAbsent('Referer', () => '${uri.scheme}://${uri.host}/');
      // Give subtitles a brief window in case they fire after the manifest.
      subtitleTimer?.cancel();
      subtitleTimer = Timer(subtitleGrace, resolveWithStream);
    }
    if (isSubtitle && subtitleUrl == null) {
      subtitleUrl = uri.toString();
    }
  }

  headless = HeadlessInAppWebView(
    initialUrlRequest: URLRequest(url: WebUri(embedUrl)),
    initialSize: const Size(1280, 720),
    initialSettings: InAppWebViewSettings(
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: false,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      iframeAllowFullscreen: true,
      useShouldInterceptRequest: true,
    ),
    initialUserScripts: UnmodifiableListView<UserScript>([
      UserScript(
        source: "sessionStorage.setItem('ads-enabled-session', 'false');",
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
      // Same aggressive auto-clicker as the player's headless extractor —
      // synthesises a full pointer/click sequence at viewport centre +
      // offsets, hits common play-button selectors, and calls video.play()
      // with a muted-autoplay fallback. This is what makes the embed
      // actually fetch its manifest so shouldInterceptRequest sees it.
      UserScript(
        forMainFrameOnly: false,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
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
      ),
    ]),
    shouldInterceptRequest: (controller, req) async {
      try {
        final url = req.url;
        final reqHeaders = <String, String>{};
        req.headers?.forEach((k, v) => reqHeaders[k] = v);
        capture(Uri.parse(url.toString()), reqHeaders);
      } catch (_) {}
      return null;
    },
  );

  timeoutTimer = Timer(timeout, () {
    // If we have a stream URL but the subtitle grace window hasn't fired
    // yet, still resolve with what we have.
    if (streamUrl != null) {
      resolveWithStream();
    } else {
      resolveNull();
    }
  });

  try {
    await headless.run();
  } catch (e) {
    resolveNull();
  }

  return completer.future;
}
