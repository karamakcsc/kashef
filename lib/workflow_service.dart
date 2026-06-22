import 'dart:convert';
import 'api_service.dart';
import 'fac_validator.dart';

// ---------------------------------------------------------------------------
// WorkflowInfo — metadata about an active Workflow on a DocType
// ---------------------------------------------------------------------------
class WorkflowInfo {
  final String name;
  final String documentType;

  // The field on the document that stores workflow state (usually 'workflow_state')
  final String workflowStateField;

  const WorkflowInfo({
    required this.name,
    required this.documentType,
    required this.workflowStateField,
  });

  factory WorkflowInfo.fromJson(Map<String, dynamic> j) => WorkflowInfo(
        name: j['name']?.toString() ?? '',
        documentType: j['document_type']?.toString() ?? '',
        workflowStateField:
            j['workflow_state_field']?.toString() ?? 'workflow_state',
      );
}

// ---------------------------------------------------------------------------
// WorkflowTransition — a single allowed transition for the current user
// ---------------------------------------------------------------------------
class WorkflowTransition {
  final String action;
  final String nextState;
  final String fromState;

  const WorkflowTransition({
    required this.action,
    required this.nextState,
    required this.fromState,
  });

  factory WorkflowTransition.fromJson(Map<String, dynamic> j) =>
      WorkflowTransition(
        action: j['action']?.toString() ?? '',
        nextState: j['next_state']?.toString() ?? '',
        fromState: j['state']?.toString() ?? '',
      );
}

// ---------------------------------------------------------------------------
// WorkflowService — singleton that wraps all workflow-related Frappe API calls.
//
// Frappe APIs used:
//   GET  /api/resource/Workflow          — check if a DocType has an active workflow
//   POST frappe.model.workflow.get_transitions  — transitions available for current user
//   POST frappe.model.workflow.apply_workflow   — execute a workflow action
//
// The workflow metadata (WorkflowInfo) is cached per DocType to avoid
// repeated API calls across the app session.
// ---------------------------------------------------------------------------
class WorkflowService {
  static final WorkflowService _instance = WorkflowService._();
  factory WorkflowService() => _instance;
  WorkflowService._();

  // doctype → WorkflowInfo (null = checked, no active workflow)
  final Map<String, WorkflowInfo?> _cache = {};

  // ── Check workflow ─────────────────────────────────────────────────────────

  /// Returns the active Workflow for [doctype], or null if none exists.
  /// Result is cached for the lifetime of the app session.
  Future<WorkflowInfo?> getWorkflowForDocType(String doctype) async {
    if (_cache.containsKey(doctype)) return _cache[doctype];

    try {
      final filters = jsonEncode([
        ['document_type', '=', doctype],
        ['is_active', '=', 1],
      ]);
      final fields =
          jsonEncode(['name', 'document_type', 'workflow_state_field']);

      final result = await ApiService.get(
        '/api/resource/Workflow'
        '?filters=${Uri.encodeComponent(filters)}'
        '&fields=${Uri.encodeComponent(fields)}'
        '&limit=1',
      );

      final list = (result['data'] as List?) ?? [];
      if (list.isEmpty) {
        _cache[doctype] = null;
        return null;
      }

      final wf = WorkflowInfo.fromJson(list[0] as Map<String, dynamic>);
      _cache[doctype] = wf;
      return wf;
    } catch (_) {
      _cache[doctype] = null;
      return null;
    }
  }

  // ── Get transitions ────────────────────────────────────────────────────────

  /// Returns the list of workflow transitions available to the current user
  /// given the document's current state.
  ///
  /// [doc] must be the full document map as returned by the Frappe REST API.
  Future<List<WorkflowTransition>> getTransitions(
      Map<String, dynamic> doc) async {
    try {
      final result = await ApiService.post(
        '/api/method/frappe.model.workflow.get_transitions',
        {'doc': jsonEncode(doc)},
      );

      final raw = result['message'];
      final list = raw is List ? raw : (result['data'] as List?);
      if (list == null) return [];

      return list
          .whereType<Map<String, dynamic>>()
          .map(WorkflowTransition.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Apply workflow action ──────────────────────────────────────────────────

  /// Executes [action] on [doc] and returns the updated document.
  ///
  /// Throws an [Exception] on failure so the caller can show a user-friendly
  /// error message.
  Future<Map<String, dynamic>> applyWorkflow(
    Map<String, dynamic> doc,
    String action,
  ) async {
    final result = await ApiService.post(
      '/api/method/frappe.model.workflow.apply_workflow',
      {'doc': jsonEncode(doc), 'action': action},
    );

    // Frappe returns the updated doc inside `message`
    final message = result['message'];
    if (message is Map<String, dynamic>) return message;

    // Fallback: some Frappe versions return doc at root
    if (result is Map<String, dynamic> &&
        (result.containsKey('doctype') || result.containsKey('name'))) {
      return result;
    }

    return result is Map<String, dynamic> ? result : {};
  }

  /// Safe variant — validates via FAC before executing.
  /// Prevents 417 EXPECTATION FAILED from stale transitions or missing roles.
  ///
  /// Returns the updated document on success.
  /// Throws [Exception] with a human-readable message on failure.
  Future<Map<String, dynamic>> safeApplyWorkflow(
    Map<String, dynamic> doc,
    String action,
  ) async {
    // Pre-execution FAC validation — catches stale state & role mismatches
    final err = await FacValidator().validateBeforeApply(doc, action);
    if (err != null) throw Exception(err);

    return applyWorkflow(doc, action);
  }

  // ── Cache helpers ──────────────────────────────────────────────────────────

  /// Invalidate the cached workflow info for a specific DocType.
  void invalidate(String doctype) => _cache.remove(doctype);

  /// Invalidate all cached workflow info (e.g. after login/logout).
  void invalidateAll() => _cache.clear();
}
