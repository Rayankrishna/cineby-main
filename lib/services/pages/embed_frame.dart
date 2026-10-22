// Browser iframe for the web build's player. The real implementation needs
// dart:js_interop + package:web, which don't exist on Android/iOS, so mobile
// builds get a no-op stub instead.
export 'embed_frame_stub.dart'
    if (dart.library.js_interop) 'embed_frame_web.dart';
