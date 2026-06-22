import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

import 'api_service.dart';
import 'background_service.dart';
import 'web_notification.dart';
import 'workflow_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RealtimeWorkflowService — Singleton
//
// Connects to Frappe Socket.IO and listens for "workflow_update" events.
// Falls back to polling every 10 s if the socket cannot connect (token auth,
// Web CORS restriction, or network issue).
//
// On count increase (new approvals):
//   • Notifies all Flutter listeners (refreshes Pending Approvals screen)
//   • Shows in-app SnackBar via global navigator key
//   • Shows Android local push notification (foreground)
//   • Shows browser notification on Web
//
// Backend requirement (FAC hooks.py):
//   frappe.publish_realtime("workflow_update", {
//     "user": doc.user,
//     "reference_doctype": doc.reference_doctype,
//     "reference_name": doc.reference_name,
//     "new_state": doc.workflow_state,
//     "action": action_taken,
//   }, user=doc.user)
// ─────────────────────────────────────────────────────────────────────────────

typedef WorkflowEventCallback = void Function(Map<String, dynamic> event);

// Global navigator key (set in main.dart) — used to show SnackBar from service
final GlobalKey<NavigatorState> workflowNavigatorKey =
    GlobalKey<NavigatorState>();

class RealtimeWorkflowService {
  static final RealtimeWorkflowService _instance =
      RealtimeWorkflowService._internal();
  factory RealtimeWorkflowService() => _instance;
  RealtimeWorkflowService._internal();

  // ── State ─────────────────────────────────────────────────────────────────
  sio.Socket? _socket;
  Timer?       _pollTimer;
  Timer?       _debounce;
  bool         _socketConnected = false;
  bool         _initialized     = false;

  int    _pendingCount    = 0;
  int    _lastKnownCount  = -1; // -1 = first run (don't notify on init)
  String _username        = '';

  int  get pendingCount  => _pendingCount;
  bool get isConnected   => _socketConnected;

  // ── Listeners ─────────────────────────────────────────────────────────────
  final List<WorkflowEventCallback> _listeners = [];

  void addListener(WorkflowEventCallback cb) {
    if (!_listeners.contains(cb)) _listeners.add(cb);
  }

  void removeListener(WorkflowEventCallback cb) => _listeners.remove(cb);

  void _notify(Map<String, dynamic> event) {
    for (final cb in List.of(_listeners)) {
      cb(event);
    }
  }

  // ── Initialize ────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    final prefs    = await SharedPreferences.getInstance();
    final url      = prefs.getString('erpnext_url')           ?? '';
    final cookie   = prefs.getString('erpnext_session_cookie') ?? '';
    final apiKey   = prefs.getString('erpnext_api_key')        ?? '';
    final userId   = await ApiService.getLoggedUserId();

    if (url.isEmpty || userId.isEmpty) return;

    if (_initialized &&
        _username == userId &&
        (_socketConnected || _pollTimer?.isActive == true)) {
      return;
    }

    _username    = userId;
    _initialized = true;
    _disconnect();

    // Request Web notification permission on first init
    if (kIsWeb) {
      requestWebNotificationPermission().ignore();
    }

    // Load initial count (don't notify — first run baseline)
    _lastKnownCount = -1;
    await _loadPendingCount();
    _lastKnownCount = _pendingCount;
    debugPrint(
      '🔔 RealtimeWorkflow: initialized for "$_username" '
      '— baseline count: $_pendingCount',
    );

