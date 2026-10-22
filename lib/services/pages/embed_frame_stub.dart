import 'dart:async';

import 'package:flutter/widgets.dart';

/// Mobile stub — the web player is never shown outside the browser.
class EmbedFrame extends StatelessWidget {
  const EmbedFrame({super.key, required this.url, this.shield = false});

  final String url;
  final bool shield;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Mobile stub — there are no window messages to listen to.
StreamSubscription<Object?>? listenToWindowMessages(
  void Function(Object? data) onData,
) => null;

bool get webHasKeyboardPointer => false;

bool appIsFullscreen() => false;

void requestAppFullscreen() {}

void exitAppFullscreen() {}

StreamSubscription<Object?>? listenToFullscreenChange(
  void Function() onChange,
) => null;
