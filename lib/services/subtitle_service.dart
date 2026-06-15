import 'dart:convert';

import 'package:app_web_ui/services/config.dart';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

void _slog(String msg) {
  if (kDebugMode) debugPrint('[SUBS] $msg');
}

/// True if [text] is clearly an HTML page rather than a subtitle file.
bool looksLikeHtml(String text) {
  final t = text.trimLeft().toLowerCase();
  return t.startsWith('<!doctype') || t.startsWith('<html');
}

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
  // zip-url → converted VTT text, cached for the session.
  final Map<String, String> _vttCache = {};

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
