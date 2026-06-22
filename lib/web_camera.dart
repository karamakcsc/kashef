/// Conditional export — web implementation on browser, no-op stub on mobile/desktop.
library;

export 'web_camera_stub.dart'
    if (dart.library.js_interop) 'web_camera_web.dart';
