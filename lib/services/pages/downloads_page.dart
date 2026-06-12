import 'package:app_web_ui/services/download_service.dart';
import 'package:app_web_ui/services/pages/native_player.dart';
import 'package:app_web_ui/shared/squeeze_button.dart';
import 'package:app_web_ui/stores/download_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  @override
  void initState() {
    super.initState();
    downloadStore.refresh();
  }

  void _openSeries(List<DownloadedItem> episodes) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SeriesEpisodesPage(
          episodes: episodes,
          onPlay: _play,
          onDelete: _delete,
        ),
      ),
    );
  }

  void _play(DownloadedItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NativePlayerPage(
          // videoUrl is unused when localFilePath is set, but the constructor
          // still requires it. Pass a placeholder.
          videoUrl: 'file://${item.playablePath}',
          localFilePath: item.playablePath,
          title: item.title,
          tmdbId: item.tmdbId,
          mediaType: item.mediaType ?? 'movie',
          seasonNumber: item.seasonNumber,
          episodeNumber: item.episodeNumber,
          posterPath: item.posterPath,
          backdropPath: item.backdropPath,
        ),
      ),
    );
  }

  Future<void> _delete(DownloadedItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F1E26),
        title: const Text('Delete download?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          item.title ?? 'This download',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFEF0003))),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await downloadStore.remove(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF18181A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF18181A),
        elevation: 0,
        title: const Text('Downloads'),
      ),
      body: Observer(builder: (_) {
        if (downloadStore.isLoading && downloadStore.completed.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFEF0003)),
          );
        }
        final active = downloadStore.active;
        final completed = downloadStore.completed;
        if (active.isEmpty && completed.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No downloads yet.\nTap the download icon on a movie to save it for offline playback.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ),
          );
        }
        // Split movies vs TV. TV episodes group by tmdbId so a series shows
        // up as one card you can drill into.
        final movies =
            completed.where((c) => c.mediaType != 'tv').toList();
        final tvByShow = <int, List<DownloadedItem>>{};
        for (final c in completed) {
          if (c.mediaType != 'tv' || c.tmdbId == null) continue;
          tvByShow.putIfAbsent(c.tmdbId!, () => []).add(c);
        }

        return RefreshIndicator(
          color: const Color(0xFFEF0003),
          backgroundColor: const Color(0xFF1F1E26),
          onRefresh: downloadStore.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              if (active.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 8, 4, 6),
                  child: Text(
                    'IN PROGRESS',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                for (final a in active) _ActiveRow(item: a),
                const SizedBox(height: 12),
              ],
              if (completed.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 8, 4, 6),
                  child: Text(
                    'AVAILABLE OFFLINE',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
              // Movies — one tile per movie, same as before.
              for (final c in movies)
                _CompletedRow(
                  item: c,
                  onPlay: () => _play(c),
                  onDelete: () => _delete(c),
                ),
              // TV series — one tile per series, count of episodes inside.
              // Tap to open a page with the individual episodes.
              for (final entry in tvByShow.entries)
                _SeriesGroupRow(
                  episodes: entry.value,
                  onOpen: () => _openSeries(entry.value),
                ),
            ],
          ),
        );
      }),
    );
  }
}

