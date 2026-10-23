import 'dart:async';

import 'package:app_web_ui/services/pages/embed_frame_controller.dart';
import 'package:flutter/widgets.dart';

/// Mobile stub — the web player is never shown outside the browser.
class EmbedFrame extends StatelessWidget {
  const EmbedFrame({
    super.key,
    required this.url,
    this.shield = false,
    this.controller,
  });

  final String url;
  final bool shield;
  final EmbedFrameController? controller;

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
