import 'package:app_web_ui/services/api_client.dart';
import 'package:dio/dio.dart';
import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'auth_store.g.dart';

class AuthStore = _AuthStore with _$AuthStore;

class AuthUser {
  final String id;
  final String name;
  final String email;
  AuthUser({required this.id, required this.name, required this.email});
  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
      );
}

abstract class _AuthStore with Store {
  final ApiClient _api = ApiClient.instance;

  @observable
  AuthUser? user;

  @observable
  String? avatarPath;

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  String _avatarKey(String userId) => 'reelix.avatar.$userId';

  @computed
  bool get isAuthenticated => user != null;

  String? _extractError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['error'] is Map) {
        return (data['error']['message'] as String?) ?? 'Request failed';
      }
      return e.message;
    }
    return e.toString();
  }

  @action
  Future<void> bootstrap() async {
    await _api.loadTokens();
    if (!_api.isAuthenticated) return;
    try {
      final res = await _api.dio.get('/me');
      user = AuthUser.fromJson(res.data as Map<String, dynamic>);
      await _loadAvatar();
    } catch (_) {
      await _api.clearTokens();
      user = null;
    }
  }

  Future<void> _loadAvatar() async {
    final u = user;
    if (u == null) return;
    final prefs = await SharedPreferences.getInstance();
    avatarPath = prefs.getString(_avatarKey(u.id));
  }

  @action
  Future<void> setAvatarPath(String? path) async {
    avatarPath = path;
    final u = user;
    if (u == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_avatarKey(u.id));
    } else {
      await prefs.setString(_avatarKey(u.id), path);
    }
  }

  @action
  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) async {
    isLoading = true;
    errorMessage = null;
    try {
      final res = await _api.dio.post('/auth/register', data: {
        'name': name,
        'email': email,
        'password': password,
      });
      await _api.setTokens(
        res.data['accessToken'] as String,
        res.data['refreshToken'] as String,
      );
      user = AuthUser.fromJson(res.data['user'] as Map<String, dynamic>);
      await _loadAvatar();
      return true;
    } catch (e) {
      errorMessage = _extractError(e);
      return false;
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> login({required String email, required String password}) async {
    isLoading = true;
    errorMessage = null;
    try {
      final res = await _api.dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      await _api.setTokens(
        res.data['accessToken'] as String,
        res.data['refreshToken'] as String,
      );
      user = AuthUser.fromJson(res.data['user'] as Map<String, dynamic>);
      await _loadAvatar();
      return true;
    } catch (e) {
      errorMessage = _extractError(e);
      return false;
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<void> logout() async {
    await _api.clearTokens();
    user = null;
    avatarPath = null;
  }
}

final authStore = AuthStore();
