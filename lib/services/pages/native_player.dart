import 'dart:async';
import 'dart:io';

import 'package:app_web_ui/services/pages/webview.dart';
import 'package:app_web_ui/services/server_vote_service.dart';
import 'package:app_web_ui/services/stream_servers.dart';
import 'package:app_web_ui/stores/history_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class NativePlayerPage extends StatefulWidget {
  final String videoUrl;
  final Map<String, String> httpHeaders;
  final String? subtitleUrl;
  final List<String> subtitleUrls; // all captured subtitle URLs
  final String? sourceUrl;          // embed URL used by the webview
  final String? title;
  final int? tmdbId;
  final String? mediaType;
  final int? seasonNumber;
  final int? episodeNumber;
  final int initialProgressSeconds;
  final String? posterPath;
  final String? backdropPath;
  /// When set, playback reads from a local file instead of fetching via
  /// network — used by the Downloads page to play offline copies.
  /// For MP4 files: VideoPlayerController.file. For local HLS (.m3u8 with
  /// neighbouring .ts segments): VideoPlayerController.networkUrl with a
  /// file:// URI (ExoPlayer handles it natively).
  final String? localFilePath;

  const NativePlayerPage({
    super.key,
    required this.videoUrl,
    this.httpHeaders = const {},
    this.subtitleUrl,
    this.subtitleUrls = const [],
    this.sourceUrl,
    this.title,
    this.tmdbId,
    this.mediaType,
    this.seasonNumber,
    this.episodeNumber,
    this.initialProgressSeconds = 0,
    this.posterPath,
    this.backdropPath,
    this.localFilePath,
  });

  @override
  State<NativePlayerPage> createState() => _NativePlayerPageState();
}

class _NativePlayerPageState extends State<NativePlayerPage> {
  VideoPlayerController? _controller;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  Timer? _saveTimer;
  int _lastSavedSeconds = -1;
  String? _error;

  // Visual feedback for double-tap seek (-10s / +10s).
  Timer? _seekIndicatorTimer;
  int _seekIndicator = 0; // -1 = left arrow, 1 = right arrow, 0 = hidden
  int _seekCount = 0;     // increments each seek so the animation re-fires

  // Zoom / fit toggle. false = AspectRatio (letterbox), true = cover (crop).
  bool _fillMode = false;

  // Pinch-to-zoom state. Only the latest scale value matters; we snap to
  // fill or fit when the pinch ends, based on whether the user pinched
  // outward (> 1.15) or inward (< 0.85).
  double _pinchScale = 1.0;

  // Vertical-drag brightness (left half) / volume (right half), like
  // MX Player / YouTube. `_vDragKind` is 'brightness' | 'volume' | null.
  // `_vDragValue` is the live 0..1 value shown in the overlay.
  String? _vDragKind;
  double _vDragValue = 0;
  Timer? _vDragHideTimer;

  static const Duration _seekStep = Duration(seconds: 10);

  Future<void> _onVerticalDragStart(String kind) async {
    double start;
    try {
      start = kind == 'brightness'
          ? await ScreenBrightness().application
          : await VolumeController.instance.getVolume();
    } catch (_) {
      start = 0.5;
    }
    if (!mounted) return;
    _vDragHideTimer?.cancel();
    setState(() {
      _vDragKind = kind;
      _vDragValue = start.clamp(0.0, 1.0);
    });
  }

  void _onVerticalDragUpdate(double primaryDelta) {
    if (_vDragKind == null) return;
    // Full-height swipe ≈ full 0..1 range. Up = increase.
    final h = MediaQuery.of(context).size.height;
    final next = (_vDragValue - primaryDelta / h).clamp(0.0, 1.0);
    setState(() => _vDragValue = next);
    // Guard against MissingPluginException / unsupported devices — the
    // overlay still tracks the gesture even if the platform call no-ops.
    try {
      if (_vDragKind == 'brightness') {
        ScreenBrightness()
            .setApplicationScreenBrightness(next)
            .catchError((_) {});
      } else {
        VolumeController.instance.setVolume(next).catchError((_) {});
      }
    } catch (_) {}
  }

