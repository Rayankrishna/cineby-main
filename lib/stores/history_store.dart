import 'package:app_web_ui/services/api_client.dart';
import 'package:mobx/mobx.dart';

part 'history_store.g.dart';

class HistoryItem {
  final String id;
  final int tmdbId;
  final String mediaType;
  final int? seasonNumber;
  final int? episodeNumber;
  final int progressSeconds;
  final int? durationSeconds;
  final bool completed;
  final String? title;
  final String? posterPath;
  final String? backdropPath;
  final DateTime watchedAt;
  final DateTime updatedAt;

  HistoryItem({
    required this.id,
    required this.tmdbId,
    required this.mediaType,
    this.seasonNumber,
    this.episodeNumber,
    required this.progressSeconds,
    this.durationSeconds,
    required this.completed,
    this.title,
    this.posterPath,
    this.backdropPath,
    required this.watchedAt,
    required this.updatedAt,
  });

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
        id: json['id'] as String,
        tmdbId: json['tmdbId'] as int,
        mediaType: json['mediaType'] as String,
        seasonNumber: json['seasonNumber'] as int?,
        episodeNumber: json['episodeNumber'] as int?,
        progressSeconds: json['progressSeconds'] as int,
        durationSeconds: json['durationSeconds'] as int?,
        completed: json['completed'] as bool,
        title: json['title'] as String?,
        posterPath: json['posterPath'] as String?,
        backdropPath: json['backdropPath'] as String?,
        watchedAt: DateTime.parse(json['watchedAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

class HistoryStore = _HistoryStore with _$HistoryStore;

abstract class _HistoryStore with Store {
  final ApiClient _api = ApiClient.instance;

  @observable
  ObservableList<HistoryItem> items = ObservableList<HistoryItem>();

  @observable
  ObservableList<HistoryItem> continueWatching =
      ObservableList<HistoryItem>();

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  @action
  Future<void> fetch() async {
    isLoading = true;
    errorMessage = null;
    try {
      final res = await _api.dio.get('/history');
      items = ObservableList.of(
        (res.data['items'] as List<dynamic>)
            .map((e) => HistoryItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  Future<HistoryItem?> latestForShow(int tmdbId) async {
    try {
      final res = await _api.dio.get(
        '/history/$tmdbId',
        queryParameters: {'mediaType': 'tv'},
      );
      final data = res.data['item'];
      if (data == null) return null;
      return HistoryItem.fromJson(data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<HistoryItem?> latestForMovie(int tmdbId) async {
    try {
      final res = await _api.dio.get(
        '/history/$tmdbId',
        queryParameters: {'mediaType': 'movie'},
      );
      final data = res.data['item'];
      if (data == null) return null;
      return HistoryItem.fromJson(data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @action
  Future<void> fetchContinueWatching() async {
    try {
      final res = await _api.dio.get('/history/continue-watching');
      continueWatching = ObservableList.of(
        (res.data['items'] as List<dynamic>)
            .map((e) => HistoryItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } catch (e) {
      errorMessage = e.toString();
    }
  }

  @action
  Future<void> record({
    required int tmdbId,
    required String mediaType,
    int? seasonNumber,
    int? episodeNumber,
    required int progressSeconds,
    int? durationSeconds,
    String? title,
    String? posterPath,
    String? backdropPath,
  }) async {
    try {
      await _api.dio.post('/history', data: {
        'tmdbId': tmdbId,
        'mediaType': mediaType,
        if (seasonNumber != null) 'seasonNumber': seasonNumber,
        if (episodeNumber != null) 'episodeNumber': episodeNumber,
        'progressSeconds': progressSeconds,
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
        if (title != null) 'title': title,
        if (posterPath != null) 'posterPath': posterPath,
        if (backdropPath != null) 'backdropPath': backdropPath,
      });
    } catch (_) {
      // silent — playback should not be blocked
    }
  }

  @action
  Future<void> remove(String id) async {
    try {
      await _api.dio.delete('/history/$id');
      items.removeWhere((i) => i.id == id);
      continueWatching.removeWhere((i) => i.id == id);
    } catch (e) {
      errorMessage = e.toString();
    }
  }

  @action
  Future<void> clearAll() async {
    try {
      await _api.dio.delete('/history');
      items.clear();
      continueWatching.clear();
    } catch (e) {
      errorMessage = e.toString();
    }
  }
}

final historyStore = HistoryStore();
