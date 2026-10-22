import 'package:app_web_ui/services/api_client.dart';

/// One subtitle file the backend found on OpenSubtitles.
class WebSubtitleTrack {
  const WebSubtitleTrack({
    required this.fileId,
    required this.release,
    required this.downloads,
    required this.hearingImpaired,
  });

  final int fileId;
  final String release;
  final int downloads;
  final bool hearingImpaired;

  factory WebSubtitleTrack.fromJson(Map<String, dynamic> j) => WebSubtitleTrack(
    fileId: (j['fileId'] as num).toInt(),
    release: j['release'] as String? ?? 'Subtitles',
    downloads: (j['downloads'] as num?)?.toInt() ?? 0,
    hearingImpaired: j['hearingImpaired'] as bool? ?? false,
  );
}

class SubtitleCue {
  const SubtitleCue(this.start, this.end, this.text);

  final double start;
  final double end;
  final String text;
}

/// Subtitles for the web player, fetched through the backend because
/// browsers can't call OpenSubtitles directly.
class WebSubtitles {
  WebSubtitles._();
  static final WebSubtitles instance = WebSubtitles._();

  final Map<int, List<SubtitleCue>> _cues = {};

  Future<List<WebSubtitleTrack>> search({
    required int tmdbId,
    required String mediaType,
    int? season,
    int? episode,
  }) async {
    final res = await ApiClient.instance.dio.get(
      '/subtitles',
      queryParameters: {
        'tmdbId': tmdbId,
        'mediaType': mediaType,
        if (mediaType == 'tv' && season != null) 'season': season,
        if (mediaType == 'tv' && episode != null) 'episode': episode,
      },
    );
    final items = (res.data['items'] as List<dynamic>?) ?? const [];
    return items
        .map((e) => WebSubtitleTrack.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<SubtitleCue>> cuesFor(WebSubtitleTrack track) async {
    final cached = _cues[track.fileId];
    if (cached != null) return cached;
    final res = await ApiClient.instance.dio.get<String>(
      '/subtitles/file/${track.fileId}',
    );
    final cues = parseSubtitles(res.data ?? '');
    _cues[track.fileId] = cues;
    return cues;
  }
}

final _timing = RegExp(
  r'(\d{1,2}:)?(\d{1,2}):(\d{2})[.,](\d{1,3})\s*-->\s*(\d{1,2}:)?(\d{1,2}):(\d{2})[.,](\d{1,3})',
);
final _tags = RegExp(r'<[^>]+>|\{\\[^}]*\}');

double _seconds(String? h, String m, String s, String ms) =>
    (h == null ? 0 : int.parse(h.substring(0, h.length - 1))) * 3600 +
    int.parse(m) * 60 +
    int.parse(s) +
    int.parse(ms.padRight(3, '0')) / 1000;

/// Parses SRT or WebVTT text into cues, sorted by start time. Styling tags
/// are stripped; line breaks inside a cue are kept.
List<SubtitleCue> parseSubtitles(String raw) {
  final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final cues = <SubtitleCue>[];
  for (final block in text.split(RegExp(r'\n\s*\n'))) {
    final lines = block.split('\n');
    final i = lines.indexWhere(_timing.hasMatch);
    if (i < 0) continue;
    final m = _timing.firstMatch(lines[i])!;
    final body = lines
        .skip(i + 1)
        .map((l) => l.replaceAll(_tags, '').trim())
        .where((l) => l.isNotEmpty)
        .join('\n');
    if (body.isEmpty) continue;
    cues.add(
      SubtitleCue(
        _seconds(m[1], m[2]!, m[3]!, m[4]!),
        _seconds(m[5], m[6]!, m[7]!, m[8]!),
        body,
      ),
    );
  }
  cues.sort((a, b) => a.start.compareTo(b.start));
  return cues;
}

/// The cue showing at [t] seconds, if any.
SubtitleCue? cueAt(List<SubtitleCue> cues, double t) {
  var lo = 0, hi = cues.length - 1, found = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (cues[mid].start <= t) {
      found = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  // Overlapping cues: walk back to any earlier one still on screen.
  for (var j = found; j >= 0 && j > found - 4; j--) {
    if (cues[j].end >= t) return cues[j];
  }
  return null;
}
