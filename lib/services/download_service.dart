import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Downloads a captured stream URL (HLS .m3u8 OR direct .mp4) to the app's
/// private documents directory. Files live under:
///
///   `<docs>/downloads/<key>/`
///
/// where `<key>` is `<tmdbId>` for movies and `<tmdbId>_s<S>e<E>` for TV
/// episodes. The returned path is what to feed back into the player.
///
/// HLS: the master playlist's highest-bandwidth variant is downloaded, every
/// segment is fetched with the captured headers, and the local manifest is
/// rewritten so segment URIs become local relative paths.
///
/// MP4: a single bytes download via Dio with progress callback.
///
/// No encryption in v1 — files sit in app-private storage which is already
/// sandboxed per Android/iOS. Add AES later if needed.
class DownloadService {
  DownloadService._();
  static final DownloadService instance = DownloadService._();

  final Dio _dio = Dio();

  Future<Directory> _downloadsRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _itemKey({
    required int tmdbId,
    required String mediaType,
    int? seasonNumber,
    int? episodeNumber,
  }) {
    if (mediaType == 'tv' && seasonNumber != null && episodeNumber != null) {
      return '${tmdbId}_s${seasonNumber}e$episodeNumber';
    }
    return tmdbId.toString();
  }

  Future<Directory> itemDir({
    required int tmdbId,
    required String mediaType,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    final root = await _downloadsRoot();
    final dir = Directory('${root.path}/${_itemKey(
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    )}');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Start a download. Calls [onProgress] with 0.0..1.0 as work completes.
  /// Returns the local path to the playable file on completion (index.m3u8
  /// for HLS, video.mp4 for MP4).
  Future<String> download({
    required int tmdbId,
    required String mediaType,
    required String url,
    Map<String, String> headers = const {},
    int? seasonNumber,
    int? episodeNumber,
    void Function(double progress)? onProgress,
    Map<String, dynamic>? meta,
  }) async {
    final dir = await itemDir(
      tmdbId: tmdbId,
      mediaType: mediaType,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );

    final lower = url.toLowerCase();
    final isHls = lower.contains('.m3u8');

    final String playablePath = isHls
        ? await _downloadHls(url, headers, dir, onProgress)
        : await _downloadMp4(url, headers, dir, onProgress);

    // Drop a small JSON manifest alongside so the Downloads page can render
    // a meaningful row (title, poster, duration, etc.).
    if (meta != null) {
      final metaFile = File('${dir.path}/meta.json');
      await metaFile.writeAsString(jsonEncode({
        ...meta,
        'tmdbId': tmdbId,
        'mediaType': mediaType,
        if (seasonNumber != null) 'seasonNumber': seasonNumber,
        if (episodeNumber != null) 'episodeNumber': episodeNumber,
        'playablePath': playablePath,
        'savedAt': DateTime.now().toIso8601String(),
      }));
    }

    return playablePath;
  }

  Future<String> _downloadMp4(
    String url,
    Map<String, String> headers,
    Directory dir,
    void Function(double)? onProgress,
  ) async {
    final out = File('${dir.path}/video.mp4');
    await _dio.download(
      url,
      out.path,
      options: Options(headers: headers, followRedirects: true),
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
    );
    return out.path;
  }

  Future<String> _downloadHls(
    String url,
    Map<String, String> headers,
    Directory dir,
    void Function(double)? onProgress,
  ) async {
    final manifestRes = await http.get(Uri.parse(url), headers: headers);
    final manifest = manifestRes.body;

    // Master playlist → recurse into the highest-bandwidth variant.
    if (manifest.contains('#EXT-X-STREAM-INF')) {
      final variantUrl = _pickBestVariant(manifest, url);
      return _downloadHls(variantUrl, headers, dir, onProgress);
    }

    // Media playlist — extract every segment URI.
    final segmentUris = _extractMediaPlaylistUris(manifest, url);
    if (segmentUris.isEmpty) {
      throw StateError('HLS manifest has no segments: $url');
    }

    final localNames = <String>[];
    for (var i = 0; i < segmentUris.length; i++) {
      final segUrl = segmentUris[i];
      final segRes = await http.get(Uri.parse(segUrl), headers: headers);
      if (segRes.statusCode < 200 || segRes.statusCode >= 300) {
        throw HttpException(
          'segment ${i + 1} returned ${segRes.statusCode}',
          uri: Uri.parse(segUrl),
        );
      }
      final localName = 'seg_${i.toString().padLeft(5, '0')}.ts';
      final segFile = File('${dir.path}/$localName');
      await segFile.writeAsBytes(segRes.bodyBytes);
      localNames.add(localName);
      onProgress?.call((i + 1) / segmentUris.length);
    }

    // Rewrite the manifest with local relative paths so ExoPlayer reads our
    // downloaded segments instead of going back to the CDN.
    final localManifest =
        _rewriteManifestPaths(manifest, localNames);
    final manifestFile = File('${dir.path}/index.m3u8');
    await manifestFile.writeAsString(localManifest);
    return manifestFile.path;
  }

  String _pickBestVariant(String masterManifest, String baseUrl) {
    final lines = masterManifest.split('\n');
    int bestBandwidth = -1;
    String? bestUri;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      final bw = bwMatch != null ? int.parse(bwMatch.group(1)!) : 0;
      for (var j = i + 1; j < lines.length; j++) {
        final next = lines[j].trim();
        if (next.isEmpty || next.startsWith('#')) continue;
        if (bw > bestBandwidth) {
          bestBandwidth = bw;
          bestUri = next;
        }
        break;
      }
    }
    return bestUri == null ? baseUrl : _resolveUri(bestUri, baseUrl);
  }

