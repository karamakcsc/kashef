// ---------------------------------------------------------------------------
// fac_mcp_service.dart — FAC MCP Direct Client (no AI involved)
//
// Confirmed tool names (exact, from tools/list — lowercase + underscores):
//   get_pending_approvals, run_workflow, get_document, fetch, search, search_doctype
//
// Actual API response for get_pending_approvals:
//   {
//     "success": true,
//     "total_pending": 8,
//     "doctypes_with_pending": ["Sales Invoice"],
//     "pending_approvals": {
//       "Sales Invoice": [
//         { "document_name": "ACC-SINV-2026-00016",
//           "workflow_state": "Pending",
//           "permitted_roles": ["Accounts Manager"],
//           "creation": "2026-05-09 00:30:01.000205",
//           "available_actions": [{"action": "Approve", "next_state": "Approved"}] }
//       ]
//     },
//     "message": "Found 8 document(s)..."
//   }
// ---------------------------------------------------------------------------

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'workflow_models.dart';

// ─── FAC Diagnostics — global singleton for debug panel & audit logging ───────
/// Updated by: FacMcpService, FacValidator, WorkflowRepository
/// Read by: PendingApprovalsPage debug panel
class FacDiagnostics {
  static final FacDiagnostics _i = FacDiagnostics._();
  factory FacDiagnostics() => _i;
  FacDiagnostics._();

  // FAC tool / skill info
  String toolName     = '';
  String skillUsed    = '';
  String responseType = ''; // MCP_TOOL | FAC_SKILL | WORKFLOW | STRUCTURED | PAYLOAD | DIRECT
  String parserMode   = ''; // content[0].text | skill_result | tool_result | …

  // Auth info
  String authMode     = ''; // 'token' | 'session'
  String activeUserId = '';

  // Availability
  bool      facAvailable    = true;
  DateTime? lastSuccessTime;
  String?   lastError;

  // Raw FAC response text (content[0].text, first 600 chars) — for debug panel
  String lastRawFacText = '';
  String facToolStatus  = ''; // '' | 'OK' | 'isError=true' | 'no_content'

  // Source counts (set by WorkflowRepository / FacMcpService)
  int source0Count = 0;
  int sourceACount = 0;
  int sourceBCount = 0;

  // Permission / security audit
  int              permissionFiltered   = 0;
  int              hiddenDocumentsCount = 0;
  final Set<String> deniedDoctypes       = {};
  final Set<String> deniedActions        = {};
  final Set<String> skippedDoctypes      = {};

  void resetSession() {
    toolName = ''; skillUsed = ''; responseType = ''; parserMode = '';
    authMode = ''; lastError = null; facAvailable = true;
    lastRawFacText = ''; facToolStatus = '';
    permissionFiltered = 0; hiddenDocumentsCount = 0;
    source0Count = 0; sourceACount = 0; sourceBCount = 0;
    deniedDoctypes.clear(); deniedActions.clear(); skippedDoctypes.clear();
  }

  Map<String, dynamic> toMap() => {
    'fac_tool':            toolName.isEmpty      ? '—' : toolName,
    'fac_skill':           skillUsed.isEmpty     ? '—' : skillUsed,
    'response_type':       responseType.isEmpty  ? '—' : responseType,
    'parser_mode':         parserMode.isEmpty    ? '—' : parserMode,
    'auth_mode':           authMode.isEmpty      ? '—' : authMode,
    'user_id':             activeUserId.isEmpty  ? '—' : activeUserId,
    'fac_available':       facAvailable,
    'source_0 (FAC)':      source0Count,
    'source_a (WF Action)':sourceACount,
    'source_b (Scan)':     sourceBCount,
    'permission_filtered': permissionFiltered,
    'denied_doctypes':     deniedDoctypes.toList(),
    'denied_actions':      deniedActions.toList(),
    'hidden_docs':         hiddenDocumentsCount,
    'skipped_doctypes':    skippedDoctypes.toList(),
    'last_success':        lastSuccessTime?.toIso8601String() ?? '—',
    'last_error':          lastError ?? '—',
    'fac_tool_status':     facToolStatus.isEmpty ? '—' : facToolStatus,
    'fac_raw_preview':     lastRawFacText.isEmpty ? '—' : lastRawFacText,
  };
}

