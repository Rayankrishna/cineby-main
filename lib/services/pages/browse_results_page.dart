import 'package:app_web_ui/models/search_model.dart';
import 'package:app_web_ui/services/config.dart';
import 'package:app_web_ui/services/page_transitions.dart';
import 'package:app_web_ui/services/pages/movie_detail_page.dart';
import 'package:app_web_ui/services/pages/tv_detail_page.dart';
import 'package:app_web_ui/services/responsive.dart';
import 'package:app_web_ui/services/tmdb_client.dart';
import 'package:app_web_ui/shared/squeeze_button.dart';
import 'package:flutter/material.dart';

/// Browse all movies of one TMDB genre. Opened from the genre chips on
/// movie / TV detail pages.
class GenreResultsPage extends StatefulWidget {
  final int genreId;
  final String genreName;
  final String mediaType; // 'movie' or 'tv'

  const GenreResultsPage({
    super.key,
    required this.genreId,
    required this.genreName,
    this.mediaType = 'movie',
  });

  @override
  State<GenreResultsPage> createState() => _GenreResultsPageState();
}

class _GenreResultsPageState extends State<GenreResultsPage> {
  final ScrollController _scroll = ScrollController();
  final List<SearchResult> _items = [];
  final Set<int> _seenIds = {};

  int _page = 0; // last page successfully loaded
  int _totalPages = 1;
  bool _loading = false; // a fetch is in flight
  bool _initialLoad = true; // before the first page resolves
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadNextPage();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    // Prefetch when within ~600px of the bottom.
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 600) {
      _loadNextPage();
    }
  }

  String _pagedUrl(int page) {
    return widget.mediaType == 'tv'
        ? '$_tmdbBase/discover/tv?api_key=$tmdbApiKey'
            '&with_genres=${widget.genreId}&sort_by=popularity.desc&language=en&page=$page'
        : '$_tmdbBase/discover/movie?api_key=$tmdbApiKey'
            '&with_genres=${widget.genreId}&sort_by=popularity.desc&language=en&page=$page';
  }

  Future<void> _loadNextPage() async {
    if (_loading) return;
    if (_page >= _totalPages) return; // no more pages
    _loading = true;
    final next = _page + 1;
    try {
      final res = await tmdbDio.get(_pagedUrl(next));
      final parsed = SearchResponse.fromJson(res.data);
      _totalPages = parsed.totalPages;
      final now = DateTime.now();
      final fresh = <SearchResult>[];
      for (final r in parsed.results) {
        if (r.posterPath == null) continue;
        if (_seenIds.contains(r.id)) continue;
        final date = r.releaseDate ?? r.firstAirDate;
        if (date == null || date.isEmpty) continue;
        final d = DateTime.tryParse(date);
        if (d == null || d.isAfter(now)) continue;
        _seenIds.add(r.id);
        // /discover omits media_type — patch it so cards route correctly.
        fresh.add(SearchResult(
          id: r.id,
          title: r.title,
          name: r.name,
          originalTitle: r.originalTitle,
          originalName: r.originalName,
          overview: r.overview,
          posterPath: r.posterPath,
          backdropPath: r.backdropPath,
          mediaType: widget.mediaType,
          releaseDate: r.releaseDate,
          firstAirDate: r.firstAirDate,
          voteAverage: r.voteAverage,
          voteCount: r.voteCount,
        ));
      }
      if (!mounted) return;
      setState(() {
        _page = next;
        _items.addAll(fresh);
        _initialLoad = false;
      });
      // If a whole page got filtered down to nothing but more pages exist,
      // keep going so the user isn't left with a short/empty list.
      if (fresh.isEmpty && _page < _totalPages) {
        _loading = false;
        _loadNextPage();
        return;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _initialLoad = false;
      });
    } finally {
      _loading = false;
    }
  }

  void _open(SearchResult r) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => r.mediaType == 'tv'
            ? TvDetailPage(tvId: r.id)
            : MovieDetailPage(movieId: r.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF18181A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF18181A),
        elevation: 0,
        title: Text(widget.genreName),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_initialLoad) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFEF0003)),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error != null ? 'Couldn\'t load — $_error' : 'Nothing found.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
        ),
      );
    }
    final columns = posterGridColumns(MediaQuery.of(context).size.width);
    final hasMore = _page < _totalPages;
    return CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: 0.58,
              crossAxisSpacing: 12,
              mainAxisSpacing: 18,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, i) => browsePosterCard(_items[i], () => _open(_items[i])),
              childCount: _items.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 120),
            child: Center(
              child: hasMore
                  ? const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Color(0xFFEF0003),
                      ),
                    )
                  : const Text(
                      'That\'s everything',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 12.5),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Every movie + TV show an actor has appeared in. Opened from cast tiles
