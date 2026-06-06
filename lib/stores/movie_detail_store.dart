import 'package:app_web_ui/models/movie_detail_model.dart';
import 'package:app_web_ui/services/config.dart';
import 'package:app_web_ui/services/tmdb_client.dart';
import 'package:mobx/mobx.dart';

part 'movie_detail_store.g.dart';

class MovieDetailStore = _MovieDetailStore with _$MovieDetailStore;

abstract class _MovieDetailStore with Store {
  @observable
  MovieDetail? movieDetail;

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  @action
  Future<void> fetchMovieDetail(int id) async {
    isLoading = true;
    errorMessage = null;
    try {
      final response =
          await tmdbDio.get('$movieDetailUrl/$id$movieDetailParams');
      if (response.statusCode == 200) {
        movieDetail = MovieDetail.fromJson(response.data);
      } else {
        errorMessage = 'Failed to load movie details';
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }
}
