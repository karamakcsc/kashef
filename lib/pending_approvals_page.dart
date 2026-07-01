import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'app_colors.dart';
import 'app_gradients.dart';
import 'app_localizations.dart';
import 'aurora_background.dart';
import 'aurora_widgets.dart';
import 'fac_mcp_service.dart' show FacDiagnostics;
import 'realtime_workflow_service.dart';
import 'workflow_service.dart';

// ═════════════════════════════════════════════════════════════════════════════
// TOP-LEVEL: MCP / FAC helpers
// ═════════════════════════════════════════════════════════════════════════════

int    _mcpSeq       = 0;
const  _kFacEndpoint = 'frappe_assistant_core.api.fac_endpoint.handle_mcp';

Future<String> _facEp() async {
  final p = await SharedPreferences.getInstance();
  return p.getString('ai_endpoint') ?? _kFacEndpoint;
}

/// JSON-RPC 2.0 POST — mirrors ai_assistant_page._mcpRequest exactly,
/// including CSRF token for session auth (which post()/postForm() also add).
Future<Map<String, dynamic>> _mcpPost(
  String endpoint,
  String method,
  Map<String, dynamic> params,
) async {
  // Trim trailing slash — prevents double-slash in URL
  final base = (await ApiService.getErpNextUrl()).replaceAll(RegExp(r'/+$'), '');
  final id   = ++_mcpSeq;
  final uri  = Uri.parse('$base/api/method/$endpoint');
  final body = jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});

  Future<http.Response> fire(Map<String, String> h) => http
      .post(uri, headers: {...h, 'Content-Type': 'application/json'}, body: body)
      .timeout(const Duration(seconds: 30));

  // getAiAuthHeaders() → token auth (no CSRF needed) or session auth
  // For session auth, also add X-Frappe-CSRF-Token (same as ApiService.post())
  var hdrs = await ApiService.getAiAuthHeaders();
  if (!hdrs.containsKey('Authorization')) {
    // Session-based — add CSRF token (required for Frappe POST)
    final prefs = await SharedPreferences.getInstance();
    final csrf  = prefs.getString('erpnext_csrf_token') ?? '';
    if (csrf.isNotEmpty) hdrs = {...hdrs, 'X-Frappe-CSRF-Token': csrf};
  }

  var resp = await fire(hdrs);
  debugPrint('[MCP] $method → ${resp.statusCode}  uri=$uri');

  if (resp.statusCode == 401 || resp.statusCode == 403) {
    debugPrint('[MCP] Re-login…');
    final err = await ApiService.login();
    if (err != null) throw Exception('Session expired. Re-login failed: $err');
    hdrs = await ApiService.getAiAuthHeaders();
    if (!hdrs.containsKey('Authorization')) {
      final prefs = await SharedPreferences.getInstance();
      final csrf  = prefs.getString('erpnext_csrf_token') ?? '';
      if (csrf.isNotEmpty) hdrs = {...hdrs, 'X-Frappe-CSRF-Token': csrf};
    }
    resp = await fire(hdrs);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode} after re-login: ${resp.body.substring(0, resp.body.length.clamp(0, 200))}');
    }
  } else if (resp.statusCode != 200) {
    throw Exception('HTTP ${resp.statusCode}: ${resp.body.substring(0, resp.body.length.clamp(0, 400))}');
  }

  debugPrint('[MCP] body(200): ${resp.body.substring(0, resp.body.length.clamp(0, 300))}');
  return _parseRpc(resp.body);
}

Map<String, dynamic> _parseRpc(String body) {
  late Map<String, dynamic> outer;
  try {
    outer = jsonDecode(body) as Map<String, dynamic>;
  } catch (_) {
    throw Exception('JSON parse error: ${body.substring(0, body.length.clamp(0, 200))}');
  }

  if (outer.containsKey('exc_type') || outer.containsKey('_server_messages')) {
    throw Exception('Frappe [${outer['exc_type']}] ${outer['_server_messages'] ?? ''}');
  }

  final msg = outer['message'];
  Map<String, dynamic> rpc;
  if (msg is String) {
    try { rpc = jsonDecode(msg) as Map<String, dynamic>; } catch (_) { rpc = outer; }
  } else if (msg is Map) {
    rpc = Map<String, dynamic>.from(msg);
  } else {
    rpc = outer;
  }

  if (rpc.containsKey('error')) {
    final e = rpc['error'];
    throw Exception((e is Map ? e['message'] : e)?.toString() ?? 'MCP error');
  }
  return rpc;
}

// ─────────────────────────────────────────────────────────────────────────────
// Universal pending_approvals extractor
//
// Supports ALL FAC / MCP response variants:
//   CASE 1 — rpc.result.content[0].text  (most common — FAC tool response)
//   CASE 2 — rpc.message  (JSON string)
//   CASE 3 — rpc.message  (Map)
//   CASE 4 — rpc.pending_approvals  (direct root)
//   CASE 5 — rpc.result.structuredContent
//   CASE 6 — nested inside rpc.data
// ─────────────────────────────────────────────────────────────────────────────

Map<String, dynamic>? _extractPa(dynamic rpc) {
  if (rpc == null || rpc is! Map) return null;
  final r = rpc.cast<String, dynamic>();

  // CASE 1: Standard MCP — result.content[0].text (JSON string)
  final resultNode = r['result'];
  if (resultNode is Map) {
    final contentList = resultNode['content'];
    if (contentList is List && contentList.isNotEmpty) {
      // Try ALL content items (not just the first)
      for (final item in contentList) {
        if (item is! Map || item['type'] != 'text') continue;
        final text = item['text']?.toString() ?? '';
        if (text.isEmpty) continue;
        final decoded = _tryDecode(text);
        final pa = _findPa(decoded);
        if (pa != null) { debugPrint('[FAC Parser] CASE 1 — content[].text'); return pa; }
      }
    }

    // CASE 1b: result directly contains pending_approvals (no content wrapper)
    final pa1b = _findPa(resultNode);
    if (pa1b != null) { debugPrint('[FAC Parser] CASE 1b — result direct'); return pa1b; }

    // CASE 5: result.structuredContent
    if (resultNode['structuredContent'] is Map) {
      final pa = _findPa(resultNode['structuredContent']);
      if (pa != null) { debugPrint('[FAC Parser] CASE 5 — structuredContent'); return pa; }
    }
  }

  // CASE 2/3: message (string or Map)
  final msg = r['message'];
  if (msg is String) {
    final pa = _findPa(_tryDecode(msg));
    if (pa != null) { debugPrint('[FAC Parser] CASE 2 — message string'); return pa; }
  } else if (msg is Map) {
    final pa = _findPa(msg);
    if (pa != null) { debugPrint('[FAC Parser] CASE 3 — message Map'); return pa; }
  }

  // CASE 4: direct root
  final pa4 = _findPa(r);
  if (pa4 != null) { debugPrint('[FAC Parser] CASE 4 — direct root'); return pa4; }

  // CASE 6: nested data
  if (r['data'] is Map) {
    final pa = _findPa(r['data']);
    if (pa != null) { debugPrint('[FAC Parser] CASE 6 — nested data'); return pa; }
  }

  debugPrint('[FAC Parser] ⚠ No pending_approvals found. Top-level keys: ${r.keys.toList()}');
  return null;
}

