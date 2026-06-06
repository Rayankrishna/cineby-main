import 'package:app_web_ui/services/download_service.dart';
import 'package:app_web_ui/services/stream_extractor.dart';
import 'package:mobx/mobx.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

part 'download_store.g.dart';

class ActiveDownload {
  final int tmdbId;
  final String mediaType;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? title;
  double progress; // 0.0..1.0
  String? error;
  // 'extracting' before the stream URL has been captured, null during the
  // actual segment download. UI uses this to switch between "Extracting…"
  // and the percentage label.
  String? phase;

  ActiveDownload({
    required this.tmdbId,
    required this.mediaType,
    this.seasonNumber,
    this.episodeNumber,
    this.title,
    this.progress = 0,
    this.error,
    this.phase,
  });

  String get key {
    if (mediaType == 'tv' && seasonNumber != null && episodeNumber != null) {
      return '${tmdbId}_s${seasonNumber}e$episodeNumber';
    }
    return tmdbId.toString();
  }
}

class DownloadStore = _DownloadStore with _$DownloadStore;

abstract class _DownloadStore with Store {
  final DownloadService _service = DownloadService.instance;

  // Per-active-download cancel tokens, keyed by ActiveDownload.key.
  final Map<String, DownloadCancelToken> _tokens = {};

  @observable
  ObservableList<ActiveDownload> active = ObservableList<ActiveDownload>();

  @observable
  ObservableList<DownloadedItem> completed = ObservableList<DownloadedItem>();

  @observable
  bool isLoading = false;

  @action
  Future<void> refresh() async {
    isLoading = true;
    try {
      final items = await _service.list();
      completed = ObservableList.of(items);
    } finally {
      isLoading = false;
    }
  }

  // Enable the wakelock for the duration of any active download. This is
  // what lets HLS segment fetches keep running when the user backgrounds
  // the app — without it, Android can suspend the Dart isolate after a few
  // dozen seconds of inactivity. Enabled on first active, disabled when
  // the queue is empty.
  Future<void> _refreshWakelock() async {
    try {
      if (active.isEmpty) {
        await WakelockPlus.disable();
      } else {
        if (!await WakelockPlus.enabled) {
          await WakelockPlus.enable();
        }
      }
    } catch (_) {
      // Wakelock plugin can throw on platforms that don't support it
      // (web/desktop). Best-effort.
    }
  }

  @action
  Future<void> start({
    required int tmdbId,
    required String mediaType,
    required String url,
    required Map<String, String> headers,
    int? seasonNumber,
    int? episodeNumber,
    String? title,
    String? posterPath,
    String? backdropPath,
  }) async {
    final item = ActiveDownload(
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      title: title,
    );
    // Replace any existing active entry for the same key so a re-download
    // doesn't show two side-by-side progress rows.
    active.removeWhere((a) => a.key == item.key);
    active.add(item);
    final token = DownloadCancelToken();
    _tokens[item.key] = token;
    _refreshWakelock();

    try {
      await _service.download(
        tmdbId: tmdbId,
        mediaType: mediaType,
        url: url,
        headers: headers,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        cancelToken: token,
        onProgress: (p) {
          // Mutating a field on an item already in the list isn't tracked
          // automatically by MobX; replace the entry so observers rebuild.
          final idx = active.indexWhere((a) => a.key == item.key);
          if (idx < 0) return;
          active[idx] = ActiveDownload(
            tmdbId: tmdbId,
            mediaType: mediaType,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            title: title,
            progress: p,
          );
        },
        meta: {
          if (title != null) 'title': title,
          if (posterPath != null) 'posterPath': posterPath,
          if (backdropPath != null) 'backdropPath': backdropPath,
        },
      );
      active.removeWhere((a) => a.key == item.key);
      await refresh();
    } catch (e) {
      // Cancellation → silently disappear; partial files have already been
      // cleaned up by cancel(). Any other error stays visible with its
      // last-known progress so the user can retry.
      if (e is DownloadCancelledException) {
        active.removeWhere((a) => a.key == item.key);
      } else {
        final idx = active.indexWhere((a) => a.key == item.key);
        if (idx >= 0) {
          active[idx] = ActiveDownload(
            tmdbId: tmdbId,
            mediaType: mediaType,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            title: title,
            progress: active[idx].progress,
            error: e.toString(),
          );
        }
      }
    } finally {
      _tokens.remove(item.key);
      _refreshWakelock();
    }
  }

  /// Kick off a download from an embed URL — runs extraction first, then
  /// the actual download. Designed to be called fire-and-forget from a UI
  /// tap so the user can back out of the detail page while it's in flight.
  /// An "Extracting…" placeholder shows up in the Downloads tab while the
  /// headless extractor is running, then morphs into the regular progress
  /// row once the manifest URL is captured.
  @action
  Future<void> startWithExtraction({
    required String embedUrl,
    required int tmdbId,
    required String mediaType,
    int? seasonNumber,
    int? episodeNumber,
    String? title,
    String? posterPath,
    String? backdropPath,
  }) async {
    final placeholder = ActiveDownload(
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      title: title,
      phase: 'extracting',
    );
    active.removeWhere((a) => a.key == placeholder.key);
    active.add(placeholder);
    _refreshWakelock();

    try {
      final extracted = await extractStream(embedUrl: embedUrl);
      // Drop the placeholder no matter what — start() below will add a
      // fresh active entry if extraction succeeded.
      active.removeWhere((a) => a.key == placeholder.key);
      if (extracted == null) {
        // Surface a transient error tile so the user knows it failed when
        // they next open the Downloads tab. dismissActiveError clears it.
        active.add(ActiveDownload(
          tmdbId: tmdbId,
          mediaType: mediaType,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
          title: title,
          error: 'Couldn\'t extract a stream from this source.',
        ));
        return;
      }
      await start(
        tmdbId: tmdbId,
        mediaType: mediaType,
        url: extracted.videoUrl,
        headers: extracted.headers,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        title: title,
        posterPath: posterPath,
        backdropPath: backdropPath,
      );
    } finally {
      _refreshWakelock();
    }
  }

  /// Cancel an in-progress download, wipe its half-downloaded files, and
  /// drop it from the active list. Safe to call from any UI tap.
  @action
  Future<void> cancel(ActiveDownload item) async {
    final token = _tokens[item.key];
    token?.cancel();
    // Wipe partial files so a future re-download starts clean. The catch
    // block above will also remove this from the active list when the
    // DownloadCancelledException surfaces.
    try {
      final dir = await _service.itemDir(
        tmdbId: item.tmdbId,
        mediaType: item.mediaType,
        seasonNumber: item.seasonNumber,
        episodeNumber: item.episodeNumber,
      );
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort.
    }
    active.removeWhere((a) => a.key == item.key);
    _tokens.remove(item.key);
    _refreshWakelock();
  }

  @action
  Future<void> remove(DownloadedItem item) async {
    await _service.delete(item);
    completed.removeWhere((c) => c.dir.path == item.dir.path);
  }

  @action
  void dismissActiveError(ActiveDownload item) {
    active.removeWhere((a) => a.key == item.key);
  }
}

final downloadStore = DownloadStore();
