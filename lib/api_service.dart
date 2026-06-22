import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Keys — must match settings_page.dart
// ---------------------------------------------------------------------------
const _keyUrl           = 'erpnext_url';
const _keyUsername      = 'erpnext_username';
const _keyPassword      = 'erpnext_password';
const _keyCompany       = 'erpnext_company';
const _keySessionCookie = 'erpnext_session_cookie';
const _keyCsrfToken     = 'erpnext_csrf_token';
const _keyApiKey        = 'erpnext_api_key';
const _keyApiSecret     = 'erpnext_api_secret';
// Frappe user identifier (email) — resolved after login; may differ from the
// typed username if the user logs in with a short name or employee ID.
const _keyUserEmail     = 'erpnext_user_email';

// ---------------------------------------------------------------------------
// ApiService
// ---------------------------------------------------------------------------
class ApiService {
  static final http.Client _client = http.Client();

  // Session-cookie auth (used by the whole app)
  static String? _sessionCookie;
  static String? _csrfToken;

  // ---------------------------------------------------------------------------
  // Load credentials from SharedPreferences
  // ---------------------------------------------------------------------------
  static Future<Map<String, String>> getCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'url':        prefs.getString(_keyUrl)        ?? '',
      'username':   prefs.getString(_keyUsername)   ?? '',
      'password':   prefs.getString(_keyPassword)   ?? '',
      'company':    prefs.getString(_keyCompany)    ?? '',
      'api_key':    prefs.getString(_keyApiKey)     ?? '',
      'api_secret': prefs.getString(_keyApiSecret)  ?? '',
    };
  }

  // ---------------------------------------------------------------------------
  // Login — POST /api/method/login using username + password (session cookie)
  // Returns null on success, or an error message string on failure.
  // ---------------------------------------------------------------------------
  static Future<String?> login() async {
    final creds = await getCredentials();
    final url      = creds['url']!;
    final username = creds['username']!;
    final password = creds['password']!;

    if (url.isEmpty || username.isEmpty || password.isEmpty) {
      return 'Missing credentials — please fill in Settings first.';
    }

    try {
      final response = await _client
          .post(
            Uri.parse('$url/api/method/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'usr': username, 'pwd': password}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final rawCookie = response.headers['set-cookie'] ?? '';
        _parseCookies(rawCookie);

        final prefs = await SharedPreferences.getInstance();
        if (_sessionCookie != null) {
          await prefs.setString(_keySessionCookie, _sessionCookie!);
        }
        if (_csrfToken != null) {
          await prefs.setString(_keyCsrfToken, _csrfToken!);
        }
        // Resolve the actual Frappe user identifier (email) and cache it.
        // Workflow Action.user stores the email, which may differ from the
        // typed username (e.g. short name vs. email).
        try {
          final me = await _client
              .get(
                Uri.parse('$url/api/method/frappe.auth.get_logged_user'),
                headers: _cookieHeaders(),
              )
              .timeout(const Duration(seconds: 10));
          if (me.statusCode == 200) {
            final email = (jsonDecode(me.body)['message'] as String?) ?? '';
            if (email.isNotEmpty) {
              await prefs.setString(_keyUserEmail, email);
            }
          }
        } catch (_) {}
        return null; // success
      } else {
        try {
          final body = jsonDecode(response.body);
          final msg = body['message'] ??
              body['exc'] ??
              'Login failed (${response.statusCode})';
          return msg.toString();
        } catch (_) {
          return 'Login failed (${response.statusCode})';
        }
      }
    } on TimeoutException {
      return 'تعذّر الاتصال بالخادم — تأكد من الشبكة أو VPN ثم حاول مجدداً.\n(Server unreachable — check network / VPN and retry)';
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('SocketException') || msg.contains('HandshakeException')) {
        return 'تعذّر الاتصال بالخادم — تأكد من الشبكة أو VPN ثم حاول مجدداً.\n(Server unreachable — check network / VPN and retry)';
      }
      return 'Connection error: $e';
    }
  }

  // ---------------------------------------------------------------------------
  // Parse sid and csrf_token out of the raw Set-Cookie header string
  // ---------------------------------------------------------------------------
  static void _parseCookies(String raw) {
    final sidMatch = RegExp(r'sid=([^;,\s]+)').firstMatch(raw);
    if (sidMatch != null) {
      _sessionCookie = 'sid=${sidMatch.group(1)}';
    }
    final csrfMatch = RegExp(r'csrf_token=([^;,\s]+)').firstMatch(raw);
    if (csrfMatch != null) {
      _csrfToken = csrfMatch.group(1);
    }
  }

  // ---------------------------------------------------------------------------
  // Logout
  // ---------------------------------------------------------------------------
  static Future<void> logout() async {
    final creds = await getCredentials();
    final url = creds['url']!;
    try {
      await _client.post(
        Uri.parse('$url/api/method/logout'),
        headers: _cookieHeaders(),
      );
    } catch (_) {}

    _sessionCookie = null;
    _csrfToken     = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySessionCookie);
    await prefs.remove(_keyCsrfToken);
  }

  // ---------------------------------------------------------------------------
  // Test connection (uses session cookie)
  // ---------------------------------------------------------------------------
  static Future<bool> testConnection() async {
    final creds = await getCredentials();
    final url = creds['url']!;
    if (url.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    _sessionCookie ??= prefs.getString(_keySessionCookie);

    try {
      final response = await _client
          .get(
            Uri.parse('$url/api/method/frappe.auth.get_logged_user'),
            headers: await getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Generic GET helper (session cookie)
  // ---------------------------------------------------------------------------
  static Future<dynamic> get(String endpoint) async {
    final creds = await getCredentials();
    final url = creds['url']!;

    final response = await _client
        .get(Uri.parse('$url$endpoint'), headers: await getAuthHeaders())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('GET $endpoint failed (${response.statusCode})');
  }

  // ---------------------------------------------------------------------------
  // Generic POST helper — JSON body (session cookie + CSRF)
  // ---------------------------------------------------------------------------
  static Future<dynamic> post(
      String endpoint, Map<String, dynamic> body) async {
    final creds = await getCredentials();
    final url = creds['url']!;

    final headers = await getAuthHeaders();
    _csrfToken ??= (await SharedPreferences.getInstance()).getString(_keyCsrfToken);
    headers['X-Frappe-CSRF-Token'] = _csrfToken ?? '';

    final response = await _client
        .post(
          Uri.parse('$url$endpoint'),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception(_extractError(response, endpoint, 'POST'));
  }

  // ---------------------------------------------------------------------------
  // Form-encoded POST helper — for Frappe whitelisted methods that need
  // application/x-www-form-urlencoded (e.g. communication.email.make)
  // ---------------------------------------------------------------------------
  static Future<dynamic> postForm(
      String endpoint, Map<String, String> body) async {
    final creds = await getCredentials();
    final url = creds['url']!;

    final headers = await getAuthHeaders();
    _csrfToken ??= (await SharedPreferences.getInstance()).getString(_keyCsrfToken);
    headers['X-Frappe-CSRF-Token'] = _csrfToken ?? '';

    final response = await _client
        .post(
          Uri.parse('$url$endpoint'),
          headers: {...headers, 'Content-Type': 'application/x-www-form-urlencoded'},
          body: body,   // http package URL-encodes Map<String,String> automatically
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception(_extractError(response, endpoint, 'POST (form)'));
  }

  // ---------------------------------------------------------------------------
  // Shared error-extraction helper
  // ---------------------------------------------------------------------------
  static String _extractError(dynamic response, String endpoint, String method) {
    String detail = '';
    try {
      final err = jsonDecode(response.body as String) as Map<String, dynamic>;
      detail = err['exception']?.toString()
          ?? err['message']?.toString()
          ?? err['_server_messages']?.toString()
          ?? '';
      if (detail.startsWith('[')) {
        final msgs = jsonDecode(detail) as List;
        detail = msgs
            .map((m) {
              try { return (jsonDecode(m as String) as Map)['message'] ?? m; }
              catch (_) { return m; }
            })
            .join('\n');
      }
    } catch (_) {
      final body = response.body as String;
      detail = body.length > 300 ? body.substring(0, 300) : body;
    }
    return '$method $endpoint failed (${response.statusCode})'
        '${detail.isNotEmpty ? '\n\n$detail' : ''}';
  }

  // ---------------------------------------------------------------------------
  // Generic PUT helper — JSON body (session cookie + CSRF)
  // ---------------------------------------------------------------------------
  static Future<dynamic> put(
      String endpoint, Map<String, dynamic> body) async {
    final creds = await getCredentials();
    final url = creds['url']!;

    final headers = await getAuthHeaders();
    _csrfToken ??= (await SharedPreferences.getInstance()).getString(_keyCsrfToken);
    headers['X-Frappe-CSRF-Token'] = _csrfToken ?? '';

    final response = await _client
        .put(
          Uri.parse('$url$endpoint'),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception(_extractError(response, endpoint, 'PUT'));
  }

  // ---------------------------------------------------------------------------
  // Generic DELETE helper (session cookie + CSRF)
  // ---------------------------------------------------------------------------
  static Future<void> delete(String endpoint) async {
    final creds = await getCredentials();
    final url = creds['url']!;

    final headers = await getAuthHeaders();
    _csrfToken ??= (await SharedPreferences.getInstance()).getString(_keyCsrfToken);
    headers['X-Frappe-CSRF-Token'] = _csrfToken ?? '';

    final response = await _client
        .delete(Uri.parse('$url$endpoint'), headers: headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 202 || response.statusCode == 200) return;
    throw Exception(_extractError(response, endpoint, 'DELETE'));
  }

  // ---------------------------------------------------------------------------
  // Get the ERPNext base URL from stored credentials
  // ---------------------------------------------------------------------------
  static Future<String> getErpNextUrl() async {
    final creds = await getCredentials();
    return creds['url']!;
  }

  // ---------------------------------------------------------------------------
  // Session-cookie headers — used by the whole app
  // On web, browsers block manually-set Cookie headers, so token auth is used.
  // ---------------------------------------------------------------------------
  static Future<Map<String, String>> getAuthHeaders() async {
    if (kIsWeb) return getAiAuthHeaders();
    final prefs = await SharedPreferences.getInstance();
    _sessionCookie ??= prefs.getString(_keySessionCookie);
    _csrfToken     ??= prefs.getString(_keyCsrfToken);
    return _cookieHeaders();
  }

  static Map<String, String> _cookieHeaders() {
    return <String, String>{
      'Accept': 'application/json',
      'Cookie': ?_sessionCookie,
    };
  }

  // ---------------------------------------------------------------------------
  // API Token headers — used ONLY by the AI assistant module
  // ---------------------------------------------------------------------------
  static Future<Map<String, String>> getAiAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey    = prefs.getString(_keyApiKey)    ?? '';
    final apiSecret = prefs.getString(_keyApiSecret) ?? '';

    if (apiKey.isNotEmpty && apiSecret.isNotEmpty) {
      return {
        'Accept': 'application/json',
        'Authorization': 'token $apiKey:$apiSecret',
      };
    }

    // Fallback to session cookie if token not configured
    return getAuthHeaders();
  }

  // ---------------------------------------------------------------------------
  // Returns the Frappe user identifier (email) for the current session.
  // Falls back to the typed username if the email was never resolved.
  // ---------------------------------------------------------------------------
  static Future<String> getLoggedUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserEmail) ??
        prefs.getString(_keyUsername) ??
        '';
  }
}