Map<String, dynamic>? _findPa(dynamic node) {
  if (node == null || node is! Map) return null;
  final m = node.cast<String, dynamic>();

  // Standard: pending_approvals key — Map OR JSON-encoded string
  if (m.containsKey('pending_approvals')) {
    var pa = m['pending_approvals'];
    // Decode if FAC returns pending_approvals as a JSON string
    if (pa is String && pa.isNotEmpty) {
      try { pa = jsonDecode(pa); } catch (_) {}
    }
    if (pa is Map) {
      FacDiagnostics().parserMode = '${FacDiagnostics().parserMode}+pending_approvals';
      return pa.cast<String, dynamic>();
    }
  }

  // FAC Skill wrapper — skill_result contains the actual data
  if (m.containsKey('skill_result')) {
    FacDiagnostics().responseType = 'FAC_SKILL';
    final r = _findPa(m['skill_result']);
    if (r != null) return r;
  }

  // Alternate tool format — tool_result wrapper
  if (m.containsKey('tool_result')) {
    FacDiagnostics().responseType = 'FAC_TOOL_ALT';
    final r = _findPa(m['tool_result']);
    if (r != null) return r;
  }

  // workflow_documents — convert to pending_approvals format
  if (m.containsKey('workflow_documents') && m['workflow_documents'] is Map) {
    FacDiagnostics().responseType = 'WORKFLOW';
    return _convertWorkflowDocuments(m['workflow_documents'] as Map);
  }

  // Generic payload wrapper
  if (m.containsKey('payload')) {
    final r = _findPa(m['payload']);
    if (r != null) return r;
  }

  // data wrapper (e.g. {"data": {"pending_approvals": {...}}})
  if (m.containsKey('data') && m['data'] is Map) {
    final r = _findPa(m['data']);
    if (r != null) return r;
  }

  // result wrapper — FAC v2.0.0 double-wraps: {success: true, result: {pending_approvals: {...}}}
  // The outer text is {"success": true, "result": {"success": true, "pending_approvals": {...}}}
  if (m.containsKey('result') && m['result'] is Map) {
    final r = _findPa(m['result']);
    if (r != null) return r;
  }

  return null;
}

/// Converts workflow_documents format → pending_approvals format.
/// workflow_documents: {"Sales Invoice": [{"name": "X", "state": "Y", ...}]}
Map<String, dynamic>? _convertWorkflowDocuments(Map raw) {
  final result = <String, dynamic>{};
  raw.forEach((doctype, docs) {
    if (docs is! List) return;
    final normalized = docs.map((doc) {
      if (doc is! Map) return doc;
      final d = doc.cast<String, dynamic>();
      return {
        'document_name':    d['document_name'] ?? d['name']    ?? d['docname']  ?? '',
        'workflow_state':   d['workflow_state'] ?? d['state']   ?? '',
        'creation':         d['creation']       ?? d['created'] ?? '',
        'available_actions':d['available_actions'] ?? d['actions'] ?? [],
        'permitted_roles':  d['permitted_roles']   ?? d['roles']   ?? [],
      };
    }).toList();
    result[doctype.toString()] = normalized;
  });
  return result.isEmpty ? null : result;
}

dynamic _tryDecode(String s) {
  try { return jsonDecode(s); } catch (_) { return null; }
}

// ─── Batch docstatus checker ──────────────────────────────────────────────────
/// Checks docstatus for groups of documents — one API call per doctype (not per doc).
///
/// `groups`          : `Map<doctype, List<docname>>`
/// `targetDocstatus` : 0=Draft, 1=Submitted, 2=Cancelled
///
/// Returns `Map<doctype, Set<docname>>` — only docs with [targetDocstatus].
/// On API error: safe fallback = show all (never block UX due to a permission check failure).
Future<Map<String, Set<String>>> _batchCheckDocstatus(
  Map<String, List<String>> groups,
  int targetDocstatus,
) async {
  final result = <String, Set<String>>{};
  if (groups.isEmpty) return result;

  await Future.wait(groups.entries.map((entry) async {
    final dt    = entry.key;
    final names = entry.value;
    if (names.isEmpty) { result[dt] = {}; return; }
    try {
      final res = await ApiService.postForm(
        '/api/method/frappe.client.get_list',
        {
          'doctype':           dt,
          'fields':            jsonEncode(['name']),
          'filters':           jsonEncode([
            ['name',      'in', names],
            ['docstatus', '=',  targetDocstatus],
          ]),
          'limit_page_length': '${names.length}',
        },
      );
      final list = (res['message'] as List?) ?? [];
      result[dt] = list
          .map<String>((e) => (e['name'] ?? '').toString())
          .where((n) => n.isNotEmpty)
          .toSet();
      debugPrint(
        '[docstatus=$targetDocstatus] $dt: '
        '${result[dt]!.length}/${names.length} matched',
      );
    } catch (e) {
      // Safe fallback: show all when check fails (avoid blank page due to perm error)
      debugPrint('[docstatus] Error checking $dt: $e — showing all as safe fallback');
      result[dt] = names.toSet();
    }
  }));
  return result;
}

// ═════════════════════════════════════════════════════════════════════════════
// Models
// ═════════════════════════════════════════════════════════════════════════════

class _Act {
  final String label;
  final String nextState;
  const _Act({required this.label, required this.nextState});
}

