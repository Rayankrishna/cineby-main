import 'package:app_web_ui/services/page_transitions.dart';
import 'package:app_web_ui/services/pages/webview.dart';
import 'package:app_web_ui/services/responsive.dart';
import 'package:app_web_ui/services/stream_servers.dart';
import 'package:app_web_ui/services/toast.dart';
import 'package:app_web_ui/shared/squeeze_button.dart';
import 'package:app_web_ui/stores/download_store.dart';
import 'package:app_web_ui/stores/history_store.dart';
import 'package:app_web_ui/stores/movie_detail_store.dart';
import 'package:app_web_ui/stores/watchlist_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

class MovieDetailPage extends StatefulWidget {
  final int movieId;

  const MovieDetailPage({super.key, required this.movieId});

  @override
  State<MovieDetailPage> createState() => _MovieDetailPageState();
}

class _MovieDetailPageState extends State<MovieDetailPage> {
  final MovieDetailStore _store = MovieDetailStore();
  HistoryItem? _lastWatched;
  bool _lastWatchedLoaded = false;
  // User-selected stream provider. Defaults to the first entry in
  // [streamServers] (currently 111Movies). Tapping the source pill below
  // the Play button updates this and the next Play uses the chosen one.
  StreamServer _selectedServer = streamServers.first;

