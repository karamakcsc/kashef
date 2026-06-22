// ---------------------------------------------------------------------------
// fac_validator.dart — FAC / Frappe Permission Validation
//
// Centralises all permission checks that must happen BEFORE:
//   • Showing a document in the Pending Approvals list
//   • Rendering workflow action buttons in DocumentViewerPage
//   • Executing a workflow action (apply_workflow)
//
// Design decisions
// ──────────────────────────────────────────────────────────────────────────
// 1. frappe.model.workflow.get_transitions already validates:
//      - the user has the required ROLE for each transition
//      - any Python CONDITION on the transition is satisfied
//    So for workflow-related permission checks, get_transitions IS the
//    authoritative FAC/permission gate.  We call it and treat an empty
//    result as "no permission to act".
//
// 2. frappe.client.has_permission is used for basic READ checks — when we
//    want to confirm the user can at least see the document.
//
// 3. Results are NOT cached here; WorkflowRepository holds the cache.
// ---------------------------------------------------------------------------

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import 'api_service.dart';
import 'fac_mcp_service.dart' show FacDiagnostics;
import 'workflow_service.dart';

class FacValidator {
  static final FacValidator _instance = FacValidator._();
  factory FacValidator() => _instance;
  FacValidator._();

  // ── Basic read permission ──────────────────────────────────────────────────

  /// Returns true if the current user has READ permission on [doctype]/[docname].
  /// On any error (network, server 403, etc.) returns false — conservative default.
  Future<bool> hasReadPermission(String doctype, String docname) async {
    try {
      final result = await ApiService.get(
        '/api/method/frappe.client.has_permission'
        '?doctype=${Uri.encodeComponent(doctype)}'
        '&docname=${Uri.encodeComponent(docname)}'
        '&ptype=read',
      );
      final msg = result['message'];
      // Frappe returns 1 (int) or true (bool)
      return msg == 1 || msg == true || msg == '1';
    } catch (_) {
      return false;
    }
  }

  // ── Workflow transition validation ─────────────────────────────────────────

  /// Returns the list of transitions the current user is allowed to take on [doc].
  ///
  /// This is the primary FAC gate for workflow actions — Frappe evaluates:
  ///   • user roles vs. transition allowed roles
  ///   • any Python condition defined on the transition
  ///   • current document state matches transition.state
  ///
  /// Returns an empty list if the user may not perform any action.
  Future<List<WorkflowTransition>> getValidatedTransitions(
      Map<String, dynamic> doc) async {
    return WorkflowService().getTransitions(doc);
  }

  // ── Pre-execution validation ───────────────────────────────────────────────

  /// Validates that [action] is still a valid transition for [doc] at the
  /// moment of execution — guards against stale UI state or race conditions.
  ///
  /// Returns null on success.
  /// Returns a human-readable error string on failure.
  Future<String?> validateBeforeApply(
      Map<String, dynamic> doc, String action) async {
    try {
      final transitions = await getValidatedTransitions(doc);
      if (transitions.isEmpty) {
        FacDiagnostics().deniedActions.add(action);
        return 'No workflow actions are available for your role on this document.';
      }
      final match = transitions.any((t) => t.action == action);
      if (!match) {
        FacDiagnostics().deniedActions.add(action);
        return 'The action "$action" is no longer available. '
            'The document state may have changed. Please refresh.';
      }
      return null; // all good
    } catch (e) {
      return 'Permission check failed: $e';
    }
  }

  // ── DocType-level permission check (no docname needed) ────────────────────

  /// Checks if the current user can READ any document of [doctype].
  /// Used by WorkflowRepository to skip doctypes the user cannot access at all.
  /// Denied doctypes are logged in FacDiagnostics for the debug panel.
  Future<bool> canAccessDocType(String doctype) async {
    try {
      final result = await ApiService.postForm(
        '/api/method/frappe.client.get_list',
        {
          'doctype': doctype,
          'fields': jsonEncode(['name']),
          'limit_page_length': '1',
        },
      );
      final hasAccess = result['exc'] == null;
      if (!hasAccess) {
        FacDiagnostics().deniedDoctypes.add(doctype);
        debugPrint('[FacValidator] ⛔ Access denied to doctype: $doctype');
      }
      return hasAccess;
    } catch (_) {
      FacDiagnostics().deniedDoctypes.add(doctype);
      debugPrint('[FacValidator] ⛔ canAccessDocType error → denying: $doctype');
      return false;
    }
  }
}
