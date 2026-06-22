/// Conditional export — web implementation on browser, stub on mobile.
library;
export 'web_download_stub.dart'
    if (dart.library.js_interop) 'web_download_web.dart';