  void _showSourcePicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1F1E26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.dns_rounded,
                        color: Color(0xFFEF0003), size: 22),
                    SizedBox(width: 10),
                    Text('Choose source',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        )),
                  ],
                ),
              ),
              for (final s in streamServers)
                InkWell(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    setState(() => _selectedServer = s);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.play_circle_outline_rounded,
                            color: s == _selectedServer
                                ? const Color(0xFFEF0003)
                                : Colors.white70,
                            size: 20),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            s.name,
                            style: TextStyle(
                              color: s == _selectedServer
                                  ? const Color(0xFFEF0003)
                                  : Colors.white,
                              fontSize: 14.5,
                              fontWeight: s == _selectedServer
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (s == _selectedServer)
                          const Icon(Icons.check_rounded,
                              color: Color(0xFFEF0003), size: 18),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _store.fetchMovieDetail(widget.movieId);
    watchlistStore.checkContains(widget.movieId, 'movie');
    _loadLastWatched();
  }

  Future<void> _loadLastWatched() async {
    final item = await historyStore.latestForMovie(widget.movieId);
    if (!mounted) return;
    setState(() {
      _lastWatched = item;
      _lastWatchedLoaded = true;
    });
  }

  void _startDownload(dynamic movie) {
    // Fire-and-forget. The DownloadStore runs extraction + the actual
    // download on its own — backing out of the detail page mid-flight no
    // longer cancels anything. The Downloads tab shows the placeholder
    // "Extracting…" state until the stream URL is captured.
    final embedUrl =
        _selectedServer.buildUrl(widget.movieId, 'movie', null, null);
    downloadStore.startWithExtraction(
      embedUrl: embedUrl,
      tmdbId: widget.movieId,
      mediaType: 'movie',
      title: movie.title,
      posterPath: movie.posterPath,
      backdropPath: movie.backdropPath,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Extracting stream… download will continue in the background. Check the Downloads tab.'),
      ),
    );
  }

  String _formatRuntime(int? minutes) {
    if (minutes == null) return '';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h}h ${m}m';
  }

  String _formatYear(String? date) {
    if (date == null || date.isEmpty) return '';
    return date.split('-').first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF18181A),
      body: Observer(
        builder: (_) {
          if (_store.isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.red),
            );
          }

          if (_store.errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Couldn\'t reach the catalog. Check your connection and try again.',
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF0003),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () =>
                              _store.fetchMovieDetail(widget.movieId),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Try again'),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'Go Back',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }

          final movie = _store.movieDetail;
          if (movie == null) {
            return const Center(
              child: Text('No details available',
                  style: TextStyle(color: Colors.white70)),
            );
          }

          return CustomScrollView(
            slivers: [
              // Backdrop with gradient
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    // Backdrop image
                    if (movie.backdropPath != null)
                      Image.network(
                        'https://image.tmdb.org/t/p/w780${movie.backdropPath}',
                        height: 280,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 280,
                          color: Colors.grey[900],
                        ),
                      )
                    else
                      Container(height: 280, color: Colors.grey[900]),

                    // Gradient overlay
                    Positioned.fill(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Color(0xFF18181A),
                            ],
                            stops: [0.4, 1.0],
                          ),
                        ),
                      ),
                    ),

                    // Back button
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 8,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),

                    // Top-right action row: Download + Watchlist toggle.
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      right: 8,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Observer(builder: (_) {
                            final key = widget.movieId.toString();
                            final activeMatch = downloadStore.active
                                .where((a) => a.key == key)
                                .toList();
                            final done = downloadStore.completed
                                .any((c) => c.tmdbId == widget.movieId);
                            if (done) {
                              return const IconButton(
                                iconSize: 32,
                                tooltip: 'Downloaded',
                                onPressed: null,
                                icon: Icon(
                                  Icons.download_done_rounded,
                                  color: Color(0xFFEF0003),
                                ),
                              );
                            }
                            if (activeMatch.isNotEmpty) {
                              final a = activeMatch.first;
                              final p = a.progress.clamp(0.0, 1.0);
                              return IconButton(
                                iconSize: 44,
                                tooltip: 'Cancel download',
                                onPressed: () => downloadStore.cancel(a),
                                icon: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: CircularProgressIndicator(
                                        value: p > 0 ? p : null,
                                        strokeWidth: 2.6,
                                        color: const Color(0xFFEF0003),
                                        backgroundColor: Colors.white12,
                                      ),
                                    ),
                                    const Icon(Icons.close_rounded,
                                        color: Colors.white, size: 16),
                                  ],
                                ),
                              );
                            }
                            return IconButton(
                              iconSize: 32,
                              tooltip: 'Download',
                              onPressed: () => _startDownload(movie),
                              icon: const Icon(
                                Icons.download_rounded,
                                color: Colors.white,
                              ),
                            );
                          }),
                          Observer(builder: (_) {
                            final inList = watchlistStore.cachedContains(
                                  widget.movieId,
                                  'movie',
                                ) ??
                                false;
                            return IconButton(
                              icon: Icon(
                                inList
                                    ? Icons.bookmark_rounded
                                    : Icons.bookmark_outline_rounded,
                                color: inList
                                    ? const Color(0xFFF7BB0D)
                                    : Colors.white,
                              ),
                              onPressed: () => watchlistStore.toggle(
                                tmdbId: widget.movieId,
                                mediaType: 'movie',
                                title: movie.title,
                                posterPath: movie.posterPath,
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              SliverToBoxAdapter(
                child: FadeInUp(
                  duration: const Duration(milliseconds: 380),
                  offset: 20,
                  child: CenteredMaxWidth(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        movie.title ?? 'Unknown',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Meta row: year · runtime · rating
                      Row(
                        children: [
                          if (_formatYear(movie.releaseDate).isNotEmpty) ...[
                            Text(
                              _formatYear(movie.releaseDate),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 14),
                            ),
                            const SizedBox(width: 12),
                          ],
                          if (movie.runtime != null && movie.runtime! > 0) ...[
                            Text(
                              _formatRuntime(movie.runtime),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 14),
                            ),
                            const SizedBox(width: 12),
                          ],
                          if (movie.voteAverage != null) ...[
                            const Icon(Icons.star,
                                color: Color(0xFFF7BB0D), size: 16),
                            const SizedBox(width: 4),
                            Text(
                              movie.voteAverage!.toStringAsFixed(1),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Play button (hidden until we know watch state)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: !_lastWatchedLoaded
                            ? Container(
                                decoration: BoxDecoration(
                                  color: Colors.white12,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              )
                            : SqueezeButton(
                          onTap: () {
                            // User explicitly chose a source via the pill
                            // below. Trust the selection; if it's down, the
                            // in-loading source switcher handles recovery.
                            showPlayerHintToast();
                            final resumeSeconds =
                                _lastWatched?.progressSeconds ?? 0;
                            historyStore.record(
                              tmdbId: movie.id,
                              mediaType: 'movie',
                              progressSeconds: resumeSeconds,
                              durationSeconds: movie.runtime != null
                                  ? movie.runtime! * 60
                                  : null,
                              title: movie.title,
                              posterPath: movie.posterPath,
                              backdropPath: movie.backdropPath,
                            );
                            final embedUrl = _selectedServer.buildUrl(
                                movie.id, 'movie', null, null);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MyWidget(
                                  url: embedUrl,
                                  tmdbId: movie.id,
                                  mediaType: 'movie',
                                  durationSeconds: movie.runtime != null
                                      ? movie.runtime! * 60
                                      : null,
                                  initialProgressSeconds: resumeSeconds,
                                  title: movie.title,
                                  posterPath: movie.posterPath,
                                  backdropPath: movie.backdropPath,
                                ),
                              ),
                            ).then((_) {
                              _loadLastWatched();
                              historyStore.fetch();
                            });
                          },
                          child: Container(
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _lastWatched != null
                                      ? Icons.play_circle_outline_rounded
                                      : Icons.play_arrow,
                                  size: 28,
                                  color: Colors.black,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _lastWatched != null ? 'Resume' : 'Play',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Source pill — tap to swap providers before launching.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SqueezeButton(
                          onTap: _showSourcePicker,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.dns_rounded,
                                    color: Color(0xFFEF0003), size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'Source: ${_selectedServer.name}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.keyboard_arrow_down_rounded,
                                    color: Colors.white54, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_lastWatched != null &&
                          _lastWatched!.durationSeconds != null &&
                          _lastWatched!.durationSeconds! > 0) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: (_lastWatched!.progressSeconds /
                                    _lastWatched!.durationSeconds!)
                                .clamp(0.0, 1.0),
                            minHeight: 3,
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation(
                                Color(0xFFEF0003)),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Tagline
                      if (movie.tagline != null &&
                          movie.tagline!.isNotEmpty) ...[
                        Text(
                          movie.tagline!,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Overview
                      if (movie.overview != null &&
                          movie.overview!.isNotEmpty) ...[
                        Text(
                          movie.overview!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Genres
                      if (movie.genres.isNotEmpty) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: movie.genres
                              .map(
                                (g) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white12,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    g.name,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Director
                      if (movie.directorName != null) ...[
                        Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(
                                text: 'Director: ',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 13),
                              ),
                              TextSpan(
                                text: movie.directorName,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Cast header
                      if (movie.cast.isNotEmpty) ...[
                        const Text(
                          'Cast',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
                ),
              ),

              // Cast horizontal list
              if (movie.cast.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 140,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: movie.cast.length,
                      itemBuilder: (context, index) {
                        final member = movie.cast[index];
                        return Container(
                          width: 90,
                          margin: const EdgeInsets.only(right: 12),
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: Colors.grey[800],
                                backgroundImage: member.profilePath != null
                                    ? NetworkImage(
                                        'https://image.tmdb.org/t/p/w185${member.profilePath}',
                                      )
                                    : null,
                                child: member.profilePath == null
                                    ? const Icon(Icons.person,
                                        color: Colors.white54, size: 28)
                                    : null,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                member.name ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 11),
                              ),
                              Text(
                                member.character ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 10),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Bottom spacing
              const SliverToBoxAdapter(
                child: SizedBox(height: 40),
              ),
            ],
          );
        },
      ),
    );
  }
}
