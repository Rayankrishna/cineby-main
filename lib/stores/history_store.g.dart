// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'history_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$HistoryStore on _HistoryStore, Store {
  late final _$itemsAtom = Atom(name: '_HistoryStore.items', context: context);

  @override
  ObservableList<HistoryItem> get items {
    _$itemsAtom.reportRead();
    return super.items;
  }

  @override
  set items(ObservableList<HistoryItem> value) {
    _$itemsAtom.reportWrite(value, super.items, () {
      super.items = value;
    });
  }

  late final _$continueWatchingAtom = Atom(
    name: '_HistoryStore.continueWatching',
    context: context,
  );

  @override
  ObservableList<HistoryItem> get continueWatching {
    _$continueWatchingAtom.reportRead();
    return super.continueWatching;
  }

  @override
  set continueWatching(ObservableList<HistoryItem> value) {
    _$continueWatchingAtom.reportWrite(value, super.continueWatching, () {
      super.continueWatching = value;
    });
  }

  late final _$isLoadingAtom = Atom(
    name: '_HistoryStore.isLoading',
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
    name: '_HistoryStore.errorMessage',
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

  late final _$fetchAsyncAction = AsyncAction(
    '_HistoryStore.fetch',
    context: context,
  );

  @override
  Future<void> fetch() {
    return _$fetchAsyncAction.run(() => super.fetch());
  }

  late final _$fetchContinueWatchingAsyncAction = AsyncAction(
    '_HistoryStore.fetchContinueWatching',
    context: context,
  );

  @override
  Future<void> fetchContinueWatching() {
    return _$fetchContinueWatchingAsyncAction.run(
      () => super.fetchContinueWatching(),
    );
  }

  late final _$recordAsyncAction = AsyncAction(
    '_HistoryStore.record',
    context: context,
  );

  @override
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
  }) {
    return _$recordAsyncAction.run(
      () => super.record(
        tmdbId: tmdbId,
        mediaType: mediaType,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        progressSeconds: progressSeconds,
        durationSeconds: durationSeconds,
        title: title,
        posterPath: posterPath,
        backdropPath: backdropPath,
      ),
    );
  }

  late final _$removeAsyncAction = AsyncAction(
    '_HistoryStore.remove',
    context: context,
  );

  @override
  Future<void> remove(String id) {
    return _$removeAsyncAction.run(() => super.remove(id));
  }

  late final _$clearAllAsyncAction = AsyncAction(
    '_HistoryStore.clearAll',
    context: context,
  );

  @override
  Future<void> clearAll() {
    return _$clearAllAsyncAction.run(() => super.clearAll());
  }

  @override
  String toString() {
    return '''
items: ${items},
continueWatching: ${continueWatching},
isLoading: ${isLoading},
errorMessage: ${errorMessage}
    ''';
  }
}
