import 'package:app_web_ui/services/page_transitions.dart';
import 'package:app_web_ui/services/pages/avatar_picker.dart';
import 'package:app_web_ui/services/pages/movie_detail_page.dart';
import 'package:app_web_ui/services/pages/tv_detail_page.dart';
import 'package:app_web_ui/services/responsive.dart';
import 'package:app_web_ui/shared/squeeze_button.dart';
import 'package:app_web_ui/stores/auth_store.dart';
import 'package:app_web_ui/stores/history_store.dart';
import 'package:app_web_ui/stores/watchlist_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  void initState() {
    super.initState();
    historyStore.fetch();
    watchlistStore.fetch();
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

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF18181A),
      body: Observer(
        builder: (_) {
          // Anything the user has tapped Play on and not finished counts as
          // "in progress". Previously this gated on progressSeconds > 30,
          // which meant freshly-played movies (initial record at 0s) only
          // appeared after the native player's first 30s+ tick — and not at
          // all if extraction failed or the user backed out early.
          final inProgress = historyStore.items
              .where((h) => !h.completed)
              .toList();

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHero()),
              SliverToBoxAdapter(child: _buildStatLine(inProgress.length)),
              if (inProgress.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    title: 'Continue Watching',
                    subtitle: 'Pick up where you left off',
                  ),
                ),
                SliverToBoxAdapter(child: _continueWatchingRail(inProgress)),
              ],
              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: 'My Watchlist',
                  subtitle: watchlistStore.items.isEmpty
                      ? 'Nothing saved yet'
                      : '${watchlistStore.items.length} '
                          '${watchlistStore.items.length == 1 ? 'title' : 'titles'} '
                          'to watch',
                ),
              ),
              _watchlistSliver(),
              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: 'History',
                  subtitle: historyStore.items.isEmpty
                      ? 'Nothing yet'
                      : '${historyStore.items.length} '
                          'recently watched',
                ),
              ),
              _historySliver(),
              SliverToBoxAdapter(child: _buildAccountSection()),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHero() {
    return Observer(builder: (_) {
      final user = authStore.user;
      final avatarPath = authStore.avatarPath;
      return Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                height: 260,
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.9),
                    radius: 0.85,
                    colors: [
                      Color(0x33E50914),
                      Color(0x00000000),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 8),
            child: CenteredMaxWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => AvatarPickerSheet.show(context),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _AvatarCircle(
                          avatarPath: avatarPath,
                          initials: _initials(user?.name),
                          size: 96,
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1F1E26),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF18181A),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.edit_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    user?.name ?? 'Guest',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user?.email ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildStatLine(int inProgressCount) {
    final watchlistCount = watchlistStore.items.length;
    final completedCount =
        historyStore.items.where((h) => h.completed).length;
    return CenteredMaxWidth(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.1,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StatInline(value: watchlistCount, label: 'saved'),
            _Dot(),
            _StatInline(value: inProgressCount, label: 'watching'),
            _Dot(),
            _StatInline(
              value: completedCount,
              label: 'finished',
              valueColor:
                  completedCount > 0 ? const Color(0xFFF7BB0D) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSection() {
    return CenteredMaxWidth(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(2, 0, 0, 10),
            child: Text(
              'Account',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
              ),
            ),
          ),
          _AccountTile(
            icon: Icons.person_outline_rounded,
            label: 'Change avatar',
            onTap: () => AvatarPickerSheet.show(context),
          ),
          _AccountTile(
            icon: Icons.logout_rounded,
            label: 'Sign out',
            destructive: true,
            onTap: () async {
              await authStore.logout();
              if (mounted) {
                Navigator.of(context).popUntil((r) => r.isFirst);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _continueWatchingRail(List inProgress) {
    return SizedBox(
      height: 218,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        itemCount: inProgress.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final item = inProgress[i];
          final progress = item.durationSeconds != null &&
                  item.durationSeconds! > 0
              ? (item.progressSeconds / item.durationSeconds!).clamp(0.0, 1.0)
              : 0.0;
          return FadeInUp(
            delay: Duration(milliseconds: 30 * i),
            child: SqueezeButton(
              onTap: () => _openDetail(item.tmdbId, item.mediaType),
              child: SizedBox(
                width: 142,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: 142,
                            height: 200 * 0.84,
                            child: item.posterPath != null
                                ? Image.network(
                                    'https://image.tmdb.org/t/p/w300${item.posterPath}',
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
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
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 3,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.25),
                              valueColor: const AlwaysStoppedAnimation(
                                Color(0xFFEF0003),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.title ?? 'Unknown',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
                    Text(
                      item.mediaType == 'tv'
                          ? 'S${item.seasonNumber} · E${item.episodeNumber}'
                          : 'Movie',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
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
  }

  Widget _watchlistSliver() {
    return Observer(builder: (_) {
      final items = watchlistStore.items;
      if (items.isEmpty) {
        return const SliverToBoxAdapter(
          child: _EmptyState(text: 'Tap the bookmark on any title to save it'),
        );
      }
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:
                posterGridColumns(MediaQuery.of(context).size.width),
            childAspectRatio: 0.58,
            crossAxisSpacing: 12,
            mainAxisSpacing: 18,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = items[index];
              return FadeInUp(
                delay: Duration(milliseconds: 30 * (index % 12)),
                child: SqueezeButton(
                  onTap: () => _openDetail(item.tmdbId, item.mediaType),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: item.posterPath != null
                              ? Image.network(
                                  'https://image.tmdb.org/t/p/w300${item.posterPath}',
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  errorBuilder: (_, __, ___) => Container(
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
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 34,
                        child: Text(
                          item.title ?? 'Unknown',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            childCount: items.length,
          ),
        ),
      );
    });
  }

  Widget _historySliver() {
    return Observer(builder: (_) {
      final items = historyStore.items;
      if (items.isEmpty) {
        return const SliverToBoxAdapter(
          child: _EmptyState(text: 'Hit play on something to start your history'),
        );
      }
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        sliver: SliverList.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = items[index];
            return Dismissible(
              key: ValueKey(item.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF0003).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.delete_outline, color: Colors.white),
              ),
              onDismissed: (_) => historyStore.remove(item.id),
              child: SqueezeButton(
                onTap: () => _openDetail(item.tmdbId, item.mediaType),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 54,
                          height: 80,
                          child: item.posterPath != null
                              ? Image.network(
                                  'https://image.tmdb.org/t/p/w185${item.posterPath}',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
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
                      const SizedBox(width: 14),
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
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.mediaType == 'tv'
                                  ? 'TV · S${item.seasonNumber} E${item.episodeNumber}'
                                  : 'Movie',
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11.5,
                                letterSpacing: 0.2,
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return CenteredMaxWidth(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
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
        ],
      ),
    );
  }
}

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({
    required this.avatarPath,
    required this.initials,
    required this.size,
  });

  final String? avatarPath;
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: avatarPath == null
            ? const LinearGradient(
                colors: [Color(0xFFEF0003), Color(0xFFC60002)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF0003).withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: ClipOval(
        child: avatarPath != null
            ? Image.network(
                'https://image.tmdb.org/t/p/w300$avatarPath',
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _initialsLabel(),
              )
            : _initialsLabel(),
      ),
    );
  }

  Widget _initialsLabel() => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        color: const Color(0xFFEF0003),
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.36,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      );
}

class _StatInline extends StatelessWidget {
  const _StatInline({
    required this.value,
    required this.label,
    this.valueColor,
  });
  final int value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 13, letterSpacing: -0.1),
        children: [
          TextSpan(
            text: '$value ',
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text: label,
            style: const TextStyle(
              color: Colors.white54,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.25),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFEF0003) : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, color: color.withValues(alpha: 0.85), size: 19),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.25),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.025),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 13,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }
}
