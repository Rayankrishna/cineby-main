import 'package:app_web_ui/models/search_model.dart';
import 'package:app_web_ui/services/config.dart';
import 'package:app_web_ui/services/tmdb_client.dart';
import 'package:mobx/mobx.dart';

part 'search_store.g.dart';

class SearchStore = _SearchStore with _$SearchStore;

abstract class _SearchStore with Store {
  @observable
  String searchQuery = '';

  @observable
  bool isLoading = false;

  @observable
  ObservableList<SearchResult> searchResults = ObservableList<SearchResult>();

  @observable
  ObservableList<SearchResult> trendingResults = ObservableList<SearchResult>();

  @observable
  ObservableList<SearchResult> topMovies = ObservableList<SearchResult>();

  @observable
  ObservableList<SearchResult> topSeries = ObservableList<SearchResult>();

  @observable
  ObservableList<SearchResult> topAnime = ObservableList<SearchResult>();

  @observable
  String? errorMessage;

  @action
  Future<void> setSearchQuery(String query) async {
    searchQuery = query;
    if (query.isNotEmpty) {
      await fetchSearchResults(query);
    } else {
      searchResults.clear();
    }
  }

  @action
  Future<void> fetchSearchResults(String query) async {
    isLoading = true;
    errorMessage = null;
    try {
      final response = await tmdbDio.get('$searchUrl$query');
      if (response.statusCode == 200) {
        final searchResponse = SearchResponse.fromJson(response.data);
        searchResults = ObservableList.of(searchResponse.results);
      } else {
        errorMessage = 'Failed to load results';
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<void> fetchTrendingResults() async {
    isLoading = true;
    errorMessage = null;
    try {
      final response = await tmdbDio.get(homeUrl);
      if (response.statusCode == 200) {
        final searchResponse = SearchResponse.fromJson(response.data);
        trendingResults = ObservableList.of(searchResponse.results);
      } else {
        errorMessage = 'Failed to load trending results';
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  Future<List<SearchResult>> _fetchList(String url, {String? mediaType}) async {
    try {
      final res = await tmdbDio.get(url);
      if (res.statusCode != 200) return const [];
      final list = SearchResponse.fromJson(res.data).results;
      if (mediaType == null) return list;
      // /discover endpoints don't include media_type — patch it in so home
      // navigation can route movies vs TV correctly.
      return list
          .map((r) => SearchResult(
                id: r.id,
                title: r.title,
                name: r.name,
                originalTitle: r.originalTitle,
                originalName: r.originalName,
                overview: r.overview,
                posterPath: r.posterPath,
                backdropPath: r.backdropPath,
                mediaType: mediaType,
                releaseDate: r.releaseDate,
                voteAverage: r.voteAverage,
                voteCount: r.voteCount,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @action
  Future<void> fetchHomeFeed() async {
    isLoading = true;
    errorMessage = null;
    try {
      final results = await Future.wait<List<SearchResult>>([
        _fetchList(homeUrl),
        _fetchList(topMoviesUrl, mediaType: 'movie'),
        _fetchList(topSeriesUrl, mediaType: 'tv'),
        _fetchList(topAnimeUrl, mediaType: 'tv'),
      ]);
      trendingResults = ObservableList.of(results[0]);
      topMovies = ObservableList.of(results[1]);
      topSeries = ObservableList.of(results[2]);
      topAnime = ObservableList.of(results[3]);
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }
}
