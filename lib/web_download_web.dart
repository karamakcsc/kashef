import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Triggers a browser file download using a Blob URL.
void downloadBytesInBrowser(List<int> bytes, String filename, String mimeType) {
  final jsBytes  = Uint8List.fromList(bytes).toJS;
  final blob     = web.Blob([jsBytes].toJS, web.BlobPropertyBag(type: mimeType));
  final url      = web.URL.createObjectURL(blob);
  final anchor   = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href     = url;
  anchor.download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
}
