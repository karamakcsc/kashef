// Stub for non-web platforms
Future<void> requestWebNotificationPermission() async {}

Future<void> showWebNotification({
  required String title,
  required String body,
  String? tag,
}) async {}

bool get webNotificationsSupported => false;
