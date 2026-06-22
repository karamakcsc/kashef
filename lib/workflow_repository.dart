// ---------------------------------------------------------------------------
// workflow_repository.dart — Central data layer for Pending Approvals
//
// THREE data sources ordered by reliability and completeness:
//
//   SOURCE 0 — FAC "Get Pending Approvals" tool  (PRIMARY)
//     Calls the FAC MCP tool directly.  FAC already understands workflow
//     roles, conditions, and user permissions — it returns exactly what the
//     current user should see, matching ERPNext Desk behaviour.
//     Falls back silently if FAC is unavailable.
//     Cache: 30 s.
//
//   SOURCE A — Workflow Action records  (FALLBACK)
//     frappe.client.get_list("Workflow Action", [status=Open, user=me])
//     Fast, but misses Draft documents without a Workflow Action record.
//     Cache: 30 s.
//
//   SOURCE B — Dynamic DocType scan  (SUPPLEMENT)
//     For each active Workflow, scans the target DocType for non-terminal
//     workflow states, then calls get_transitions() to confirm the user can
//     act.  Catches Draft invoices and any doc missing from SOURCE 0 / A.
//     Performance: limited to _kDynPerDoctype docs per DocType, background.
//     Cache: 60 s.
//
// Merge strategy:
//   SOURCE 0 wins → SOURCE A fills gaps → SOURCE B supplements.
//   Deduplication by doctype::docname.  Sorted by creation desc.
// ---------------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import 'api_service.dart';
import 'fac_mcp_service.dart';
import 'fac_validator.dart';
import 'workflow_models.dart';
import 'workflow_service.dart';

const _kPageSize        = 20;
const _kSourceALimit    = 200;
const _kDynPerDoctype   = 30;
const _kCacheTtlA       = 30;   // seconds
const _kCacheTtlB       = 60;   // seconds
const _kCacheTtl0       = 30;   // seconds — FAC tool cache

/// Terminal workflow states — documents in these states are done; skip them.
const _kTerminalStates = {
  'approved', 'rejected', 'cancelled', 'closed', 'completed',
  'submitted', 'done', 'paid', 'delivered', 'fulfilled',
  'موافق عليه', 'مرفوض', 'ملغي', 'مكتمل', 'مدفوع',
};

bool _isTerminal(String state) =>
    _kTerminalStates.contains(state.toLowerCase().trim());

// ---------------------------------------------------------------------------

class WorkflowRepository {
  static final WorkflowRepository _instance = WorkflowRepository._();
  factory WorkflowRepository() => _instance;
  WorkflowRepository._();

  // ── SOURCE 0 cache (FAC tool) ─────────────────────────────────────────────
  List<PendingDoc>? _cache0;
  DateTime? _cache0Time;
  bool _facAvailable = true; // set false after first unavailable response

  // ── SOURCE A cache ─────────────────────────────────────────────────────────
  List<PendingDoc>? _cacheA;
  DateTime? _cacheATime;

  // ── SOURCE B cache ─────────────────────────────────────────────────────────
  List<PendingDoc>? _cacheB;
  DateTime? _cacheBTime;
  bool _scanInProgress = false;

  // ── Active workflow list cache (for SOURCE B) ─────────────────────────────
  List<WorkflowInfo>? _activeWorkflows;
  DateTime? _activeWorkflowsTime;

  // ── Cache validity helpers ─────────────────────────────────────────────────
  bool _facCacheValid() => _cache0 != null && _cache0Time != null &&
      DateTime.now().difference(_cache0Time!).inSeconds < _kCacheTtl0;

  bool _aValid() => _cacheA != null && _cacheATime != null &&
      DateTime.now().difference(_cacheATime!).inSeconds < _kCacheTtlA;

  bool _bValid() => _cacheB != null && _cacheBTime != null &&
      DateTime.now().difference(_cacheBTime!).inSeconds < _kCacheTtlB;

  bool _workflowsValid() => _activeWorkflows != null &&
      _activeWorkflowsTime != null &&
      DateTime.now().difference(_activeWorkflowsTime!).inSeconds < 300;

  // ── Invalidation ──────────────────────────────────────────────────────────