// ─── Enhanced FAC content extractor ──────────────────────────────────────────
/// Extracts the payload from any FAC/MCP response format.
/// Supports all known variants:
///   Format 1  content[0].text     — standard MCP tool response (JSON string)
///   Format 2  skill_result         — FAC Skills
///   Format 3  tool_result          — alternate FAC tool format
///   Format 4  workflow_documents   — workflow-specific response
///   Format 5  structuredContent    — MCP extended (Anthropic spec)
///   Format 6  payload              — generic payload wrapper
///   Format 7  data                 — simple data wrapper
///   Format 8  direct object        — result IS the payload (no wrapper)
dynamic _extractFacContent(Map<String, dynamic> rpcResult, String toolName) {
  final diag = FacDiagnostics()..toolName = toolName;

  // Format 1: Standard MCP — content[0].text (JSON string or plain text)
  final content = rpcResult['content'];
  if (content is List && content.isNotEmpty) {
    final first = content.first;
    if (first is Map && first['type'] == 'text') {
      final text = first['text']?.toString() ?? '';
      diag.parserMode  = 'content[0].text';
      diag.responseType = 'MCP_TOOL';
      debugPrint('[FAC] Parser: content[0].text (${text.length} chars)');
      try { return jsonDecode(text); } catch (_) { return text; }
    }
  }

  // Format 2: FAC Skill — skill_result
  if (rpcResult.containsKey('skill_result')) {
    diag.parserMode  = 'skill_result';
    diag.responseType = 'FAC_SKILL';
    diag.skillUsed   = rpcResult['skill_name']?.toString() ?? toolName;
    debugPrint('[FAC] Parser: skill_result (skill="${diag.skillUsed}")');
    final sr = rpcResult['skill_result'];
    if (sr is String) { try { return jsonDecode(sr); } catch (_) { return sr; } }
    return sr;
  }

  // Format 3: Alternate tool format — tool_result
  if (rpcResult.containsKey('tool_result')) {
    diag.parserMode  = 'tool_result';
    diag.responseType = 'FAC_TOOL_ALT';
    debugPrint('[FAC] Parser: tool_result');
    final tr = rpcResult['tool_result'];
    if (tr is String) { try { return jsonDecode(tr); } catch (_) { return tr; } }
    return tr;
  }

  // Format 4: Workflow-specific — workflow_documents
  if (rpcResult.containsKey('workflow_documents')) {
    diag.parserMode  = 'workflow_documents';
    diag.responseType = 'WORKFLOW';
    debugPrint('[FAC] Parser: workflow_documents');
    return rpcResult; // return full map; downstream handles workflow_documents key
  }

  // Format 5: MCP extended — structuredContent
  if (rpcResult.containsKey('structuredContent')) {
    diag.parserMode  = 'structuredContent';
    diag.responseType = 'STRUCTURED';
    debugPrint('[FAC] Parser: structuredContent');
    return rpcResult['structuredContent'];
  }

  // Format 6: Generic payload wrapper
  if (rpcResult.containsKey('payload')) {
    diag.parserMode  = 'payload';
    diag.responseType = 'PAYLOAD';
    debugPrint('[FAC] Parser: payload');
    final p = rpcResult['payload'];
    if (p is String) { try { return jsonDecode(p); } catch (_) { return p; } }
    return p;
  }

  // Format 7: Simple data wrapper
  if (rpcResult.containsKey('data')) {
    final d = rpcResult['data'];
    if (d != null) {
      diag.parserMode  = 'data';
      diag.responseType = 'DATA_WRAP';
      debugPrint('[FAC] Parser: data wrapper');
      if (d is String) { try { return jsonDecode(d); } catch (_) { return d; } }
      return d;
    }
  }

  // Format 8: Direct result object
  diag.parserMode  = 'direct';
  diag.responseType = 'DIRECT';
  debugPrint('[FAC] Parser: direct object keys=${rpcResult.keys.toList()}');
  return rpcResult;
}

