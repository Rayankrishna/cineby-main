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

// Available embed providers. Order = display order in the picker.
final List<StreamServer> streamServers = [
  StreamServer(
    name: 'Videasy',
    hostMatch: 'videasy.net',
    buildUrl: (id, mt, s, e) => mt == 'tv'
        ? 'https://player.videasy.net/tv/$id/$s/$e'
            '?episodeSelector=true&nextEpisode=true&autoplayNextEpisode=true'
        : 'https://player.videasy.net/movie/$id',
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
  StreamServer(
    name: '111Movies',
    hostMatch: '111movies.net',
    buildUrl: (id, mt, s, e) => mt == 'tv'
        ? 'https://111movies.net/tv/$id/$s/$e'
        : 'https://111movies.net/movie/$id',
  ),
];
