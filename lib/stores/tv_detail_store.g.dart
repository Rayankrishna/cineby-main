// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tv_detail_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$TvDetailStore on _TvDetailStore, Store {
  late final _$tvDetailAtom = Atom(
    name: '_TvDetailStore.tvDetail',
    context: context,
  );

  @override
  TvDetail? get tvDetail {
    _$tvDetailAtom.reportRead();
    return super.tvDetail;
  }

  @override
  set tvDetail(TvDetail? value) {
    _$tvDetailAtom.reportWrite(value, super.tvDetail, () {
      super.tvDetail = value;
    });
  }

  late final _$selectedSeasonAtom = Atom(
    name: '_TvDetailStore.selectedSeason',
    context: context,
  );

  @override
  SeasonDetail? get selectedSeason {
    _$selectedSeasonAtom.reportRead();
    return super.selectedSeason;
  }

  @override
  set selectedSeason(SeasonDetail? value) {
    _$selectedSeasonAtom.reportWrite(value, super.selectedSeason, () {
      super.selectedSeason = value;
    });
  }

  late final _$selectedSeasonNumberAtom = Atom(
    name: '_TvDetailStore.selectedSeasonNumber',
    context: context,
  );

  @override
  int? get selectedSeasonNumber {
    _$selectedSeasonNumberAtom.reportRead();
    return super.selectedSeasonNumber;
  }

  @override
  set selectedSeasonNumber(int? value) {
    _$selectedSeasonNumberAtom.reportWrite(
      value,
      super.selectedSeasonNumber,
      () {
        super.selectedSeasonNumber = value;
      },
    );
  }

  late final _$isLoadingAtom = Atom(
    name: '_TvDetailStore.isLoading',
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

  late final _$isSeasonLoadingAtom = Atom(
    name: '_TvDetailStore.isSeasonLoading',
    context: context,
  );

  @override
  bool get isSeasonLoading {
    _$isSeasonLoadingAtom.reportRead();
    return super.isSeasonLoading;
  }

  @override
  set isSeasonLoading(bool value) {
    _$isSeasonLoadingAtom.reportWrite(value, super.isSeasonLoading, () {
      super.isSeasonLoading = value;
    });
  }

  late final _$errorMessageAtom = Atom(
    name: '_TvDetailStore.errorMessage',
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

  late final _$fetchTvDetailAsyncAction = AsyncAction(
    '_TvDetailStore.fetchTvDetail',
    context: context,
  );

  @override
  Future<void> fetchTvDetail(int id) {
    return _$fetchTvDetailAsyncAction.run(() => super.fetchTvDetail(id));
  }

  late final _$fetchSeasonAsyncAction = AsyncAction(
    '_TvDetailStore.fetchSeason',
    context: context,
  );

  @override
  Future<void> fetchSeason(int tvId, int seasonNumber) {
    return _$fetchSeasonAsyncAction.run(
      () => super.fetchSeason(tvId, seasonNumber),
    );
  }

  @override
  String toString() {
    return '''
tvDetail: ${tvDetail},
selectedSeason: ${selectedSeason},
selectedSeasonNumber: ${selectedSeasonNumber},
isLoading: ${isLoading},
isSeasonLoading: ${isSeasonLoading},
errorMessage: ${errorMessage}
    ''';
  }
}
