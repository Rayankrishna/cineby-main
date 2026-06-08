import 'package:app_web_ui/models/search_model.dart';
import 'package:app_web_ui/services/page_transitions.dart';
import 'package:app_web_ui/services/pages/movie_detail_page.dart';
import 'package:app_web_ui/services/pages/tv_detail_page.dart';
import 'package:app_web_ui/services/responsive.dart';
import 'package:app_web_ui/stores/history_store.dart';
import 'package:app_web_ui/shared/helper.dart';
import 'package:app_web_ui/shared/squeeze_button.dart';

import 'package:app_web_ui/stores/search_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final SearchStore _searchStore = SearchStore();

  @override
  void initState() {
    super.initState();
    _searchStore.fetchHomeFeed();
    historyStore.fetch();
    _searchFocus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_onFocusChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CenteredMaxWidth(
          child: Column(
            children: [
              _buildHeader(),
              _buildSearchBar(),
              Expanded(
                child: Observer(
                  builder: (_) {
                    if (_searchStore.isLoading &&
                        _searchStore.searchResults.isEmpty &&
                        _searchStore.trendingResults.isEmpty) {
                      return const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Color(0xFFEF0003),
                        ),
                      );
                    }

                    if (_searchStore.errorMessage != null) {
                      return Center(
                        child: Text(
                          _searchStore.errorMessage!,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      );
                    }

                    final isSearching = _searchStore.searchQuery.isNotEmpty;
                    if (isSearching) {
                      return _buildSearchResults(_searchStore.searchResults);
                    }
                    return _buildFeed();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.asset(
              'assets/favicon.jpg',
              width: 32,
              height: 32,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            "Reelix",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final hasText = _searchController.text.isNotEmpty;
    final focused = _searchFocus.hasFocus;
    final active = hasText || focused;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: 46,
        decoration: BoxDecoration(
          color:
              active
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color:
                focused
                    ? const Color(0xFFF7BB0D).withValues(alpha: 0.55)
                    : active
                    ? Colors.white.withValues(alpha: 0.16)
                    : Colors.white.withValues(alpha: 0.06),
            width: focused ? 1.2 : 1,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(
              Icons.search_rounded,
              size: 18,
              color: active ? Colors.white70 : Colors.white38,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                ),
                cursorColor: const Color(0xFFF7BB0D),
                cursorWidth: 1.5,
                cursorHeight: 16,
                decoration: const InputDecoration(
                  hintText: 'Search titles, people, genres',
                  hintStyle: TextStyle(
                    color: Colors.white30,
                    fontWeight: FontWeight.w400,
                    fontSize: 14.5,
                    letterSpacing: -0.1,
                  ),
                  isCollapsed: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (value) {
                  _searchStore.setSearchQuery(value);
                  setState(() {});
                },
              ),
            ),
            if (hasText) ...[
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  _searchStore.setSearchQuery('');
                  _searchFocus.unfocus();
                  setState(() {});
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white70,
                    size: 14,
                  ),
                ),
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: const Text(
                    'K',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openDetail(SearchResult r) {
    final isTv =
        r.mediaType == 'tv' ||
        (r.mediaType == null && r.title == null && r.name != null);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) =>
                isTv
                    ? TvDetailPage(tvId: r.id)
                    : MovieDetailPage(movieId: r.id),
      ),
    );
  }

  Widget _buildSearchResults(List<SearchResult> results) {
    if (results.isEmpty) {
      return const Center(
        child: Text(
          'No results found',
          style: TextStyle(color: Colors.white54, fontSize: 15),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Results',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${results.length} '
                '${results.length == 1 ? 'match' : 'matches'} '
                'for "${_searchStore.searchQuery}"',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 12.5,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: posterGridColumns(
                MediaQuery.of(context).size.width,
              ),
              childAspectRatio: 0.58,
              crossAxisSpacing: 12,
              mainAxisSpacing: 18,
            ),
            itemCount: results.length,
            itemBuilder: (context, index) {
              final result = results[index];
              return FadeInUp(
                delay: Duration(milliseconds: 30 * (index % 12)),
                child: _PosterCard(
                  posterPath: result.posterPath,
                  title: result.title ?? result.name ?? 'Unknown',
                  onTap: () => _openDetail(result),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _refreshFeed() async {
    await Future.wait([
      _searchStore.fetchHomeFeed(),
      historyStore.fetch(),
    ]);
  }

  Widget _buildFeed() {
    return RefreshIndicator(
      color: const Color(0xFFEF0003),
      backgroundColor: const Color(0xFF1F1E26),
      onRefresh: _refreshFeed,
      child: ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 120),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Observer(
          builder: (_) {
            if (historyStore.items.isEmpty) return const SizedBox.shrink();
            final items = historyStore.items.take(12).toList();
            return _RailSection(
              title: 'Continue Watching',
              subtitle: 'Pick up where you left off',
              children: [
                for (final h in items)
                  _RailPoster(
                    posterPath: h.posterPath,
                    title: h.title ?? 'Unknown',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) =>
                                  h.mediaType == 'tv'
                                      ? TvDetailPage(tvId: h.tmdbId)
                                      : MovieDetailPage(movieId: h.tmdbId),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
        _RailSection(
          title: 'Trending Today',
          subtitle: 'What everyone\'s watching right now',
          children: [
            for (final r in _searchStore.trendingResults.take(20))
              _RailPoster(
                posterPath: r.posterPath,
                title: r.title ?? r.name ?? 'Unknown',
                onTap: () => _openDetail(r),
              ),
          ],
        ),
        _RailSection(
          title: 'Top Movies',
          subtitle: 'Most popular this week',
          children: [
            for (final r in _searchStore.topMovies.take(20))
              _RailPoster(
                posterPath: r.posterPath,
                title: r.title ?? r.name ?? 'Unknown',
                onTap: () => _openDetail(r),
              ),
          ],
        ),
        _RailSection(
          title: 'Top Series',
          subtitle: 'Binge-worthy shows',
          children: [
            for (final r in _searchStore.topSeries.take(20))
              _RailPoster(
                posterPath: r.posterPath,
                title: r.title ?? r.name ?? 'Unknown',
                onTap: () => _openDetail(r),
              ),
          ],
        ),
        _RailSection(
          title: 'Top Anime',
          subtitle: 'From Japan & China',
          children: [
            for (final r in _searchStore.topAnime.take(20))
              _RailPoster(
                posterPath: r.posterPath,
                title: r.title ?? r.name ?? 'Unknown',
                onTap: () => _openDetail(r),
              ),
          ],
        ),
        _RailSection(
          title: 'Best in Action',
          subtitle: 'Explosions, chases, fights',
          children: [
            for (final r in _searchStore.actionMovies.take(20))
              _RailPoster(
                posterPath: r.posterPath,
                title: r.title ?? r.name ?? 'Unknown',
                onTap: () => _openDetail(r),
              ),
          ],
        ),
        _RailSection(
          title: 'Best in Comedy',
          subtitle: 'Laugh-out-loud picks',
          children: [
            for (final r in _searchStore.comedyMovies.take(20))
              _RailPoster(
                posterPath: r.posterPath,
                title: r.title ?? r.name ?? 'Unknown',
                onTap: () => _openDetail(r),
              ),
          ],
        ),
        _RailSection(
          title: 'Best in Drama',
          subtitle: 'Stories that hit hard',
          children: [
            for (final r in _searchStore.dramaMovies.take(20))
              _RailPoster(
                posterPath: r.posterPath,
                title: r.title ?? r.name ?? 'Unknown',
                onTap: () => _openDetail(r),
              ),
          ],
        ),
        _RailSection(
          title: 'Best in Horror',
          subtitle: 'Don\'t watch alone',
          children: [
            for (final r in _searchStore.horrorMovies.take(20))
              _RailPoster(
                posterPath: r.posterPath,
                title: r.title ?? r.name ?? 'Unknown',
                onTap: () => _openDetail(r),
              ),
          ],
        ),
        _RailSection(
          title: 'Best in Sci-Fi',
          subtitle: 'Worlds beyond ours',
          children: [
            for (final r in _searchStore.sciFiMovies.take(20))
              _RailPoster(
                posterPath: r.posterPath,
                title: r.title ?? r.name ?? 'Unknown',
                onTap: () => _openDetail(r),
              ),
          ],
        ),
        _RailSection(
          title: 'Best in Romance',
          subtitle: 'Love stories worth your time',
          children: [
            for (final r in _searchStore.romanceMovies.take(20))
              _RailPoster(
                posterPath: r.posterPath,
                title: r.title ?? r.name ?? 'Unknown',
                onTap: () => _openDetail(r),
              ),
          ],
        ),
      ],
      ),
    );
  }
}

class _RailSection extends StatelessWidget {
  const _RailSection({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12.5,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 230,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: children.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => children[i],
            ),
          ),
        ],
      ),
    );
  }
}

class _RailPoster extends StatelessWidget {
  const _RailPoster({
    required this.posterPath,
    required this.title,
    required this.onTap,
  });

  final String? posterPath;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SqueezeButton(
      onTap: onTap,
      child: SizedBox(
        width: 118,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 118,
                height: 176,
                child:
                    posterPath != null
                        ? Image.network(
                          'https://image.tmdb.org/t/p/w300$posterPath',
                          fit: BoxFit.cover,
                          errorBuilder:
                              (_, __, ___) => Container(
                                color: const Color(0xFF35343E),
                                child: const Icon(
                                  Icons.movie_rounded,
                                  color: Colors.white24,
                                ),
                              ),
                        )
                        : Container(
                          color: const Color(0xFF35343E),
                          child: const Icon(
                            Icons.movie_rounded,
                            color: Colors.white24,
                          ),
                        ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
    return SqueezeButton(
      onTap: () {
        removeFocus(context);
        onTap();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: const Color(0xFF35343E),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child:
                    posterPath != null
                        ? Image.network(
                          "https://image.tmdb.org/t/p/w300$posterPath",
                          fit: BoxFit.cover,
                          width: double.infinity,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white30,
                                ),
                              ),
                            );
                          },
                          errorBuilder:
                              (context, error, stackTrace) => const Center(
                                child: Icon(
                                  Icons.movie_rounded,
                                  color: Colors.white24,
                                  size: 32,
                                ),
                              ),
                        )
                        : const Center(
                          child: Icon(
                            Icons.movie_rounded,
                            color: Colors.white24,
                            size: 32,
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
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
