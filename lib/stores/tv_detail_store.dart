import 'package:app_web_ui/models/tv_detail_model.dart';
import 'package:app_web_ui/services/config.dart';
import 'package:app_web_ui/services/tmdb_client.dart';
import 'package:mobx/mobx.dart';

part 'tv_detail_store.g.dart';

class TvDetailStore = _TvDetailStore with _$TvDetailStore;

abstract class _TvDetailStore with Store {

  @observable
  TvDetail? tvDetail;

  @observable
  SeasonDetail? selectedSeason;

  @observable
  int? selectedSeasonNumber;

  @observable
  bool isLoading = false;

  @observable
  bool isSeasonLoading = false;

  @observable
  String? errorMessage;

  @action
  Future<void> fetchTvDetail(int id) async {
    isLoading = true;
    errorMessage = null;
    try {
      final response = await tmdbDio.get('$tvDetailUrl/$id$tvDetailParams');
      if (response.statusCode == 200) {
        tvDetail = TvDetail.fromJson(response.data);
        final first = tvDetail!.seasons.isNotEmpty
            ? tvDetail!.seasons.first.seasonNumber
            : 1;
        await fetchSeason(id, first);
      } else {
        errorMessage = 'Failed to load show details';
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<void> fetchSeason(int tvId, int seasonNumber) async {
    isSeasonLoading = true;
    selectedSeasonNumber = seasonNumber;
    try {
      final response = await tmdbDio.get(
        '$tvSeasonUrl/$tvId/season/$seasonNumber$tvSeasonParams',
      );
      if (response.statusCode == 200) {
        selectedSeason = SeasonDetail.fromJson(response.data);
      } else {
        errorMessage = 'Failed to load season';
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isSeasonLoading = false;
    }
  }
}
