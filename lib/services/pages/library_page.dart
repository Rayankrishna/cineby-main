import 'package:app_web_ui/services/page_transitions.dart';
import 'package:app_web_ui/services/pages/movie_detail_page.dart';
import 'package:app_web_ui/services/pages/tv_detail_page.dart';
import 'package:app_web_ui/services/responsive.dart';
import 'package:app_web_ui/stores/auth_store.dart';
import 'package:app_web_ui/stores/history_store.dart';
import 'package:app_web_ui/stores/watchlist_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    historyStore.fetch();
    watchlistStore.fetch();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _openDetail(int tmdbId, String mediaType) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => mediaType == 'tv'
            ? TvDetailPage(tvId: tmdbId)
            : MovieDetailPage(movieId: tmdbId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B10),
        elevation: 0,
        title: const Text(
          'Library',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded, color: Colors.white70),
            onPressed: () async {
              await authStore.logout();
              if (mounted) {
                Navigator.of(context).popUntil((r) => r.isFirst);
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          indicatorColor: const Color(0xFFE50914),
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Watchlist'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: CenteredMaxWidth(
        child: TabBarView(
          controller: _tab,
          children: [_watchlistTab(), _historyTab()],
        ),
      ),
    );
  }

  Widget _watchlistTab() {
    return Observer(builder: (_) {
      if (watchlistStore.isLoading && watchlistStore.items.isEmpty) {
        return const Center(
          child: CircularProgressIndicator(color: Color(0xFFE50914)),
        );
      }
      if (watchlistStore.items.isEmpty) {
        return const Center(
          child: Text(
            'Your watchlist is empty',
            style: TextStyle(color: Colors.white54, fontSize: 15),
          ),
        );
      }
      return RefreshIndicator(
        color: const Color(0xFFE50914),
        onRefresh: watchlistStore.fetch,
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: posterGridColumns(
              MediaQuery.of(context).size.width,
            ),
            childAspectRatio: 0.58,
            crossAxisSpacing: 12,
            mainAxisSpacing: 18,
          ),
          itemCount: watchlistStore.items.length,
          itemBuilder: (context, index) {
            final item = watchlistStore.items[index];
            return FadeInUp(
              delay: Duration(milliseconds: 30 * (index % 12)),
              child: _PosterCard(
                posterPath: item.posterPath,
                title: item.title ?? 'Unknown',
                onTap: () => _openDetail(item.tmdbId, item.mediaType),
              ),
            );
          },
        ),
      );
    });
  }

  Widget _historyTab() {
    return Observer(builder: (_) {
      if (historyStore.isLoading && historyStore.items.isEmpty) {
        return const Center(
          child: CircularProgressIndicator(color: Color(0xFFE50914)),
        );
      }
      if (historyStore.items.isEmpty) {
        return const Center(
          child: Text(
            'No watch history yet',
            style: TextStyle(color: Colors.white54, fontSize: 15),
          ),
        );
      }
      return RefreshIndicator(
        color: const Color(0xFFE50914),
        onRefresh: historyStore.fetch,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: historyStore.items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final item = historyStore.items[index];
            final progress = item.durationSeconds != null &&
                    item.durationSeconds! > 0
                ? (item.progressSeconds / item.durationSeconds!).clamp(0.0, 1.0)
                : 0.0;
            return Dismissible(
              key: ValueKey(item.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFE50914),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.delete_outline, color: Colors.white),
              ),
              onDismissed: (_) => historyStore.remove(item.id),
              child: InkWell(
                onTap: () => _openDetail(item.tmdbId, item.mediaType),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A22),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 60,
                          height: 90,
                          child: item.posterPath != null
                              ? Image.network(
                                  'https://image.tmdb.org/t/p/w185${item.posterPath}',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Colors.black26,
                                    child: const Icon(
                                      Icons.movie_rounded,
                                      color: Colors.white24,
                                    ),
                                  ),
                                )
                              : Container(
                                  color: Colors.black26,
                                  child: const Icon(
                                    Icons.movie_rounded,
                                    color: Colors.white24,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title ?? 'Unknown',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.mediaType == 'tv'
                                  ? 'S${item.seasonNumber} · E${item.episodeNumber}'
                                  : 'Movie',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 3,
                                backgroundColor: Colors.white12,
                                valueColor: const AlwaysStoppedAnimation(
                                  Color(0xFFE50914),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    });
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.posterPath,
    required this.title,
    required this.onTap,
  });

  final String? posterPath;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: const Color(0xFF1A1A22),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: posterPath != null
                    ? Image.network(
                        'https://image.tmdb.org/t/p/w300$posterPath',
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(
                            Icons.movie_rounded,
                            color: Colors.white24,
                          ),
                        ),
                      )
                    : const Center(
                        child: Icon(
                          Icons.movie_rounded,
                          color: Colors.white24,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
