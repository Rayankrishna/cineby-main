import 'package:app_web_ui/services/api_client.dart';

/// Talks to /api/v1/server-votes. Records which embed provider worked for
/// a title (every successful native-player init pings here) and reads back
/// the global ranking so detail pages can pre-select the source most likely
/// to play. All votes are aggregated globally — one user's success becomes
/// the next user's default.
class ServerVoteService {
  ServerVoteService._();
  static final ServerVoteService instance = ServerVoteService._();

  /// Bump the success count for (tmdbId, mediaType, serverName). Fails
  /// silently — we never block playback on a stats call.
  Future<void> recordSuccess({
    required int tmdbId,
    required String mediaType,
    required String serverName,
  }) async {
    try {
      await ApiClient.instance.dio.post('/server-votes', data: {
        'tmdbId': tmdbId,
        'mediaType': mediaType,
        'serverName': serverName,
      });
    } catch (_) {
      // best-effort
    }
  }

  /// Return the highest-ranked server name for a title, or `null` if there
  /// are no votes yet (caller falls back to the local default).
  Future<String?> bestServerName({
    required int tmdbId,
    required String mediaType,
  }) async {
    try {
      final res = await ApiClient.instance.dio.get(
        '/server-votes/$tmdbId',
        queryParameters: {'mediaType': mediaType},
      );
      final items = res.data['items'] as List<dynamic>;
      if (items.isEmpty) return null;
      final top = items.first as Map<String, dynamic>;
      return top['serverName'] as String?;
    } catch (_) {
      return null;
    }
  }
}
