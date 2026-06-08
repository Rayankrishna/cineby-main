import 'package:app_web_ui/services/pages/downloads_page.dart';
import 'package:app_web_ui/services/pages/home.dart';
import 'package:app_web_ui/services/pages/profile_page.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;
  // Timestamp of the last back-press that we caught at the root. If the user
  // presses again within `_exitWindow`, we exit. Otherwise we show a toast
  // and reset the counter.
  DateTime? _lastBackPress;
  static const Duration _exitWindow = Duration(seconds: 2);

  // Called by Flutter when the system back gesture is invoked AND the route
  // can't pop further (we set canPop: false so it always arrives here).
  void _onBack(bool didPop, Object? _) {
    if (didPop) return;
    final now = DateTime.now();
    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > _exitWindow) {
      _lastBackPress = now;
      BotToast.showText(
        text: 'Tap back again to exit',
        align: const Alignment(0, 0.8),
        duration: _exitWindow,
      );
      return;
    }
    // Within the window — actually leave the app.
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onBack,
      child: Scaffold(
      backgroundColor: const Color(0xFF18181A),
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: const [
              MyHomePage(title: 'Reelix'),
              DownloadsPage(),
              ProfilePage(),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _FloatingNav(
                    index: _index,
                    onChanged: (i) => setState(() {
                      _index = i;
                      // Switching tabs resets the back-to-exit counter
                      // exactly as the user requested.
                      _lastBackPress = null;
                    }),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _FloatingNav extends StatelessWidget {
  const _FloatingNav({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1E26).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NavPill(
            icon: Icons.home_rounded,
            label: 'Home',
            selected: index == 0,
            onTap: () => onChanged(0),
          ),
          const SizedBox(width: 4),
          _NavPill(
            icon: Icons.download_rounded,
            label: 'Downloads',
            selected: index == 1,
            onTap: () => onChanged(1),
          ),
          const SizedBox(width: 4),
          _NavPill(
            icon: Icons.person_rounded,
            label: 'Profile',
            selected: index == 2,
            onTap: () => onChanged(2),
          ),
        ],
      ),
    );
  }
}

class _NavPill extends StatelessWidget {
  const _NavPill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: selected ? 18 : 14,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? Colors.black : Colors.white60,
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: selected
                  ? Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