class _Doc {
  final String    name;
  final String    state;
  final String    creation;
  final List<_Act> actions;
  const _Doc({
    required this.name,
    required this.state,
    required this.creation,
    required this.actions,
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// Page
// ═════════════════════════════════════════════════════════════════════════════

class PendingApprovalsPage extends StatefulWidget {
  const PendingApprovalsPage({super.key});

  @override
  State<PendingApprovalsPage> createState() => _State();
}

class _State extends State<PendingApprovalsPage> {

  // ── State fields ──────────────────────────────────────────────────────────

  bool   _loading      = true;
  bool   _refreshing   = false;
  bool   _busy         = false;        // guard against overlapping loads
  String _error        = '';
  String _facError     = '';   // visible to user in fallback banner
  bool   _isFallback   = false;

  Map<String, List<_Doc>> _data = {};
  String _search        = '';
  String _filterDoctype = '';

  final _searchCtrl  = TextEditingController();
  Timer? _debounce;
  Timer? _autoTimer;
  final Set<String> _dismissing = {}; // names currently fading out
  late  WorkflowEventCallback _rtCb;

  // ── Derived ───────────────────────────────────────────────────────────────

  int get _total => _data.values.fold(0, (s, l) => s + l.length);

  Map<String, List<_Doc>> get _display {
    var src = _data;

    if (_filterDoctype.isNotEmpty) {
      src = {if (src.containsKey(_filterDoctype)) _filterDoctype: src[_filterDoctype]!};
    }

    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      final out = <String, List<_Doc>>{};
      src.forEach((dt, docs) {
        final hits = docs.where((d) =>
          d.name.toLowerCase().contains(q) ||
          d.state.toLowerCase().contains(q)).toList();
        if (hits.isNotEmpty) out[dt] = hits;
      });
      debugPrint('[Pending] Filter "$_search" → ${out.values.fold(0,(s,l)=>s+l.length)} docs');
      return out;
    }
    return src;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load();
    _autoTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      debugPrint('[Pending] ⏰ Auto-refresh');
      _load(silent: true);
    });
    _rtCb = (ev) {
      debugPrint('[Pending] 📡 Realtime: $ev');
      _load(silent: true);
    };
    RealtimeWorkflowService().addListener(_rtCb);
  }

  @override
  void dispose() {
    _busy = false;
    _autoTimer?.cancel();
    _debounce?.cancel();
    _searchCtrl.dispose();
    RealtimeWorkflowService().removeListener(_rtCb);
    super.dispose();
  }

  // ── Load ─────────────────────────────────────────────────────────────────

  Future<void> _load({bool silent = false}) async {
    if (!mounted || _busy) return;
    _busy = true;

    if (!silent && mounted) setState(() { _loading = true; _error = ''; });

    // ── Try FAC ────────────────────────────────────────────────────────────
    try {
      final facData = await _fetchFac();
      debugPrint('[Pending] FAC data: ${facData?.map((k,v)=>MapEntry(k,v.length))}');

      if (facData != null && mounted) {
        setState(() {
          _data       = facData;
          _isFallback = false;
          _loading    = false;
        });
        debugPrint('[Pending] ✅ Rendered $_total docs in ${facData.length} groups');
        _busy = false;
        return;
      }
    } catch (e, st) {
      _facError = e.toString();
      debugPrint('[Pending] ❌ FAC error: $e\n$st');
    }

    // ── Fallback ────────────────────────────────────────────────────────────
    try {
      final fbData = await _fetchFallback();
      debugPrint('[Pending] Fallback data: ${fbData.map((k,v)=>MapEntry(k,v.length))}');
      if (mounted) setState(() { _data = fbData; _isFallback = true; _loading = false; });
    } catch (e) {
      debugPrint('[Pending] ❌ Fallback error: $e');
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }

    _busy = false;
  }

  Future<void> _manualRefresh() async {
    if (_refreshing) return;
    if (mounted) setState(() => _refreshing = true);
    _mcpSeq = 0;
    _busy   = false;
    await _load();
    if (mounted) setState(() => _refreshing = false);
  }

  // ── FAC fetch ─────────────────────────────────────────────────────────────

  Future<Map<String, List<_Doc>>?> _fetchFac() async {
    final ep = await _facEp();
    debugPrint('[FAC] endpoint=$ep');

    // ── Update auth diagnostics ──────────────────────────────────────────────
    try {
      final h = await ApiService.getAiAuthHeaders();
      FacDiagnostics()
        ..authMode     = h.containsKey('Authorization') ? 'token' : 'session'
        ..activeUserId = await ApiService.getLoggedUserId()
        ..toolName     = 'get_pending_approvals';
    } catch (_) {}

    // ── Initialize (non-fatal) ───────────────────────────────────────────────
    try {
      await _mcpPost(ep, 'initialize', {
        'protocolVersion': '2024-11-05',
        'capabilities':    {},
        'clientInfo':      {'name': 'kcsc_pending', 'version': '1.0'},
      });
      debugPrint('[FAC] initialized');
    } catch (e) {
      debugPrint('[FAC] init error (non-fatal): $e');
    }

    // ── Call tool ────────────────────────────────────────────────────────────
    debugPrint('[FAC] → get_pending_approvals');
    final rpc = await _mcpPost(ep, 'tools/call', {
      'name': 'get_pending_approvals', 'arguments': {},
    });

    final rpcStr = jsonEncode(rpc);
    debugPrint('[FAC] raw RPC (${rpcStr.length} chars): ${rpcStr.substring(0, rpcStr.length.clamp(0, 600))}');

    // ── Extract content text + check isError ─────────────────────────────────
    try {
      final resultNode = rpc['result'];
      if (resultNode is Map) {
        final isErr    = resultNode['isError'] == true;
        final content  = resultNode['content'];
        final text     = (content is List && content.isNotEmpty)
            ? (content[0]['text']?.toString() ?? '')
            : '';

        FacDiagnostics()
          ..lastRawFacText = text.substring(0, text.length.clamp(0, 600))
          ..facToolStatus  = isErr ? 'isError=true' : (text.isEmpty ? 'no_content' : 'OK');

        if (isErr) {
          final errMsg = 'FAC tool error: ${text.substring(0, text.length.clamp(0, 300))}';
          debugPrint('[FAC] ⚠ isError=true — $errMsg');
          FacDiagnostics()
            ..lastError    = errMsg
            ..facAvailable = false;
          if (mounted) setState(() => _facError = errMsg);
          return null;
        }
      } else {
        FacDiagnostics().facToolStatus = 'no_result_node';
      }
    } catch (e) {
      debugPrint('[FAC] content-extraction diagnostic error: $e');
    }

    // ── Parse pending_approvals ───────────────────────────────────────────────
    final paMap = _extractPa(rpc);
    if (paMap == null) {
      final rawPreview = FacDiagnostics().lastRawFacText;
      debugPrint('[FAC] ⚠ pending_approvals null — keys: ${rpc.keys}');
      debugPrint('[FAC] ⚠ raw content preview: $rawPreview');
      FacDiagnostics()
        ..lastError    = 'No pending_approvals key in FAC response. '
            'Preview: ${rawPreview.isEmpty ? rpcStr.substring(0, rpcStr.length.clamp(0, 200)) : rawPreview}'
        ..facAvailable = false;
      return null;
    }
    debugPrint('[FAC] doctypes: ${paMap.keys.toList()}');
    FacDiagnostics()
      ..facAvailable    = true
      ..lastSuccessTime = DateTime.now();

    // Parse
    final result = <String, List<_Doc>>{};
    paMap.forEach((doctype, docsRaw) {
      if (docsRaw is! List) {
        debugPrint('[FAC] ⚠ $doctype not a List: ${docsRaw.runtimeType}');
        return;
      }
      final docs = docsRaw.map<_Doc?>((e) {
        if (e is! Map) return null;
        final raw = e.cast<String, dynamic>();
        final actRaw = raw['available_actions'];
        final acts = (actRaw is List)
            ? actRaw.map((a) => _Act(
                label:     (a['action']     ?? '').toString(),
                nextState: (a['next_state'] ?? '').toString(),
              )).where((a) => a.label.isNotEmpty).toList()
            : <_Act>[];
        return _Doc(
          name:     (raw['document_name']  ?? '').toString(),
          state:    (raw['workflow_state'] ?? '').toString(),
          creation: _shortDate((raw['creation'] ?? '').toString()),
          actions:  acts,
        );
      }).whereType<_Doc>().where((d) => d.name.isNotEmpty).toList();

      if (docs.isNotEmpty) result[doctype.toString()] = docs;
    });

    debugPrint('[FAC] parsed (before filter): ${result.map((k,v)=>MapEntry(k,v.length))}');

    // ── Server-side confirmation: only docstatus=0 (Draft) docs ──────────────
    // FAC may occasionally include submitted docs — batch-check removes them.
    final groups  = result.map((dt, docs) => MapEntry(dt, docs.map((d) => d.name).toList()));
    final allowed = await _batchCheckDocstatus(groups, 0);
    final filtered = <String, List<_Doc>>{};
    result.forEach((dt, docs) {
      final ok = docs.where((d) => (allowed[dt] ?? {}).contains(d.name)).toList();
      if (ok.isNotEmpty) filtered[dt] = ok;
    });
    debugPrint('[FAC] after docstatus=0 filter: ${filtered.map((k,v)=>MapEntry(k,v.length))}');
    return filtered;
  }