// ─── Proper data models matching the actual FAC response ─────────────────────

class FacWorkflowAction {
  final String action;
  final String nextState;

  const FacWorkflowAction({required this.action, required this.nextState});

  factory FacWorkflowAction.fromJson(dynamic j) {
    final m = j is Map ? Map<String, dynamic>.from(j) : <String, dynamic>{};
    return FacWorkflowAction(
      action:    m['action']?.toString()     ?? '',
      nextState: m['next_state']?.toString() ?? '',
    );
  }
}

class FacPendingDoc {
  final String               doctype;
  final String               documentName;
  final String               workflowState;
  final String               creation;
  final List<String>         permittedRoles;
  final List<FacWorkflowAction> availableActions;

  const FacPendingDoc({
    required this.doctype,
    required this.documentName,
    required this.workflowState,
    required this.creation,
    required this.permittedRoles,
    required this.availableActions,
  });

  factory FacPendingDoc.fromJson(String doctype, dynamic j) {
    final m = j is Map ? Map<String, dynamic>.from(j) : <String, dynamic>{};
    final roles = (m['permitted_roles'] as List? ?? [])
        .map((r) => r.toString())
        .toList();
    final actions = (m['available_actions'] as List? ?? [])
        .map((a) => FacWorkflowAction.fromJson(a))
        .toList();
    return FacPendingDoc(
      doctype:          doctype,
      documentName:     m['document_name']?.toString() ?? '',
      workflowState:    m['workflow_state']?.toString() ?? '',
      creation:         m['creation']?.toString()       ?? '',
      permittedRoles:   roles,
      availableActions: actions,
    );
  }

  // First 10 chars of creation → YYYY-MM-DD
  String get creationShort =>
      creation.length >= 10 ? creation.substring(0, 10) : creation;

  // Convert to the generic PendingDoc for badge / realtime counting
  PendingDoc toPendingDoc() => PendingDoc(
        doctype:       doctype,
        docname:       documentName,
        workflowState: workflowState,
        creation:      creation,
        source:        WorkflowSource.facTool,
      );
}

class FacPendingResult {
  final bool                           success;
  final int                            totalPending;
  final List<String>                   doctypesWithPending;
  final Map<String, List<FacPendingDoc>> pendingApprovals;
  final String                         message;

  const FacPendingResult({
    required this.success,
    required this.totalPending,
    required this.doctypesWithPending,
    required this.pendingApprovals,
    required this.message,
  });

  bool get isEmpty => pendingApprovals.isEmpty || totalPending == 0;

  int get totalDocs =>
      pendingApprovals.values.fold(0, (sum, list) => sum + list.length);

  List<FacPendingDoc> get allDocs =>
      pendingApprovals.values.expand((l) => l).toList();

