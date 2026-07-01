// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool get webNotificationsSupported => true;

/// Requests browser notification permission (must be called from a user gesture).
Future<void> requestWebNotificationPermission() async {
  try {
    if (web.Notification.permission == 'default') {
      await web.Notification.requestPermission().toDart;
    }
  } catch (_) {}
}

/// Shows a browser notification if permission is granted.
Future<void> showWebNotification({
  required String title,
  required String body,
  String? tag,
}) async {
  try {
    if (web.Notification.permission != 'granted') return;
    web.Notification(
      title,
      web.NotificationOptions(
        body: body,
        tag: tag ?? 'kashef-workflow',
        icon: '/kashef/icons/Icon-192.png',
      ),
    );
  } catch (_) {}
}
