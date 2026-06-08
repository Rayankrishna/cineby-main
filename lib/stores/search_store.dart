import 'dart:math';

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

  // Genre rows — one observable list per genre we surface on home.
  @observable
  ObservableList<SearchResult> actionMovies = ObservableList<SearchResult>();
  @observable
  ObservableList<SearchResult> comedyMovies = ObservableList<SearchResult>();
  @observable
  ObservableList<SearchResult> dramaMovies = ObservableList<SearchResult>();
  @observable
  ObservableList<SearchResult> horrorMovies = ObservableList<SearchResult>();
  @observable
  ObservableList<SearchResult> sciFiMovies = ObservableList<SearchResult>();
  @observable
  ObservableList<SearchResult> romanceMovies = ObservableList<SearchResult>();

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
        var results = searchResponse.results;

        // Filter out noise:
        //  - people (we don't have person pages here)
        //  - things with zero votes (TMDB ghost entries, unreleased trash)
        //  - things missing any date
        //  - unreleased titles (future air/release dates)
        final now = DateTime.now();
        results = results.where((item) {
          if (item.mediaType == 'person') return false;
          if ((item.voteCount ?? 0) == 0) return false;
          final date = item.releaseDate ?? item.firstAirDate;
          if (date == null || date.isEmpty) return false;
          final parsed = DateTime.tryParse(date);
          if (parsed == null) return false;
          if (parsed.isAfter(now)) return false;
          return true;
        }).toList();

        // Sort by relevance score so the best title match leads.
        results.sort((a, b) =>
            _score(b, query).compareTo(_score(a, query)));

        searchResults = ObservableList.of(results);
      } else {
        errorMessage = 'Failed to load results';
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  /// Relevance score for ranking search results. Combines:
  ///   • textual match against the query (exact > startsWith > contains)
  ///   • crowd signals (vote count + vote average)
  /// Higher = more relevant.
  double _score(SearchResult r, String query) {
    final q = query.trim().toLowerCase();
    final title = (r.title ?? r.name ?? '').toLowerCase();
    final original = (r.originalTitle ?? r.originalName ?? '').toLowerCase();

    double textScore = 0;
    if (title == q || original == q) {
      textScore = 1000;
    } else if (title.startsWith(q) || original.startsWith(q)) {
      textScore = 500;
    } else if (title.contains(q) || original.contains(q)) {
      textScore = 200;
    }

    // log(voteCount) keeps blockbusters from completely drowning out
    // smaller-but-relevant matches.
    final votes = (r.voteCount ?? 0).toDouble();
    final voteScore = votes > 0 ? log(votes) * 8 : 0;
    final avgScore = (r.voteAverage ?? 0) * 4;

    return textScore + voteScore + avgScore;
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
      var list = SearchResponse.fromJson(res.data).results;

      // Drop unreleased / dateless rows so the home feed only ever shows
      // things the user can actually watch right now.
      final now = DateTime.now();
      list = list.where((r) {
        final date = r.releaseDate ?? r.firstAirDate;
        if (date == null || date.isEmpty) return false;
        final parsed = DateTime.tryParse(date);
        if (parsed == null) return false;
        return !parsed.isAfter(now);
      }).toList();

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
                firstAirDate: r.firstAirDate,
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
        _fetchList(movieByGenreUrl(int.parse(tmdbGenreAction)),
            mediaType: 'movie'),
        _fetchList(movieByGenreUrl(int.parse(tmdbGenreComedy)),
            mediaType: 'movie'),
        _fetchList(movieByGenreUrl(int.parse(tmdbGenreDrama)),
            mediaType: 'movie'),
        _fetchList(movieByGenreUrl(int.parse(tmdbGenreHorror)),
            mediaType: 'movie'),
        _fetchList(movieByGenreUrl(int.parse(tmdbGenreSciFi)),
            mediaType: 'movie'),
        _fetchList(movieByGenreUrl(int.parse(tmdbGenreRomance)),
            mediaType: 'movie'),
      ]);
      trendingResults = ObservableList.of(results[0]);
      topMovies = ObservableList.of(results[1]);
      topSeries = ObservableList.of(results[2]);
      topAnime = ObservableList.of(results[3]);
      actionMovies = ObservableList.of(results[4]);
      comedyMovies = ObservableList.of(results[5]);
      dramaMovies = ObservableList.of(results[6]);
      horrorMovies = ObservableList.of(results[7]);
      sciFiMovies = ObservableList.of(results[8]);
      romanceMovies = ObservableList.of(results[9]);
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }
}
