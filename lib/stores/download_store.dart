import 'package:app_web_ui/services/download_service.dart';
import 'package:mobx/mobx.dart';

part 'download_store.g.dart';

class ActiveDownload {
  final int tmdbId;
  final String mediaType;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? title;
  double progress; // 0.0..1.0
  String? error;

  ActiveDownload({
    required this.tmdbId,
    required this.mediaType,
    this.seasonNumber,
    this.episodeNumber,
    this.title,
    this.progress = 0,
    this.error,
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

    try {
      await _service.download(
        tmdbId: tmdbId,
        mediaType: mediaType,
        url: url,
        headers: headers,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
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
