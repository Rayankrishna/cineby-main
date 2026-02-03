// import 'package:dio/dio.dart';
// import 'package:saas/locator.dart';
// import 'package:saas/stores/auth_store.dart';

import 'package:dio/dio.dart';

const String serverurl = 'https://www.vidking.net/embed/movie/';

const String searchUrl =
    'https://db.videasy.net/3/search/multi?language=en&page=1&query=';

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
