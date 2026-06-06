import 'package:app_web_ui/services/config.dart';
import 'package:app_web_ui/services/tmdb_client.dart';
import 'package:app_web_ui/shared/squeeze_button.dart';
import 'package:app_web_ui/stores/auth_store.dart';
import 'package:flutter/material.dart';

class AvatarPickerSheet extends StatefulWidget {
  const AvatarPickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AvatarPickerSheet(),
    );
  }

  @override
  State<AvatarPickerSheet> createState() => _AvatarPickerSheetState();
}

class _AvatarPickerSheetState extends State<AvatarPickerSheet> {
  List<_AvatarChoice> _choices = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<_AvatarChoice> all = [];
      for (final page in [1, 2]) {
        final res = await tmdbDio.get(
          'https://api.themoviedb.org/3/person/popular',
          queryParameters: {
            'api_key': tmdbApiKey,
            'language': 'en',
            'page': page,
          },
        );
        final results = (res.data['results'] as List<dynamic>);
        for (final p in results) {
          final m = p as Map<String, dynamic>;
          final path = m['profile_path'] as String?;
          if (path == null) continue;
          all.add(_AvatarChoice(path: path, name: m['name'] as String? ?? ''));
        }
      }
      if (!mounted) return;
      setState(() {
        _choices = all;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Couldn\'t load avatars';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = authStore.avatarPath;
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1F1E26),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Choose your avatar',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Pick a face from the world of cinema',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected != null)
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                        ),
                        onPressed: () async {
                          await authStore.setAvatarPath(null);
                          if (mounted) Navigator.pop(context);
                        },
                        child: const Text(
                          'Reset',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(child: _buildBody(scrollController, selected)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(ScrollController controller, String? selected) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFEF0003)),
      );
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.white54)),
      );
    }
    return GridView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 14,
        mainAxisSpacing: 18,
        childAspectRatio: 0.78,
      ),
      itemCount: _choices.length,
      itemBuilder: (context, index) {
        final c = _choices[index];
        final isSelected = selected == c.path;
        return SqueezeButton(
          onTap: () async {
            await authStore.setAvatarPath(c.path);
            if (mounted) Navigator.pop(context);
          },
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.all(isSelected ? 3 : 0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        isSelected
                            ? const Color(0xFFF7BB0D)
                            : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: ClipOval(
                  child: SizedBox(
                    width: 68,
                    height: 68,
                    child: Image.network(
                      'https://image.tmdb.org/t/p/w185${c.path}',
                      fit: BoxFit.cover,
                      errorBuilder:
                          (_, __, ___) => Container(
                            color: const Color(0xFF35343E),
                            child: const Icon(
                              Icons.person_rounded,
                              color: Colors.white24,
                            ),
                          ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                c.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  color: isSelected ? Colors.white : Colors.white54,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AvatarChoice {
  final String path;
  final String name;
  _AvatarChoice({required this.path, required this.name});
}
