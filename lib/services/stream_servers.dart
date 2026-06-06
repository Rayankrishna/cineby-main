import 'package:dio/dio.dart';

class StreamServer {
  final String name;
  final String hostMatch; // substring used to identify this server from a URL
  final String Function(int tmdbId, String mediaType, int? season, int? episode)
      buildUrl;

  StreamServer({
    required this.name,
    required this.hostMatch,
    required this.buildUrl,
  });
}

StreamServer? streamServerForUrl(String url) {
  final lower = url.toLowerCase();
  for (final s in streamServers) {
    if (lower.contains(s.hostMatch)) return s;
  }
  return null;
}

/// Pings an embed URL with a short timeout. Any HTTP response (even 4xx)
/// counts as "host is alive"; only connection / DNS / timeout failures
/// return false.
Future<bool> isEmbedReachable(String url) async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 3),
    sendTimeout: const Duration(seconds: 3),
    receiveTimeout: const Duration(seconds: 3),
    validateStatus: (_) => true,
    followRedirects: true,
  ));
  try {
    // HEAD is cheap; many embeds reject it though, so fall through to GET.
    final res = await dio.head(url);
    if (res.statusCode != null) return true;
  } catch (_) {}
  try {
    final res = await dio.get(url);
    return res.statusCode != null;
  } catch (_) {
    return false;
  }
}

/// Returns the first stream server in [streamServers] whose embed URL for
/// the given title responds to a reachability probe. Returns null if every
/// configured provider is down.
Future<StreamServer?> findReachableServer({
  required int tmdbId,
  required String mediaType,
  int? seasonNumber,
  int? episodeNumber,
}) async {
  for (final s in streamServers) {
    final url = s.buildUrl(tmdbId, mediaType, seasonNumber, episodeNumber);
    if (await isEmbedReachable(url)) return s;
  }
  return null;
}

// Available embed providers. Order = display order in the picker, and the
// FIRST entry is the default used by detail-page Play buttons. Videasy is
// dead so it's no longer listed.
final List<StreamServer> streamServers = [
  StreamServer(
    name: '111Movies',
    hostMatch: '111movies.net',
    buildUrl: (id, mt, s, e) => mt == 'tv'
        ? 'https://111movies.net/tv/$id/$s/$e'
        : 'https://111movies.net/movie/$id',
  ),
  StreamServer(
    name: 'VidSrc',
    hostMatch: 'vidsrc.to',
    buildUrl: (id, mt, s, e) => mt == 'tv'
        ? 'https://vidsrc.to/embed/tv/$id/$s/$e'
        : 'https://vidsrc.to/embed/movie/$id',
  ),
  StreamServer(
    name: 'Vidlink',
    hostMatch: 'vidlink.pro',
    buildUrl: (id, mt, s, e) => mt == 'tv'
        ? 'https://vidlink.pro/tv/$id/$s/$e'
        : 'https://vidlink.pro/movie/$id',
  ),
  StreamServer(
    name: '2Embed',
    hostMatch: '2embed.cc',
    buildUrl: (id, mt, s, e) => mt == 'tv'
        ? 'https://www.2embed.cc/embedtv/$id&s=$s&e=$e'
        : 'https://www.2embed.cc/embed/$id',
  ),
];
