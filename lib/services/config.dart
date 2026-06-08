// import 'package:dio/dio.dart';
// import 'package:saas/locator.dart';
// import 'package:saas/stores/auth_store.dart';

import 'package:dio/dio.dart';

// videasy.net is dead (NXDOMAIN). Catalog metadata now comes straight from
// TMDB v3 — same paths as before, just a different host + a required api_key.
// Override the key at build time with --dart-define=TMDB_API_KEY=... to keep
// it out of source.
const String tmdbApiKey = String.fromEnvironment(
  'TMDB_API_KEY',
  defaultValue: '480d0e6b81cc6e4505b0da63dabecf14',
);
const String _tmdbBase = 'https://api.themoviedb.org/3';

// Playback embed defaults — 111Movies is the current default (Videasy is
// dead). The full provider list lives in lib/services/stream_servers.dart;
// detail pages should prefer streamServers.first.buildUrl(...) over building
// URLs from these constants directly.
const String serverurl = 'https://111movies.net/movie/';
const String tvServerurl = 'https://111movies.net/tv/';

const String searchUrl =
    '$_tmdbBase/search/multi?api_key=$tmdbApiKey&language=en&page=1&query=';

const String homeUrl =
    '$_tmdbBase/trending/all/day?api_key=$tmdbApiKey&language=en';

const String topMoviesUrl =
    '$_tmdbBase/discover/movie?api_key=$tmdbApiKey&sort_by=popularity.desc&language=en&page=1';
const String topSeriesUrl =
    '$_tmdbBase/discover/tv?api_key=$tmdbApiKey&sort_by=popularity.desc&language=en&page=1';
const String topAnimeUrl =
    '$_tmdbBase/discover/tv?api_key=$tmdbApiKey&with_genres=16&with_origin_country=JP|CN&sort_by=popularity.desc&language=en&page=1';

// Genre rows on home. Same /discover/movie endpoint, one with_genres filter
// per row. TMDB genre ids — see https://developer.themoviedb.org/reference/genre-movie-list
String movieByGenreUrl(int genreId) =>
    '$_tmdbBase/discover/movie?api_key=$tmdbApiKey'
    '&with_genres=$genreId&sort_by=popularity.desc&language=en&page=1';

const String tmdbGenreAction = '28';
const String tmdbGenreComedy = '35';
const String tmdbGenreDrama = '18';
const String tmdbGenreHorror = '27';
const String tmdbGenreSciFi = '878';
const String tmdbGenreRomance = '10749';
const String tmdbGenreThriller = '53';
const String tmdbGenreFamily = '10751';

// Person filmography — every movie an actor has appeared in.
String personMovieCreditsUrl(int personId) =>
    '$_tmdbBase/person/$personId/movie_credits?api_key=$tmdbApiKey&language=en';
String personTvCreditsUrl(int personId) =>
    '$_tmdbBase/person/$personId/tv_credits?api_key=$tmdbApiKey&language=en';

const String movieDetailUrl = '$_tmdbBase/movie';
const String movieDetailParams =
    '?api_key=$tmdbApiKey&append_to_response=credits,external_ids,videos&language=en';

const String tvDetailUrl = '$_tmdbBase/tv';
const String tvDetailParams =
    '?api_key=$tmdbApiKey&append_to_response=credits,external_ids,videos&language=en';
const String tvSeasonUrl = '$_tmdbBase/tv';
const String tvSeasonParams = '?api_key=$tmdbApiKey&language=en';

// Reelix backend API.
// Production (Vercel): https://cineby-main.vercel.app/api/v1
// Local dev:
//   Android emulator → http://10.0.2.2:4000/api/v1
//   iOS simulator    → http://localhost:4000/api/v1
//   Physical device  → http://<your-mac-LAN-ip>:4000/api/v1
const String apiBaseUrl = 'https://cineby-main.vercel.app/api/v1';

const String authServiceUrl = serverurl;

HttpClient? http;

// final AppController appController = Get.put(AppController());

class HttpClient {
  static Map<String, String> requestHeaders = {
    "Content-Type": "application/json",
    "Authorization": "Bearer guest",
  };

  String accessToken = 'guest';
  final Dio authService;

  HttpClient({required this.authService});

  factory HttpClient.init({Map<String, String>? headers}) {
    // int timeout = 10000; //ms
    http = HttpClient(
      authService: Dio(
        BaseOptions(
          receiveDataWhenStatusError: true,
          baseUrl: authServiceUrl,
          // connectTimeout: timeout,
          // receiveTimeout: timeout,
          headers: headers ?? requestHeaders,
        ),
      ),
    );
    return http!;
  }

  String? parseError(DioException error) {
    // String? message = error.response!.data['message'];

    if (error.response == null) {
      return error.message;
    } else {
      if (error.response!.statusCode == 500) {
        return error.response!.data['message'];
      }
      if (error.response!.statusCode == 401 ||
          error.response!.statusCode == 403 ||
          error.response!.statusCode == 404) {
        return error.response!.data['message'];
      }
      print(" gdsgdsagjnijkadshinopj ubgagiudfo ${error.response?.toString()}");
      if (error.response!.data['message'] == "Product slug not found") {
        return error.response!.data['message'];
      }
      if (error.response!.data['message'] == "Token expired") {
        return error.response!.data['message'];
      }
      if (error.response!.data['message'] == "User Not Active") {
        return error.response!.data['message'];
      }
      if (error.response!.data['message'] == "Invalid Token ID") {
        return error.response!.data['message'];
      }
      if (error.response!.data['message'] == "USER NOT EXIST") {
        return error.response!.data['message'];
      }

      if (error.response!.data['message'] == "Invalid Token Provided") {
        return error.response!.data['message'];
      }

      if (error.response!.data['message'] == "Token not provided") {
        return error.response!.data['message'];
      }

      if (error.response!.data['message'] == "Invalid Token") {
        return error.response!.data['message'];
      }

      if (error.response!.data.runtimeType == String) {
        return error.response!.data;
      }
      if (error.response!.data['message'].runtimeType == String) {
        return error.response!.data['message'];
      }
      if (error.response!.data['error'] != null &&
          error.response!.data['error'].runtimeType == String) {
        return error.response!.data['error'];
      } else {
        return 'Something went wrong , Please Check Your Internet Connection';
      }
    }
  }
}
