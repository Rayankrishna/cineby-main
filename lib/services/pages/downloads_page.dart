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
              for (final c in completed)
                _CompletedRow(
                  item: c,
                  onPlay: () => _play(c),
                  onDelete: () => _delete(c),
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
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF35343E),
        borderRadius: BorderRadius.circular(12),
      ),
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
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: item.progress > 0 ? item.progress : null,
              minHeight: 3,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(Color(0xFFEF0003)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.error != null
                ? 'Failed — ${item.error}'
                : '${(item.progress * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              color: item.error != null
                  ? const Color(0xFFEF0003)
                  : Colors.white54,
              fontSize: 11.5,
            ),
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