  /// Full invalidation — called after a workflow action or force-refresh.
  /// Also resets _facAvailable so FAC is retried after any previous failure.
  void invalidate() {
    _cache0 = null; _cache0Time = null;
    _cacheA = null; _cacheATime = null;
    _cacheB = null; _cacheBTime = null;
    _facAvailable = true; // allow FAC retry after error or name-mismatch fix
    debugPrint('🗑️  WorkflowRepo: full cache invalidated (FAC retry enabled)');
  }

  /// Light invalidation — only SOURCE 0 and A (for realtime poll events).
  void invalidateA() {
    _cache0 = null; _cache0Time = null;
    _cacheA = null; _cacheATime = null;
    _facAvailable = true; // allow FAC retry
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns a paginated slice of pending documents for [userId].
  Future<List<PendingDoc>> fetchPending({
    required String userId,
    bool forceRefresh = false,
    String filterDoctype = '',
    String searchQuery = '',
    int limitStart = 0,
    int pageSize = _kPageSize,
  }) async {
    if (forceRefresh) invalidate();

    // ── SOURCE 0: FAC tool (primary) ─────────────────────────────────────────
    if (_facAvailable && !_facCacheValid()) {
      debugPrint(
        '📥 WorkflowRepo: calling FAC tool '
        '"${FacMcpService.kToolPendingApprovals}"…',
      );
      // getPendingApprovals returns all docs for current user — filter client-side
      final facPending = await FacMcpService().getPendingApprovals();
      final facResult  = facPending?.allDocs
          .map((d) => d.toPendingDoc())
          .toList();
      if (facResult != null) {
        _cache0 = facResult;
        _cache0Time = DateTime.now();
        FacDiagnostics().source0Count = facResult.length;
        debugPrint(
          '✅ WorkflowRepo: SOURCE 0 (FAC) → ${facResult.length} docs',
        );
        for (final d in facResult) {
          debugPrint(
            '   FAC ✔ ${d.doctype}/${d.docname} — "${d.workflowState}"',
          );
        }
      } else {
        _facAvailable = false;
        FacDiagnostics().facAvailable = false;
        debugPrint(
          '⚠️ WorkflowRepo: SOURCE 0 (FAC) unavailable or tool not found. '
          'Falling back to SOURCE A + B. '
          'Check that "${FacMcpService.kToolPendingApprovals}" '
          'appears in tools/list.',
        );
      }
    } else if (!_facAvailable) {
      debugPrint(
        '⏭️  WorkflowRepo: SOURCE 0 (FAC) skipped — marked unavailable. '
        'Call invalidate() to retry.',
      );
    }

    // ── SOURCE A: Workflow Action records (fallback) ──────────────────────────
    if (!_aValid()) {
      debugPrint('📥 WorkflowRepo: fetching SOURCE A (Workflow Action)…');
      _cacheA = await _fetchSourceA(userId: userId);
      _cacheATime = DateTime.now();
      FacDiagnostics().sourceACount = _cacheA!.length;
      debugPrint('📥 WorkflowRepo: SOURCE A → ${_cacheA!.length} docs');
    }

    // ── SOURCE B: Dynamic scan (background supplement) ────────────────────────
    if (!_bValid() && !_scanInProgress) {
      _runSourceBInBackground(userId: userId);
    }

    // ── Merge ─────────────────────────────────────────────────────────────────
    final merged = _merge(
      _cache0 ?? [],
      _cacheA ?? [],
      _cacheB ?? [],
    );

    debugPrint(
      '📊 WorkflowRepo: merged total = ${merged.length} '
      '(FAC=${(_cache0 ?? []).length}, '
      'A=${(_cacheA ?? []).length}, '
      'B=${(_cacheB ?? []).length})',
    );

    // ── Filter ────────────────────────────────────────────────────────────────
    var filtered = filterDoctype.isEmpty
        ? merged
        : merged.where((d) => d.doctype == filterDoctype).toList();

    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      filtered = filtered
          .where((d) =>
              d.docname.toLowerCase().contains(q) ||
              d.doctype.toLowerCase().contains(q) ||
              d.workflowState.toLowerCase().contains(q))
          .toList();
    }

    // ── Paginate ──────────────────────────────────────────────────────────────
    if (limitStart >= filtered.length) return [];
    final end = (limitStart + pageSize).clamp(0, filtered.length);
    return filtered.sublist(limitStart, end);
  }

