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
  Future<List<SearchResult>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<SearchResult>> _load() async {
    final base = widget.mediaType == 'tv'
        ? '$_tmdbTvBase/discover/tv?api_key=$tmdbApiKey'
            '&with_genres=${widget.genreId}&sort_by=popularity.desc&language=en&page=1'
        : movieByGenreUrl(widget.genreId);
    final res = await tmdbDio.get(base);
    final results = SearchResponse.fromJson(res.data).results;
    // /discover doesn't include media_type — patch it in so the cards know
    // which detail page to route to.
    return results
        .map((r) => SearchResult(
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
            ))
        .toList();
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
      body: _ResultsBody(future: _future!),
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
              child: SqueezeButton(
                onTap: () => _open(ctx, r),
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
                              child: Icon(Icons.movie_rounded,
                                  color: Colors.white24),
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
              ),
            );
          },
        );
      },
    );
  }
}

// Re-export the TMDB base for the genre fetch that needs a /discover/tv URL
// (config.dart only exposes a movie helper).
const String _tmdbTvBase = 'https://api.themoviedb.org/3';
