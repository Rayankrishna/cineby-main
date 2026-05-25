// import 'package:dio/dio.dart';
// import 'package:saas/locator.dart';
// import 'package:saas/stores/auth_store.dart';

import 'package:dio/dio.dart';

const String serverurl = 'https://player.videasy.net/movie/';

const String searchUrl =
    'https://db.videasy.net/3/search/multi?language=en&page=1&query=';

const String homeUrl =
    "https://db.videasy.net/3/trending/all/day?region=US&language=en";

const String topMoviesUrl =
    'https://db.videasy.net/3/discover/movie?sort_by=popularity.desc&language=en&page=1';
const String topSeriesUrl =
    'https://db.videasy.net/3/discover/tv?sort_by=popularity.desc&language=en&page=1';
const String topAnimeUrl =
    'https://db.videasy.net/3/discover/tv?with_genres=16&with_origin_country=JP|CN&sort_by=popularity.desc&language=en&page=1';

const String movieDetailUrl = 'https://db.videasy.net/3/movie';
const String movieDetailParams =
    '?append_to_response=credits,external_ids,videos&language=en';

// Reelix backend API.
// Production (Vercel): https://cineby-main.vercel.app/api/v1
// Local dev:
//   Android emulator → http://10.0.2.2:4000/api/v1
//   iOS simulator    → http://localhost:4000/api/v1
//   Physical device  → http://<your-mac-LAN-ip>:4000/api/v1
const String apiBaseUrl = 'https://cineby-main.vercel.app/api/v1';

const String tvServerurl = 'https://player.videasy.net/tv/';
const String tvDetailUrl = 'https://db.videasy.net/3/tv';
const String tvDetailParams =
    '?append_to_response=credits,external_ids,videos&language=en';
const String tvSeasonUrl = 'https://db.videasy.net/3/tv';
const String tvSeasonParams = '?language=en';

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