  /// Returns the total pending count from all sources — used for badges.
  Future<int> fetchCount(String userId) async {
    // Re-use cached data if valid; don't force a full fetch
    final merged = _merge(
      _cache0 ?? [],
      _cacheA ?? [],
      _cacheB ?? [],
    );
    if (merged.isNotEmpty) return merged.length;

    // Nothing cached → fetch SOURCE A at minimum
    _cacheA = await _fetchSourceA(userId: userId);
    _cacheATime = DateTime.now();
    return (_cache0 ?? []).length + (_cacheA ?? []).length;
  }

  /// Returns all unique DocTypes in the current merged list.
  List<String> uniqueDoctypes() {
    final merged = _merge(_cache0 ?? [], _cacheA ?? [], _cacheB ?? []);
    final seen = <String>{};
    return merged
        .map((d) => d.doctype)
        .where((dt) => dt.isNotEmpty && seen.add(dt))
        .toList();
  }

  // ── SOURCE A: Workflow Action records ─────────────────────────────────────

  Future<List<PendingDoc>> _fetchSourceA({required String userId}) async {
    try {
      final filters = [
        ['status', '=', 'Open'],
        ['user', '=', userId],
      ];
      const fields = [
        'name', 'reference_doctype', 'reference_name',
        'workflow_state', 'status', 'creation',
      ];

      final result = await ApiService.postForm(
        '/api/method/frappe.client.get_list',
        {
          'doctype': 'Workflow Action',
          'filters': jsonEncode(filters),
          'fields': jsonEncode(fields),
          'order_by': 'creation desc',
          'limit_page_length': '$_kSourceALimit',
        },
      );

      final raw = (result['message'] as List?) ?? [];
      final docs = raw
          .whereType<Map<String, dynamic>>()
          .map((e) => PendingDoc(
                doctype: e['reference_doctype']?.toString() ?? '',
                docname: e['reference_name']?.toString() ?? '',
                workflowState: e['workflow_state']?.toString() ?? '',
                creation: e['creation']?.toString() ?? '',
                source: WorkflowSource.workflowAction,
              ))
          .where((d) => d.doctype.isNotEmpty && d.docname.isNotEmpty)
          .toList();

      for (final d in docs) {
        debugPrint(
          '  SOURCE A: ${d.doctype} / ${d.docname} — state: "${d.workflowState}"',
        );
      }
      return docs;
    } catch (e) {
      debugPrint('❌ WorkflowRepo SOURCE A error: $e');
      return [];
    }
  }

  // ── SOURCE B: Dynamic DocType scan ────────────────────────────────────────

  void _runSourceBInBackground({required String userId}) {
    _scanInProgress = true;
    debugPrint('🔍 WorkflowRepo: starting SOURCE B background scan…');
    _fetchSourceB(userId: userId).then((docs) {
      _cacheB = docs;
      _cacheBTime = DateTime.now();
      _scanInProgress = false;
      FacDiagnostics().sourceBCount = docs.length;
      debugPrint(
        '🔍 WorkflowRepo: SOURCE B scan complete → ${docs.length} docs',
      );
    }).catchError((e) {
      debugPrint('❌ WorkflowRepo SOURCE B error: $e');
      _scanInProgress = false;
    });
  }

  Future<List<PendingDoc>> _fetchSourceB({required String userId}) async {
    final workflows = await _fetchActiveWorkflows();
    if (workflows.isEmpty) return [];

    final results = <PendingDoc>[];
    final fac = FacValidator();

    for (final wf in workflows) {
      try {
        final canAccess = await fac.canAccessDocType(wf.documentType);
        if (!canAccess) {
          FacDiagnostics().skippedDoctypes.add(wf.documentType);
          debugPrint(
            '  SOURCE B: skipping ${wf.documentType} — no read permission',
          );
          continue;
        }

        final docs = await _fetchNonTerminalDocs(wf);
        if (docs.isEmpty) continue;

        debugPrint(
          '  SOURCE B: scanning ${docs.length} docs in ${wf.documentType}…',
        );

        final futures = docs.map((doc) => _evalDoc(doc, wf));
        final evaluated = await Future.wait(futures);

        for (final pd in evaluated) {
          if (pd != null) {
            debugPrint(
              '  SOURCE B: ✔ ${pd.doctype}/${pd.docname} — state: "${pd.workflowState}"',
            );
            results.add(pd);
          }
        }
      } catch (e) {
        debugPrint(
          '  SOURCE B: error scanning ${wf.documentType}: $e — skipping',
        );
      }
    }

    return results;
  }