  // ── Fallback ──────────────────────────────────────────────────────────────

  Future<Map<String, List<_Doc>>> _fetchFallback() async {
    final uid = await ApiService.getLoggedUserId();
    debugPrint('[Pending] fallback userId=$uid');

    final res = await ApiService.postForm(
      '/api/method/frappe.client.get_list',
      {
        'doctype': 'Workflow Action',
        'fields': jsonEncode(['name','reference_doctype','reference_name',
            'workflow_state','status','creation']),
        'filters': jsonEncode([
          ['status', '=', 'Open'],
          ['user',   '=', uid],
        ]),
        'limit_page_length': '100',
      },
    );

    final list    = res['message'] as List? ?? [];
    debugPrint('[Pending] fallback raw count: ${list.length}');
    final grouped = <String, List<_Doc>>{};
    for (final item in list) {
      final dt = (item['reference_doctype'] ?? '').toString();
      final dn = (item['reference_name']    ?? '').toString();
      if (dt.isEmpty || dn.isEmpty) continue;
      grouped.putIfAbsent(dt, () => []).add(_Doc(
        name:     dn,
        state:    (item['workflow_state'] ?? '').toString(),
        creation: _shortDate((item['creation'] ?? '').toString()),
        actions:  [],
      ));
    }

    // Confirm docstatus=0 for reference docs (Workflow Action is Open but doc may be submitted)
    final groups   = grouped.map((dt, docs) => MapEntry(dt, docs.map((d) => d.name).toList()));
    final allowed  = await _batchCheckDocstatus(groups, 0);
    final filtered = <String, List<_Doc>>{};
    grouped.forEach((dt, docs) {
      final ok = docs.where((d) => (allowed[dt] ?? {}).contains(d.name)).toList();
      if (ok.isNotEmpty) filtered[dt] = ok;
    });
    debugPrint('[Pending] fallback after docstatus=0 filter: ${filtered.map((k,v)=>MapEntry(k,v.length))}');
    return filtered;
  }

  // ── Execute action ────────────────────────────────────────────────────────

