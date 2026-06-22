import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BackgroundService
//
// Runs a WorkManager periodic task every 15 minutes.
// If pending approval count increases since the last check, a local
// notification is shown.  Tapping the notification opens /pending-approvals.
//
// Notification channel: 'kcsc_approvals'
// Notification ID: 42 (fixed — updates the same notification on each fire)
// ─────────────────────────────────────────────────────────────────────────────

const _kTaskName       = 'kcsc_ai_approval_check';
const _kUniqueTaskName = 'kcsc_ai_approval_check_periodic';
const _kLastCountKey   = 'bg_last_approval_count';
const _kChannelId      = 'kcsc_approvals';
const _kNotifId        = 42;

// Singleton instance shared with the foreground app.
final _notifs = FlutterLocalNotificationsPlugin();

// ── Entry point called by WorkManager in a separate Dart isolate ─────────────
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task == _kTaskName) await _checkAndNotify();
    return true;
  });
}

// ── Call once from main() ─────────────────────────────────────────────────────
Future<void> initBackgroundService() async {
  // Notifications
  await _notifs.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  // Request Android 13+ notification permission (no-op on older versions)
  final android =
      _notifs.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await android?.requestNotificationsPermission();

  // WorkManager — periodic task, minimum 15-minute interval
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  await Workmanager().registerPeriodicTask(
    _kUniqueTaskName,
    _kTaskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: const Duration(minutes: 5),
  );
}

// ── Call from main() to handle notification tap while app is terminated ───────
Future<String?> getInitialNotificationRoute() async {
  final details = await _notifs.getNotificationAppLaunchDetails();
  if (details?.didNotificationLaunchApp == true) {
    return details!.notificationResponse?.payload;
  }
  return null;
}

// ── Cancel the background task (e.g. on logout) ───────────────────────────────
Future<void> stopBackgroundService() async {
  await Workmanager().cancelByUniqueName(_kUniqueTaskName);
}

// ── Show a notification from the foreground (reuse same channel) ─────────────
Future<void> showApprovalNotification(int count) async {
  await _notifs.show(
    _kNotifId,
    'Kashef',
    count == 1 ? 'لديك طلب موافقة جديد' : 'لديك $count طلبات موافقة جديدة',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _kChannelId,
        'الموافقات المعلقة',
        channelDescription: 'إشعارات طلبات الموافقة الجديدة',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
    payload: '/pending-approvals',
  );
}

// ── Core polling logic — runs inside the WorkManager isolate ─────────────────
Future<void> _checkAndNotify() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final url      = prefs.getString('erpnext_url') ?? '';
    final userId   = prefs.getString('erpnext_user_email') ??
        prefs.getString('erpnext_username') ?? '';
    final cookie   = prefs.getString('erpnext_session_cookie') ?? '';
    final apiKey   = prefs.getString('erpnext_api_key') ?? '';
    final apiSec   = prefs.getString('erpnext_api_secret') ?? '';

    if (url.isEmpty || userId.isEmpty) return;

    // Build auth headers (token preferred; fall back to session cookie)
    final headers = <String, String>{'Accept': 'application/json'};
    if (apiKey.isNotEmpty && apiSec.isNotEmpty) {
      headers['Authorization'] = 'token $apiKey:$apiSec';
    } else if (cookie.isNotEmpty) {
      final sid = cookie.startsWith('sid=') ? cookie : 'sid=$cookie';
      headers['Cookie'] = sid;
    } else {
      return; // no auth available
    }

    final resp = await http
        .post(
          Uri.parse('$url/api/method/frappe.client.get_list'),
          headers: {
            ...headers,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'doctype': 'Workflow Action',
            'filters': jsonEncode([
              ['status', '=', 'Open'],
              ['user', '=', userId],
            ]),
            'fields': jsonEncode(['name']),
            'limit_page_length': '200',
          },
        )
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode != 200) return;

    final list  = (jsonDecode(resp.body)['message'] as List?) ?? [];
    final count = list.length;
    final last  = prefs.getInt(_kLastCountKey) ?? -1;

    await prefs.setInt(_kLastCountKey, count);

    if (last >= 0 && count > last) {
      await showApprovalNotification(count - last);
    }
  } catch (_) {}
}