  Future<PendingDoc?> _evalDoc(
      Map<String, dynamic> doc, WorkflowInfo wf) async {
    try {
      final transitions = await WorkflowService().getTransitions(doc);
      if (transitions.isEmpty) {
        debugPrint(
          '  SOURCE B: ${doc['name']} — no transitions for current user',
        );
        return null;
      }

      final stateField = wf.workflowStateField;
      final state = doc[stateField]?.toString() ??
          doc['workflow_state']?.toString() ?? '';

      if (_isTerminal(state)) {
        debugPrint('  SOURCE B: ${doc['name']} — terminal state "$state" — skip');
        return null;
      }

      debugPrint(
        '  SOURCE B: ${doc['name']} — ${transitions.length} transitions available',
      );

      return PendingDoc(
        doctype: wf.documentType,
        docname: doc['name']?.toString() ?? '',
        workflowState: state,
        creation: doc['creation']?.toString() ?? '',
        source: WorkflowSource.dynamicScan,
      );
    } catch (e) {
      debugPrint('  SOURCE B: eval error for ${doc['name']}: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchNonTerminalDocs(
      WorkflowInfo wf) async {
    try {
      final stateField = wf.workflowStateField;
      final result = await ApiService.postForm(
        '/api/method/frappe.client.get_list',
        {
          'doctype': wf.documentType,
          'filters': jsonEncode([['docstatus', '!=', 2]]),
          'fields': jsonEncode(
              ['name', stateField, 'creation', 'docstatus', 'owner']),
          'order_by': 'creation desc',
          'limit_page_length': '$_kDynPerDoctype',
        },
      );

      final raw = (result['message'] as List?) ?? [];
      return raw.whereType<Map<String, dynamic>>().where((d) {
        final state = d[stateField]?.toString() ??
            d['workflow_state']?.toString() ?? '';
        return state.isNotEmpty && !_isTerminal(state);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Active workflows ───────────────────────────────────────────────────────

  Future<List<WorkflowInfo>> _fetchActiveWorkflows() async {
    if (_workflowsValid()) return _activeWorkflows!;
    try {
      final filters =
          jsonEncode([['is_active', '=', 1]]);
      final fields =
          jsonEncode(['name', 'document_type', 'workflow_state_field']);

      final result = await ApiService.get(
        '/api/resource/Workflow'
        '?filters=${Uri.encodeComponent(filters)}'
        '&fields=${Uri.encodeComponent(fields)}'
        '&limit=50',
      );

      final list = (result['data'] as List?) ?? [];
      _activeWorkflows = list
          .whereType<Map<String, dynamic>>()
          .map(WorkflowInfo.fromJson)
          .toList();
      _activeWorkflowsTime = DateTime.now();

      debugPrint(
        '📋 WorkflowRepo: ${_activeWorkflows!.length} active workflows: '
        '${_activeWorkflows!.map((w) => w.documentType).join(', ')}',
      );
      return _activeWorkflows!;
    } catch (e) {
      debugPrint('❌ WorkflowRepo: failed to fetch active workflows: $e');
      return [];
    }
  }

  // ── Merge + dedup ──────────────────────────────────────────────────────────

  /// Merges SOURCE 0, A, B — deduplicating by doctype::docname.
  /// Priority: SOURCE 0 > SOURCE A > SOURCE B.
  List<PendingDoc> _merge(
    List<PendingDoc> s0,
    List<PendingDoc> a,
    List<PendingDoc> b,
  ) {
    final map = <String, PendingDoc>{};
    for (final d in b) { map[d.key] = d; }   // lowest priority first
    for (final d in a) { map[d.key] = d; }
    for (final d in s0) { map[d.key] = d; }  // highest priority last

    final list = map.values.toList();
    list.sort((x, y) => y.creation.compareTo(x.creation));
    return list;
  }
}
