import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:app_web_ui/services/pages/webview.dart';
import 'package:app_web_ui/services/server_vote_service.dart';
import 'package:app_web_ui/services/stream_servers.dart';
import 'package:app_web_ui/services/subtitle_service.dart';
import 'package:app_web_ui/shared/squeeze_button.dart';
import 'package:app_web_ui/stores/history_store.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:screen_brightness/screen_brightness.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// How the video frame is sized against the screen. Picked from Settings →
/// Video size (or the quick toggle in the top bar) and remembered across
/// videos.
enum _VideoFit {
  fit('Fit to screen',
      'Whole picture visible. Black bars where the shapes differ.',
      Icons.fit_screen_rounded),
  fill('Expand to fill',
      'Zooms in until there are no black bars. Crops the edges.',
      Icons.zoom_out_map_rounded),
  stretch('Stretch', 'Fills the screen exactly. May distort the picture.',
      Icons.open_in_full_rounded),
  original('Original size', 'Native video resolution, no scaling.',
      Icons.crop_original_rounded);

  const _VideoFit(this.label, this.description, this.icon);
  final String label;
  final String description;
  final IconData icon;
}

class NativePlayerPage extends StatefulWidget {
  final String videoUrl;
  final Map<String, String> httpHeaders;
  final String? subtitleUrl;
  final List<String> subtitleUrls; // all captured subtitle URLs
  final String? sourceUrl;          // embed URL used by the webview
  final String? imdbId;             // for YIFY subtitle lookup
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
    this.imdbId,
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
  // Raw error from initialize() or the controller; mapped to a readable
  // message by [_errorText].
  Object? _error;
  bool _retriedWithoutHeaders = false;
  // The controller whose initialize() is still running. Reload and leaving
  // the page dispose it, so a slow load can't start playing audio after the
  // user has moved on.
  VideoPlayerController? _pendingController;
  // Bumped on every (re)load. A load that finishes after a newer one started,
  // or after the page closed, throws its controller away.
  int _loadGen = 0;
  // Where the next load starts playback. Tracks the last known position
  // while playing, so Reload resumes even after a mid-playback error (an
  // errored controller reports position 0).
  int _resumeSeconds = 0;
  // Set once the player has buffered for [_stallTimeout] while it should be
  // playing — shows the "still loading" banner with a Reload button.
  bool _stalled = false;
  Timer? _stallTimer;
  // Whether playback is meant to be running. The stall check uses this, not
  // value.isPlaying, which Android reports as false while buffering.
  bool _wantPlay = false;
  // App lifecycle: a backgrounded app can't finish loading (iOS suspends
  // it), so a load timeout that spans a trip to the background is retried —
  // on return, if the app is still away — instead of shown as an error.
  // Stalls aren't flagged, and playback isn't started, in the background.
  AppLifecycleListener? _lifecycle;
  bool _inForeground = true;
  bool _loadSawBackground = false;
  bool _retryOnResume = false;

  static const Duration _initTimeout = Duration(seconds: 30);
  static const Duration _stallTimeout = Duration(seconds: 20);

  // Visual feedback for double-tap seek (-10s / +10s).
  Timer? _seekIndicatorTimer;
  int _seekIndicator = 0; // -1 = left arrow, 1 = right arrow, 0 = hidden
  int _seekCount = 0;     // increments each seek so the animation re-fires

  // How the frame is sized against the screen. The saved choice loads
  // asynchronously in initState; [_userPickedFit] stops that load from
  // overriding a pick the user made in the meantime.
  _VideoFit _videoFit = _VideoFit.fit;
  bool _userPickedFit = false;
  static const String _videoFitPrefKey = 'player_video_fit';
  // Label flashed on screen right after the size mode changes.
  String? _fitToast;
  Timer? _fitToastTimer;

  // Video frame size in pixels, as reported at load. iOS reports an HLS
  // stream's size only once, at load, and often as 0×0 — which made the
  // frame fall back to a 1:1 box (squashed picture, wide black bars). On
  // iOS the video is now drawn by AVPlayerLayer, which keeps the real shape
  // regardless; see [_createController] and [_buildVideo].
  Size? _videoSize;
  // Largest resolution the stream offers, from its video tracks. Used for
  // "Original size": adaptive streams usually start on a lower rendition,
  // so the size reported at load can be smaller than what plays later.
  Size? _maxVideoSize;

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

