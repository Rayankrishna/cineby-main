import 'dart:convert';
import 'dart:io';

import 'package:app_web_ui/services/config.dart';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _slog(String msg) {
  if (kDebugMode) debugPrint('[SUBS] $msg');
}

/// True if [text] is clearly an HTML page rather than a subtitle file.
bool looksLikeHtml(String text) {
  final t = text.trimLeft().toLowerCase();
  return t.startsWith('<!doctype') || t.startsWith('<html');
}

/// Where a subtitle track comes from.
enum SubtitleSource { yify, openSubtitles }

/// One subtitle entry scraped from yifysubtitles.ch for a title.
class YifySubtitle {
  final String language; // e.g. "English"
  final String langCode; // e.g. "en"
  final int rating;
  final String zipUrl; // https://yifysubtitles.ch/subtitle/<slug>.zip

  const YifySubtitle({
    required this.language,
    required this.langCode,
    required this.rating,
    required this.zipUrl,
  });
}

/// A subtitle track the player can list and select, regardless of provider.
/// [key] is a stable, unique selection id; the player keys its active-track
/// state off it. Resolve the actual VTT with [SubtitleService.vttForTrack].
class SubtitleTrack {
  final String key;
  final String language; // "English"
  final String langCode; // "en"
  final SubtitleSource source;
  final int rank; // YIFY rating or OpenSubtitles download_count (desc sort)
  final String? zipUrl; // YIFY
  final int? fileId; // OpenSubtitles file_id
  final String? release; // OpenSubtitles release name (extra context)

  const SubtitleTrack({
    required this.key,
    required this.language,
    required this.langCode,
    required this.source,
    required this.rank,
    this.zipUrl,
    this.fileId,
    this.release,
  });

  /// Display label, e.g. "English (OpenSubtitles)".
  String get label {
    final tag = source == SubtitleSource.yify ? 'YIFY' : 'OpenSubtitles';
    return '$language ($tag)';
  }
}

/// Fetches subtitles from yifysubtitles.ch by IMDb id (the approach the
/// `yify-subs` npm package uses) and turns the downloaded SRT into WebVTT
/// that `video_player` can render directly — so subtitles no longer depend
/// on whatever the embed iframe happened to expose.
class SubtitleService {
  SubtitleService._();
  static final SubtitleService instance = SubtitleService._();