  Future<void> _executeAction(String dt, String dn, _Act act) async {
    final c = AppColors.of(context);
    final l = AppLocalizations.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l.wfLocalizeAction(act.label),
            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dn,  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(dt,  style: TextStyle(color: c.textSecondary, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel, style: TextStyle(color: c.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _clr(act.label),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.wfLocalizeAction(act.label),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final sm = ScaffoldMessenger.of(context);
    sm.showSnackBar(SnackBar(
      content: Text(l.wfExecutingMsg(l.wfLocalizeAction(act.label))),
      duration: const Duration(seconds: 60)));

    try {
      final isCancelLike = _isCancelAction(act.label);

      debugPrint('[Pending Cancel] Action Triggered: ${act.label}  isCancelLike=$isCancelLike');
      debugPrint('[Pending Cancel] Doctype: $dt  Name: $dn');

      bool done = false;

      // ── CASE 1: FAC run_workflow (handles all workflow actions) ────────────
      // FAC expects 'name' (not 'docname') — confirmed from audit log error.
      try {
        final ep = await _facEp();
        try {
          await _mcpPost(ep, 'initialize', {
            'protocolVersion': '2024-11-05',
            'capabilities': {},
            'clientInfo': {'name': 'kcsc_pending', 'version': '1.0'},
          });
        } catch (_) {}
        final rpcResult = await _mcpPost(ep, 'tools/call', {
          'name': 'run_workflow',
          'arguments': {
            'doctype': dt,
            'name':    dn,
            'action':  act.label,
          },
        });
        final resultNode = rpcResult['result'];
        if (resultNode is Map && resultNode['isError'] == true) {
          final text = (resultNode['content'] as List?)?.firstOrNull?['text']?.toString() ?? '';
          throw Exception('FAC run_workflow error: $text');
        }
        done = true;
        debugPrint('[Pending Cancel] Using run_workflow: true');
        debugPrint('[FAC] run_workflow ✓ $dn → ${act.label}');
      } catch (e) {
        debugPrint('[FAC] run_workflow failed: $e — trying fallback');
      }

      // ── Fallback when run_workflow failed ──────────────────────────────────
      if (!done) {
        // Fetch the full document to inspect state and available transitions
        final docRes2 = await ApiService.get('/api/resource/$dt/$dn');
        final raw2    = docRes2 is Map ? (docRes2['data'] ?? docRes2) : {};
        final docMap2 = Map<String, dynamic>.from(raw2 as Map);
        final oldDocstatus = (docMap2['docstatus'] as num?)?.toInt() ?? 0;

        debugPrint('[Pending Cancel] Docstatus Before: $oldDocstatus');

        if (isCancelLike) {
          // Discover whether a workflow cancel/reject transition is available
          final transitions  = await WorkflowService().getTransitions(docMap2);
          final hasCancelT   = transitions.any((t) => _isCancelAction(t.action));
          debugPrint('[Pending Cancel] Workflow Cancel Exists: $hasCancelT');
          debugPrint('[Pending Cancel] Available transitions: '
              '${transitions.map((t) => t.action).toList()}');

          if (hasCancelT) {
            // Workflow provides a cancel transition → safeApplyWorkflow
            debugPrint('[Pending Cancel] Using run_workflow: false → safeApplyWorkflow');
            await WorkflowService().safeApplyWorkflow(docMap2, act.label);
            done = true;
          } else if (oldDocstatus == 1) {
            // CASE 2: no workflow cancel transition, doc is submitted → direct ERPNext cancel
            debugPrint('[Pending Cancel] Using ERPNext Cancel API');

            bool hasCancelPermission = false;
            try {
              final permRes = await ApiService.get(
                '/api/method/frappe.client.has_permission'
                '?doctype=${Uri.encodeComponent(dt)}'
                '&docname=${Uri.encodeComponent(dn)}'
                '&ptype=cancel',
              );
              final msg = permRes['message'];
              hasCancelPermission = msg == 1 || msg == true || msg == '1';
            } catch (permErr) {
              debugPrint('[Pending Cancel] Permission check error: $permErr');
            }
            debugPrint('[Pending Cancel] Has Cancel Permission: $hasCancelPermission');
            if (!hasCancelPermission) {
              throw Exception('You do not have permission to cancel $dn.');
            }

            // frappe.client.cancel(doctype, name) — correct API signature
            debugPrint('[Pending Cancel] Payload → doctype=$dt  name=$dn');
            final cancelRes = await ApiService.postForm(
              '/api/method/frappe.client.cancel',
              {'doctype': dt, 'name': dn},
            );
            debugPrint('[Pending Cancel] API Response: $cancelRes');
            if (cancelRes['exc'] != null) {
              final srvMsg = cancelRes['_server_messages']?.toString() ?? '';
              final exc    = cancelRes['exc'].toString();
              debugPrint('[Pending Cancel] Server error: $exc');
              throw Exception(srvMsg.isNotEmpty ? srvMsg : exc);
            }
            done = true;
            debugPrint('[Pending Cancel] ✅ Direct cancel succeeded');
          } else {
            // docstatus=0 and no workflow cancel transition → safeApplyWorkflow anyway
            debugPrint('[Pending Cancel] No cancel transition, docstatus=0 → safeApplyWorkflow');
            await WorkflowService().safeApplyWorkflow(docMap2, act.label);
            done = true;
          }
        } else {
          // Non-cancel action → standard safeApplyWorkflow
          await WorkflowService().safeApplyWorkflow(docMap2, act.label);
          debugPrint('[WF] safeApplyWorkflow ✓ $dn → ${act.label}');
          done = true;
        }
      }

      // ── NEVER call submit_document here ────────────────────────────────────
      // Submission (docstatus 0→1) is the ERPNext workflow engine's responsibility.
      // Calling submitDocument() after every workflow action causes reverse
      // transitions (e.g. Review→Pending) to incorrectly produce docstatus=1.

      // ── Fetch authoritative server state after action ──────────────────────
      int    newDocstatus = 0;
      String newWfState   = act.nextState;
      try {
        final docRes = await ApiService.get(
          '/api/resource/${Uri.encodeComponent(dt)}/${Uri.encodeComponent(dn)}'
          '?fields=${Uri.encodeComponent('["docstatus","workflow_state","name"]')}',
        );
        final docData = docRes is Map ? Map<String, dynamic>.from(
            (docRes['data'] ?? docRes) as Map) : <String, dynamic>{};
        newDocstatus = (docData['docstatus'] as num?)?.toInt() ?? 0;
        newWfState   = docData['workflow_state']?.toString() ?? act.nextState;

        debugPrint('[WF] ─────────────────────────────');
        debugPrint('[WF] Action         : ${act.label}');
        debugPrint('[WF] Document       : $dt / $dn');
        debugPrint('[WF] After  docstatus: $newDocstatus');
        debugPrint('[WF] After  state   : $newWfState');
        debugPrint('[Pending Cancel] Docstatus After: $newDocstatus');
        debugPrint('[Pending Cancel] Workflow State After: $newWfState');
        debugPrint('[WF] ─────────────────────────────');
      } catch (e) {
        debugPrint('[WF] Could not reload doc after action: $e');
      }

      // ── Page movement logic based on ACTUAL server docstatus ──────────────
      if (!mounted) return;
      sm.hideCurrentSnackBar();

      if (newDocstatus == 1) {
        debugPrint('[WF] docstatus=1 → moving $dn from Pending → Approved');
        sm.showSnackBar(SnackBar(
          content: Text(l.wfActionDoneMsg(l.wfLocalizeAction(act.label), dn, newWfState)),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 3),
        ));
        _removeDoc(dt, dn);
        RealtimeWorkflowService().broadcastLocal({
          'reference_doctype': dt,
          'reference_name':    dn,
          'action':            act.label,
          'new_state':         newWfState,
          'docstatus':         1,
        });
      } else if (newDocstatus == 2) {
        // Cancelled → remove from Pending AND notify Approved page to remove it too
        debugPrint('[WF] docstatus=2 → $dn cancelled, removing from Pending + Approved');
        sm.showSnackBar(SnackBar(
          content: Text(l.wfActionCancelledMsg(l.wfLocalizeAction(act.label), dn)),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 3),
        ));
        _removeDoc(dt, dn);
        RealtimeWorkflowService().broadcastLocal({
          'reference_doctype': dt,
          'reference_name':    dn,
          'action':            act.label,
          'new_state':         newWfState,
          'docstatus':         2,
        });
      } else {
        // docstatus=0 → draft state (reverse/reject action) — reload to confirm
        debugPrint('[WF] docstatus=0 → $dn stays in Draft/Pending pool. Reloading…');
        sm.showSnackBar(SnackBar(
          content: Text(l.wfActionDoneMsg(l.wfLocalizeAction(act.label), dn, newWfState)),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 3),
        ));
        _removeDoc(dt, dn);
        RealtimeWorkflowService().broadcastLocal({
          'reference_doctype': dt,
          'reference_name':    dn,
          'action':            act.label,
          'new_state':         newWfState,
          'docstatus':         0,
        });
      }

      _mcpSeq = 0;
      _busy   = false;
      _load(silent: true);
    } catch (e) {
      debugPrint('[Pending] executeAction error: $e');
      if (mounted) {
        sm.hideCurrentSnackBar();
        sm.showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 6),
        ));
      }
    }
  }

  Future<void> _openDoc(String dt, String dn) async {
    await Navigator.pushNamed(
      context, '/document-viewer',
      arguments: {'doctype': dt, 'docname': dn},
    );
    if (!mounted) return;
    // Check docstatus after returning — if no longer Draft (0), remove immediately
    _removeIfActioned(dt, dn);
    _mcpSeq = 0;
    _busy = false;
    _load(silent: true);
  }

  /// Checks docstatus for [dt]/[dn] and removes it from the list if no longer Draft.
  /// Called after returning from DocumentViewerPage to catch actions taken there.
  Future<void> _removeIfActioned(String dt, String dn) async {
    try {
      final res = await ApiService.get('/api/resource/$dt/$dn?fields=["docstatus","workflow_state"]');
      final data = res is Map ? (res['data'] ?? res) : {};
      final docstatus = (data['docstatus'] as num?)?.toInt() ?? 0;
      // docstatus 0 = Draft, 1 = Submitted, 2 = Cancelled
      if (docstatus != 0 && mounted) {
        debugPrint('[Pending] $dn docstatus=$docstatus → removing from list');
        _removeDoc(dt, dn);
      }
    } catch (_) {
      // Ignore — background reload will sync
    }
  }

  /// Removes a single document with a fade-out micro-interaction.
  void _removeDoc(String dt, String dn) {
    if (!mounted) return;
    setState(() => _dismissing.add(dn));
    Future.delayed(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      setState(() {
        _dismissing.remove(dn);
        final docs = _data[dt];
        if (docs == null) return;
        final remaining = docs.where((d) => d.name != dn).toList();
        if (remaining.isEmpty) {
          _data.remove(dt);
        } else {
          _data[dt] = remaining;
        }
      });
      debugPrint('[Pending] removed $dt/$dn from UI');
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _shortDate(String s) => s.length >= 10 ? s.substring(0, 10) : s;

  static Color _clr(String action) {
    final a = action.toLowerCase();
    if (a.contains('approv') || a.contains('accept') || a.contains('submit') ||
        a.contains('confirm') || a.contains('موافق') || a.contains('قبول')) {
      return AppColors.success;
    }
    if (a.contains('reject') || a.contains('cancel') || a.contains('deny') ||
        a.contains('رفض') || a.contains('رد')) {
      return AppColors.error;
    }
    return AppColors.warning;
  }

  static bool _isCancelAction(String action) {
    final a = action.toLowerCase();
    return ['cancel', 'reject', 'deny', 'refuse', 'إلغاء', 'رفض', 'reverse']
        .any((k) => a.contains(k));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l = AppLocalizations.of(context);
    debugPrint('[Pending] build() — total=$_total, loading=$_loading, display=${_display.length} groups');

    return Stack(
      children: [
        // Solid base so blobs have a background to float on
        ColoredBox(color: c.background, child: const SizedBox.expand()),
        // Animated aurora blobs (full-screen, behind Scaffold)
        Positioned.fill(child: AuroraBackground(child: const SizedBox.shrink())),
        // Transparent Scaffold so blobs show through
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: _appBar(c, l),
          body: SafeArea(
            child: Column(
              children: [
                _searchBar(c, l),
                _filterRow(c, l),
                if (_isFallback) _fallbackBanner(c),
                Expanded(child: _body(c, l)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _appBar(AppColors c, AppLocalizations l) {
    final titleWidget = Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Text(l.wfPendingApprovals,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  letterSpacing: 0.2,
                ),
                overflow: TextOverflow.ellipsis),
            if (_total > 0) ...[
              const SizedBox(width: 8),
              _Badge(n: _total),
            ],
          ]),
          if (_total > 0)
            Text(
              l.isArabic ? '$_total بند في الانتظار' : '$_total pending',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
        ],
      ),
    );

    final actions = <Widget>[
      if (_refreshing)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
      else
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          tooltip: null,
          onPressed: _manualRefresh,
        ),
      IconButton(
        icon: Icon(Icons.bug_report_outlined,
            color: Colors.white.withValues(alpha: 0.65), size: 20),
        tooltip: 'FAC Diagnostics',
        onPressed: _showDebugPanel,
      ),
      const SizedBox(width: 4),
    ];

    return _SheenAppBar(titleWidget: titleWidget, actions: actions);
  }

  // ── Debug Panel ───────────────────────────────────────────────────────────

  void _showDebugPanel() {
    final diag = FacDiagnostics().toMap();
    final c    = AppColors.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        builder: (ctx, scroll) => Column(children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: c.surfaceHigh, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(children: [
              Icon(Icons.bug_report_outlined, color: c.primary, size: 20),
              const SizedBox(width: 8),
              Text('FAC Diagnostics',
                  style: TextStyle(color: c.textPrimary,
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              TextButton(
                onPressed: () { FacDiagnostics().resetSession(); Navigator.pop(ctx); },
                child: Text('Reset', style: TextStyle(color: c.primary, fontSize: 13)),
              ),
            ]),
          ),
          Divider(height: 1, color: c.surfaceHigh),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              children: diag.entries.map((e) {
                final val = e.value;
                final valStr = val is List
                    ? (val.isEmpty ? '—' : val.join(', '))
                    : val.toString();
                final isAlert = (e.key.contains('denied') || e.key.contains('skipped') ||
                    e.key.contains('hidden') || e.key.contains('filtered')) &&
                    val != '—' && val.toString() != '[]' && val.toString() != '0';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 140,
                        child: Text(e.key,
                            style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                      ),
                      Expanded(
                        child: Text(valStr,
                            style: TextStyle(
                                color: isAlert ? AppColors.warning : c.textPrimary,
                                fontSize: 12,
                                fontWeight: isAlert ? FontWeight.bold : FontWeight.normal)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Search bar ────────────────────────────────────────────────────────────

  Widget _searchBar(AppColors c, AppLocalizations l) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
    child: TextField(
      controller: _searchCtrl,
      style: TextStyle(color: c.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText:  l.wfSearchHint,
        hintStyle: TextStyle(color: c.textSecondary, fontSize: 14),
        prefixIcon: Icon(Icons.search_rounded, color: c.textSecondary, size: 20),
        suffixIcon: _search.isNotEmpty
            ? IconButton(
                icon: Icon(Icons.clear_rounded, color: c.textSecondary, size: 18),
                onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); },
              )
            : null,
        filled:     true,
        fillColor:  c.surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.surfaceHigh, width: 1)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.primary, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onChanged: (v) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 300),
            () { if (mounted) setState(() => _search = v.trim()); });
      },
    ),
  );

  // ── Filter chips (always visible) ─────────────────────────────────────────

  Widget _filterRow(AppColors c, AppLocalizations l) => SizedBox(
    height: 44,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      children: [
        _Chip(
          label: l.wfAllTypes, selected: _filterDoctype.isEmpty,
          color: c.primary, onColor: c.onPrimary,
          onTap: () => setState(() => _filterDoctype = ''),
        ),
        ..._data.keys.map((dt) => _Chip(
          label: dt, selected: _filterDoctype == dt,
          color: c.primary, onColor: c.onPrimary,
          onTap: () => setState(() =>
              _filterDoctype = _filterDoctype == dt ? '' : dt),
        )),
      ],
    ),
  );

  // ── Fallback banner ───────────────────────────────────────────────────────

  Widget _fallbackBanner(AppColors c) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color:  AppColors.warning.withValues(alpha: 0.10),
      border: Border(
          bottom: BorderSide(color: AppColors.warning.withValues(alpha: 0.25))),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(Icons.info_outline_rounded, size: 15, color: AppColors.warning),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(AppLocalizations.of(context).wfFallbackMode,
                  style: TextStyle(color: AppColors.warning, fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
            GestureDetector(
              onTap: _showDebugPanel,
              child: Text(AppLocalizations.of(context).wfFallbackDetails,
                  style: TextStyle(color: AppColors.warning,
                      fontSize: 11, decoration: TextDecoration.underline)),
            ),
          ]),
          if (_facError.isNotEmpty)
            Text(_facError,
                style: TextStyle(color: AppColors.warning.withValues(alpha: 0.85),
                    fontSize: 11),
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
        ]),
      ),
    ]),
  );

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _body(AppColors c, AppLocalizations l) {
    if (_loading)      return _skeleton(c);
    if (_error.isNotEmpty) return _errState(c, l);

    final disp = _display;
    final total = disp.values.fold(0, (s, list) => s + list.length);
    debugPrint('[Pending] _body — groups=${disp.length} docs=$total');

    if (disp.isEmpty) return _emptyState(c, l);

    // Build flat item list: [header, card, card, …, spacer, header, …]
    final items = <_Item>[];
    disp.forEach((dt, docs) {
      items.add(_Item.header(dt, docs.length));
      for (final d in docs) { items.add(_Item.doc(dt, d)); }
      items.add(_Item.spacer());
    });

    // Pre-compute per-card index for staggered entry delays
    int docCounter = 0;
    final docIndices = <String, int>{};
    for (final item in items) {
      if (item.isDoc) docIndices[item.doc!.name] = docCounter++;
    }

    return RefreshIndicator(
      onRefresh: _manualRefresh,
      color: c.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final item = items[i];
          if (item.isHeader) {
            return _SectionHdr(
                doctype: item.doctype!, count: item.count!, c: c);
          }
          if (item.isDoc) {
            final isDismissing = _dismissing.contains(item.doc!.name);
            return AnimatedOpacity(
              key: ValueKey(item.doc!.name),
              opacity: isDismissing ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 260),
              child: AnimatedScale(
                scale: isDismissing ? 0.92 : 1.0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOut,
                child: _Card(
                  doc:       item.doc!,
                  c:         c,
                  cardIndex: docIndices[item.doc!.name] ?? 0,
                  onTap:     () => _openDoc(item.doctype!, item.doc!.name),
                  onAct:     (a) => _executeAction(item.doctype!, item.doc!.name, a),
                  clrFn:     _clr,
                ),
              ),
            );
          }
          return const SizedBox(height: 12);
        },
      ),
    );
  }

  // ── Skeleton ──────────────────────────────────────────────────────────────

  Widget _skeleton(AppColors c) => ListView.builder(
    padding: const EdgeInsets.all(12),
    itemCount: 5,
    itemBuilder: (context, index) => _SkeletonCard(c: c),
  );

  // ── Error / Empty states ──────────────────────────────────────────────────

  Widget _errState(AppColors c, AppLocalizations l) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline_rounded, size: 56, color: AppColors.error),
        const SizedBox(height: 16),
        Text(_error, textAlign: TextAlign.center,
            style: TextStyle(color: c.textSecondary, fontSize: 13),
            maxLines: 6, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 20),
        _RefreshBtn(onPressed: _manualRefresh, c: c),
      ]),
    ),
  );

  Widget _emptyState(AppColors c, AppLocalizations l) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.check_circle_outline_rounded, size: 72,
          color: AppColors.success.withValues(alpha: 0.8)),
      const SizedBox(height: 16),
      Text(l.wfNoPendingApprovals,
          style: TextStyle(fontSize: 18, color: c.textSecondary,
              fontWeight: FontWeight.w500)),
      const SizedBox(height: 24),
      _RefreshBtn(onPressed: _manualRefresh, c: c),
    ]),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Internal item model — flat list builder