/// on detail pages.
class PersonFilmographyPage extends StatefulWidget {
  final int personId;
  final String personName;

  const PersonFilmographyPage({
    super.key,
    required this.personId,
    required this.personName,
  });

  @override
  State<PersonFilmographyPage> createState() => _PersonFilmographyPageState();
}

class _PersonFilmographyPageState extends State<PersonFilmographyPage> {
  Future<List<SearchResult>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<SearchResult>> _load() async {
    // Fetch both movie + TV credits in parallel, merge by popularity.
    final results = await Future.wait([
      tmdbDio.get(personMovieCreditsUrl(widget.personId)),
      tmdbDio.get(personTvCreditsUrl(widget.personId)),
    ]);
    final movies = (results[0].data['cast'] as List<dynamic>? ?? [])
        .map((e) => _personCreditToSearchResult(
              e as Map<String, dynamic>,
              mediaType: 'movie',
            ))
        .toList();
    final tv = (results[1].data['cast'] as List<dynamic>? ?? [])
        .map((e) => _personCreditToSearchResult(
              e as Map<String, dynamic>,
              mediaType: 'tv',
            ))
        .toList();
    final all = [...movies, ...tv]..sort(
        (a, b) => (b.voteCount ?? 0).compareTo(a.voteCount ?? 0),
      );
    return all;
  }

  SearchResult _personCreditToSearchResult(
    Map<String, dynamic> json, {
    required String mediaType,
  }) {
    return SearchResult(
      id: json['id'] as int,
      title: json['title'] as String?,
      name: json['name'] as String?,
      originalTitle: json['original_title'] as String?,
      originalName: json['original_name'] as String?,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      mediaType: mediaType,
      releaseDate: json['release_date'] as String?,
      firstAirDate: json['first_air_date'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
      voteCount: json['vote_count'] as int?,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF18181A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF18181A),
        elevation: 0,
        title: Text(widget.personName),
      ),
      body: _ResultsBody(future: _future!),
    );
  }
}

class _ResultsBody extends StatelessWidget {
  final Future<List<SearchResult>> future;
  const _ResultsBody({required this.future});

  void _open(BuildContext context, SearchResult r) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => r.mediaType == 'tv'
            ? TvDetailPage(tvId: r.id)
            : MovieDetailPage(movieId: r.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SearchResult>>(
      future: future,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFEF0003)),
          );
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Couldn\'t load — ${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          );
        }
        final items = (snap.data ?? const <SearchResult>[])
            .where((r) => r.posterPath != null)
            .toList();
        if (items.isEmpty) {
          return const Center(
            child: Text(
              'Nothing found.',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }
        final width = MediaQuery.of(context).size.width;
        final columns = posterGridColumns(width);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 0.58,
            crossAxisSpacing: 12,
            mainAxisSpacing: 18,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final r = items[i];
            return FadeInUp(
              delay: Duration(milliseconds: 30 * (i % 12)),
              child: browsePosterCard(r, () => _open(ctx, r)),
            );
          },
        );
      },
    );
  }
}

// TMDB base for the genre /discover URLs (config.dart only exposes a
// page-1 movie helper; paginated browse builds its own URLs).
const String _tmdbBase = 'https://api.themoviedb.org/3';

/// Shared poster card used by both the genre grid and the person grid, so
/// they look and behave identically.
Widget browsePosterCard(SearchResult r, VoidCallback onTap) {
  return SqueezeButton(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              'https://image.tmdb.org/t/p/w300${r.posterPath}',
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFF35343E),
                child: const Center(
                  child: Icon(Icons.movie_rounded, color: Colors.white24),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 34,
          child: Text(
            r.title ?? r.name ?? 'Unknown',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
          ),
        ),
      ],
    ),
  );
}
