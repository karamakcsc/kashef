/// Stub for non-web platforms — never called at runtime on mobile.
void downloadBytesInBrowser(List<int> bytes, String filename, String mimeType) {
  throw UnsupportedError('downloadBytesInBrowser is only available on web');
}