class _ActiveRow extends StatelessWidget {
  final ActiveDownload item;
  const _ActiveRow({required this.item});
  @override
  Widget build(BuildContext context) {
    final isExtracting = item.phase == 'extracting';
    final hasError = item.error != null;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF35343E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title ?? 'Untitled',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (item.mediaType == 'tv' &&
                        item.seasonNumber != null &&
                        item.episodeNumber != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        'S${item.seasonNumber} · E${item.episodeNumber}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    // Indeterminate during extraction (no progress to show).
                    value: isExtracting
                        ? null
                        : (item.progress > 0 ? item.progress : null),
                    minHeight: 3,
                    backgroundColor: Colors.white12,
                    valueColor:
                        const AlwaysStoppedAnimation(Color(0xFFEF0003)),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  hasError
                      ? 'Failed — ${item.error}'
                      : isExtracting
                          ? 'Extracting stream…'
                          : '${(item.progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: hasError
                        ? const Color(0xFFEF0003)
                        : Colors.white54,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          // Cancel / dismiss. While extracting or downloading, ✕ aborts and
          // wipes partials. If the row is in an error state, ✕ just clears
          // it (no partials to delete).
          IconButton(
            iconSize: 28,
            tooltip: hasError ? 'Dismiss' : 'Cancel download',
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            onPressed: () {
              if (hasError) {
                downloadStore.dismissActiveError(item);
              } else {
                downloadStore.cancel(item);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _CompletedRow extends StatelessWidget {
  final DownloadedItem item;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  const _CompletedRow({
    required this.item,
    required this.onPlay,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SqueezeButton(
        onTap: onPlay,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF35343E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 54,
                  height: 80,
                  child: item.posterPath != null
                      ? Image.network(
                          'https://image.tmdb.org/t/p/w185${item.posterPath}',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.black26,
                            child: const Icon(Icons.movie_rounded,
                                color: Colors.white24),
                          ),
                        )
                      : Container(
                          color: Colors.black26,
                          child: const Icon(Icons.movie_rounded,
                              color: Colors.white24),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title ?? 'Untitled',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.mediaType == 'tv' &&
                              item.seasonNumber != null &&
                              item.episodeNumber != null
                          ? 'S${item.seasonNumber} · E${item.episodeNumber}'
                          : 'Movie',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline,
                    color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row representing a whole TV series in the downloads list. Tap to
/// drill into the individual episode list.
class _SeriesGroupRow extends StatelessWidget {
  final List<DownloadedItem> episodes;
  final VoidCallback onOpen;
  const _SeriesGroupRow({required this.episodes, required this.onOpen});

  DownloadedItem get _showcase => episodes.first;

  @override
  Widget build(BuildContext context) {
    final count = episodes.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SqueezeButton(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF35343E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 54,
                  height: 80,
                  child: _showcase.posterPath != null
                      ? Image.network(
                          'https://image.tmdb.org/t/p/w185${_showcase.posterPath}',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.black26,
                            child: const Icon(Icons.tv_rounded,
                                color: Colors.white24),
                          ),
                        )
                      : Container(
                          color: Colors.black26,
                          child: const Icon(Icons.tv_rounded,
                              color: Colors.white24),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _showcase.title ?? 'Untitled series',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$count episode${count == 1 ? '' : 's'} downloaded',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white38, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Drill-down page showing every downloaded episode of one series. Each row
/// reuses the same `_CompletedRow` widget as movies so play / delete work
/// the same way.
class _SeriesEpisodesPage extends StatelessWidget {
  final List<DownloadedItem> episodes;
  final ValueChanged<DownloadedItem> onPlay;
  final Future<void> Function(DownloadedItem) onDelete;

  const _SeriesEpisodesPage({
    required this.episodes,
    required this.onPlay,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // Identify the series from the snapshot we were opened with, then render
    // the episode list LIVE from downloadStore.completed inside an Observer.
    // Without this, deleting an episode here doesn't refresh the list (the
    // store updates but a captured snapshot doesn't) — you'd have to pop and
    // re-enter to see the change.
    final int? seriesTmdbId =
        episodes.isNotEmpty ? episodes.first.tmdbId : null;
    final String fallbackTitle =
        episodes.isNotEmpty ? (episodes.first.title ?? 'Series') : 'Series';

    return Scaffold(
      backgroundColor: const Color(0xFF18181A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF18181A),
        elevation: 0,
        title: Text(fallbackTitle),
      ),
      body: Observer(
        builder: (_) {
          final sorted = downloadStore.completed
              .where((c) =>
                  c.mediaType == 'tv' && c.tmdbId == seriesTmdbId)
              .toList()
            ..sort((a, b) {
              final sa = a.seasonNumber ?? 0;
              final sb = b.seasonNumber ?? 0;
              if (sa != sb) return sa.compareTo(sb);
              return (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
            });

          // Last episode deleted → return to the downloads list automatically
          // instead of leaving an empty page open.
          if (sorted.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).maybePop();
            });
            return const SizedBox.shrink();
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              for (final ep in sorted)
                _CompletedRow(
                  item: ep,
                  onPlay: () => onPlay(ep),
                  onDelete: () => onDelete(ep),
                ),
            ],
          );
        },
      ),
    );
  }
}