  /// Parse the actual FAC get_pending_approvals response.
  factory FacPendingResult.fromJson(dynamic raw) {
    debugPrint('[FAC] Parsing response type: ${raw.runtimeType}');

    if (raw is! Map) {
      debugPrint('[FAC] ERROR: raw is not a Map — got ${raw.runtimeType}');
      return const FacPendingResult(
        success: false, totalPending: 0,
        doctypesWithPending: [], pendingApprovals: {}, message: '',
      );
    }

    final m = Map<String, dynamic>.from(raw);

    debugPrint('[FAC] Raw keys: ${m.keys.toList()}');
    debugPrint('[FAC] success=${m['success']}  total_pending=${m['total_pending']}');

    final success      = m['success'] == true;
    final totalPending = (m['total_pending'] as num?)?.toInt() ?? 0;
    final message      = m['message']?.toString() ?? '';
    final dtList       = (m['doctypes_with_pending'] as List? ?? [])
        .map((e) => e.toString())
        .toList();

    // The key field: pending_approvals is Map<String, List>
    final paRaw = m['pending_approvals'];
    debugPrint('[FAC] pending_approvals type: ${paRaw?.runtimeType}');

    final Map<String, List<FacPendingDoc>> pa = {};

    if (paRaw is Map) {
      debugPrint('[FAC] pending_approvals keys: ${paRaw.keys.toList()}');
      for (final entry in paRaw.entries) {
        final doctype = entry.key.toString();
        final rawList = entry.value;
        if (rawList is! List) {
          debugPrint('[FAC] Skipping $doctype — value is not a List');
          continue;
        }
        final docs = <FacPendingDoc>[];
        for (final item in rawList) {
          final doc = FacPendingDoc.fromJson(doctype, item);
          if (doc.documentName.isNotEmpty) {
            debugPrint('[FAC]   ✔ $doctype/${doc.documentName} — "${doc.workflowState}"');
            docs.add(doc);
          } else {
            debugPrint('[FAC]   ⚠ Skipping item with empty documentName: $item');
          }
        }
        if (docs.isNotEmpty) pa[doctype] = docs;
      }
    } else {
      debugPrint('[FAC] pending_approvals is null or not a Map — nothing to parse');
    }

    debugPrint(
      '[FAC] Parse complete: '
      '${pa.length} doctypes, '
      '${pa.values.fold(0, (s, l) => s + l.length)} docs total',
    );

    return FacPendingResult(
      success:             success,
      totalPending:        totalPending,
      doctypesWithPending: dtList,
      pendingApprovals:    pa,
      message:             message,
    );
  }
}

// ---------------------------------------------------------------------------

class FacMcpService {
  static final FacMcpService _instance = FacMcpService._();
  factory FacMcpService() => _instance;
  FacMcpService._();

  bool _initialized = false;
  int  _reqId       = 0;
  List<Map<String, dynamic>>? _cachedTools;

  static const _kToolPendingApprovals = 'get_pending_approvals';
  static const _kToolRunWorkflow      = 'run_workflow';
  static const _kToolGetDocument      = 'get_document';
  static const _kToolFetch            = 'fetch';
  static const _kToolSearch           = 'search';
  static const _kToolSearchDoctype    = 'search_doctype';

  // Public constants
  static const kToolPendingApprovals = _kToolPendingApprovals;
  static const kToolRunWorkflow      = _kToolRunWorkflow;
  static const kToolGetDocument      = _kToolGetDocument;

  void reset() {
    _initialized = false;
    _cachedTools = null;
    _reqId       = 0;
    debugPrint('[FAC] Session reset');
  }

  // ── Core MCP request (with retry) ────────────────────────────────────────

