// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$DownloadStore on _DownloadStore, Store {
  late final _$activeAtom =
      Atom(name: '_DownloadStore.active', context: context);

  @override
  ObservableList<ActiveDownload> get active {
    _$activeAtom.reportRead();
    return super.active;
  }

  @override
  set active(ObservableList<ActiveDownload> value) {
    _$activeAtom.reportWrite(value, super.active, () {
      super.active = value;
    });
  }

  late final _$completedAtom =
      Atom(name: '_DownloadStore.completed', context: context);

  @override
  ObservableList<DownloadedItem> get completed {
    _$completedAtom.reportRead();
    return super.completed;
  }

  @override
  set completed(ObservableList<DownloadedItem> value) {
    _$completedAtom.reportWrite(value, super.completed, () {
      super.completed = value;
    });
  }

  late final _$isLoadingAtom =
      Atom(name: '_DownloadStore.isLoading', context: context);

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

  late final _$refreshAsyncAction =
      AsyncAction('_DownloadStore.refresh', context: context);

  @override
  Future<void> refresh() {
    return _$refreshAsyncAction.run(() => super.refresh());
  }

  late final _$startAsyncAction =
      AsyncAction('_DownloadStore.start', context: context);

  @override
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
  }) {
    return _$startAsyncAction.run(() => super.start(
          tmdbId: tmdbId,
          mediaType: mediaType,
          url: url,
          headers: headers,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
          title: title,
          posterPath: posterPath,
          backdropPath: backdropPath,
        ));
  }

  late final _$removeAsyncAction =
      AsyncAction('_DownloadStore.remove', context: context);

  @override
  Future<void> remove(DownloadedItem item) {
    return _$removeAsyncAction.run(() => super.remove(item));
  }

  late final _$_DownloadStoreActionController =
      ActionController(name: '_DownloadStore', context: context);

  @override
  void dismissActiveError(ActiveDownload item) {
    final _$actionInfo = _$_DownloadStoreActionController.startAction(
        name: '_DownloadStore.dismissActiveError');
    try {
      return super.dismissActiveError(item);
    } finally {
      _$_DownloadStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
active: ${active},
completed: ${completed},
isLoading: ${isLoading}
''';
  }
}
