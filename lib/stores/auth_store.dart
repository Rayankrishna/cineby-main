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

  // Stores the FULL avatar image URL (e.g.
  // `https://image.tmdb.org/t/p/w300/abc.jpg`). The field is still named
  // `avatarPath` for backward compatibility with the generated MobX atom
  // (`_$avatarPathAtom` in auth_store.g.dart) — renaming would require
  // a build_runner regeneration that's currently broken on this Dart SDK.
  @observable
  String? avatarPath;

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  // Key prefix bumped from `reelix.avatar.*` so old caches (which held only
  // a TMDB path like `/abc.jpg`) are ignored — they'd render as broken URLs.
  String _avatarKey(String userId) => 'reelix.avatarUrl.$userId';

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
      // Warm from local cache first so the avatar appears instantly while
      // the server round-trip happens. The server response then overwrites.
      await _loadCachedAvatar();
      final res = await _api.dio.get('/me');
      final data = res.data as Map<String, dynamic>;
      user = AuthUser.fromJson(data);
      await _adoptServerAvatar(data['avatarUrl'] as String?);
    } catch (_) {
      await _api.clearTokens();
      user = null;
    }
  }

  Future<void> _loadCachedAvatar() async {
    final u = user;
    if (u == null) return;
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_avatarKey(u.id));
    if (cached != null) avatarPath = cached;
  }

  Future<void> _adoptServerAvatar(String? url) async {
    avatarPath = url;
    final u = user;
    if (u == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (url == null) {
      await prefs.remove(_avatarKey(u.id));
    } else {
      await prefs.setString(_avatarKey(u.id), url);
    }
  }

  /// Called by the avatar picker with a full image URL (or `null` to clear).
  /// Mirrors to the server via `PATCH /me` and to the local cache.
  @action
  Future<void> setAvatarPath(String? url) async {
    // Optimistic local update so the UI flips immediately.
    avatarPath = url;
    final u = user;
    if (u == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (url == null) {
      await prefs.remove(_avatarKey(u.id));
    } else {
      await prefs.setString(_avatarKey(u.id), url);
    }
    try {
      await _api.dio.patch('/me', data: {'avatarUrl': url ?? ''});
    } catch (_) {
      // Best-effort sync — the cache still serves the latest value locally,
      // and a successful future PATCH will reconcile with the server.
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
      final userJson = res.data['user'] as Map<String, dynamic>;
      user = AuthUser.fromJson(userJson);
      await _adoptServerAvatar(userJson['avatarUrl'] as String?);
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
      final userJson = res.data['user'] as Map<String, dynamic>;
      user = AuthUser.fromJson(userJson);
      await _adoptServerAvatar(userJson['avatarUrl'] as String?);
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
