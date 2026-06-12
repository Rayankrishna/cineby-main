// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$SearchStore on _SearchStore, Store {
  late final _$searchQueryAtom = Atom(
    name: '_SearchStore.searchQuery',
    context: context,
  );

  @override
  String get searchQuery {
    _$searchQueryAtom.reportRead();
    return super.searchQuery;
  }

  @override
  set searchQuery(String value) {
    _$searchQueryAtom.reportWrite(value, super.searchQuery, () {
      super.searchQuery = value;
    });
  }

  late final _$isLoadingAtom = Atom(
    name: '_SearchStore.isLoading',
    context: context,
  );

  @override
  bool get isLoading {
    _$isLoadingAtom.reportRead();
    return super.isLoading;
  }

  @override
  set isLoading(bool value) {
    _$isLoadingAtom.reportWrite(value, super.isLoading, () {
      super.isLoading = value;
    });
  }

  late final _$searchResultsAtom = Atom(
    name: '_SearchStore.searchResults',
    context: context,
  );

  @override
  ObservableList<SearchResult> get searchResults {
    _$searchResultsAtom.reportRead();
    return super.searchResults;
  }

  @override
  set searchResults(ObservableList<SearchResult> value) {
    _$searchResultsAtom.reportWrite(value, super.searchResults, () {
      super.searchResults = value;
    });
  }

  late final _$trendingResultsAtom = Atom(
    name: '_SearchStore.trendingResults',
    context: context,
  );

  @override
  ObservableList<SearchResult> get trendingResults {
    _$trendingResultsAtom.reportRead();
    return super.trendingResults;
  }

  @override
  set trendingResults(ObservableList<SearchResult> value) {
    _$trendingResultsAtom.reportWrite(value, super.trendingResults, () {
      super.trendingResults = value;
    });
  }

  late final _$topMoviesAtom = Atom(
    name: '_SearchStore.topMovies',
    context: context,
  );

  @override
  ObservableList<SearchResult> get topMovies {
    _$topMoviesAtom.reportRead();
    return super.topMovies;
  }

  @override
  set topMovies(ObservableList<SearchResult> value) {
    _$topMoviesAtom.reportWrite(value, super.topMovies, () {
      super.topMovies = value;
    });
  }

  late final _$topSeriesAtom = Atom(
    name: '_SearchStore.topSeries',
    context: context,
  );

  @override
  ObservableList<SearchResult> get topSeries {
    _$topSeriesAtom.reportRead();
    return super.topSeries;
  }

  @override
  set topSeries(ObservableList<SearchResult> value) {
    _$topSeriesAtom.reportWrite(value, super.topSeries, () {
      super.topSeries = value;
    });
  }

  late final _$topAnimeAtom = Atom(
    name: '_SearchStore.topAnime',
    context: context,
  );

  @override
  ObservableList<SearchResult> get topAnime {
    _$topAnimeAtom.reportRead();
    return super.topAnime;
  }

  @override
  set topAnime(ObservableList<SearchResult> value) {
    _$topAnimeAtom.reportWrite(value, super.topAnime, () {
      super.topAnime = value;
    });
  }

  late final _$actionMoviesAtom = Atom(
    name: '_SearchStore.actionMovies',
    context: context,
  );

  @override
  ObservableList<SearchResult> get actionMovies {
    _$actionMoviesAtom.reportRead();
    return super.actionMovies;
  }

  @override
  set actionMovies(ObservableList<SearchResult> value) {
    _$actionMoviesAtom.reportWrite(value, super.actionMovies, () {
      super.actionMovies = value;
    });
  }

  late final _$comedyMoviesAtom = Atom(
    name: '_SearchStore.comedyMovies',
    context: context,
  );

  @override
  ObservableList<SearchResult> get comedyMovies {
    _$comedyMoviesAtom.reportRead();
    return super.comedyMovies;
  }

  @override
  set comedyMovies(ObservableList<SearchResult> value) {
    _$comedyMoviesAtom.reportWrite(value, super.comedyMovies, () {
      super.comedyMovies = value;
    });
  }

  late final _$dramaMoviesAtom = Atom(
    name: '_SearchStore.dramaMovies',
    context: context,
  );

  @override
  ObservableList<SearchResult> get dramaMovies {
    _$dramaMoviesAtom.reportRead();
    return super.dramaMovies;
  }

  @override
  set dramaMovies(ObservableList<SearchResult> value) {
    _$dramaMoviesAtom.reportWrite(value, super.dramaMovies, () {
      super.dramaMovies = value;
    });
  }

  late final _$horrorMoviesAtom = Atom(
    name: '_SearchStore.horrorMovies',
    context: context,
  );

  @override
  ObservableList<SearchResult> get horrorMovies {
    _$horrorMoviesAtom.reportRead();
    return super.horrorMovies;
  }

  @override
  set horrorMovies(ObservableList<SearchResult> value) {
    _$horrorMoviesAtom.reportWrite(value, super.horrorMovies, () {
      super.horrorMovies = value;
    });
  }

  late final _$sciFiMoviesAtom = Atom(
    name: '_SearchStore.sciFiMovies',
    context: context,
  );

  @override
  ObservableList<SearchResult> get sciFiMovies {
    _$sciFiMoviesAtom.reportRead();
    return super.sciFiMovies;
  }

  @override
  set sciFiMovies(ObservableList<SearchResult> value) {
    _$sciFiMoviesAtom.reportWrite(value, super.sciFiMovies, () {
      super.sciFiMovies = value;
    });
  }

  late final _$romanceMoviesAtom = Atom(
    name: '_SearchStore.romanceMovies',
    context: context,
  );

  @override
  ObservableList<SearchResult> get romanceMovies {
    _$romanceMoviesAtom.reportRead();
    return super.romanceMovies;
  }

  @override
  set romanceMovies(ObservableList<SearchResult> value) {
    _$romanceMoviesAtom.reportWrite(value, super.romanceMovies, () {
      super.romanceMovies = value;
    });
  }

  late final _$forYouAtom = Atom(
    name: '_SearchStore.forYou',
    context: context,
  );

  @override
  ObservableList<SearchResult> get forYou {
    _$forYouAtom.reportRead();
    return super.forYou;
  }

  @override
  set forYou(ObservableList<SearchResult> value) {
    _$forYouAtom.reportWrite(value, super.forYou, () {
      super.forYou = value;
    });
  }

  late final _$errorMessageAtom = Atom(
    name: '_SearchStore.errorMessage',
    context: context,
  );

  @override
  String? get errorMessage {
    _$errorMessageAtom.reportRead();
    return super.errorMessage;
  }

  @override
  set errorMessage(String? value) {
    _$errorMessageAtom.reportWrite(value, super.errorMessage, () {
      super.errorMessage = value;
    });
  }

  late final _$setSearchQueryAsyncAction = AsyncAction(
    '_SearchStore.setSearchQuery',
    context: context,
  );

  @override
  Future<void> setSearchQuery(String query) {
    return _$setSearchQueryAsyncAction.run(() => super.setSearchQuery(query));
  }

  late final _$fetchSearchResultsAsyncAction = AsyncAction(
    '_SearchStore.fetchSearchResults',
    context: context,
  );

  @override
  Future<void> fetchSearchResults(String query) {
    return _$fetchSearchResultsAsyncAction.run(
      () => super.fetchSearchResults(query),
    );
  }

  late final _$fetchTrendingResultsAsyncAction = AsyncAction(
    '_SearchStore.fetchTrendingResults',
    context: context,
  );

  @override
  Future<void> fetchTrendingResults() {
    return _$fetchTrendingResultsAsyncAction.run(
      () => super.fetchTrendingResults(),
    );
  }

  late final _$fetchHomeFeedAsyncAction = AsyncAction(
    '_SearchStore.fetchHomeFeed',
    context: context,
  );

  @override
  Future<void> fetchHomeFeed() {
    return _$fetchHomeFeedAsyncAction.run(() => super.fetchHomeFeed());
  }

  @override
  String toString() {
    return '''
searchQuery: ${searchQuery},
isLoading: ${isLoading},
searchResults: ${searchResults},
trendingResults: ${trendingResults},
topMovies: ${topMovies},
topSeries: ${topSeries},
topAnime: ${topAnime},
errorMessage: ${errorMessage}
    ''';
  }
}