  List<String> _extractMediaPlaylistUris(String manifest, String baseUrl) {
    final lines = manifest.split('\n');
    final uris = <String>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      uris.add(_resolveUri(line, baseUrl));
    }
    return uris;
  }

  String _rewriteManifestPaths(String manifest, List<String> localNames) {
    final lines = manifest.split('\n');
    var segIndex = 0;
    final out = <String>[];
    for (final raw in lines) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        out.add(raw);
        continue;
      }
      if (segIndex < localNames.length) {
        out.add(localNames[segIndex]);
        segIndex++;
      } else {
        out.add(raw);
      }
    }
    return out.join('\n');
  }

  String _resolveUri(String uri, String baseUrl) {
    if (uri.startsWith('http://') || uri.startsWith('https://')) return uri;
    return Uri.parse(baseUrl).resolve(uri).toString();
  }

  /// Returns all completed downloads (directories that hold either a
  /// `video.mp4` or `index.m3u8`).
  Future<List<DownloadedItem>> list() async {
    final root = await _downloadsRoot();
    if (!await root.exists()) return const [];
    final children = root.listSync();
    final items = <DownloadedItem>[];
    for (final entity in children) {
      if (entity is! Directory) continue;
      final mp4 = File('${entity.path}/video.mp4');
      final m3u8 = File('${entity.path}/index.m3u8');
      final playable = await mp4.exists()
          ? mp4.path
          : (await m3u8.exists() ? m3u8.path : null);
      if (playable == null) continue;
      final metaFile = File('${entity.path}/meta.json');
      Map<String, dynamic> meta = const {};
      if (await metaFile.exists()) {
        try {
          meta = Map<String, dynamic>.from(
              jsonDecode(await metaFile.readAsString()) as Map);
        } catch (_) {}
      }
      items.add(DownloadedItem(
        dir: entity,
        playablePath: playable,
        meta: meta,
      ));
    }
    items.sort((a, b) =>
        (b.savedAt ?? DateTime(0)).compareTo(a.savedAt ?? DateTime(0)));
    return items;
  }

  Future<void> delete(DownloadedItem item) async {
    if (await item.dir.exists()) {
      await item.dir.delete(recursive: true);
    }
  }
}

class DownloadedItem {
  final Directory dir;
  final String playablePath;
  final Map<String, dynamic> meta;

  DownloadedItem({
    required this.dir,
    required this.playablePath,
    required this.meta,
  });

  String? get title => meta['title'] as String?;
  String? get posterPath => meta['posterPath'] as String?;
  String? get backdropPath => meta['backdropPath'] as String?;
  int? get tmdbId => meta['tmdbId'] is int
      ? meta['tmdbId'] as int
      : int.tryParse('${meta['tmdbId']}');
  String? get mediaType => meta['mediaType'] as String?;
  int? get seasonNumber => meta['seasonNumber'] is int
      ? meta['seasonNumber'] as int
      : int.tryParse('${meta['seasonNumber']}');
  int? get episodeNumber => meta['episodeNumber'] is int
      ? meta['episodeNumber'] as int
      : int.tryParse('${meta['episodeNumber']}');
  DateTime? get savedAt {
    final s = meta['savedAt'];
    if (s is String) return DateTime.tryParse(s);
    return null;
  }
}
