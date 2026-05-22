import 'package:app_web_ui/services/config.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  ApiClient._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: apiBaseUrl,
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 60),
        contentType: 'application/json',
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (_accessToken != null) {
            options.headers['Authorization'] = 'Bearer $_accessToken';
          }
          handler.next(options);
        },
        onError: (e, handler) async {
          final status = e.response?.statusCode;
          final isAuthCall = e.requestOptions.path.startsWith('/auth/');
          if (status == 401 && !isAuthCall && _refreshToken != null) {
            final refreshed = await _tryRefresh();
            if (refreshed) {
              final retry = await _dio.fetch(e.requestOptions);
              return handler.resolve(retry);
            }
          }
          handler.next(e);
        },
      ),
    );
  }

  static final ApiClient instance = ApiClient._();

  late final Dio _dio;
  Dio get dio => _dio;

  String? _accessToken;
  String? _refreshToken;

  String? get accessToken => _accessToken;
  bool get isAuthenticated => _accessToken != null;

  static const _kAccess = 'reelix.accessToken';
  static const _kRefresh = 'reelix.refreshToken';

  Future<void> loadTokens() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_kAccess);
    _refreshToken = prefs.getString(_kRefresh);
  }

  Future<void> setTokens(String access, String refresh) async {
    _accessToken = access;
    _refreshToken = refresh;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccess, access);
    await prefs.setString(_kRefresh, refresh);
  }

  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccess);
    await prefs.remove(_kRefresh);
  }

  Future<bool> _tryRefresh() async {
    try {
      final res = await Dio().post(
        '$apiBaseUrl/auth/refresh',
        data: {'refreshToken': _refreshToken},
      );
      final token = res.data['accessToken'] as String?;
      if (token == null) return false;
      _accessToken = token;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAccess, token);
      return true;
    } catch (_) {
      await clearTokens();
      return false;
    }
  }
}
