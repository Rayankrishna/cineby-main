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

  @override
  String toString() {
    return '''
searchQuery: ${searchQuery},
isLoading: ${isLoading},
searchResults: ${searchResults},
errorMessage: ${errorMessage}
    ''';
  }
}
