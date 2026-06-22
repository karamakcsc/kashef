/// Stub for non-web platforms — function is never called at runtime on mobile.
/// Returns (null, false): no image captured, no fallback needed.
Future<(List<int>?, bool)> showWebCameraOverlay() async => (null, false);
