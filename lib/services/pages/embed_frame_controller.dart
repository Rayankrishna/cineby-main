/// Lets the web player send commands (e.g. seek) into the embed's iframe.
/// The browser implementation of EmbedFrame attaches itself here.
class EmbedFrameController {
  void Function(Map<String, Object?> message)? _post;

  /// Called by EmbedFrame; null detaches.
  set postHandler(void Function(Map<String, Object?> message)? handler) =>
      _post = handler;

  /// Sends [message] to the embedded player with window.postMessage.
  void post(Map<String, Object?> message) => _post?.call(message);
}