  /// Wrapper with exponential-backoff retry (max 2 retries) for transient errors.
  /// Does NOT retry permission/auth errors (403, "not allowed", "not found").
  Future<Map<String, dynamic>> _mcpRequest(
    String method,
    Map<String, dynamic> params,
  ) async {
    const maxRetries = 2;
    Exception? lastErr;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await _mcpRequestOnce(method, params);
      } on Exception catch (e) {
        lastErr = e;
        FacDiagnostics().lastError = e.toString();
        final msg = e.toString().toLowerCase();
        // Never retry permission / permanent failures
        if (msg.contains('403') || msg.contains('permission denied') ||
            msg.contains('not allowed') || msg.contains('not found') ||
            msg.contains('401')) {
          rethrow;
        }
        if (attempt < maxRetries) {
          final delay = Duration(seconds: (attempt + 1) * 2);
          debugPrint('[FAC] Retry ${attempt + 1}/$maxRetries in ${delay.inSeconds}s: $e');
          await Future.delayed(delay);
        }
      }
    }
    throw lastErr!;
  }

  Future<Map<String, dynamic>> _mcpRequestOnce(
    String method,
    Map<String, dynamic> params,
  ) async {
    final prefs    = await SharedPreferences.getInstance();
    final baseUrl  = prefs.getString('erpnext_url') ?? '';
    final endpoint = prefs.getString('ai_endpoint')  ?? '';

    if (baseUrl.isEmpty || endpoint.isEmpty) {
      throw Exception('FAC endpoint not configured in Settings.');
    }

    var headers = await ApiService.getAiAuthHeaders();
    // For session auth, add CSRF token (required for Frappe POST)
    if (!headers.containsKey('Authorization')) {
      final csrf = prefs.getString('erpnext_csrf_token') ?? '';
      if (csrf.isNotEmpty) headers = {...headers, 'X-Frappe-CSRF-Token': csrf};
    }
    final id   = ++_reqId;
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id':      id,
      'method':  method,
      'params':  params,
    });

    debugPrint('[FAC] → [$id] $method');

    final url      = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/method/$endpoint');
    final response = await http
        .post(url, headers: {...headers, 'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 30));

    debugPrint('[FAC] ← [$id] ${response.statusCode}');

    if (response.statusCode == 401 || response.statusCode == 403) {
      debugPrint('[FAC] Session expired — re-logging in');
      final err = await ApiService.login();
      if (err != null) throw Exception('Re-login failed: $err');
      final newH  = await ApiService.getAiAuthHeaders();
      final retry = await http
          .post(url, headers: {...newH, 'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 30));
      return _parseResponse(retry);
    }
    return _parseResponse(response);
  }

  Map<String, dynamic> _parseResponse(http.Response resp) {
    if (resp.statusCode != 200) {
      throw Exception('[FAC] HTTP ${resp.statusCode}: ${resp.body}');
    }
    final outer = jsonDecode(resp.body);
    if (outer is! Map<String, dynamic>) {
      throw Exception('[FAC] Unexpected outer response type');
    }
    final msg = outer['message'];
    Map<String, dynamic> rpc;
    if (msg is String) {
      rpc = jsonDecode(msg) as Map<String, dynamic>;
    } else if (msg is Map) {
      rpc = Map<String, dynamic>.from(msg);
    } else {
      rpc = outer;
    }
    if (rpc.containsKey('error')) {
      final err = rpc['error'];
      throw Exception(
        err is Map ? (err['message']?.toString() ?? err.toString()) : err.toString(),
      );
    }
    return rpc;
  }

  // ── Initialize ────────────────────────────────────────────────────────────

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    debugPrint('[FAC] Initializing MCP session…');
    await _mcpRequest('initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': {},
      'clientInfo': {'name': 'kcsc_ai_pending', 'version': '1.0'},
    });
    _initialized = true;
    debugPrint('[FAC] MCP session initialized ✅');
  }

  // ── Tool discovery ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _getTools() async {
    if (_cachedTools != null) return _cachedTools!;
    await _ensureInitialized();

    final res    = await _mcpRequest('tools/list', {});
    final result = res['result'] as Map? ?? {};
    final tools  =
        (result['tools'] as List? ?? []).cast<Map<String, dynamic>>();
    _cachedTools = tools;

    debugPrint('[FAC] ${tools.length} tools available:');
    for (final t in tools) { debugPrint('  • "${t['name']}"'); }
    return tools;
  }

  Future<Map<String, dynamic>?> _findTool(String toolName) async {
    final tools = await _getTools();
    try {
      return tools.firstWhere((t) => t['name']?.toString() == toolName);
    } catch (_) {
      debugPrint(
        '[FAC] Tool "$toolName" not found. '
        'Available: ${tools.map((t) => '"${t['name']}"').join(', ')}',
      );
      return null;
    }
  }

  // ── Call tool ─────────────────────────────────────────────────────────────

  Future<dynamic> _callTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    await _ensureInitialized();
    debugPrint('[FAC] Calling "$toolName" args=${jsonEncode(arguments)}');

    final res = await _mcpRequest('tools/call', {
      'name':      toolName,
      'arguments': arguments,
    });

    // Unpack MCP envelope: {result: {content: [...] | skill_result | tool_result | ...}}
    final result = res['result'];
    if (result == null) {
      FacDiagnostics().parserMode = 'null_result';
      return null;
    }
    if (result is! Map) {
      FacDiagnostics().parserMode = 'direct_non_map';
      return result;
    }

    final resultMap = Map<String, dynamic>.from(result);
    debugPrint('[FAC] result keys: ${resultMap.keys.toList()}');

    // Use enhanced content extractor supporting all 8 FAC response formats
    final extracted = _extractFacContent(resultMap, toolName);
    final preview = extracted?.toString() ?? 'null';
    debugPrint('[FAC] Extracted[${FacDiagnostics().parserMode}] (first 400): '
        '${preview.substring(0, preview.length.clamp(0, 400))}');
    return extracted;
  }

  // ── get_pending_approvals ─────────────────────────────────────────────────

  /// Returns [FacPendingResult] with properly typed data, or null if FAC fails.
  Future<FacPendingResult?> getPendingApprovals() async {
    final diag = FacDiagnostics();
    try {
      // Detect auth mode for diagnostics
      final authHeaders = await ApiService.getAiAuthHeaders();
      diag
        ..authMode     = authHeaders.containsKey('Authorization') ? 'token' : 'session'
        ..activeUserId = await ApiService.getLoggedUserId()
        ..facAvailable = true;

      final tool = await _findTool(_kToolPendingApprovals);
      if (tool == null) {
        diag.facAvailable = false;
        debugPrint('[FAC] get_pending_approvals not found on this server');
        return null;
      }
      final raw    = await _callTool(_kToolPendingApprovals, {});
      final result = FacPendingResult.fromJson(raw);
      diag
        ..lastSuccessTime = DateTime.now()
        ..source0Count    = result.totalDocs
        ..facAvailable    = true;
      debugPrint(
        '[FAC] getPendingApprovals: '
        'success=${result.success} total=${result.totalPending} '
        'doctypes=${result.doctypesWithPending} '
        'auth=${diag.authMode} user=${diag.activeUserId}',
      );
      return result;
    } catch (e, st) {
      diag
        ..lastError    = e.toString()
        ..facAvailable = false;
      debugPrint('[FAC] getPendingApprovals ERROR: $e\n$st');
      return null;
    }
  }

  // ── run_workflow ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> runWorkflow(
    Map<String, dynamic> doc,
    String action,
  ) async {
    try {
      final tool = await _findTool(_kToolRunWorkflow);
      if (tool == null) return null;
      final raw = await _callTool(_kToolRunWorkflow, {
        'doctype': doc['doctype']?.toString() ?? '',
        'name':    doc['name']?.toString()    ?? '',   // FAC expects 'name', not 'docname'
        'action':  action,
      });
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) {
        final nested = raw['doc'] ?? raw['document'] ?? raw['data'];
        if (nested is Map<String, dynamic>) return nested;
      }
      return null;
    } catch (e) {
      debugPrint('[FAC] runWorkflow ERROR: $e');
      return null;
    }
  }

  // ── submit_document ───────────────────────────────────────────────────────

  /// Submits a document (docstatus 0 → 1) via the FAC submit_document tool.
  /// Returns the result map on success, or null if the tool is unavailable.
  /// Throws on tool-level errors (permission denied, validation failure, etc.).
  Future<Map<String, dynamic>?> submitDocument(
      String doctype, String name) async {
    const kTool = 'submit_document';
    try {
      final tool = await _findTool(kTool);
      if (tool == null) {
        debugPrint('[FAC] submit_document not found on this server');
        return null; // caller should fall back to frappe.client.submit
      }
      FacDiagnostics().toolName = kTool;
      debugPrint('[FAC] submit_document → $doctype/$name');
      final raw = await _callTool(kTool, {
        'doctype': doctype,
        'name':    name,
      });
      // FAC wraps the result inside result.success / result.data
      if (raw is Map) {
        final m    = raw.cast<String, dynamic>();
        final ok   = m['success'] == true;
        final data = m['data'] ?? m['doc'] ?? m['result'] ?? m;
        if (!ok) {
          final err = m['error']?.toString() ?? m['message']?.toString() ?? 'submit_document failed';
          throw Exception(err);
        }
        FacDiagnostics().lastSuccessTime = DateTime.now();
        debugPrint('[FAC] submit_document ✅ $doctype/$name');
        return data is Map<String, dynamic> ? data : m;
      }
      return null;
    } catch (e) {
      debugPrint('[FAC] submit_document ERROR: $e');
      rethrow;
    }
  }

  // ── cancel_document ───────────────────────────────────────────────────────

  /// Cancels a document (docstatus 1 → 2) via the FAC cancel_document tool.
  /// Returns result map on success, null if tool is unavailable (caller falls back).
  /// Throws on permission/validation errors.
  Future<Map<String, dynamic>?> cancelDocument(
      String doctype, String name) async {
    const kTool = 'cancel_document';
    try {
      final tool = await _findTool(kTool);
      if (tool == null) {
        debugPrint('[FAC] cancel_document not found on this server');
        return null;
      }
      FacDiagnostics().toolName = kTool;
      debugPrint('[FAC] cancel_document → $doctype/$name');
      final raw = await _callTool(kTool, {'doctype': doctype, 'name': name});
      if (raw is Map) {
        final m   = raw.cast<String, dynamic>();
        final ok  = m['success'] == true;
        if (!ok) {
          throw Exception(
              m['error']?.toString() ?? m['message']?.toString() ?? 'cancel_document failed');
        }
        FacDiagnostics().lastSuccessTime = DateTime.now();
        debugPrint('[FAC] cancel_document ✅ $doctype/$name');
        final data = m['data'] ?? m['doc'] ?? m['result'] ?? m;
        return data is Map<String, dynamic> ? data : m;
      }
      return null;
    } catch (e) {
      debugPrint('[FAC] cancel_document ERROR: $e');
      rethrow;
    }
  }

  // ── get_document ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getDocument(
      String doctype, String docname) async {
    try {
      final tool = await _findTool(_kToolGetDocument);
      if (tool == null) return null;
      final raw = await _callTool(_kToolGetDocument, {
        'doctype': doctype,
        'name':    docname,
      });
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) {
        final nested = raw['data'] ?? raw['doc'] ?? raw['message'];
        if (nested is Map<String, dynamic>) return nested;
      }
      return null;
    } catch (e) {
      debugPrint('[FAC] getDocument ERROR: $e');
      return null;
    }
  }

  // ── Other tools ───────────────────────────────────────────────────────────

  Future<dynamic> fetch(Map<String, dynamic> args) async {
    try {
      final tool = await _findTool(_kToolFetch);
      if (tool == null) return null;
      return _callTool(_kToolFetch, args);
    } catch (e) {
      debugPrint('[FAC] fetch ERROR: $e');
      return null;
    }
  }

  Future<dynamic> search(Map<String, dynamic> args) async {
    try {
      final tool = await _findTool(_kToolSearch);
      if (tool == null) return null;
      return _callTool(_kToolSearch, args);
    } catch (e) {
      debugPrint('[FAC] search ERROR: $e');
      return null;
    }
  }

  Future<dynamic> searchDoctype(Map<String, dynamic> args) async {
    try {
      final tool = await _findTool(_kToolSearchDoctype);
      if (tool == null) return null;
      return _callTool(_kToolSearchDoctype, args);
    } catch (e) {
      debugPrint('[FAC] searchDoctype ERROR: $e');
      return null;
    }
  }

  Future<List<String>> listAvailableTools() async {
    final tools = await _getTools();
    return tools.map((t) => t['name']?.toString() ?? '').toList();
  }
}
