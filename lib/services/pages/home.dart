import 'package:app_web_ui/services/page_transitions.dart';
import 'package:app_web_ui/services/pages/library_page.dart';
import 'package:app_web_ui/services/pages/movie_detail_page.dart';
import 'package:app_web_ui/services/pages/tv_detail_page.dart';
import 'package:app_web_ui/services/responsive.dart';
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
    _searchStore.fetchTrendingResults();
  }

  @override
  void dispose() {
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
                          color: Color(0xFFE50914),
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
                    final results =
                        isSearching
                            ? _searchStore.searchResults
                            : _searchStore.trendingResults;

                    if (results.isEmpty) {
                      return const Center(
                        child: Text(
                          "No results found",
                          style: TextStyle(color: Colors.white54, fontSize: 15),
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                isSearching ? "Results" : "Trending Today",
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.5,
                                  color: Colors.white,
                                ),
                              ),
                              if (!isSearching)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFFE50914,
                                    ).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.local_fire_department_rounded,
                                        size: 14,
                                        color: Color(0xFFE50914),
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        "HOT",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.0,
                                          color: Color(0xFFE50914),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
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
                              final isTv =
                                  result.mediaType == 'tv' ||
                                  (result.mediaType == null &&
                                      result.title == null &&
                                      result.name != null);
                              return FadeInUp(
                                delay: Duration(
                                  milliseconds: 30 * (index % 12),
                                ),
                                child: _PosterCard(
                                  posterPath: result.posterPath,
                                  title:
                                      result.title ?? result.name ?? 'Unknown',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (context) =>
                                                isTv
                                                    ? TvDetailPage(
                                                      tvId: result.id,
                                                    )
                                                    : MovieDetailPage(
                                                      movieId: result.id,
                                                    ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.asset(
                  'assets/reelix.jpeg',
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
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E26),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              tooltip: 'Library',
              icon: const Icon(
                Icons.bookmark_outline_rounded,
                color: Colors.white70,
                size: 22,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LibraryPage()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          cursorColor: const Color(0xFFE50914),
          decoration: InputDecoration(
            hintText: 'Search movies, shows, people…',
            hintStyle: const TextStyle(
              color: Colors.white38,
              fontWeight: FontWeight.w400,
              fontSize: 15,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: Colors.white54,
              size: 22,
            ),
            suffixIcon:
                _searchController.text.isNotEmpty
                    ? IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white54,
                        size: 20,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        _searchStore.setSearchQuery('');
                        setState(() {});
                      },
                    )
                    : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 16,
            ),
          ),
          onChanged: (value) {
            _searchStore.setSearchQuery(value);
            setState(() {});
          },
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
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: const Color(0xFF1A1A22),
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