  static const String _yifyBase = 'https://yifysubtitles.ch';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 12),
      followRedirects: true,
      headers: {
        // yifysubtitles serves a different (sometimes blocking) page to
        // non-browser user agents.
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0 Safari/537.36',
      },
    ),
  );

  // imdb-id → scraped subtitle list, cached for the session.
  final Map<String, List<YifySubtitle>> _listCache = {};
  // track key (zip url / "os:<fileId>") → converted VTT text, session-cached.
  final Map<String, String> _vttCache = {};

  // --- OpenSubtitles REST (api.opensubtitles.com) -------------------------
  // Default base; login may hand back a per-user base_url we should switch to.
  String _osBaseUrl = 'https://api.opensubtitles.com/api/v1';
  String? _osToken; // JWT from login — raises the daily download quota.
  // search-params signature → english tracks, cached for the session.
  final Map<String, List<SubtitleTrack>> _osSearchCache = {};
  // Persisted-session state. OpenSubtitles issues a ~24h token and rate-limits
  // /login, so we must cache the token across launches and reuse it rather
  // than logging in on every cold start (doing so gets throttled, drops us to
  // the anonymous 5/day quota, and silently breaks downloads).
  static const String _kOsToken = 'os_jwt_token';
  static const String _kOsTokenAt = 'os_jwt_token_at_ms';
  static const String _kOsBase = 'os_base_url';
  static const Duration _osTokenTtl = Duration(hours: 23);
  bool _osSessionLoaded = false;
  Future<void>? _osLoginFuture; // dedupes concurrent logins
  DateTime? _osLoginFailedAt; // cooldown so failures don't spam /login

  bool get _osEnabled => openSubtitlesApiKey.isNotEmpty;

  Map<String, String> get _osHeaders => {
        'Api-Key': openSubtitlesApiKey,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': openSubtitlesUserAgent,
        if (_osToken != null) 'Authorization': 'Bearer $_osToken',
      };

  /// Resolve a title's IMDb id from TMDB external_ids. yify is keyed by IMDb,
  /// not TMDB. Works for movies; TV returns the show-level id (yify rarely
  /// has per-episode subs, so TV mostly falls back to iframe-captured subs).
  Future<String?> imdbIdFor(int tmdbId, String mediaType) async {
    try {
      final path = mediaType == 'tv' ? 'tv' : 'movie';
      final res = await _dio.get(
        'https://api.themoviedb.org/3/$path/$tmdbId/external_ids',
        queryParameters: {'api_key': tmdbApiKey},
      );
      final id = res.data['imdb_id'] as String?;
      _slog('imdbIdFor($tmdbId,$mediaType) -> $id');
      if (id == null || id.isEmpty) return null;
      return id;
    } catch (e) {
      _slog('imdbIdFor($tmdbId,$mediaType) FAILED: $e');
      return null;
    }
  }

  /// Scrape every subtitle row for an IMDb id, sorted best-rated first.
  Future<List<YifySubtitle>> listForImdb(String imdbId) async {
    if (_listCache.containsKey(imdbId)) return _listCache[imdbId]!;
    final out = <YifySubtitle>[];
    try {
      final res = await _dio.get(
        '$_yifyBase/movie-imdb/$imdbId',
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Referer': '$_yifyBase/'},
        ),
      );
      final body = res.data.toString();
      // Diagnose Cloudflare / bot-challenge interstitials: the real listing
      // contains "sub-lang"; a challenge page won't.
      final challenged = !body.contains('sub-lang') &&
          (body.toLowerCase().contains('cloudflare') ||
              body.toLowerCase().contains('captcha') ||
              body.toLowerCase().contains('just a moment') ||
              body.toLowerCase().contains('attention required'));
      _slog('listForImdb($imdbId) status=${res.statusCode} '
          'len=${body.length} hasSubLang=${body.contains('sub-lang')} '
          'challenged=$challenged');
      final doc = html_parser.parse(body);
      for (final row in doc.querySelectorAll('tr')) {
        final link = row.querySelector('a[href*="/subtitles/"]');
        if (link == null) continue;
        final href = link.attributes['href'];
        if (href == null || !href.contains('/subtitles/')) continue;
        final slug = href.split('/subtitles/').last.trim();
        if (slug.isEmpty) continue;

        // Language: prefer the dedicated cell, else infer from the slug.
        final langEl = row.querySelector('.sub-lang');
        final language =
            (langEl?.text.trim().isNotEmpty ?? false)
                ? langEl!.text.trim()
                : _languageFromSlug(slug);
        final ratingEl =
            row.querySelector('.rating-cell') ??
            row.querySelector('span.label');
        final rating =
            int.tryParse(
              (ratingEl?.text ?? '').replaceAll(RegExp(r'\D'), ''),
            ) ??
            0;

        out.add(
          YifySubtitle(
            language: language,
            langCode: _codeForLanguage(language),
            rating: rating,
            zipUrl: '$_yifyBase/subtitle/$slug.zip',
          ),
        );
      }
    } catch (e) {
      _slog('listForImdb($imdbId) FAILED: $e');
    }
    out.sort((a, b) => b.rating.compareTo(a.rating));
    _slog('listForImdb($imdbId) parsed ${out.length} subs '
        '(${out.where((s) => s.langCode == 'en').length} english)');
    _listCache[imdbId] = out;
    return out;
  }

  /// English subtitles for a known IMDb id (best-rated first). Preferred over
  /// [englishForTitle] when the caller already has the id (the TMDB movie
  /// detail response includes `imdb_id`), avoiding a second TMDB request.
  Future<List<YifySubtitle>> englishForImdb(String imdbId) async {
    final all = await listForImdb(imdbId);
    return all.where((s) => s.langCode == 'en').toList();
  }

  /// Convenience: resolve imdb then return only the English subtitles
  /// (best-rated first). Empty if none / lookup failed.
  Future<List<YifySubtitle>> englishForTitle(
    int tmdbId,
    String mediaType,
  ) async {
    final imdb = await imdbIdFor(tmdbId, mediaType);
    if (imdb == null) return const [];
    return englishForImdb(imdb);
  }

  /// Unified English subtitle tracks for a title. Combines free YIFY (movies
  /// only — it has no per-episode subs) with OpenSubtitles (movies AND TV
  /// episodes via parent_imdb_id + season/episode). Searching is free; the
  /// returned tracks are only downloaded when the player actually selects one.
  /// YIFY tracks come first so movies default to the free source.
  Future<List<SubtitleTrack>> englishTracks({
    String? imdbId,
    int? tmdbId,
    String mediaType = 'movie',
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    var imdb = imdbId;
    if ((imdb == null || imdb.isEmpty) && tmdbId != null) {
      imdb = await imdbIdFor(tmdbId, mediaType);
    }
    final isEpisode =
        mediaType == 'tv' && seasonNumber != null && episodeNumber != null;

    final results = await Future.wait<List<SubtitleTrack>>([
      // YIFY: movies only — its /movie-imdb endpoint 404s for TV shows.
      (mediaType != 'tv' && imdb != null && imdb.isNotEmpty)
          ? englishForImdb(imdb).then(
              (l) => l.map(_trackFromYify).toList(),
            )
          : Future.value(const <SubtitleTrack>[]),
      // OpenSubtitles: movies and TV episodes.
      _osSearchEnglish(
        imdbId: imdb,
        season: isEpisode ? seasonNumber : null,
        episode: isEpisode ? episodeNumber : null,
      ),
    ]);
    return [...results[0], ...results[1]];
  }

  /// Resolve a track to WebVTT, dispatching to the right provider. Cached.
  Future<String?> vttForTrack(SubtitleTrack t) {
    switch (t.source) {
      case SubtitleSource.yify:
        return vttForZip(t.zipUrl!);
      case SubtitleSource.openSubtitles:
        return _osVttForFile(t.fileId!);
    }
  }

  SubtitleTrack _trackFromYify(YifySubtitle s) => SubtitleTrack(
        key: s.zipUrl,
        language: s.language,
        langCode: s.langCode,
        source: SubtitleSource.yify,
        rank: s.rating,
        zipUrl: s.zipUrl,
      );

  /// Strip the "tt" + leading zeros from an IMDb id → the numeric form the
  /// OpenSubtitles API expects (tt0099685 → "99685"). null if not an id.
  String? _imdbNumeric(String? imdb) {
    if (imdb == null) return null;
    final digits = imdb.replaceAll(RegExp(r'\D'), '');
    return int.tryParse(digits)?.toString();
  }

  /// Restore a persisted JWT (if still fresh) from disk into memory, once.
  Future<void> _loadOsSession() async {
    if (_osSessionLoaded) return;
    _osSessionLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final tok = prefs.getString(_kOsToken);
      final atMs = prefs.getInt(_kOsTokenAt);
      final base = prefs.getString(_kOsBase);
      if (tok != null && tok.isNotEmpty && atMs != null) {
        final age = DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(atMs));
        if (age < _osTokenTtl) {
          _osToken = tok;
          if (base != null && base.isNotEmpty) _osBaseUrl = base;
          _slog('OS session restored from disk (age=${age.inMinutes}m)');
        } else {
          _slog('OS stored token expired (age=${age.inHours}h)');
        }
      }
    } catch (e) {
      _slog('OS session load failed: $e');
    }
  }

  Future<void> _persistOsSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tok = _osToken;
      if (tok != null) {
        await prefs.setString(_kOsToken, tok);
        await prefs.setInt(_kOsTokenAt, DateTime.now().millisecondsSinceEpoch);
        await prefs.setString(_kOsBase, _osBaseUrl);
      } else {
        await prefs.remove(_kOsToken);
        await prefs.remove(_kOsTokenAt);
      }
    } catch (_) {}
  }

  /// Ensure we hold a usable JWT, reusing a disk-persisted one across launches.
  /// Logs in only when there's no valid token (OpenSubtitles rate-limits
  /// /login). Anonymous use still works — it's just capped at 5 downloads/day.
  Future<void> _osEnsureLogin() async {
    if (!_osEnabled) return;
    await _loadOsSession();
    if (_osToken != null) return;
    if (openSubtitlesUsername.isEmpty || openSubtitlesPassword.isEmpty) return;
    // Back off after a failed login so we don't hammer (and get throttled by)
    // the endpoint on every request.
    if (_osLoginFailedAt != null &&
        DateTime.now().difference(_osLoginFailedAt!) <
            const Duration(minutes: 5)) {
      return;
    }
    _osLoginFuture ??= _doOsLogin();
    await _osLoginFuture;
    _osLoginFuture = null;
  }

  /// Token was rejected (401) — drop it and log in fresh once.
  Future<void> _osRelogin() async {
    _osToken = null;
    _osLoginFailedAt = null; // an explicit 401 warrants an immediate retry
    await _persistOsSession(); // clears the stored (dead) token
    _osLoginFuture ??= _doOsLogin();
    await _osLoginFuture;
    _osLoginFuture = null;
  }

  Future<void> _doOsLogin() async {
    try {
      final res = await _dio.post(
        '$_osBaseUrl/login',
        data: {
          'username': openSubtitlesUsername,
          'password': openSubtitlesPassword,
        },
        options: Options(headers: _osHeaders),
      );
      final tok = res.data['token'] as String?;
      if (tok != null && tok.isNotEmpty) {
        _osToken = tok;
        final base = res.data['base_url'] as String?;
        if (base != null && base.isNotEmpty) {
          _osBaseUrl = 'https://$base/api/v1';
        }
        _osLoginFailedAt = null;
        await _persistOsSession();
        _slog('OS login OK (base=$_osBaseUrl)');
      } else {
        _osLoginFailedAt = DateTime.now();
        _slog('OS login: no token in response');
      }
    } catch (e) {
      _osLoginFailedAt = DateTime.now();
      _slog('OS login FAILED: $e');
    }
  }

  /// Search OpenSubtitles for English tracks. For movies pass [imdbId]; for TV
  /// pass the show's [imdbId] as parent plus [season]/[episode]. Search does
  /// NOT count against the download quota.
  Future<List<SubtitleTrack>> _osSearchEnglish({
    String? imdbId,
    int? season,
    int? episode,
  }) async {
    if (!_osEnabled) return const [];
    final numeric = _imdbNumeric(imdbId);
    if (numeric == null) return const [];
    final isEpisode = season != null && episode != null;
    final cacheKey = isEpisode ? '$numeric:s$season:e$episode' : numeric;
    if (_osSearchCache.containsKey(cacheKey)) return _osSearchCache[cacheKey]!;

    final params = <String, dynamic>{
      'languages': 'en',
      'order_by': 'download_count',
      'order_direction': 'desc',
      if (isEpisode) ...{
        'parent_imdb_id': numeric,
        'season_number': season,
        'episode_number': episode,
        'type': 'episode',
      } else ...{
        'imdb_id': numeric,
        'type': 'movie',
      },
    };

    // Two attempts: a 401 means the cached token is dead, so re-login + retry.
    for (var attempt = 0; attempt < 2; attempt++) {
      await _osEnsureLogin();
      try {
        final res = await _dio.get(
          '$_osBaseUrl/subtitles',
          queryParameters: params,
          options: Options(headers: _osHeaders),
        );
        final out = <SubtitleTrack>[];
        final data = res.data['data'] as List? ?? const [];
        for (final item in data) {
          final attrs = (item as Map)['attributes'] as Map?;
          if (attrs == null) continue;
          if ((attrs['language'] as String?)?.toLowerCase() != 'en') continue;
          final files = attrs['files'] as List? ?? const [];
          if (files.isEmpty) continue;
          final rawId = (files.first as Map)['file_id'];
          if (rawId is! num) continue;
          final fileId = rawId.toInt();
          out.add(
            SubtitleTrack(
              key: 'os:$fileId',
              language: 'English',
              langCode: 'en',
              source: SubtitleSource.openSubtitles,
              rank: (attrs['download_count'] as num?)?.toInt() ?? 0,
              fileId: fileId,
              release: attrs['release'] as String?,
            ),
          );
        }
        out.sort((a, b) => b.rank.compareTo(a.rank));
        _slog('OS search($cacheKey) -> ${out.length} english tracks');
        _osSearchCache[cacheKey] = out; // cache only successful responses
        return out;
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        _slog('OS search($cacheKey) FAILED: $code');
        if (code == 401 && attempt == 0) {
          await _osRelogin();
          continue;
        }
        return const [];
      } catch (e) {
        _slog('OS search($cacheKey) FAILED: $e');
        return const [];
      }
    }
    return const [];
  }

  /// Request a temporary download link for an OpenSubtitles file_id, fetch the
  /// SRT, and convert to WebVTT. This is the call that consumes daily quota, so
  /// results are cached to disk — re-watching a title never re-downloads.
  Future<String?> _osVttForFile(int fileId) async {
    if (!_osEnabled) return null;
    final cacheKey = 'os:$fileId';
    final mem = _vttCache[cacheKey];
    if (mem != null) return mem;
    final disk = await _readDiskVtt(cacheKey);
    if (disk != null) {
      _vttCache[cacheKey] = disk;
      _slog('OS download file=$fileId served from disk cache');
      return disk;
    }
    // Two attempts: a 401 means the cached token is dead, so re-login + retry.
    for (var attempt = 0; attempt < 2; attempt++) {
      await _osEnsureLogin();
      try {
        final res = await _dio.post(
          '$_osBaseUrl/download',
          data: {'file_id': fileId, 'sub_format': 'srt'},
          options: Options(headers: _osHeaders),
        );
        final link = res.data['link'] as String?;
        _slog('OS download file=$fileId remaining=${res.data['remaining']} '
            'link=${link != null}');
        if (link == null || link.isEmpty) return null; // e.g. quota exhausted
        final sub = await _dio.get<String>(
          link,
          options: Options(responseType: ResponseType.plain),
        );
        final body = sub.data ?? '';
        if (looksLikeHtml(body) || !body.contains('-->')) {
          _slog('OS download file=$fileId: payload not a subtitle');
          return null;
        }
        final vtt =
            body.trimLeft().startsWith('WEBVTT') ? body : srtToVtt(body);
        _vttCache[cacheKey] = vtt;
        await _writeDiskVtt(cacheKey, vtt);
        return vtt;
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        _slog('OS download file=$fileId FAILED: $code');
        if (code == 401 && attempt == 0) {
          await _osRelogin();
          continue;
        }
        return null;
      } catch (e) {
        _slog('OS download file=$fileId FAILED: $e');
        return null;
      }
    }
    return null;
  }

  // --- on-disk VTT cache (survives app restarts; conserves OS quota) -------
  Future<Directory?> _vttCacheDir() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/subtitle_cache');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } catch (_) {
      return null;
    }
  }

  String _diskName(String cacheKey) =>
      '${cacheKey.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}.vtt';

  Future<String?> _readDiskVtt(String cacheKey) async {
    try {
      final dir = await _vttCacheDir();
      if (dir == null) return null;
      final f = File('${dir.path}/${_diskName(cacheKey)}');
      if (await f.exists()) {
        final s = await f.readAsString();
        if (s.contains('-->')) return s;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _writeDiskVtt(String cacheKey, String vtt) async {
    try {
      final dir = await _vttCacheDir();
      if (dir == null) return;
      await File('${dir.path}/${_diskName(cacheKey)}').writeAsString(vtt);
    } catch (_) {}
  }

  /// Download a yify subtitle zip, extract the first .srt inside, and return
  /// it converted to WebVTT. Cached per zip URL.
  Future<String?> vttForZip(String zipUrl) async {
    if (_vttCache.containsKey(zipUrl)) return _vttCache[zipUrl];
    try {
      // yifysubtitles 403s the zip without a same-site Referer.
      final res = await _dio.get<List<int>>(
        zipUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Referer': '$_yifyBase/'},
        ),
      );
      final bytes = res.data;
      _slog('vttForZip status=${res.statusCode} bytes=${bytes?.length ?? 0}');
      if (bytes == null || bytes.isEmpty) return null;
      final Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(bytes);
      } catch (e) {
        // Not a real zip — almost always an HTML 403/challenge page.
        _slog('vttForZip NOT A ZIP (likely blocked HTML): $e');
        return null;
      }
      ArchiveFile? srt;
      for (final f in archive.files) {
        if (f.isFile && f.name.toLowerCase().endsWith('.srt')) {
          srt = f;
          break;
        }
      }
      if (srt == null) {
        _slog('vttForZip no .srt in zip (files: '
            '${archive.files.map((f) => f.name).join(', ')})');
        return null;
      }
      final raw = srt.content as List<int>;
      // SRT files are commonly Windows-1252/latin1; utf8-with-malformed keeps
      // it readable either way.
      final srtText = utf8.decode(raw, allowMalformed: true);
      if (!srtText.contains('-->')) {
        _slog('vttForZip extracted file has no cues (not an SRT)');
        return null;
      }
      final vtt = srtToVtt(srtText);
      _slog('vttForZip OK: srt=${srt.name} vttLen=${vtt.length}');
      _vttCache[zipUrl] = vtt;
      return vtt;
    } catch (e) {
      _slog('vttForZip FAILED: $e');
      return null;
    }
  }

  /// Minimal SRT→WebVTT conversion: add the header and turn `,` millisecond
  /// separators into `.` (the only hard format difference video_player cares
  /// about). Cue numbers are kept as VTT cue identifiers.
  String srtToVtt(String srt) {
    var text = srt.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1);
    }
    text = text.replaceAllMapped(
      RegExp(r'(\d{2}:\d{2}:\d{2}),(\d{3})'),
      (m) => '${m.group(1)}.${m.group(2)}',
    );
    return 'WEBVTT\n\n$text';
  }

  String _languageFromSlug(String slug) {
    // slug e.g. "the-dark-knight-2008-english-yify-12345" → "english"
    final m = RegExp(r'-([a-z]+)-yify-', caseSensitive: false).firstMatch(slug);
    if (m != null) {
      final w = m.group(1)!;
      return w.isEmpty ? 'Unknown' : '${w[0].toUpperCase()}${w.substring(1)}';
    }
    return 'Unknown';
  }

  String _codeForLanguage(String language) {
    const map = {
      'english': 'en',
      'spanish': 'es',
      'french': 'fr',
      'german': 'de',
      'italian': 'it',
      'portuguese': 'pt',
      'brazilian portuguese': 'pt',
      'russian': 'ru',
      'chinese': 'zh',
      'chinese bg code': 'zh',
      'japanese': 'ja',
      'korean': 'ko',
      'arabic': 'ar',
      'hindi': 'hi',
      'turkish': 'tr',
      'dutch': 'nl',
      'polish': 'pl',
      'swedish': 'sv',
      'indonesian': 'id',
      'thai': 'th',
      'vietnamese': 'vi',
      'persian': 'fa',
      'farsi/persian': 'fa',
    };
    return map[language.trim().toLowerCase()] ?? language.trim().toLowerCase();
  }
}
