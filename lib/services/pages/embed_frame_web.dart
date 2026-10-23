import 'dart:async';
import 'dart:js_interop';

import 'package:app_web_ui/services/pages/embed_frame_controller.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Shows an embed provider's player page in a real browser <iframe> and
/// guards it against ads two ways:
///
/// * [shield]: a click-catching layer over the frame. A browser only lets a
///   page open a tab from a click that landed in that page, so when clicks
///   never reach the embed, its ad scripts can't open tabs.
/// * Hijack recovery: when the frame navigates away from the player on its
///   own, it is covered immediately and replaced with a fresh frame on
///   [url], so the ad page is never shown.
///
/// Key it by [url] so switching sources builds a fresh frame.
class EmbedFrame extends StatefulWidget {
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
  State<EmbedFrame> createState() => _EmbedFrameState();
}

class _EmbedFrameState extends State<EmbedFrame> {
  // Bumped to throw a hijacked iframe away and build a new one. Dropping
  // the element also drops the ad page from the browser's history, so Back
  // can't land on it.
  int _generation = 0;
  web.HTMLIFrameElement? _iframe;
  JSFunction? _onLoad;

  web.HTMLElement? _shieldEl;
  JSFunction? _onShieldDown;
  JSFunction? _onShieldClick;

  // Covered until the player has loaded, and again while a hijacked frame
  // is being replaced.
  bool _covered = true;
  Timer? _uncoverTimer;
  int _loads = 0;
  DateTime? _lastLoadAt;
  int _resets = 0;

  // Loads this close together are the provider's own redirect chain, not an
  // ad; resetting on those would loop forever.
  static const _redirectWindow = Duration(milliseconds: 1500);
  static const _maxResets = 3;