// ═════════════════════════════════════════════════════════════════════════════

class _Item {
  final bool    isHeader;
  final bool    isDoc;
  final String? doctype;
  final int?    count;
  final _Doc?   doc;

  const _Item._({
    required this.isHeader,
    required this.isDoc,
    this.doctype,
    this.count,
    this.doc,
  });

  factory _Item.header(String dt, int n) =>
      _Item._(isHeader: true,  isDoc: false, doctype: dt, count: n);
  factory _Item.doc(String dt, _Doc d) =>
      _Item._(isHeader: false, isDoc: true,  doctype: dt, doc: d);
  factory _Item.spacer() =>
      _Item._(isHeader: false, isDoc: false);
}

// ═════════════════════════════════════════════════════════════════════════════
// Sub-widgets
// ═════════════════════════════════════════════════════════════════════════════

// ── Count badge ───────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final int n;
  const _Badge({required this.n});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.warning, borderRadius: BorderRadius.circular(20)),
    child: Text('$n',
        style: const TextStyle(color: Colors.white, fontSize: 12,
            fontWeight: FontWeight.bold)),
  );
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHdr extends StatelessWidget {
  final String doctype;
  final int    count;
  final AppColors c;
  const _SectionHdr({required this.doctype, required this.count, required this.c});

  @override
  Widget build(BuildContext context) => Container(
    width:   double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    margin:  const EdgeInsets.only(bottom: 10, top: 4),
    decoration: BoxDecoration(
      gradient: AppGradients.auroraGradient(Theme.of(context).brightness),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(children: [
      Expanded(
        child: Text(doctype,
            style: TextStyle(color: c.onPrimary,
                fontWeight: FontWeight.bold, fontSize: 15)),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: c.onPrimary.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('$count',
            style: TextStyle(color: c.onPrimary,
                fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    ]),
  );
}

// ── Approval card ─────────────────────────────────────────────────────────────

class _Card extends StatefulWidget {
  final _Doc    doc;
  final AppColors c;
  final int     cardIndex;
  final VoidCallback onTap;
  final void Function(_Act) onAct;
  final Color Function(String) clrFn;

  const _Card({
    required this.doc,
    required this.c,
    required this.cardIndex,
    required this.onTap,
    required this.onAct,
    required this.clrFn,
  });

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _fade;
  late final Animation<Offset>   _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    final delay = Duration(
        milliseconds: widget.cardIndex.clamp(0, 8) * 60);
    Future.delayed(delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doc   = widget.doc;
    final c     = widget.c;
    final clrFn = widget.clrFn;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: GlassCard(
            padding:      const EdgeInsets.all(16),
            borderRadius: 14,
            onTap:        widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Name + chevron
                Row(children: [
                  Expanded(
                    child: Text(doc.name,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                            color: c.textPrimary)),
                  ),
                  Icon(Icons.chevron_right_rounded, color: c.textSecondary, size: 20),
                ]),

                const SizedBox(height: 10),

                // State badge + date
                Row(children: [
                  _StateBadge(state: doc.state),
                  const Spacer(),
                  Icon(Icons.calendar_today_outlined, size: 12, color: c.textSecondary),
                  const SizedBox(width: 4),
                  Text(doc.creation,
                      style: TextStyle(color: c.textSecondary, fontSize: 12)),
                ]),

                // Action buttons
                if (doc.actions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Divider(height: 1, color: c.surfaceHigh),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8, runSpacing: 6,
                    children: doc.actions.map((a) => _ActBtn(
                      label: a.label,
                      color: clrFn(a.label),
                      onTap: () => widget.onAct(a),
                    )).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── State badge ───────────────────────────────────────────────────────────────

class _StateBadge extends StatelessWidget {
  final String state;
  const _StateBadge({required this.state});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color:  AppColors.warning.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
    ),
    child: Text(state,
        style: TextStyle(color: AppColors.warning,
            fontWeight: FontWeight.bold, fontSize: 12)),
  );
}

// ── Action button ─────────────────────────────────────────────────────────────

class _ActBtn extends StatefulWidget {
  final String label;
  final Color  color;
  final VoidCallback onTap;
  const _ActBtn({required this.label, required this.color, required this.onTap});

  @override
  State<_ActBtn> createState() => _ActBtnState();
}

class _ActBtnState extends State<_ActBtn> {
  bool _pressing = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown:   (_) => setState(() => _pressing = true),
    onTapUp:     (_) => setState(() => _pressing = false),
    onTapCancel: ()  => setState(() => _pressing = false),
    child: AnimatedScale(
      scale:    _pressing ? 0.92 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve:    _pressing ? Curves.easeIn : Curves.easeOutBack,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.color,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        onPressed: widget.onTap,
        child: Text(AppLocalizations.of(context).wfLocalizeAction(widget.label)),
      ),
    ),
  );
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final bool   selected;
  final Color  color;
  final Color  onColor;
  final VoidCallback onTap;
  const _Chip({
    required this.label, required this.selected,
    required this.color, required this.onColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color:        selected ? color : Colors.transparent,
          border:       Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
              color:      selected ? onColor : color,
              fontWeight: FontWeight.w600,
              fontSize:   13,
            )),
      ),
    ),
  );
}