    if (cookie.isNotEmpty && apiKey.isEmpty) {
      _connectSocket(url, cookie);
    } else {
      _startPolling();
    }
  }

  // ── Socket connection ─────────────────────────────────────────────────────

  void _connectSocket(String url, String sessionCookie) {
    final sid = sessionCookie.startsWith('sid=')
        ? sessionCookie.substring(4)
        : sessionCookie;

    try {
      _socket = sio.io(
        url,
        sio.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .setExtraHeaders({'Cookie': 'sid=$sid'})
            .disableAutoConnect()
            .enableReconnection()
            .setReconnectionAttempts(5)
            .setReconnectionDelay(2000)
            .build(),
      );

      _socket!.onConnect((_) {
        _socketConnected = true;
        debugPrint('🔌 RealtimeWorkflow: Socket.IO connected');
        _socket!.emit('login', {'sid': sid});
        _stopPolling();
      });

      _socket!.on('workflow_update', (data) {
        final event = data is Map<String, dynamic>
            ? data
            : data is Map
                ? Map<String, dynamic>.from(data)
                : <String, dynamic>{};
        debugPrint('📡 RealtimeWorkflow: socket event: $event');
        _handleIncomingEvent(event);
      });

      _socket!.onConnectError((_) {
        _socketConnected = false;
        debugPrint('⚠️ RealtimeWorkflow: socket error — starting polling');
        _startPolling();
      });
      _socket!.onDisconnect((_) {
        _socketConnected = false;
        _startPolling();
      });
      _socket!.onReconnectFailed((_) {
        _socketConnected = false;
        _startPolling();
      });

      _socket!.connect();
    } catch (_) {
      _startPolling();
    }
  }

  // ── Polling fallback (10 s) ───────────────────────────────────────────────

  void _startPolling() {
    if (_pollTimer?.isActive == true) return;
    debugPrint('⏱️ RealtimeWorkflow: polling every 10 s');
    _pollTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _doPoll());
  }

  void _stopPolling() => _pollTimer?.cancel();

  Future<void> _doPoll() async {
    final prev = _pendingCount;
    await _loadPendingCount();
    debugPrint(
      '⏱️ RealtimeWorkflow: poll — count=$_pendingCount (prev=$prev)',
    );

    if (_pendingCount != prev) {
      final delta    = _pendingCount - prev;
      final isIncrease = delta > 0;
      debugPrint(
        '🔔 RealtimeWorkflow: count changed $prev → $_pendingCount '
        '(delta=$delta)',
      );

      // Notify Flutter listeners (refreshes screen)
      _notify({'poll': true, 'user': _username, 'count': _pendingCount});

      // Show notifications only when count INCREASES
      if (isIncrease && _lastKnownCount >= 0) {
        _dispatchNotifications(newCount: delta);
      }
      _lastKnownCount = _pendingCount;
    }
  }

  // ── Incoming socket event handler ─────────────────────────────────────────

  void _handleIncomingEvent(Map<String, dynamic> event) {
    final eventUser = event['user']?.toString() ?? '';
    if (eventUser.isNotEmpty && eventUser != _username) return;

    if (_pendingCount > 0) _pendingCount--;

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      _notify(event);
      // Socket events indicate a workflow change — reload count for accuracy
      _loadPendingCount().ignore();
    });
  }

  // Optimistic broadcast — called immediately after a workflow action succeeds.
  void broadcastLocal(Map<String, dynamic> event) {
    debugPrint('📢 RealtimeWorkflow: broadcastLocal: $event');
    WorkflowRepository().invalidate();
    _handleIncomingEvent({'user': _username, ...event});
  }

  // ── Dispatch notifications ────────────────────────────────────────────────

  /// Called when pending approval count increases.
  /// Sends in-app SnackBar + Android push + Web browser notification.
  Future<void> _dispatchNotifications({required int newCount}) async {
    final title = 'Kashef';
    final body  = newCount == 1
        ? 'لديك طلب موافقة جديد'
        : 'لديك $newCount طلبات موافقة جديدة';

    debugPrint('🔔 RealtimeWorkflow: dispatching notification — $body');

    // 1. In-app SnackBar (visible when app is open)
    _showInAppSnackBar(title: title, body: body);

    if (kIsWeb) {
      // 2. Web Browser Notification
      await showWebNotification(title: title, body: body);
    } else {
      // 3. Android local push notification
      try {
        await showApprovalNotification(newCount);
      } catch (e) {
        debugPrint('⚠️ RealtimeWorkflow: push notification error: $e');
      }
    }
  }

  void _showInAppSnackBar({required String title, required String body}) {
    try {
      final ctx = workflowNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;

      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.approval_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  body,
                  style: const TextStyle(
                    color:      Colors.white,
                    fontSize:   13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E3A5F),
          duration:         const Duration(seconds: 5),
          behavior:         SnackBarBehavior.floating,
          margin: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          action: SnackBarAction(
            label:     'عرض',
            textColor: const Color(0xFF60A5FA),
            onPressed: () {
              workflowNavigatorKey.currentState
                  ?.pushNamed('/pending-approvals');
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ RealtimeWorkflow: SnackBar error: $e');
    }
  }

  // ── Load pending count ────────────────────────────────────────────────────

  Future<void> _loadPendingCount() async {
    if (_username.isEmpty) return;
    try {
      _pendingCount = await WorkflowRepository().fetchCount(_username);
    } catch (_) {
      try {
        final result = await ApiService.postForm(
          '/api/method/frappe.client.get_list',
          {
            'doctype':           'Workflow Action',
            'filters':           jsonEncode([
              ['status', '=', 'Open'],
              ['user',   '=', _username],
            ]),
            'fields':            jsonEncode(['name']),
            'limit_page_length': '200',
          },
        );
        final list    = (result['message'] as List?) ?? [];
        _pendingCount = list.length;
      } catch (_) {}
    }
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  void _disconnect() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _debounce?.cancel();
    _socketConnected = false;
    _socket?.dispose();
    _socket = null;
  }

  void reset() {
    _initialized    = false;
    _pendingCount   = 0;
    _lastKnownCount = -1;
    _username       = '';
    _disconnect();
    _listeners.clear();
  }
}
