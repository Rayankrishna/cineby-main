// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'watchlist_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$WatchlistStore on _WatchlistStore, Store {
  late final _$itemsAtom = Atom(
    name: '_WatchlistStore.items',
    context: context,
  );

  @override
  ObservableList<WatchlistItem> get items {
    _$itemsAtom.reportRead();
    return super.items;
  }

  @override
  set items(ObservableList<WatchlistItem> value) {
    _$itemsAtom.reportWrite(value, super.items, () {
      super.items = value;
    });
  }

  late final _$isLoadingAtom = Atom(
    name: '_WatchlistStore.isLoading',
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

  late final _$errorMessageAtom = Atom(
    name: '_WatchlistStore.errorMessage',
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

  late final _$_containsCacheAtom = Atom(
    name: '_WatchlistStore._containsCache',
    context: context,
  );

  @override
  ObservableMap<String, bool> get _containsCache {
    _$_containsCacheAtom.reportRead();
    return super._containsCache;
  }

  @override
  set _containsCache(ObservableMap<String, bool> value) {
    _$_containsCacheAtom.reportWrite(value, super._containsCache, () {
      super._containsCache = value;
    });
  }

  late final _$fetchAsyncAction = AsyncAction(
    '_WatchlistStore.fetch',
    context: context,
  );

  @override
  Future<void> fetch() {
    return _$fetchAsyncAction.run(() => super.fetch());
  }

  late final _$checkContainsAsyncAction = AsyncAction(
    '_WatchlistStore.checkContains',
    context: context,
  );

  @override
  Future<bool> checkContains(int tmdbId, String mediaType) {
    return _$checkContainsAsyncAction.run(
      () => super.checkContains(tmdbId, mediaType),
    );
  }

  late final _$addAsyncAction = AsyncAction(
    '_WatchlistStore.add',
    context: context,
  );

  @override
  Future<void> add({
    required int tmdbId,
    required String mediaType,
    String? title,
    String? posterPath,
  }) {
    return _$addAsyncAction.run(
      () => super.add(
        tmdbId: tmdbId,
        mediaType: mediaType,
        title: title,
        posterPath: posterPath,
      ),
    );
  }

  late final _$removeAsyncAction = AsyncAction(
    '_WatchlistStore.remove',
    context: context,
  );

  @override
  Future<void> remove({required int tmdbId, required String mediaType}) {
    return _$removeAsyncAction.run(
      () => super.remove(tmdbId: tmdbId, mediaType: mediaType),
    );
  }

  @override
  String toString() {
    return '''
items: ${items},
isLoading: ${isLoading},
errorMessage: ${errorMessage}
    ''';
  }
}
