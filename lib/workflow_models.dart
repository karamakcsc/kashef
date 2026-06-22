// ---------------------------------------------------------------------------
// workflow_models.dart — Unified data models for the Workflow system
//
// PendingDoc is the single type used across the app to represent a document
// that is awaiting a workflow action from the current user.
// It can originate from two sources:
//   • WorkflowAction — the Frappe Workflow Action doctype (traditional inbox)
//   • DynamicScan    — discovered by scanning workflow-enabled doctypes directly
//
// Using both sources ensures that:
//   • Draft documents with an active workflow appear even if no Workflow Action
//     record has been created yet (e.g., first state after document creation).
//   • Submitted documents still waiting for a final approval step are included.
// ---------------------------------------------------------------------------

enum WorkflowSource {
  facTool,        // SOURCE 0 — returned directly by FAC "Get Pending Approvals" tool
  workflowAction, // SOURCE A — Workflow Action record exists
  dynamicScan,    // SOURCE B — found by scanning the doctype directly
}

class PendingDoc {
  final String doctype;
  final String docname;
  final String workflowState;
  final String creation;
  final WorkflowSource source;

  const PendingDoc({
    required this.doctype,
    required this.docname,
    required this.workflowState,
    required this.creation,
    required this.source,
  });

  /// Unique key for deduplication (same doc should not appear twice).
  String get key => '$doctype::$docname';

  /// Creation date formatted as YYYY-MM-DD for display.
  String get creationShort =>
      creation.length >= 10 ? creation.substring(0, 10) : creation;

  @override
  bool operator ==(Object other) => other is PendingDoc && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
