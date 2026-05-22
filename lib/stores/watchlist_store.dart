import 'package:app_web_ui/services/api_client.dart';
import 'package:mobx/mobx.dart';

part 'watchlist_store.g.dart';

class WatchlistItem {
  final String id;
  final int tmdbId;
  final String mediaType;
  final String? title;
  final String? posterPath;
  final DateTime addedAt;

  WatchlistItem({
    required this.id,
    required this.tmdbId,
    required this.mediaType,
    this.title,
    this.posterPath,
    required this.addedAt,
  });

  factory WatchlistItem.fromJson(Map<String, dynamic> json) => WatchlistItem(
        id: json['id'] as String,
        tmdbId: json['tmdbId'] as int,
        mediaType: json['mediaType'] as String,
        title: json['title'] as String?,
        posterPath: json['posterPath'] as String?,
        addedAt: DateTime.parse(json['addedAt'] as String),
      );
}

class WatchlistStore = _WatchlistStore with _$WatchlistStore;

abstract class _WatchlistStore with Store {
  final ApiClient _api = ApiClient.instance;

  @observable
  ObservableList<WatchlistItem> items = ObservableList<WatchlistItem>();

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  @observable
  ObservableMap<String, bool> _containsCache = ObservableMap<String, bool>();

  String _key(int tmdbId, String mediaType) => '$mediaType:$tmdbId';

  bool? cachedContains(int tmdbId, String mediaType) =>
      _containsCache[_key(tmdbId, mediaType)];

  @action
  Future<void> fetch() async {
    isLoading = true;
    errorMessage = null;
    try {
      final res = await _api.dio.get('/watchlist');
      final list = (res.data['items'] as List<dynamic>)
          .map((e) => WatchlistItem.fromJson(e as Map<String, dynamic>))
          .toList();
      items = ObservableList.of(list);
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> checkContains(int tmdbId, String mediaType) async {
    try {
      final res = await _api.dio.get(
        '/watchlist/contains/$tmdbId',
        queryParameters: {'mediaType': mediaType},
      );
      final inList = res.data['inWatchlist'] as bool;
      _containsCache[_key(tmdbId, mediaType)] = inList;
      return inList;
    } catch (_) {
      return false;
    }
  }

  @action
  Future<void> add({
    required int tmdbId,
    required String mediaType,
    String? title,
    String? posterPath,
  }) async {
    try {
      await _api.dio.post('/watchlist', data: {
        'tmdbId': tmdbId,
        'mediaType': mediaType,
        if (title != null) 'title': title,
        if (posterPath != null) 'posterPath': posterPath,
      });
      _containsCache[_key(tmdbId, mediaType)] = true;
      await fetch();
    } catch (e) {
      errorMessage = e.toString();
    }
  }

  @action
  Future<void> remove({
    required int tmdbId,
    required String mediaType,
  }) async {
    try {
      await _api.dio.delete(
        '/watchlist/$tmdbId',
        queryParameters: {'mediaType': mediaType},
      );
      _containsCache[_key(tmdbId, mediaType)] = false;
      items.removeWhere(
        (i) => i.tmdbId == tmdbId && i.mediaType == mediaType,
      );
    } catch (e) {
      errorMessage = e.toString();
    }
  }

  Future<void> toggle({
    required int tmdbId,
    required String mediaType,
    String? title,
    String? posterPath,
  }) async {
    final inList = cachedContains(tmdbId, mediaType) ??
        await checkContains(tmdbId, mediaType);
    if (inList) {
      await remove(tmdbId: tmdbId, mediaType: mediaType);
    } else {
      await add(
        tmdbId: tmdbId,
        mediaType: mediaType,
        title: title,
        posterPath: posterPath,
      );
    }
  }
}

final watchlistStore = WatchlistStore();