  void _setVideoFit(_VideoFit fit) {
    _userPickedFit = true;
    _fitToastTimer?.cancel();
    setState(() {
      _videoFit = fit;
      _fitToast = fit.label;
    });
    _fitToastTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _fitToast = null);
    });
    SharedPreferences.getInstance()
        .then((p) => p.setString(_videoFitPrefKey, fit.name))
        .catchError((_) => false);
    _scheduleHideControls();
  }

  // Quick toggle in the top bar — steps through the modes in order, skipping
  // any this stream can't show.
  void _cycleVideoFit() {
    const modes = _VideoFit.values;
    var next = _effectiveFit;
    do {
      next = modes[(next.index + 1) % modes.length];
    } while (_modeUnavailable(next));
    _setVideoFit(next);
  }

  // Whether [f] can't be shown for the playing stream (decided once a video
  // is playing; until then every mode stays pickable). "Original size"
  // needs the resolution. On iOS "Stretch" needs the frame's shape too:
  // AVPlayerLayer would just letterbox inside a guessed one.
  bool _modeUnavailable(_VideoFit f) {
    if (_controller == null) return false;
    switch (f) {
      case _VideoFit.original:
        return (_maxVideoSize ?? _videoSize) == null;
      case _VideoFit.stretch:
        return Platform.isIOS && _videoAspect == null;
      case _VideoFit.fit:
      case _VideoFit.fill:
        return false;
    }
  }

  // The mode actually in effect. A saved mode this stream can't show is
  // displayed as Fit, but stays saved for the next video.
  _VideoFit get _effectiveFit =>
      _modeUnavailable(_videoFit) ? _VideoFit.fit : _videoFit;

  Future<void> _loadSavedVideoFit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved =
          _VideoFit.values.asNameMap()[prefs.getString(_videoFitPrefKey)];
      if (saved == null || !mounted || _userPickedFit) return;
      setState(() => _videoFit = saved);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _resumeSeconds = widget.initialProgressSeconds;
    _activeSubtitleUrl = widget.subtitleUrl;
    _activeSubLabel =
        widget.subtitleUrl != null ? _subtitleLabel(widget.subtitleUrl!) : 'Off';
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
    _loadSavedVideoFit();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycleChange);
    // Subtitles load alongside the video (not after it) so the Subtitles
    // menu is already usable while the player is still loading.
    _loadInitialSubtitle();
    _loadSubtitleTracks();
    _init();
  }

  void _onLifecycleChange(AppLifecycleState state) {
    // Inactive (Control Center, the app switcher, a call banner) still has
    // the app on screen; only hidden/paused count as away.
    final fg = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (fg == _inForeground) return;
    _inForeground = fg;
    if (!fg) {
      if (_controller == null) _loadSawBackground = true;
      _stallTimer?.cancel();
      _stallTimer = null;
      return;
    }
    if (_retryOnResume) {
      _retryOnResume = false;
      _init();
      return;
    }
    final c = _controller;
    if (c == null) return;
    // A load that finished while away was adopted without starting.
    if (_wantPlay && c.value.isInitialized && !c.value.isPlaying) c.play();
    // Re-check for a stall that was already under way.
    _onControllerUpdate();
  }

  bool _landscapeLocked = true;
  // Active subtitle key: a captured iframe URL OR a SubtitleTrack.key. null = Off.
  String? _activeSubtitleUrl;
  String _activeSubLabel = 'Off';
  // English-by-default tracks: YIFY (movies) + OpenSubtitles (movies + TV),
  // by IMDb id. Best-ranked first; the first is auto-selected as the default.
  List<SubtitleTrack> _subTracks = [];
  // True once the user manually picks a track, so the async English
  // auto-select doesn't override their choice.
  bool _userPickedSub = false;
  // The English default is auto-picked only once playback has started, so a
  // video that never plays doesn't spend OpenSubtitles download quota.
  bool _autoSubDone = false;
  // True while the English track list is still being fetched, so the menu
  // says "Searching…" rather than "No subtitles found".
  bool _subTracksLoading = true;
  // Rebuilds the open settings sheet (null when it's closed), so it shows
  // tracks and selections that arrive while it's open.
  StateSetter? _sheetSetState;
  // A subtitle file loaded from device storage (.srt/.vtt), if any.
  String? _localSubVtt; // converted WebVTT
  String? _localSubName; // file name, for the menu label
  // Parsed captions of the selected subtitle. Kept so they're applied to
  // whichever controller exists — a track picked while loading, or before a
  // Reload, still shows up once playback starts.
  WebVTTCaptionFile? _captionFile;

  /// Apply [vtt] (null = subtitles off) to the current controller, if any,
  /// and keep it for the next one. Returns false, leaving the current
  /// captions alone, if the text doesn't parse into any cues — the parser
  /// throws on some malformed timestamps and silently skips others, and
  /// nothing here may throw into the load path.
  bool _setCaptionVtt(String? vtt) {
    WebVTTCaptionFile? file;
    if (vtt != null) {
      try {
        file = WebVTTCaptionFile(vtt);
      } catch (e) {
        debugPrint('[SUBS] unreadable subtitle file: $e');
        return false;
      }
      if (file.captions.isEmpty) return false;
    }
    _captionFile = file;
    _controller?.setClosedCaptionFile(file == null ? null : Future.value(file));
    return true;
  }

  void _maybeAutoPickSub() {
    if (_autoSubDone ||
        _userPickedSub ||
        _subTracks.isEmpty ||
        _controller == null) {
      return;
    }
    _autoSubDone = true;
    _setTrack(_subTracks.first, userInitiated: false);
  }

  void _refreshSheet() => _sheetSetState?.call(() {});

  // A user-picked subtitle failed to load: point the menu back at what's
  // actually on screen and say so.
  void _subtitleFailed(String? prevKey, String prevLabel) {
    setState(() {
      _activeSubtitleUrl = prevKey;
      _activeSubLabel = prevLabel;
    });
    _refreshSheet();
    BotToast.showText(text: "Couldn't load that subtitle.");
  }

  /// Fetch the subtitle captured from the embed (if any) so it shows as soon
  /// as playback starts. An auto-selected English track replaces it later.
  Future<void> _loadInitialSubtitle() async {
    final url = widget.subtitleUrl;
    if (url == null || url.isEmpty) return;
    String? vtt;
    try {
      vtt = await _fetchVtt(url);
    } catch (_) {
      // Subtitles are best-effort; ignore failure.
    }
    if (!mounted || _activeSubtitleUrl != url) return;
    if (vtt != null && _setCaptionVtt(vtt)) return;
    // Nothing usable there — don't leave the menu claiming it's on.
    setState(() {
      _activeSubtitleUrl = null;
      _activeSubLabel = 'Off';
    });
    _refreshSheet();
  }

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

  /// Select a captured iframe subtitle URL, or `null` to turn subtitles off.
  /// Works while the player is still loading — it's applied once it starts.
  Future<void> _setSubtitle(String? url, {bool userInitiated = true}) async {
    if (userInitiated) _userPickedSub = true;
    final prevKey = _activeSubtitleUrl;
    final prevLabel = _activeSubLabel;
    setState(() {
      _activeSubtitleUrl = url;
      _activeSubLabel = url == null ? 'Off' : _subtitleLabel(url);
    });
    if (url == null) {
      _setCaptionVtt(null);
      return;
    }
    String? vtt;
    try {
      vtt = await _fetchVtt(url);
    } catch (_) {}
    // Drop it if another track was picked while this one downloaded.
    if (!mounted || _activeSubtitleUrl != url) return;
    if (vtt == null || !_setCaptionVtt(vtt)) _subtitleFailed(prevKey, prevLabel);
  }

  /// Select a fetched subtitle track (YIFY or OpenSubtitles): resolve it to
  /// WebVTT via the service and apply it. An automatic pick only takes over
  /// once its file has downloaded, so the captured iframe subtitle keeps
  /// showing meanwhile — and stays if the download fails.
  Future<void> _setTrack(SubtitleTrack t, {bool userInitiated = true}) async {
    final prevKey = _activeSubtitleUrl;
    final prevLabel = _activeSubLabel;
    if (userInitiated) {
      _userPickedSub = true;
      setState(() {
        _activeSubtitleUrl = t.key;
        _activeSubLabel = t.label;
      });
    }
    String? vtt;
    try {
      vtt = await SubtitleService.instance.vttForTrack(t);
    } catch (_) {}
    if (!mounted) return;
    if (userInitiated) {
      // Drop it if another track was picked while this one downloaded.
      if (_activeSubtitleUrl != t.key) return;
      if (vtt == null || !_setCaptionVtt(vtt)) {
        _subtitleFailed(prevKey, prevLabel);
      }
      return;
    }
    // An automatic pick yields to anything the user chose meanwhile.
    if (_userPickedSub || vtt == null || !_setCaptionVtt(vtt)) return;
    setState(() {
      _activeSubtitleUrl = t.key;
      _activeSubLabel = t.label;
    });
    _refreshSheet();
  }

  /// Fetch English subtitle tracks for this title — YIFY for movies,
  /// OpenSubtitles for movies and TV episodes (by IMDb id from the detail
  /// response). The best one is auto-selected as the default once playback
  /// starts ([_maybeAutoPickSub]), unless the user already picked a track.
  Future<void> _loadSubtitleTracks() async {
    try {
      final id = widget.tmdbId;
      final mt = widget.mediaType;
      final imdb = widget.imdbId;
      if ((imdb == null || imdb.isEmpty) && id == null) {
        debugPrint('[SUBS] player: no imdbId/tmdbId — skipping subtitle fetch');
        return;
      }
      final tracks = await SubtitleService.instance.englishTracks(
        imdbId: imdb,
        tmdbId: id,
        mediaType: mt ?? 'movie',
        seasonNumber: widget.seasonNumber,
        episodeNumber: widget.episodeNumber,
      );
      debugPrint('[SUBS] player: ${tracks.length} english tracks '
          '(imdb=$imdb tmdb=$id s=${widget.seasonNumber} e=${widget.episodeNumber})');
      if (!mounted || tracks.isEmpty) return;
      setState(() => _subTracks = tracks);
      _maybeAutoPickSub();
    } catch (e) {
      debugPrint('[SUBS] player: track fetch failed: $e');
    } finally {
      if (mounted) {
        setState(() => _subTracksLoading = false);
        _refreshSheet();
      }
    }
  }

  /// Let the user pick a subtitle file (.srt/.vtt) from device storage,
  /// convert it to WebVTT, and apply it.
  Future<void> _pickLocalSubtitle() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'vtt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.first;
      var bytes = f.bytes;
      if (bytes == null && f.path != null) {
        bytes = await File(f.path!).readAsBytes();
      }
      if (bytes == null) return;
      // SRT files are commonly Windows-1252/latin1; allowMalformed keeps them
      // readable either way.
      final text = utf8.decode(bytes, allowMalformed: true);
      if (!text.contains('-->')) {
        BotToast.showText(text: 'That file has no subtitle cues.');
        return;
      }
      final vtt = text.trimLeft().startsWith('WEBVTT')
          ? text
          : SubtitleService.instance.srtToVtt(text);
      // Parse up front: a malformed file throws here (→ the toast below)
      // instead of being stored and failing every time it's applied.
      if (WebVTTCaptionFile(vtt).captions.isEmpty) {
        BotToast.showText(text: 'That file has no subtitle cues.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _localSubVtt = vtt;
        _localSubName = f.name;
      });
      _applyLocalSubtitle();
    } catch (e) {
      BotToast.showText(text: "Couldn't load that subtitle file.");
    }
  }

  /// Apply the loaded local subtitle file to the player.
  void _applyLocalSubtitle() {
    final vtt = _localSubVtt;
    if (vtt == null || !_setCaptionVtt(vtt)) return;
    _userPickedSub = true;
    setState(() {
      _activeSubtitleUrl = 'local';
      _activeSubLabel = _localSubName ?? 'Local file';
    });
  }

  // Usable before the video has loaded and after it fails: every option
  // here (source, subtitles, video size, reload) works without a controller.
  void _showSettings({String initialView = 'main'}) {
    _hideTimer?.cancel();
    final currentServer =
        widget.sourceUrl == null ? null : streamServerForUrl(widget.sourceUrl!);
    // 'main' | 'source' | 'subtitles' | 'size' — drives the in-place
    // drill-down.
    String view = initialView;

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
            _sheetSetState = (fn) {
              if (ctx.mounted) setSheet(fn);
            };
            final subtitleValue = _activeSubLabel;

            Widget header(String title, IconData icon,
                    {bool showBack = false}) =>
                Padding(
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
                        icon,
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

            final Widget headerWidget;
            final List<Widget> children;
            if (view == 'source') {
              headerWidget = header('Source', Icons.dns_rounded, showBack: true);
              children = [
                for (final s in streamServers)
                  _settingsRow(
                    label: s.name,
                    icon: Icons.play_circle_outline_rounded,
                    selected: s == currentServer,
                    onTap: () => _switchServer(s),
                  ),
                const SizedBox(height: 8),
              ];
            } else if (view == 'size') {
              headerWidget =
                  header('Video size', Icons.aspect_ratio_rounded, showBack: true);
              children = [
                for (final f in _VideoFit.values)
                  if (!_modeUnavailable(f))
                    _settingsRow(
                      label: f.label,
                      description: f.description,
                      icon: f.icon,
                      selected: f == _effectiveFit,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _setVideoFit(f);
                      },
                    ),
                const SizedBox(height: 8),
              ];
            } else if (view == 'subtitles') {
              headerWidget =
                  header('Subtitles', Icons.subtitles_rounded, showBack: true);
              children = [
                _settingsRow(
                  label: 'Off',
                  icon: Icons.subtitles_off_rounded,
                  selected: _activeSubtitleUrl == null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _setSubtitle(null);
                  },
                ),
                // Fetched subtitles (English-first, by IMDb id): YIFY for
                // movies, OpenSubtitles for movies + TV. Default when present.
                for (final t in _subTracks)
                  _settingsRow(
                    label: t.label,
                    icon: Icons.subtitles_rounded,
                    selected: _activeSubtitleUrl == t.key,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _setTrack(t);
                    },
                  ),
                // Tracks captured from the embed iframe, if any.
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
                // A subtitle file the user loaded from device storage.
                if (_localSubVtt != null)
                  _settingsRow(
                    label: _localSubName ?? 'Local file',
                    icon: Icons.description_rounded,
                    selected: _activeSubtitleUrl == 'local',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _applyLocalSubtitle();
                    },
                  ),
                if (_subTracks.isEmpty &&
                    widget.subtitleUrls.isEmpty &&
                    _localSubVtt == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Text(
                      _subTracksLoading
                          ? 'Searching for subtitles…'
                          : 'No subtitles found for this title.',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12.5),
                    ),
                  ),
                const Divider(color: Colors.white12, height: 8),
                // Load a subtitle file (.srt/.vtt) from device storage.
                _settingsRow(
                  label: 'Add subtitle file…',
                  icon: Icons.upload_file_rounded,
                  selected: false,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickLocalSubtitle();
                  },
                ),
                const SizedBox(height: 8),
              ];
            } else {
              // Main menu — options that drill into their lists, plus Reload.
              headerWidget = header('Settings', Icons.settings_rounded);
              children = [
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
                _settingsNavRow(
                  icon: Icons.aspect_ratio_rounded,
                  label: 'Video size',
                  value: _effectiveFit.label,
                  onTap: () => setSheet(() => view = 'size'),
                ),
                // A missing download won't come back by reloading.
                if (_error is! FileSystemException)
                  _settingsRow(
                    label: 'Reload video',
                    icon: Icons.refresh_rounded,
                    selected: false,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _reload();
                    },
                  ),
                const SizedBox(height: 8),
              ];
            }

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pinned header — stays put while only the list scrolls.
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: headerWidget,
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: children,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      _sheetSetState = null;
      _scheduleHideControls();
    });
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
    String? description,
  }) {
    final title = Text(
      label,
      style: TextStyle(
        color: selected ? const Color(0xFFEF0003) : Colors.white,
        fontSize: 14.5,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
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
              child: description == null
                  ? title
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                      ],
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
          initialProgressSeconds: _currentPositionSeconds(),
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
          initialProgressSeconds: _currentPositionSeconds(),
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
    final gen = ++_loadGen;
    _loadSawBackground = !_inForeground;
    try {
      await _startController(_createController(withHeaders: true), gen);
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      if (e is TimeoutException && _loadSawBackground) {
        _retryAfterBackground();
        return;
      }
      // iOS: a first init with headers sometimes fails even when the same
      // URL plays fine without them (or with only Referer). Retry once bare.
      // Not after a timeout — that's a dead source, not a header problem.
      if (Platform.isIOS &&
          widget.localFilePath == null &&
          !_retriedWithoutHeaders &&
          e is! TimeoutException) {
        _retriedWithoutHeaders = true;
        _loadSawBackground = !_inForeground;
        try {
          await _startController(_createController(withHeaders: false), gen);
          return;
        } catch (e2) {
          if (!mounted || gen != _loadGen) return;
          if (e2 is TimeoutException && _loadSawBackground) {
            // The bare attempt never got a fair run; redo both attempts.
            _retriedWithoutHeaders = false;
            _retryAfterBackground();
            return;
          }
        }
      }
      debugPrint('[PLAYER] load failed: $e');
      setState(() => _error = e);
    }
  }

  // A load timeout that spanned a trip to the background says nothing about
  // the source — iOS suspends the app meanwhile — so the load is redone:
  // now if the app is back, otherwise as soon as it returns.
  void _retryAfterBackground() {
    if (_inForeground) {
      _init();
    } else {
      _retryOnResume = true;
    }
  }

  VideoPlayerController _createController({required bool withHeaders}) {
    // iOS draws through AVPlayerLayer (a platform view) instead of a Flutter
    // texture. It keeps the frame's real shape by itself, even when the
    // plugin reports no size for an HLS stream (see [_videoSize]); a texture
    // just stretches to whatever box it's given.
    final viewType =
        Platform.isIOS ? VideoViewType.platformView : VideoViewType.textureView;
    // Local file → use VideoPlayerController.file for MP4, networkUrl with
    // a file:// URI for HLS (ExoPlayer recognises the manifest extension).
    // Otherwise fall back to the network constructor with captured headers.
    final local = widget.localFilePath;
    if (local != null) {
      if (!File(local).existsSync()) {
        throw FileSystemException('Downloaded file not found', local);
      }
      return local.endsWith('.m3u8')
          ? VideoPlayerController.networkUrl(Uri.file(local),
              viewType: viewType)
          : VideoPlayerController.file(File(local), viewType: viewType);
    }
    final lower = widget.videoUrl.toLowerCase();
    final formatHint = lower.contains('.m3u8')
        ? VideoFormat.hls
        : lower.contains('.mpd')
            ? VideoFormat.dash
            : null;
    return VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
      formatHint: formatHint,
      httpHeaders: withHeaders ? _playbackHeaders() : const {},
      viewType: viewType,
    );
  }

  Map<String, String> _playbackHeaders() {
    // Browser-like headers. iOS AVPlayer is picky: Android UA + sec-*
    // headers from WebView interception often 403, and Referer must be
    // the embed origin (not the CDN host).
    final headers = <String, String>{};
    widget.httpHeaders.forEach((k, v) {
      if (k.toLowerCase().startsWith('sec-')) return;
      headers[k] = v;
    });
    final src = widget.sourceUrl;
    if (src != null) {
      final u = Uri.tryParse(src);
      if (u != null && u.hasScheme && u.host.isNotEmpty) {
        final origin = '${u.scheme}://${u.host}';
        headers['Referer'] = '$origin/';
        headers['Origin'] = origin;
      }
    }
    headers['User-Agent'] = Platform.isIOS
        ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
            'Mobile/15E148 Safari/604.1'
        : 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
    return headers;
  }

  /// Initialise [controller], seek to the resume point and start playback,
  /// then make it the page's controller. Throws (after disposing it) if it
  /// fails or doesn't start within [_initTimeout]. If the page closed or a
  /// newer load started meanwhile ([gen] is stale), it's quietly discarded.
  Future<void> _startController(
      VideoPlayerController controller, int gen) async {
    bool stale() => !mounted || gen != _loadGen;
    _pendingController = controller;
    try {
      // AVPlayer can sit "loading" forever on a dead stream, and the resume
      // seek waits for the segments at that point — cap the whole start-up.
      await () async {
        await controller.initialize();
        if (!stale() && _resumeSeconds > 0) {
          await controller.seekTo(Duration(seconds: _resumeSeconds));
        }
        // Don't start playing in the background (on Android that's audible
        // and takes audio focus) — the lifecycle handler starts it on return.
        if (!stale() && _inForeground) await controller.play();
      }()
          .timeout(_initTimeout);
      // An error during the seek or play() doesn't throw — it leaves the
      // controller uninitialised and silent. Treat that as a failed load.
      if (!stale() &&
          (controller.value.hasError || !controller.value.isInitialized)) {
        throw PlatformException(
          code: 'VideoError',
          message: controller.value.errorDescription ?? 'Playback did not start',
        );
      }
    } catch (_) {
      if (identical(_pendingController, controller)) _pendingController = null;
      controller.dispose();
      rethrow;
    }
    if (identical(_pendingController, controller)) _pendingController = null;
    if (stale()) {
      controller.dispose();
      return;
    }

    // NOTE: we deliberately do NOT record a server "success" here — play()
    // returning doesn't mean playback works (a source exception can still
    // fire). _onControllerUpdate records the vote only once real progress
    // is observed, so we don't reward sources that error immediately.

    // Watch for errors that surface AFTER initialize() succeeds — e.g.
    // ExoPlayer rejecting segments/codecs once playback actually starts.
    // initialize() returning fine doesn't guarantee the source plays.
    controller.addListener(_onControllerUpdate);
    _wantPlay = true;
    final size = controller.value.size;
    setState(() {
      _controller = controller;
      _error = null;
      _stalled = false;
      _controlsVisible = true;
      if (size.width > 0 && size.height > 0) _videoSize = size;
    });
    // The controller is live from here on. Nothing below may throw: an
    // exception would send _init down its retry/error path and orphan this
    // controller, still playing.
    try {
      _resolveVideoSize(controller);
      // Apply whichever subtitle is selected — it may have been picked (or
      // finished downloading) while the video was loading.
      final captions = _captionFile;
      if (captions != null) {
        controller.setClosedCaptionFile(Future.value(captions));
      }
      _maybeAutoPickSub();
      _refreshSheet();
      _saveTimer?.cancel();
      _saveTimer =
          Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress());
      _scheduleHideControls();
      // Catch a stall that began before the listener was attached (e.g. at
      // the resume point) — otherwise nothing re-checks until a value change.
      _onControllerUpdate();
    } catch (e) {
      debugPrint('[PLAYER] post-start setup failed: $e');
    }
  }

  // Asks the stream for its video tracks (HLS variants list their
  // resolution) and keeps the largest. It sizes "Original size", and stands
  // in for the frame size when the platform reported none.
  Future<void> _resolveVideoSize(VideoPlayerController c) async {
    try {
      if (!c.isVideoTrackSupportAvailable()) return;
      final tracks = await c.getVideoTracks();
      Size? largest;
      for (final t in tracks) {
        final w = t.width ?? 0;
        final h = t.height ?? 0;
        if (w <= 0 || h <= 0) continue;
        if (largest == null || w * h > largest.width * largest.height) {
          largest = Size(w.toDouble(), h.toDouble());
        }
      }
      if (largest == null || !mounted || !identical(c, _controller)) return;
      final found = largest;
      setState(() => _maxVideoSize = found);
      _refreshSheet();
    } catch (_) {}
  }

  // Width ÷ height of the frame, or null while it's unknown.
  double? get _videoAspect {
    final s = _videoSize ?? _maxVideoSize;
    if (s == null || s.width <= 0 || s.height <= 0) return null;
    return s.width / s.height;
  }

  /// Where playback is (or last was), in seconds — used to resume after a
  /// Reload, a source switch, or falling back to the web player.
  int _currentPositionSeconds() {
    final c = _controller;
    if (c != null && c.value.isInitialized) return c.value.position.inSeconds;
    return _resumeSeconds;
  }

  /// Tear down the current player and load the same video again from where
  /// it stopped. Used by the error screen, the stall banner and Settings.
  void _reload() {
    _saveProgress();
    _resumeSeconds = _currentPositionSeconds();
    _saveTimer?.cancel();
    _stallTimer?.cancel();
    _stallTimer = null;
    _wantPlay = false;
    _retryOnResume = false;
    _pendingController?.dispose();
    _pendingController = null;
    final old = _controller;
    old?.removeListener(_onControllerUpdate);
    setState(() {
      _controller = null;
      _error = null;
      _stalled = false;
      _controlsVisible = true;
    });
    // Dispose after this frame, once the old VideoPlayer widget has left the
    // tree and dropped its listeners.
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    _retriedWithoutHeaders = false;
    _init();
  }

  bool _votedSuccess = false;

  // Fires on every controller value change. Three jobs:
  //  1. Surface a source error that only appears once playback starts.
  //  2. Flag a stall — buffering for [_stallTimeout] while it should be
  //     playing — so the user gets a Reload option instead of a spinner.
  //  3. Record the server "success" vote once real progress is seen (≥3s),
  //     so sources that error immediately don't get rewarded as defaults.
  void _onControllerUpdate() {
    final c = _controller;
    if (c == null) return;
    // Track the position while it's valid: an errored controller reports 0,
    // and Reload must resume where playback actually stopped.
    if (c.value.isInitialized) _resumeSeconds = c.value.position.inSeconds;
    if (c.value.hasError && _error == null) {
      _wantPlay = false;
      _stallTimer?.cancel();
      _stallTimer = null;
      setState(() =>
          _error = c.value.errorDescription ?? 'Playback error');
      return;
    }
    if (c.value.isCompleted) _wantPlay = false;
    if (c.value.isBuffering && _wantPlay && _inForeground) {
      _stallTimer ??= Timer(_stallTimeout, () {
        if (mounted) setState(() => _stalled = true);
      });
    } else if (_stallTimer != null || _stalled) {
      _stallTimer?.cancel();
      _stallTimer = null;
      if (_stalled) setState(() => _stalled = false);
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
      // WebVTT is always UTF-8, but servers rarely send a charset, and
      // res.body then decodes as Latin-1 (garbling accents and ’ quotes).
      final body = utf8.decode(res.bodyBytes, allowMalformed: true);
      // A captured "subtitle" URL often turns out to be an HTML page or some
      // non-subtitle resource — never feed that to the caption parser.
      if (looksLikeHtml(body) ||
          (!body.contains('-->') && !body.trimLeft().startsWith('WEBVTT'))) {
        return null;
      }
      return body.trimLeft().startsWith('WEBVTT')
          ? body
          : SubtitleService.instance.srtToVtt(body);
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
    // Nothing to hide until a video is playing; the controls are shown fresh
    // when one starts.
    if (_controller == null) return;
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
      _wantPlay = false;
      c.pause();
    } else {
      _wantPlay = true;
      c.play();
    }
    _scheduleHideControls();
  }

  @override
  void dispose() {
    _loadGen++; // any load still running discards its controller
    _lifecycle?.dispose();
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _seekIndicatorTimer?.cancel();
    _vDragHideTimer?.cancel();
    _stallTimer?.cancel();
    _fitToastTimer?.cancel();
    // Hand brightness control back to the system.
    ScreenBrightness().resetApplicationScreenBrightness().catchError((_) {});
    _saveProgress();
    _pendingController?.dispose();
    _controller?.removeListener(_onControllerUpdate);
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
    // No page-wide SafeArea: the video is drawn edge to edge (on iPhones a
    // SafeArea kept it clear of the Dynamic Island and home indicator, so
    // even "fill" left black bars). Controls and text get their own
    // SafeArea instead.
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) return _buildError();
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return _buildLoading();
    }
    final safe = MediaQuery.paddingOf(context);
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
        // Pinch out → expand to fill; pinch in → back to fit.
        final zoomedOut =
            _videoFit == _VideoFit.fit || _videoFit == _VideoFit.original;
        if (_pinchScale > 1.15 && zoomedOut) {
          _setVideoFit(_VideoFit.fill);
        } else if (_pinchScale < 0.85 && !zoomedOut) {
          _setVideoFit(_VideoFit.fit);
        }
        _pinchScale = 1.0;
      },
      child: Stack(
      children: [
        // The video itself — wrapped so it never rebuilds on controller ticks.
        Positioned.fill(child: _buildVideo(c)),
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
        // Kept inside the safe area (the video itself is edge to edge).
        Positioned(
          left: safe.left,
          right: safe.right,
          bottom: 80 + safe.bottom,
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
        // These two sit above the controls so their dimmed backdrop
        // doesn't grey them out.
        // Flashes the new mode's name after a video size change.
        if (_fitToast != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: const Alignment(0, -0.6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_effectiveFit.icon, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _fitToast!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // Stuck buffering — offer a reload instead of an endless spinner.
        if (_stalled)
          Positioned.fill(
            child: SafeArea(
              child: Align(
                alignment: const Alignment(0, 0.45),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Taking longer than usual…',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(width: 10),
                      _pillButton(
                        icon: Icons.refresh_rounded,
                        label: 'Reload',
                        onTap: _reload,
                        primary: true,
                        dense: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
      ),
    );
  }

  // Lays the frame out for the current size mode, centred and clipped to the
  // screen. Every mode builds the same widget shape — only the frame size
  // and scale change — so switching never recreates the iOS platform view
  // (which would flash black).
  //
  // Sized from [_videoAspect], not controller.value.aspectRatio (1.0 when
  // the platform reported no size), assuming 16:9 while it's unknown. On
  // iOS, Fit hands AVPlayerLayer the whole screen and lets it letterbox at
  // the real shape; an Android texture stretches to its box instead.
  Widget _buildVideo(VideoPlayerController c) {
    return LayoutBuilder(
      builder: (context, box) {
        final screen = box.biggest;
        final aspect = _videoAspect ?? 16 / 9;
        Size frameFor({required bool cover}) {
          final w = cover
              ? math.max(screen.width, screen.height * aspect)
              : math.min(screen.width, screen.height * aspect);
          return Size(w, w / aspect);
        }

        var frame = frameFor(cover: false);
        var scaleX = 1.0;
        var scaleY = 1.0;
        switch (_effectiveFit) {
          case _VideoFit.fit:
            // AVPlayerLayer letterboxes at the true shape by itself, so on
            // iOS this is right even if the reported size is missing or off.
            if (Platform.isIOS) frame = screen;
          case _VideoFit.fill:
            frame = frameFor(cover: true);
          case _VideoFit.stretch:
            // Scale the correctly shaped frame out to the screen. Scaling,
            // rather than sizing the box to the screen, is what makes
            // AVPlayerLayer stretch instead of letterboxing.
            scaleX = screen.width / frame.width;
            scaleY = screen.height / frame.height;
          case _VideoFit.original:
            // One video pixel per screen pixel; cropped if it's larger.
            var px = _maxVideoSize ?? _videoSize;
            // Track sizes are coded sizes; the reported size is the display
            // size (after pixel aspect and rotation). If their shapes
            // disagree, trust the display size.
            final shown = _videoSize;
            if (px != null &&
                shown != null &&
                (px.aspectRatio - shown.aspectRatio).abs() > 0.02) {
              px = shown;
            }
            if (px != null) {
              final dpr = MediaQuery.devicePixelRatioOf(context);
              frame = Size(px.width / dpr, px.height / dpr);
            }
        }
        return ClipRect(
          child: OverflowBox(
            minWidth: 0,
            minHeight: 0,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(scaleX, scaleY, 1),
              child: SizedBox(
                width: frame.width,
                height: frame.height,
                child: VideoPlayer(c),
              ),
            ),
          ),
        );
      },
    );
  }

  // Back + title + [actions]. Shared by the loading, error and playback
  // screens so Back and Settings are always reachable.
  Widget _topBar(List<Widget> actions) {
    return Row(
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
        ...actions,
      ],
    );
  }

  Widget _settingsButton() {
    return IconButton(
      icon: const Icon(Icons.settings_rounded, color: Colors.white),
      tooltip: 'Settings',
      onPressed: _showSettings,
    );
  }

  // Rounded pill button, matching the player-page failure screen.
  Widget _pillButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
    bool dense = false,
  }) {
    return SqueezeButton(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 14 : 20,
          vertical: dense ? 8 : 11,
        ),
        decoration: BoxDecoration(
          color: primary
              ? const Color(0xFFEF0003)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(100),
          border: primary
              ? null
              : Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1.2,
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: dense ? 16 : 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: dense ? 13 : 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Turns a raw player error into a title + plain-language message. Matched
  // on the text because AVFoundation (iOS) and ExoPlayer (Android) word the
  // same failures very differently.
  (String, String) _errorText(Object e) {
    if (e is TimeoutException) {
      return (
        'Video took too long to start',
        'The source didn\'t respond in time.',
      );
    }
    if (e is FileSystemException) {
      return (
        'Download not found',
        'This file is no longer on your device. Delete it from Downloads '
            'and download it again.',
      );
    }
    final s = e.toString().toLowerCase();
    bool has(List<String> keys) => keys.any(s.contains);
    if (has([
      'offline',
      'internet connection',
      'network connection was lost',
      '-1009',
      '-1005',
      'failed host lookup',
      'unknownhost',
      'unable to connect',
      'socketexception',
    ])) {
      return (
        'No internet connection',
        'Check your connection and try again.',
      );
    }
    if (has(['403', 'forbidden', '401', 'unauthorized'])) {
      return (
        'The source refused this video',
        'The video link was rejected or has expired.',
      );
    }
    if (has(['404', '410', 'not found'])) {
      return (
        'Video link not found',
        'This video link is no longer available.',
      );
    }
    if (has(['timed out', '-1001'])) {
      return (
        'Connection timed out',
        'The server took too long to respond.',
      );
    }
    if (has([
      'cannot decode',
      'cannot open',
      'not supported',
      'unsupported',
      'unrecognizedinputformat',
      '-11821',
      '-11828',
      '-11829',
    ])) {
      return (
        'Format not supported',
        'This video\'s format can\'t be played on this device.',
      );
    }
    return (
      'Playback failed',
      'Something went wrong while playing this video.',
    );
  }

  // Technical detail shown in small print under the message, for reports.
  String _errorDetail(Object e) {
    if (e is PlatformException) return e.message ?? e.code;
    if (e is TimeoutException) {
      return 'No response after ${_initTimeout.inSeconds}s';
    }
    return e.toString();
  }

  // Error screen — readable reason plus every way forward: reload (resumes
  // where it stopped), switch source, or the web player.
  Widget _buildError() {
    final error = _error!;
    final (title, message) = _errorText(error);
    final isLocal = widget.localFilePath != null;
    final canSwitch =
        !isLocal && widget.tmdbId != null && widget.mediaType != null;
    final canIframe = !isLocal && widget.sourceUrl != null;
    // A missing download won't come back by reloading.
    final canReload = error is! FileSystemException;
    return SafeArea(
      child: Column(
        children: [
          _topBar([_settingsButton()]),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFEF0003),
                      size: 44,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12.5),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        if (canReload)
                          _pillButton(
                            icon: Icons.refresh_rounded,
                            label: 'Reload',
                            onTap: _reload,
                            primary: true,
                          )
                        else
                          _pillButton(
                            icon: Icons.arrow_back_rounded,
                            label: 'Back',
                            onTap: () => Navigator.of(context).pop(),
                            primary: true,
                          ),
                        if (canSwitch)
                          _pillButton(
                            icon: Icons.dns_rounded,
                            label: 'Change source',
                            onTap: () => _showSettings(initialView: 'source'),
                          ),
                        if (canIframe)
                          _pillButton(
                            icon: Icons.public_rounded,
                            label: 'Web player',
                            onTap: _openIframeFallback,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _errorDetail(error),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white30, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
        // Back and Settings stay available while loading — source,
        // subtitles and video size can all be changed before playback.
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: _topBar([_settingsButton()]),
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
        SafeArea(
        child: Column(
        children: [
          _topBar([
            // Steps through the video size modes; the full list with
            // descriptions is in Settings → Video size.
            IconButton(
              icon: Icon(_effectiveFit.icon, color: Colors.white),
              tooltip: 'Video size: ${_effectiveFit.label}',
              onPressed: _cycleVideoFit,
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
          ]),
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