// ── Refresh button ────────────────────────────────────────────────────────────

class _RefreshBtn extends StatelessWidget {
  final VoidCallback onPressed;
  final AppColors c;
  const _RefreshBtn({required this.onPressed, required this.c});

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
    style: ElevatedButton.styleFrom(
      backgroundColor: c.primary,
      foregroundColor: c.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    ),
    onPressed: onPressed,
    icon:  const Icon(Icons.refresh_rounded),
    label: Text(AppLocalizations.of(context).wfRefreshApprovals),
  );
}

// ── Skeleton card ─────────────────────────────────────────────────────────────

class _SkeletonCard extends StatefulWidget {
  final AppColors c;
  const _SkeletonCard({required this.c});

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Opacity(
        opacity: 0.35 + _anim.value * 0.45,
        child: Card(
          elevation: 1,
          color:  c.surface,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: c.surfaceHigh, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _box(c, double.infinity, 16),
              const SizedBox(height: 12),
              Row(children: [
                _box(c, 90, 24), const Spacer(), _box(c, 70, 14),
              ]),
              const SizedBox(height: 16),
              Row(children: [_box(c, 88, 32), const SizedBox(width: 8), _box(c, 88, 32)]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _box(AppColors c, double w, double h) => Container(
    width: w, height: h,
    decoration: BoxDecoration(
      color: c.surfaceHigh, borderRadius: BorderRadius.circular(6)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _SheenAppBar — Aurora gradient AppBar with periodic sheen sweep
// ─────────────────────────────────────────────────────────────────────────────

class _SheenAppBar extends StatefulWidget implements PreferredSizeWidget {
  final Widget        titleWidget;
  final List<Widget>  actions;

  const _SheenAppBar({
    required this.titleWidget,
    required this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<_SheenAppBar> createState() => _SheenAppBarState();
}

class _SheenAppBarState extends State<_SheenAppBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sheen;

  @override
  void initState() {
    super.initState();
    _sheen = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return AppBar(
      title:        widget.titleWidget,
      actions:      widget.actions,
      titleSpacing: 0,
      elevation:    3,
      shadowColor:  Colors.black.withValues(alpha: 0.25),
      backgroundColor:    Colors.transparent,
      foregroundColor:    Colors.white,
      iconTheme:          const IconThemeData(color: Colors.white),
      actionsIconTheme:   const IconThemeData(color: Colors.white),
      systemOverlayStyle: SystemUiOverlayStyle.light,
      flexibleSpace: ClipRect(
        child: AnimatedBuilder(
          animation: _sheen,
          builder: (ctx, _) {
            final screenW = MediaQuery.of(ctx).size.width;
            final sheenX  = (_sheen.value * 2.0 - 0.5) * screenW;
            return Stack(
              children: [
                // Base aurora gradient
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: AppGradients.auroraGradient(brightness),
                    ),
                  ),
                ),
                // Sweeping sheen stripe
                Positioned(
                  left:   sheenX - 60,
                  top:    -12,
                  bottom: -12,
                  width:  120,
                  child: Transform.rotate(
                    angle: -0.3,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.16),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
