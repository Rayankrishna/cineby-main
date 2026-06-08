import 'package:app_web_ui/models/tv_detail_model.dart';
import 'package:app_web_ui/services/page_transitions.dart';
import 'package:app_web_ui/services/pages/webview.dart';
import 'package:app_web_ui/services/responsive.dart';
import 'package:app_web_ui/services/server_vote_service.dart';
import 'package:app_web_ui/services/stream_servers.dart';
import 'package:app_web_ui/services/toast.dart';
import 'package:app_web_ui/shared/squeeze_button.dart';
import 'package:app_web_ui/stores/download_store.dart';
import 'package:app_web_ui/stores/history_store.dart';
import 'package:app_web_ui/stores/tv_detail_store.dart';
import 'package:app_web_ui/stores/watchlist_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

class TvDetailPage extends StatefulWidget {
  final int tvId;

  const TvDetailPage({super.key, required this.tvId});

  @override
  State<TvDetailPage> createState() => _TvDetailPageState();
}

class _TvDetailPageState extends State<TvDetailPage> {
  final TvDetailStore _store = TvDetailStore();
  HistoryItem? _lastWatched;
  bool _lastWatchedLoaded = false;
  // User-selected stream provider. Defaults to streamServers.first; tapping
  // the Source pill below the Play button swaps it for the next launch.
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
    _store.fetchTvDetail(widget.tvId);
    watchlistStore.checkContains(widget.tvId, 'tv');
    _loadLastWatched();
    _loadBestServer();
  }

  /// Ask the backend which provider has been working best for this show
  /// and pre-select it as the default Source. Falls back to the local
  /// default if there are no votes yet.
  Future<void> _loadBestServer() async {
    final name = await ServerVoteService.instance.bestServerName(
      tmdbId: widget.tvId,
      mediaType: 'tv',
    );
    if (!mounted || name == null) return;
    final match = streamServers
        .where((s) => s.name == name)
        .cast<StreamServer?>()
        .firstWhere((s) => s != null, orElse: () => null);
    if (match != null) setState(() => _selectedServer = match);
  }

  Future<void> _loadLastWatched() async {
    final item = await historyStore.latestForShow(widget.tvId);
    if (!mounted) return;
    setState(() {
      _lastWatched = item;
      _lastWatchedLoaded = true;
    });
  }

  String _formatYear(String? date) {
    if (date == null || date.isEmpty) return '';
    return date.split('-').first;
  }

  void _downloadEpisode(int season, int episode) {
    // Fire-and-forget. Backing out of the TV detail page mid-extraction
    // no longer cancels the download.
    final tv = _store.tvDetail;
    final embedUrl =
        _selectedServer.buildUrl(widget.tvId, 'tv', season, episode);
    downloadStore.startWithExtraction(
      embedUrl: embedUrl,
      tmdbId: widget.tvId,
      mediaType: 'tv',
      seasonNumber: season,
      episodeNumber: episode,
      title: tv?.name,
      posterPath: tv?.posterPath,
      backdropPath: tv?.backdropPath,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Extracting S$season · E$episode… continues in the background.'),
      ),
    );
  }

  void _playEpisode(
    int season,
    int episode, {
    int progressSeconds = 0,
    int? runtimeMinutes,
  }) {
    final tv = _store.tvDetail;
    // Look up episode runtime from the loaded season if not provided.
    final ep = _store.selectedSeason?.episodes.firstWhere(
      (e) => e.seasonNumber == season && e.episodeNumber == episode,
      orElse: () => _store.selectedSeason!.episodes.first,
    );
    final runtime = runtimeMinutes ?? ep?.runtime;
    final durationSeconds = (runtime != null && runtime > 0) ? runtime * 60 : null;

    // User explicitly chose a source via the pill below the Play button.
    // Trust the selection; if it's down, the in-loading source switcher
    // handles recovery.
    showPlayerHintToast();
    historyStore.record(
      tmdbId: widget.tvId,
      mediaType: 'tv',
      seasonNumber: season,
      episodeNumber: episode,
      progressSeconds: progressSeconds,
      durationSeconds: durationSeconds,
      title: tv?.name,
      posterPath: tv?.posterPath,
      backdropPath: tv?.backdropPath,
    );
    final url = _selectedServer.buildUrl(widget.tvId, 'tv', season, episode);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyWidget(
          url: url,
          tmdbId: widget.tvId,
          mediaType: 'tv',
          seasonNumber: season,
          episodeNumber: episode,
          durationSeconds: durationSeconds,
          initialProgressSeconds: progressSeconds,
          title: tv?.name,
          posterPath: tv?.posterPath,
          backdropPath: tv?.backdropPath,
        ),
      ),
    ).then((_) {
      _loadLastWatched();
      historyStore.fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF18181A),
      body: Observer(
        builder: (_) {
          if (_store.isLoading && _store.tvDetail == null) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFEF0003)),
            );
          }

          if (_store.errorMessage != null && _store.tvDetail == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Color(0xFFEF0003),
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Couldn\'t reach the catalog. Check your connection and try again.',
                      style: TextStyle(color: Colors.white70),
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
                              _store.fetchTvDetail(widget.tvId),
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

          final tv = _store.tvDetail;
          if (tv == null) {
            return const Center(
              child: Text(
                'No details available',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(tv)),
              SliverToBoxAdapter(child: _buildBody(tv)),
              if (tv.seasons.isNotEmpty)
                SliverToBoxAdapter(child: _buildSeasonPicker(tv)),
              _buildEpisodeList(),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(TvDetail tv) {
    return Stack(
      children: [
        if (tv.backdropPath != null)
          Image.network(
            'https://image.tmdb.org/t/p/w780${tv.backdropPath}',
            height: 280,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Container(height: 280, color: Colors.grey[900]),
          )
        else
          Container(height: 280, color: Colors.grey[900]),
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xFF18181A)],
                stops: [0.4, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          right: 8,
          child: Observer(builder: (_) {
            final inList =
                watchlistStore.cachedContains(widget.tvId, 'tv') ?? false;
            return IconButton(
              icon: Icon(
                inList
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_outline_rounded,
                color: inList ? const Color(0xFFF7BB0D) : Colors.white,
              ),
              onPressed: () => watchlistStore.toggle(
                tmdbId: widget.tvId,
                mediaType: 'tv',
                title: tv.name,
                posterPath: tv.posterPath,
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildBody(TvDetail tv) {
    return FadeInUp(
      duration: const Duration(milliseconds: 380),
      offset: 20,
      child: CenteredMaxWidth(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tv.name ?? 'Unknown',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (_formatYear(tv.firstAirDate).isNotEmpty) ...[
                Text(
                  _formatYear(tv.firstAirDate),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(width: 12),
              ],
              if (tv.numberOfSeasons != null && tv.numberOfSeasons! > 0) ...[
                Text(
                  '${tv.numberOfSeasons} Season${tv.numberOfSeasons == 1 ? '' : 's'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(width: 12),
              ],
              if (tv.voteAverage != null) ...[
                const Icon(Icons.star, color: Color(0xFFF7BB0D), size: 16),
                const SizedBox(width: 4),
                Text(
                  tv.voteAverage!.toStringAsFixed(1),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
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
                if (_lastWatched != null) {
                  _playEpisode(
                    _lastWatched!.seasonNumber ?? 1,
                    _lastWatched!.episodeNumber ?? 1,
                    progressSeconds: _lastWatched!.progressSeconds,
                  );
                } else {
                  final firstSeason = tv.seasons.isNotEmpty
                      ? tv.seasons.first.seasonNumber
                      : 1;
                  _playEpisode(firstSeason, 1);
                }
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
                      _lastWatched != null
                          ? 'Resume S${_lastWatched!.seasonNumber} · E${_lastWatched!.episodeNumber}'
                          : (() {
                              final s = tv.seasons.isNotEmpty
                                  ? tv.seasons.first.seasonNumber
                                  : 1;
                              return 'Play S$s · E1';
                            })(),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                valueColor:
                    const AlwaysStoppedAnimation(Color(0xFFEF0003)),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (tv.tagline != null && tv.tagline!.isNotEmpty) ...[
            Text(
              tv.tagline!,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (tv.overview != null && tv.overview!.isNotEmpty) ...[
            Text(
              tv.overview!,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (tv.genres.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tv.genres
                  .map(
                    (g) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        g.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],
          if (tv.creatorName != null) ...[
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Created by: ',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  TextSpan(
                    text: tv.creatorName,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
      ),
    );
  }

  Widget _buildSeasonPicker(TvDetail tv) {
    // Single-season shows: render a static chip instead of a dropdown — no
    // point making it tappable when there's nothing to pick.
    final singleSeason = tv.seasons.length <= 1;
    final currentSeason = tv.seasons.firstWhere(
      (s) => s.seasonNumber == _store.selectedSeasonNumber,
      orElse: () => tv.seasons.isNotEmpty
          ? tv.seasons.first
          : tv.seasons.first, // safe: only called when seasons isn't empty
    );

    return CenteredMaxWidth(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          const Text(
            'Episodes',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // Constrained so a long season name (e.g. "Season 1: The Original
          // Sin") truncates with ellipsis instead of pushing the row off
          // screen.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF35343E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                child: singleSeason
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          currentSeason.name ??
                              'Season ${currentSeason.seasonNumber}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _store.selectedSeasonNumber,
                          dropdownColor: const Color(0xFF35343E),
                          isExpanded: true,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Colors.white70,
                          ),
                          selectedItemBuilder: (_) => tv.seasons
                              .map((s) => Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      s.name ?? 'Season ${s.seasonNumber}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ))
                              .toList(),
                          items: tv.seasons
                              .map(
                                (s) => DropdownMenuItem<int>(
                                  value: s.seasonNumber,
                                  child: Text(
                                    s.name ?? 'Season ${s.seasonNumber}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              _store.fetchSeason(widget.tvId, value);
                            }
                          },
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEpisodeList() {
    if (_store.isSeasonLoading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: CircularProgressIndicator(color: Color(0xFFEF0003)),
          ),
        ),
      );
    }

    final season = _store.selectedSeason;
    if (season == null || season.episodes.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Text(
            'No episodes available',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    return SliverList.separated(
      itemCount: season.episodes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final ep = season.episodes[index];
        return CenteredMaxWidth(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _EpisodeTile(
            tvId: widget.tvId,
            episode: ep,
            onTap: () => _playEpisode(ep.seasonNumber, ep.episodeNumber),
            onDownload: () =>
                _downloadEpisode(ep.seasonNumber, ep.episodeNumber),
          ),
        );
      },
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.tvId,
    required this.episode,
    required this.onTap,
    required this.onDownload,
  });

  final int tvId;
  final Episode episode;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  String get _dlKey =>
      '${tvId}_s${episode.seasonNumber}e${episode.episodeNumber}';

  @override
  Widget build(BuildContext context) {
    return SqueezeButton(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF35343E),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 130,
                    height: 76,
                    child: episode.stillPath != null
                        ? Image.network(
                            'https://image.tmdb.org/t/p/w300${episode.stillPath}',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.black26,
                              child: const Icon(
                                Icons.tv_rounded,
                                color: Colors.white24,
                              ),
                            ),
                          )
                        : Container(
                            color: Colors.black26,
                            child: const Icon(
                              Icons.tv_rounded,
                              color: Colors.white24,
                            ),
                          ),
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${episode.episodeNumber}. ${episode.name ?? 'Episode ${episode.episodeNumber}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (episode.overview != null && episode.overview!.isNotEmpty)
                    Text(
                      episode.overview!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  if (episode.runtime != null && episode.runtime! > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${episode.runtime}m',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Per-episode download icon — observes the DownloadStore so it
            // renders idle / progress / done / cancel correctly. Hit-tested
            // before the outer SqueezeButton (taps here don't start playback).
            Observer(builder: (_) {
              final active = downloadStore.active
                  .where((a) => a.key == _dlKey)
                  .toList();
              final isDone = downloadStore.completed.any((c) =>
                  c.tmdbId == tvId &&
                  c.seasonNumber == episode.seasonNumber &&
                  c.episodeNumber == episode.episodeNumber);
              if (isDone) {
                return const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.download_done_rounded,
                      color: Color(0xFFEF0003), size: 32),
                );
              }
              if (active.isNotEmpty) {
                final a = active.first;
                final p = a.progress.clamp(0.0, 1.0);
                // Stack a progress ring with a ✕ cancel icon in the middle.
                // Tap the whole thing to abort + wipe partials.
                return Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: IconButton(
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
                  ),
                );
              }
              return IconButton(
                iconSize: 32,
                icon: const Icon(Icons.download_rounded,
                    color: Colors.white70),
                tooltip: 'Download',
                onPressed: onDownload,
              );
            }),
          ],
        ),
      ),
    );
  }
}