  void _onVerticalDragEnd() {
    // Keep the indicator on-screen briefly after the finger lifts.
    _vDragHideTimer?.cancel();
    _vDragHideTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _vDragKind = null);
    });
  }

  void _seekBy(Duration delta) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final target = c.value.position + delta;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > c.value.duration ? c.value.duration : target);
    c.seekTo(clamped);
    setState(() {
      _seekIndicator = delta.isNegative ? -1 : 1;
      _seekCount++; // re-trigger the AnimatedSwitcher / Tween animation
    });
    _seekIndicatorTimer?.cancel();
    _seekIndicatorTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _seekIndicator = 0);
    });
  }

  void _toggleFillMode() {
    setState(() => _fillMode = !_fillMode);
    _scheduleHideControls();
  }

  @override
  void initState() {
    super.initState();
    _activeSubtitleUrl = widget.subtitleUrl;
    // Suppress the OS volume HUD — our own drag overlay shows the level.
    VolumeController.instance.showSystemUI = false;
    WakelockPlus.enable();
    // Always start in landscape; the rotate button in the controls overlay
    // lets the user unlock to allow auto-rotation if they want portrait.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Hide the status & nav bars entirely while the player is open.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: const [],
    );
    _init();
  }

  bool _landscapeLocked = true;
  String? _activeSubtitleUrl;

  String _subtitleLabel(String url) {
    final uri = Uri.tryParse(url);
    final filename = (uri?.pathSegments.isNotEmpty ?? false)
        ? uri!.pathSegments.last
        : url;
    final m = RegExp(r'[._-]([a-z]{2,3})(?:[._-]|\.(?:vtt|srt)$)',
            caseSensitive: false)
        .firstMatch(filename);
    if (m != null) return _langName(m.group(1)!);
    return filename.length > 30 ? '${filename.substring(0, 30)}…' : filename;
  }

  String _langName(String code) {
    const langs = {
      'en': 'English', 'es': 'Spanish', 'fr': 'French', 'de': 'German',
      'it': 'Italian', 'pt': 'Portuguese', 'ru': 'Russian', 'zh': 'Chinese',
      'ja': 'Japanese', 'ko': 'Korean', 'ar': 'Arabic', 'hi': 'Hindi',
      'tr': 'Turkish', 'nl': 'Dutch', 'pl': 'Polish', 'sv': 'Swedish',
      'id': 'Indonesian', 'th': 'Thai', 'vi': 'Vietnamese', 'fa': 'Persian',
    };
    return langs[code.toLowerCase()] ?? code.toUpperCase();
  }

  Future<void> _setSubtitle(String? url) async {
    final c = _controller;
    if (c == null) return;
    setState(() => _activeSubtitleUrl = url);
    if (url == null) {
      // Clear captions with an empty WebVTT document.
      c.setClosedCaptionFile(
        Future.value(WebVTTCaptionFile('WEBVTT\n\n')),
      );
      return;
    }
    try {
      final res = await http.get(Uri.parse(url), headers: widget.httpHeaders);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        c.setClosedCaptionFile(Future.value(WebVTTCaptionFile(res.body)));
      }
    } catch (_) {}
  }

  void _showSettings() {
    _hideTimer?.cancel();
    final currentServer =
        widget.sourceUrl == null ? null : streamServerForUrl(widget.sourceUrl!);
    // 'main' | 'source' | 'subtitles' — drives the in-place drill-down.
    String view = 'main';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1F1E26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final maxH = MediaQuery.of(ctx).size.height * 0.7;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final subtitleValue = _activeSubtitleUrl == null
                ? 'Off'
                : _subtitleLabel(_activeSubtitleUrl!);

            Widget header(String title, {bool showBack = false}) => Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 20, 14),
                  child: Row(
                    children: [
                      if (showBack)
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded,
                              color: Colors.white, size: 22),
                          onPressed: () => setSheet(() => view = 'main'),
                        )
                      else
                        const SizedBox(width: 8),
                      Icon(
                        showBack
                            ? (title == 'Source'
                                ? Icons.dns_rounded
                                : Icons.subtitles_rounded)
                            : Icons.settings_rounded,
                        color: const Color(0xFFEF0003),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );

            final List<Widget> children;
            if (view == 'source') {
              children = [
                header('Source', showBack: true),
                for (final s in streamServers)
                  _settingsRow(
                    label: s.name,
                    icon: Icons.play_circle_outline_rounded,
                    selected: s == currentServer,
                    onTap: () => _switchServer(s),
                  ),
                const SizedBox(height: 8),
              ];
            } else if (view == 'subtitles') {
              children = [
                header('Subtitles', showBack: true),
                _settingsRow(
                  label: 'Off',
                  icon: Icons.subtitles_off_rounded,
                  selected: _activeSubtitleUrl == null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _setSubtitle(null);
                  },
                ),
                if (widget.subtitleUrls.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Text(
                      'No subtitle tracks captured.',
                      style: TextStyle(color: Colors.white38, fontSize: 12.5),
                    ),
                  )
                else
                  for (final url in widget.subtitleUrls)
                    _settingsRow(
                      label: _subtitleLabel(url),
                      icon: Icons.subtitles_rounded,
                      selected: _activeSubtitleUrl == url,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _setSubtitle(url);
                      },
                    ),
                const SizedBox(height: 8),
              ];
            } else {
              // Main menu — two options that drill into their lists.
              children = [
                header('Settings'),
                _settingsNavRow(
                  icon: Icons.dns_rounded,
                  label: 'Source',
                  value: currentServer?.name ?? 'Default',
                  onTap: () => setSheet(() => view = 'source'),
                ),
                _settingsNavRow(
                  icon: Icons.subtitles_rounded,
                  label: 'Subtitles',
                  value: subtitleValue,
                  onTap: () => setSheet(() => view = 'subtitles'),
                ),
                const SizedBox(height: 8),
              ];
            }

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(_scheduleHideControls);
  }

  // A top-level settings entry: icon + label on the left, current value +
  // chevron on the right. Tapping drills into that option's list.
  Widget _settingsNavRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 20),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFEF0003),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _settingsRow({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(icon,
                color: selected ? const Color(0xFFEF0003) : Colors.white70,
                size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? const Color(0xFFEF0003) : Colors.white,
                  fontSize: 14.5,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selected)
              const Icon(Icons.check_rounded,
                  color: Color(0xFFEF0003), size: 18),
          ],
        ),
      ),
    );
  }

  void _switchServer(StreamServer server) {
    final tmdbId = widget.tmdbId;
    final mediaType = widget.mediaType;
    if (tmdbId == null || mediaType == null) {
      Navigator.of(context).pop();
      return;
    }
    final newUrl = server.buildUrl(
      tmdbId,
      mediaType,
      widget.seasonNumber,
      widget.episodeNumber,
    );
    Navigator.of(context).pop(); // close the sheet
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MyWidget(
          url: newUrl,
          tmdbId: tmdbId,
          mediaType: mediaType,
          seasonNumber: widget.seasonNumber,
          episodeNumber: widget.episodeNumber,
          initialProgressSeconds:
              _controller?.value.position.inSeconds ?? widget.initialProgressSeconds,
          title: widget.title,
          posterPath: widget.posterPath,
          backdropPath: widget.backdropPath,
        ),
      ),
    );
  }
  // Native playback failed → open the original embed in a visible webview
  // (the iframe), which the content plays fine in. pushReplacement so backing
  // out returns to the detail page, not the broken native player.
  void _openIframeFallback() {
    final src = widget.sourceUrl;
    if (src == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MyWidget(
          url: src,
          tmdbId: widget.tmdbId,
          mediaType: widget.mediaType,
          seasonNumber: widget.seasonNumber,
          episodeNumber: widget.episodeNumber,
          initialProgressSeconds:
              _controller?.value.position.inSeconds ??
                  widget.initialProgressSeconds,
          title: widget.title,
          posterPath: widget.posterPath,
          backdropPath: widget.backdropPath,
          iframePlayback: true,
        ),
      ),
    );
  }

  void _toggleLandscapeLock() {
    setState(() => _landscapeLocked = !_landscapeLocked);
    SystemChrome.setPreferredOrientations(
      _landscapeLocked
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : DeviceOrientation.values,
    );
    _scheduleHideControls();
  }

  Future<void> _init() async {
    try {
      // Local file → use VideoPlayerController.file for MP4, networkUrl with
      // a file:// URI for HLS (ExoPlayer recognises the manifest extension).
      // Otherwise fall back to the network constructor with captured headers.
      VideoPlayerController controller;
      final local = widget.localFilePath;
      if (local != null) {
        if (local.endsWith('.m3u8')) {
          controller = VideoPlayerController.networkUrl(Uri.file(local));
        } else {
          controller = VideoPlayerController.file(File(local));
        }
      } else {
        // Always send a browser User-Agent — some CDNs 403 segment requests
        // without one, which surfaces as a source exception mid-playback.
        final headers = Map<String, String>.from(widget.httpHeaders);
        headers.putIfAbsent(
          'User-Agent',
          () => 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        );
        controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.videoUrl),
          httpHeaders: headers,
        );
      }
      await controller.initialize();
      // Watch for errors that surface AFTER initialize() succeeds — e.g.
      // ExoPlayer rejecting segments/codecs once playback actually starts.
      // initialize() returning fine doesn't guarantee the source plays.
      controller.addListener(_onControllerUpdate);

      if (widget.subtitleUrl != null && widget.subtitleUrl!.isNotEmpty) {
        try {
          final vtt = await _fetchVtt(widget.subtitleUrl!);
          if (vtt != null) {
            controller.setClosedCaptionFile(Future.value(WebVTTCaptionFile(vtt)));
          }
        } catch (_) {
          // Subtitles are best-effort; ignore failure.
        }
      }

      if (widget.initialProgressSeconds > 0) {
        await controller.seekTo(Duration(seconds: widget.initialProgressSeconds));
      }
      await controller.play();

      // NOTE: we deliberately do NOT record a server "success" here — play()
      // returning doesn't mean playback works (a source exception can still
      // fire). _onControllerUpdate records the vote only once real progress
      // is observed, so we don't reward sources that error immediately.

      _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress());
      _scheduleHideControls();

      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  bool _votedSuccess = false;

  // Fires on every controller value change. Two jobs:
  //  1. Surface a source error that only appears once playback starts.
  //  2. Record the server "success" vote once real progress is seen (≥3s),
  //     so sources that error immediately don't get rewarded as defaults.
  void _onControllerUpdate() {
    final c = _controller;
    if (c == null) return;
    if (c.value.hasError && _error == null) {
      setState(() =>
          _error = c.value.errorDescription ?? 'Playback error');
      return;
    }
    if (!_votedSuccess &&
        c.value.isInitialized &&
        c.value.isPlaying &&
        c.value.position.inSeconds >= 3) {
      _votedSuccess = true;
      _recordServerSuccess();
    }
  }

  // Fire-and-forget vote that the current source actually worked for this
  // title. Skips if we can't identify the server (e.g. sourceUrl missing or
  // it doesn't match any known provider host).
  void _recordServerSuccess() {
    final src = widget.sourceUrl;
    final id = widget.tmdbId;
    final mt = widget.mediaType;
    if (src == null || id == null || mt == null) return;
    final server = streamServerForUrl(src);
    if (server == null) return;
    ServerVoteService.instance.recordSuccess(
      tmdbId: id,
      mediaType: mt,
      serverName: server.name,
    );
  }

  Future<String?> _fetchVtt(String url) async {
    final headers = Map<String, String>.from(widget.httpHeaders);
    final res = await http.get(Uri.parse(url), headers: headers);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.body;
    }
    return null;
  }

  // We DO NOT rebuild the whole widget tree on every controller tick — that
  // was the cause of the laggy loading indicator (a setState every frame
  // means the whole Scaffold + spinner repaints at 60 Hz). Instead, the
  // controls overlay subscribes to the controller via ValueListenableBuilder
  // so only the seek bar / time labels rebuild as the position advances.

  void _saveProgress() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (widget.tmdbId == null || widget.mediaType == null) return;
    final secs = c.value.position.inSeconds;
    if (secs <= _lastSavedSeconds) return;
    _lastSavedSeconds = secs;
    historyStore.record(
      tmdbId: widget.tmdbId!,
      mediaType: widget.mediaType!,
      seasonNumber: widget.seasonNumber,
      episodeNumber: widget.episodeNumber,
      progressSeconds: secs,
      durationSeconds: c.value.duration.inSeconds,
      title: widget.title,
      posterPath: widget.posterPath,
      backdropPath: widget.backdropPath,
    );
  }

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHideControls();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    _scheduleHideControls();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _seekIndicatorTimer?.cancel();
    _vDragHideTimer?.cancel();
    // Hand brightness control back to the system.
    ScreenBrightness().resetApplicationScreenBrightness().catchError((_) {});
    _saveProgress();
    _controller?.dispose();
    WakelockPlus.disable();
    // Restore free rotation (matches the global default from main.dart),
    // not portrait-only — so tablets keep landscape after closing the player.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      final canIframe =
          widget.localFilePath == null && widget.sourceUrl != null;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white70, size: 48),
              const SizedBox(height: 12),
              Text(
                canIframe
                    ? 'This source won\'t play in the native player.\n'
                        'Try watching it in the web player instead.'
                    : 'Could not play stream natively.\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 18),
              if (canIframe)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF0003),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  onPressed: _openIframeFallback,
                  icon: const Icon(Icons.public_rounded, size: 18),
                  label: const Text('Play in web player'),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back',
                    style: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
        ),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return _buildLoading();
    }
    return GestureDetector(
      // Pinch handlers live on an outer translucent detector so the inner
      // tap zones (left/right halves) still handle taps and double-taps.
      // The scale recognizer only wins the gesture arena when it actually
      // sees multi-finger scaling motion, so single taps stay snappy.
      behavior: HitTestBehavior.translucent,
      onScaleStart: (_) => _pinchScale = 1.0,
      onScaleUpdate: (d) {
        if (d.pointerCount < 2) return;
        _pinchScale = d.scale;
      },
      onScaleEnd: (_) {
        if (_pinchScale > 1.15 && !_fillMode) {
          setState(() => _fillMode = true);
          _scheduleHideControls();
        } else if (_pinchScale < 0.85 && _fillMode) {
          setState(() => _fillMode = false);
          _scheduleHideControls();
        }
        _pinchScale = 1.0;
      },
      child: Stack(
      children: [
        // The video itself — wrapped so it never rebuilds on controller ticks.
        Positioned.fill(
          child: _fillMode
              ? FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: c.value.size.width,
                    height: c.value.size.height,
                    child: VideoPlayer(c),
                  ),
                )
              : Center(
                  child: AspectRatio(
                    aspectRatio: c.value.aspectRatio,
                    child: VideoPlayer(c),
                  ),
                ),
        ),
        // Full-width 50/50 hit zones. Single-tap toggles controls, double-tap
        // (fires on the second tap-down, not tap-up, for snappy YouTube feel).
        Positioned.fill(
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  onDoubleTapDown: (_) => _seekBy(-_seekStep),
                  onDoubleTap: () {},
                  // Left half — slide vertically to control brightness.
                  onVerticalDragStart: (_) =>
                      _onVerticalDragStart('brightness'),
                  onVerticalDragUpdate: (d) =>
                      _onVerticalDragUpdate(d.primaryDelta ?? 0),
                  onVerticalDragEnd: (_) => _onVerticalDragEnd(),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  onDoubleTapDown: (_) => _seekBy(_seekStep),
                  onDoubleTap: () {},
                  // Right half — slide vertically to control volume.
                  onVerticalDragStart: (_) => _onVerticalDragStart('volume'),
                  onVerticalDragUpdate: (d) =>
                      _onVerticalDragUpdate(d.primaryDelta ?? 0),
                  onVerticalDragEnd: (_) => _onVerticalDragEnd(),
                ),
              ),
            ],
          ),
        ),
        // Animated seek indicator — fades in / scales up / fades out.
        if (_seekIndicator != 0)
          IgnorePointer(
            child: Row(
              children: [
                Expanded(
                  child: _seekIndicator < 0
                      ? _animatedSeekOverlay(forward: false)
                      : const SizedBox.shrink(),
                ),
                Expanded(
                  child: _seekIndicator > 0
                      ? _animatedSeekOverlay(forward: true)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        // Brightness / volume drag indicator.
        if (_vDragKind != null)
          IgnorePointer(child: Center(child: _verticalDragIndicator())),
        // Captions — only this strip rebuilds as the caption text changes.
        Positioned(
          left: 0,
          right: 0,
          bottom: 80,
          child: IgnorePointer(
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: c,
              builder: (_, v, __) {
                if (v.caption.text.isEmpty) return const SizedBox.shrink();
                return Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    color: Colors.black54,
                    child: Text(
                      v.caption.text,
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // Buffering spinner — centred, shown whenever the player is waiting
        // for data mid-playback so it's clear the video is loading (not
        // frozen). Only this widget rebuilds on the buffering flag.
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: c,
              builder: (_, v, __) {
                if (!v.isBuffering) return const SizedBox.shrink();
                return const Center(
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      color: Color(0xFFEF0003),
                      strokeWidth: 3,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (_controlsVisible) _buildControls(c),
      ],
      ),
    );
  }

  // Loading screen — backdrop poster (if available) dimmed, with a small,
  // lightweight spinner. Wrapped in RepaintBoundary so the spinner repaints
  // in isolation from whatever else is going on in the tree.
  Widget _buildLoading() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.backdropPath != null)
          Image.network(
            'https://image.tmdb.org/t/p/w780${widget.backdropPath}',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: Colors.black),
            loadingBuilder: (_, child, prog) =>
                prog == null ? child : Container(color: Colors.black),
          ),
        Container(color: Colors.black.withValues(alpha: 0.55)),
        const Center(
          child: RepaintBoundary(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: Color(0xFFEF0003),
                strokeWidth: 2.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControls(VideoPlayerController c) {
    return Stack(
      children: [
        // Dim background — purely visual, lets taps fall through to the
        // gesture zones beneath so double-tap-to-seek still works.
        const Positioned.fill(
          child: IgnorePointer(child: ColoredBox(color: Colors.black45)),
        ),
        Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text(
                  widget.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
              IconButton(
                icon: Icon(
                  _fillMode ? Icons.zoom_in_map_rounded : Icons.zoom_out_map_rounded,
                  color: Colors.white,
                ),
                tooltip: _fillMode ? 'Fit to screen' : 'Zoom to fill',
                onPressed: _toggleFillMode,
              ),
              IconButton(
                icon: Icon(
                  _landscapeLocked
                      ? Icons.screen_lock_landscape
                      : Icons.screen_rotation,
                  color: Colors.white,
                ),
                tooltip: _landscapeLocked
                    ? 'Unlock rotation'
                    : 'Lock landscape',
                onPressed: _toggleLandscapeLock,
              ),
            ],
          ),
          const Spacer(),
          // Play/pause icon — only this widget rebuilds when isPlaying flips.
          // Hidden while buffering so the central loading spinner shows alone.
          Center(
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: c,
              builder: (_, v, __) {
                if (v.isBuffering) {
                  return const SizedBox(width: 64, height: 64);
                }
                return IconButton(
                  iconSize: 64,
                  icon: Icon(
                    v.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    color: Colors.white,
                  ),
                  onPressed: _togglePlay,
                );
              },
            ),
          ),
          const Spacer(),
          // Seek bar + time labels — isolated to one ValueListenableBuilder
          // so the rest of the player tree doesn't rebuild every frame.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: c,
              builder: (_, v, __) {
                final pos = v.position;
                final dur = v.duration;
                return Row(
                  children: [
                    Text(_fmt(pos),
                        style: const TextStyle(color: Colors.white)),
                    Expanded(
                      child: Slider(
                        activeColor: const Color(0xFFEF0003),
                        inactiveColor: Colors.white24,
                        min: 0,
                        max: dur.inMilliseconds
                            .toDouble()
                            .clamp(1, double.infinity),
                        value: pos.inMilliseconds
                            .clamp(0, dur.inMilliseconds)
                            .toDouble(),
                        onChanged: (val) =>
                            c.seekTo(Duration(milliseconds: val.toInt())),
                        onChangeEnd: (_) => _scheduleHideControls(),
                      ),
                    ),
                    Text(_fmt(dur),
                        style: const TextStyle(color: Colors.white)),
                    IconButton(
                      icon: const Icon(Icons.settings_rounded,
                          color: Colors.white),
                      tooltip: 'Settings',
                      onPressed: _showSettings,
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
        ),
      ],
    );
  }

  // Animated seek overlay — a soft radial glow on the tapped side with a
  // big fast-forward / rewind icon. Fades and scales in, holds briefly,
  // then fades out. The TweenAnimationBuilder's key changes each seek so
  // the animation re-fires for rapid double-double-taps.
  // Pill overlay shown while sliding for brightness (left) / volume (right):
  // an icon + a vertical fill bar reflecting the live 0..1 value.
  Widget _verticalDragIndicator() {
    final isBrightness = _vDragKind == 'brightness';
    final pct = (_vDragValue * 100).round();
    final IconData icon = isBrightness
        ? (_vDragValue < 0.5
            ? Icons.brightness_low_rounded
            : Icons.brightness_high_rounded)
        : (_vDragValue <= 0.0
            ? Icons.volume_off_rounded
            : _vDragValue < 0.5
                ? Icons.volume_down_rounded
                : Icons.volume_up_rounded);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 30),
          const SizedBox(height: 12),
          // Vertical fill bar.
          SizedBox(
            width: 6,
            height: 110,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Container(color: Colors.white24),
                  FractionallySizedBox(
                    heightFactor: _vDragValue.clamp(0.0, 1.0),
                    child: Container(color: const Color(0xFFEF0003)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$pct%',
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

  Widget _animatedSeekOverlay({required bool forward}) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('seek-$_seekCount'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) {
        // Phases: fade-in (0–0.25), hold (0.25–0.7), fade-out (0.7–1.0).
        final opacity = t < 0.25
            ? t / 0.25
            : (t > 0.7 ? (1 - t) / 0.3 : 1.0);
        final scale = 0.85 + (Curves.easeOutBack.transform(t.clamp(0, 1)) * 0.15);
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            alignment: forward ? Alignment.centerRight : Alignment.centerLeft,
            child: child,
          ),
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center:
                forward ? const Alignment(0.6, 0) : const Alignment(-0.6, 0),
            radius: 0.9,
            colors: [
              Colors.white.withValues(alpha: 0.18),
              Colors.white.withValues(alpha: 0.06),
              Colors.transparent,
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        child: Align(
          alignment: forward
              ? const Alignment(0.5, 0)
              : const Alignment(-0.5, 0),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.25),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  forward
                      ? Icons.fast_forward_rounded
                      : Icons.fast_rewind_rounded,
                  color: Colors.white,
                  size: 48,
                ),
                const SizedBox(height: 4),
                const Text(
                  '10s',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