  void _onElementCreated(Object element) {
    _detachListener();
    final iframe = element as web.HTMLIFrameElement;
    _iframe = iframe;
    _loads = 0;
    _lastLoadAt = null;
    iframe
      ..src = widget.url
      ..allow = 'autoplay; fullscreen; encrypted-media; picture-in-picture'
      ..allowFullscreen = true
      ..referrerPolicy = 'origin';
    iframe.style
      ..border = 'none'
      ..width = '100%'
      ..height = '100%'
      ..backgroundColor = 'black';
    final generation = _generation;
    _onLoad = ((web.Event _) => _handleLoad(generation)).toJS;
    iframe.addEventListener('load', _onLoad);
    widget.controller?.postHandler = _post;

    // If the provider never fires load (blocked, hanging), show whatever is
    // there rather than a spinner forever.
    _uncoverTimer?.cancel();
    _uncoverTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _covered) setState(() => _covered = false);
    });
  }

  void _handleLoad(int generation) {
    // Loads from a frame we've already discarded.
    if (!mounted || generation != _generation) return;
    final now = DateTime.now();
    final sinceLast = _lastLoadAt == null ? null : now.difference(_lastLoadAt!);
    _loads++;
    _lastLoadAt = now;

    // The player itself.
    if (_loads == 1) {
      _uncoverTimer?.cancel();
      if (_covered) setState(() => _covered = false);
      // Keys only reach the player while the frame has focus.
      if (widget.shield) _focusFrame();
      return;
    }
    // The frame navigated on its own. A fast follow-up is the provider
    // redirecting itself; anything later is an ad taking over the frame.
    if (sinceLast != null && sinceLast < _redirectWindow) return;
    if (_resets >= _maxResets) return;
    _resets++;
    setState(() {
      _covered = true;
      _generation++;
    });
  }

  void _post(Map<String, Object?> message) {
    try {
      _iframe?.contentWindow?.postMessage(message.jsify(), '*'.toJS);
    } catch (_) {}
  }

  void _onShieldCreated(Object element) {
    _detachShield();
    final div = element as web.HTMLElement;
    _shieldEl = div;
    div.setAttribute('data-role', 'ad-shield');
    div.style
      ..width = '100%'
      ..height = '100%';
    // No cursor of its own: it inherits the app's, so the player can hide it.
    // Don't move focus to the shield: keep it on the frame so the player's
    // keyboard shortcuts keep working.
    _onShieldDown = ((web.Event e) => e.preventDefault()).toJS;
    div.addEventListener('mousedown', _onShieldDown);
    // Hand focus back to the frame only once the click is over. Doing it on
    // mousedown blurs the page mid-click, and Flutter then cancels the tap,
    // so the first click on one of our controls did nothing.
    _onShieldClick =
        ((web.Event _) {
          Timer(const Duration(milliseconds: 400), _focusFrame);
        }).toJS;
    div.addEventListener('click', _onShieldClick);
  }

  void _focusFrame() {
    final iframe = _iframe;
    if (iframe == null) return;
    iframe.focus();
    try {
      iframe.contentWindow?.focus();
    } catch (_) {}
  }

  @override
  void didUpdateWidget(EmbedFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shield && !oldWidget.shield) _focusFrame();
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.postHandler = null;
      widget.controller?.postHandler = _post;
    }
  }

  void _detachListener() {
    if (_iframe != null && _onLoad != null) {
      _iframe!.removeEventListener('load', _onLoad);
    }
    _iframe = null;
    _onLoad = null;
  }

  void _detachShield() {
    if (_shieldEl != null && _onShieldClick != null) {
      _shieldEl!.removeEventListener('click', _onShieldClick);
    }
    _onShieldClick = null;
    if (_shieldEl != null && _onShieldDown != null) {
      _shieldEl!.removeEventListener('mousedown', _onShieldDown);
    }
    _shieldEl = null;
    _onShieldDown = null;
  }

  @override
  void dispose() {
    widget.controller?.postHandler = null;
    _uncoverTimer?.cancel();
    _detachListener();
    _detachShield();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        HtmlElementView.fromTagName(
          key: ValueKey(_generation),
          tagName: 'iframe',
          onElementCreated: _onElementCreated,
        ),
        if (_covered)
          const ColoredBox(
            color: Colors.black,
            child: Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  color: Color(0xFFEF0003),
                  strokeWidth: 2.5,
                ),
              ),
            ),
          ),
        // A Flutter widget can't block pointer events from reaching a
        // platform view, so the shield is a real DOM element above the
        // iframe.
        if (widget.shield)
          HtmlElementView.fromTagName(
            key: const ValueKey('shield'),
            tagName: 'div',
            onElementCreated: _onShieldCreated,
          ),
      ],
    );
  }
}

/// Embed players report playback progress with window.postMessage. Calls
/// [onData] with each message's payload, converted to Dart maps/lists/strings.
StreamSubscription<Object?>? listenToWindowMessages(
  void Function(Object? data) onData,
) {
  return web.EventStreamProviders.messageEvent
      .forTarget(web.window)
      .listen((event) => onData(event.data.dartify()));
}

/// Desktop-class input: a mouse and, in practice, a keyboard. With the ad
/// shield on the player is driven by keys, so it's only on by default here.
bool get webHasKeyboardPointer =>
    web.window.matchMedia('(hover: hover) and (pointer: fine)').matches;

bool appIsFullscreen() => web.document.fullscreenElement != null;

/// Fullscreens the whole app rather than the iframe, so the ad shield stays
/// on top of the player.
void requestAppFullscreen() {
  final root = web.document.documentElement;
  if (root == null) return;
  unawaited(root.requestFullscreen().toDart.catchError((_) => null));
}

void exitAppFullscreen() {
  if (!appIsFullscreen()) return;
  unawaited(web.document.exitFullscreen().toDart.catchError((_) => null));
}

StreamSubscription<Object?>? listenToFullscreenChange(
  void Function() onChange,
) {
  // Wired by hand: package:web's fullscreenChangeEvent listens for the
  // legacy 'webkitfullscreenchange' name, which current browsers don't fire.
  final controller = StreamController<Object?>();
  final listener = ((web.Event _) => controller.add(null)).toJS;
  web.document.addEventListener('fullscreenchange', listener);
  controller.onCancel = () {
    web.document.removeEventListener('fullscreenchange', listener);
    controller.close();
  };
  return controller.stream.listen((_) => onChange());
}
