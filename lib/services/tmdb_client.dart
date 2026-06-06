import 'package:dio/dio.dart';

/// Shared Dio instance for TMDB catalog calls. Reuses one HTTP client across
/// the app (better connection pooling) and retries transient errors —
/// `Connection reset by peer`, TLS hiccups, timeouts. Without this every
/// detail page open is a fresh socket and a single drop kills the request.
class TmdbClient {
  TmdbClient._() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        responseType: ResponseType.json,
      ),
    );
    _dio.interceptors.add(_retryInterceptor());
  }

  static final TmdbClient instance = TmdbClient._();
  late final Dio _dio;
  Dio get dio => _dio;

  static const _maxAttempts = 3;
  static const _baseBackoff = Duration(milliseconds: 350);

  Interceptor _retryInterceptor() {
    return InterceptorsWrapper(
      onError: (e, handler) async {
        // Only retry on transport-level failures. 4xx / 5xx responses are
        // legitimate server answers and shouldn't be hammered.
        final retriable = e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout;
        if (!retriable) return handler.next(e);

        final attempt = (e.requestOptions.extra['retryAttempt'] as int?) ?? 0;
        if (attempt >= _maxAttempts - 1) return handler.next(e);

        // Exponential backoff: 350ms, 700ms, 1400ms…
        final delay = _baseBackoff * (1 << attempt);
        await Future.delayed(delay);

        try {
          final retried = await _dio.fetch(
            e.requestOptions
              ..extra['retryAttempt'] = attempt + 1,
          );
          return handler.resolve(retried);
        } catch (err) {
          if (err is DioException) return handler.next(err);
          return handler.next(e);
        }
      },
    );
  }
}

/// Convenience getter — `tmdbDio.get(url)` reads cleaner than
/// `TmdbClient.instance.dio.get(url)` at call sites.
Dio get tmdbDio => TmdbClient.instance.dio;
