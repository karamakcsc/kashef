// n8n_chat_service.dart
// Fully isolated n8n chat service.
// Direct HTTP connection to n8n webhook — no ERPNext / ApiService dependency.
// Webhook URL is read from SharedPreferences key 'n8n_chat_url' (Settings page).

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── Config ────────────────────────────────────────────────────────────────────

const _kUrlKey     = 'n8n_chat_url'; // set in Settings page
const _kSessionKey = 'n8n_session_id';
const _kTimeout    = Duration(seconds: 15);
const _kMaxRetries = 2;

// ── Service ───────────────────────────────────────────────────────────────────

/// Singleton service for n8n webhook communication.
/// Zero dependency on ERPNext, ApiService, or any other app module.
class N8nWebhookChatService {
  const N8nWebhookChatService._();
  static const instance = N8nWebhookChatService._();

  // ── Webhook URL ───────────────────────────────────────────────────────────

  /// Returns the webhook URL stored in Settings, or empty string if not set.
  static Future<String> getWebhookUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_kUrlKey) ?? '').trim();
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  /// POST message to n8n. Reads webhook URL from SharedPreferences on each call.
  /// Throws [Exception] if URL is not configured or all retries fail.
  Future<String> sendMessage({
    required String message,
    required String sessionId,
    required String language,
  }) async {
    final url = await getWebhookUrl();
    if (url.isEmpty) {
      throw Exception('n8n_not_configured');
    }

    Exception? lastErr;

    for (int attempt = 0; attempt <= _kMaxRetries; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(seconds: attempt * 2));
        debugPrint('[n8n] retry #$attempt');
      }
      try {
        final res = await http
            .post(
              Uri.parse(url),
              headers: {
                'Content-Type': 'application/json',
                'Accept':       'application/json',
              },
              body: jsonEncode({
                'message':    message,
                'session_id': sessionId,
                'language':   language,
              }),
            )
            .timeout(_kTimeout);

        if (res.statusCode == 200) {
          final reply = _parse(res.body);
          debugPrint('[n8n] ✓ reply(${reply.length}c): '
              '${reply.substring(0, reply.length.clamp(0, 60))}…');
          return reply;
        }
        throw Exception('HTTP ${res.statusCode}: ${res.reasonPhrase}');
      } catch (e) {
        lastErr = e is Exception ? e : Exception('$e');
        debugPrint('[n8n] attempt $attempt failed: $e');
      }
    }
    throw lastErr!;
  }

  // ── Parser ────────────────────────────────────────────────────────────────

  String _parse(String body) {
    try {
      final d = jsonDecode(body);
      if (d is Map<String, dynamic>) {
        return (d['output']   ??
                d['text']     ??
                d['message']  ??
                d['response'] ??
                d['answer']   ??
                '')
            .toString();
      }
      if (d is List && d.isNotEmpty) {
        final first = d.first;
        if (first is Map<String, dynamic>) {
          return (first['output'] ?? first['text'] ?? '').toString();
        }
      }
      return body;
    } catch (_) {
      return body;
    }
  }

  // ── Session ───────────────────────────────────────────────────────────────

  /// Returns existing session ID or creates and persists a new one.
  static Future<String> loadOrCreateSession() async {
    final prefs = await SharedPreferences.getInstance();
    final id    = prefs.getString(_kSessionKey) ?? '';
    if (id.isNotEmpty) return id;
    return _writeNew(prefs);
  }

  /// Discards the current session and generates a fresh one.
  static Future<String> resetSession() async {
    return _writeNew(await SharedPreferences.getInstance());
  }

  static Future<String> _writeNew(SharedPreferences prefs) async {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng   = Random.secure();
    final suffix =
        List.generate(16, (_) => chars[rng.nextInt(chars.length)]).join();
    final id = 'kcsc_${DateTime.now().millisecondsSinceEpoch}_$suffix';
    await prefs.setString(_kSessionKey, id);
    debugPrint('[n8n] new session: $id');
    return id;
  }
}
