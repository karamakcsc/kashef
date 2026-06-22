import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_service.dart';
import 'app_colors.dart';
import 'app_localizations.dart';
import 'fac_mcp_service.dart';
import 'realtime_workflow_service.dart';
import 'workflow_service.dart';

// ---------------------------------------------------------------------------
// DocumentViewerPage
//
// A read-only view of any Frappe document with dynamic Workflow support.
//
// Behaviour mirrors ERPNext Desk:
//   • If the DocType has NO active Workflow → shows Save / Submit / Cancel
//     (current docstatus-based actions).
//   • If the DocType HAS an active Workflow → hides the docstatus buttons
//     and shows only the transitions that the current user may take.
//
// Entry points:
//   • AI Assistant  — via <open_document doctype="X" docname="Y"/> tag
//   • App Drawer    — "Pending Approvals" page taps each item
//   • Report rows   — tap on a row whose first column is a document name
// ---------------------------------------------------------------------------

class DocumentViewerPage extends StatefulWidget {
  final String doctype;
  final String docname;

  const DocumentViewerPage({
    super.key,
    required this.doctype,
    required this.docname,
  });

  @override
  State<DocumentViewerPage> createState() => _DocumentViewerPageState();
}

// ─────────────────────────────────────────────────────────────────────────────

enum _Phase { loading, loaded, error }

class _DocumentViewerPageState extends State<DocumentViewerPage> {
  _Phase _phase = _Phase.loading;
  String _errorMsg = '';
  bool _actionLoading = false;

  Map<String, dynamic> _doc = {};
  WorkflowInfo? _workflow;
  List<WorkflowTransition> _transitions = [];

  final _ws = WorkflowService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Data loading ─────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _phase = _Phase.loading;
      _errorMsg = '';
    });

    try {
      // 1. Fetch the document
      final docResult = await ApiService.get(
        '/api/resource/${Uri.encodeComponent(widget.doctype)}/${Uri.encodeComponent(widget.docname)}',
      );
      final doc = (docResult['data'] as Map<String, dynamic>?) ??
          (docResult as Map<String, dynamic>);

      // 2. Check for active workflow (cached)
      final wf = await _ws.getWorkflowForDocType(widget.doctype);

      // 3. If workflow exists, fetch available transitions
      List<WorkflowTransition> transitions = [];
      if (wf != null) {
        transitions = await _ws.getTransitions(doc);
      }

      if (mounted) {
        setState(() {
          _doc = doc;
          _workflow = wf;
          _transitions = transitions;
          _phase = _Phase.loaded;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _errorMsg = e.toString();
        });
      }
    }
  }

  // ── Execute workflow action ───────────────────────────────────────────────

  Future<void> _executeAction(String action) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.of(ctx).surface,
        title: Text(action,
            style: TextStyle(color: AppColors.of(ctx).textPrimary)),
        content: Text(
          l.wfConfirmAction(action, widget.docname),
          style: TextStyle(color: AppColors.of(ctx).textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _actionColor(action),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _actionLoading = true);

    try {
      // Try FAC run_workflow first (respects FAC permissions + workflow roles)
      // Fall back to safeApplyWorkflow (Frappe native API with pre-validation)
      Map<String, dynamic> updatedDoc;
      final facResult =
          await FacMcpService().runWorkflow(_doc, action);
      if (facResult != null && facResult.isNotEmpty) {
        debugPrint('✅ DocumentViewer: workflow executed via FAC');
        updatedDoc = facResult;
      } else {
        debugPrint(
          '⚠️ DocumentViewer: FAC run_workflow unavailable — '
          'falling back to safeApplyWorkflow',
        );
        updatedDoc = await _ws.safeApplyWorkflow(_doc, action);
      }

      // Reload with updated data + transitions
      final refreshedTransitions = await _ws.getTransitions(updatedDoc);

      if (mounted) {
        setState(() {
          _doc = updatedDoc.isNotEmpty ? updatedDoc : _doc;
          _transitions = refreshedTransitions;
          _actionLoading = false;
        });
        final newState = _currentState();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.wfActionSuccess(action, newState)),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 3),
          ),
        );
        // Notify PendingApprovalsPage + Drawer badge immediately
        RealtimeWorkflowService().broadcastLocal({
          'reference_doctype': widget.doctype,
          'reference_name': widget.docname,
          'new_state': newState,
          'action': action,
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _actionLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.wfActionFailed(e.toString())),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _currentState() {
    final field = _workflow?.workflowStateField ?? 'workflow_state';
    return _doc[field]?.toString() ??
        _doc['status']?.toString() ??
        _doc['docstatus']?.toString() ??
        '';
  }

  int _docstatus() {
    final ds = _doc['docstatus'];
    if (ds is int) return ds;
    if (ds is String) return int.tryParse(ds) ?? 0;
    return 0;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.doctype, style: const TextStyle(fontSize: 15)),
            Text(
              widget.docname,
              style: TextStyle(
                  fontSize: 11,
                  color: c.onPrimary.withValues(alpha: 0.7)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l.refresh,
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(c, l)),
    );
  }

  Widget _buildBody(AppColors c, AppLocalizations l) {
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: CircularProgressIndicator());

      case _Phase.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded,
                    color: AppColors.error, size: 48),
                const SizedBox(height: 12),
                Text(
                  _errorMsg,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 20),
                ElevatedButton(onPressed: _load, child: Text(l.retry)),
              ],
            ),
          ),
        );

      case _Phase.loaded:
        return _buildLoaded(c, l);
    }
  }

  Widget _buildLoaded(AppColors c, AppLocalizations l) {
    final fields = _smartFields();
    final state = _currentState();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Document header ──────────────────────────────────────────
              _DocHeader(
                doctype: widget.doctype,
                docname: widget.docname,
                state: state,
                workflow: _workflow,
                docstatus: _docstatus(),
                c: c,
                l: l,
              ),

              const SizedBox(height: 16),

              // ── Field grid ────────────────────────────────────────────────
              if (fields.isNotEmpty) ...[
                _SectionLabel(l.wfDocumentDetails, c),
                const SizedBox(height: 8),
                _FieldGrid(fields: fields, c: c),
                const SizedBox(height: 24),
              ],

              // ── Workflow info (if active) ─────────────────────────────────
              if (_workflow != null) ...[
                _SectionLabel(l.wfWorkflowState, c),
                const SizedBox(height: 8),
                _WorkflowStateBadge(
                  state: state,
                  workflowName: _workflow!.name,
                  c: c,
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),

        // ── Action buttons ────────────────────────────────────────────────
        _ActionBar(
          workflow: _workflow,
          transitions: _transitions,
          docstatus: _docstatus(),
          loading: _actionLoading,
          c: c,
          l: l,
          onAction: _executeAction,
          onSave: _handleSave,
          onSubmit: _handleSubmit,
          onCancel: _handleCancel,
        ),
      ],
    );
  }

  // ── Docstatus actions (only when no workflow) ─────────────────────────────

  Future<void> _handleSave() async {
    // For read-only view, Save is a no-op (fields are not editable)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).wfNoEditInViewer),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.of(ctx).surface,
        title: Text(l.wfSubmitDoc,
            style: TextStyle(color: AppColors.of(ctx).textPrimary)),
        content: Text(l.wfSubmitConfirm(widget.docname),
            style: TextStyle(color: AppColors.of(ctx).textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.wfSubmitDoc),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _actionLoading = true);
    try {
      // Use FAC submit_document (respects permissions + audit log)
      // Falls back to frappe.client.submit if FAC tool is unavailable
      final doctype = widget.doctype;
      final name    = widget.docname;
      bool submitted = false;

      try {
        final result = await FacMcpService().submitDocument(doctype, name);
        if (result != null) {
          submitted = true;
          debugPrint('✅ DocumentViewer: submitted via FAC submit_document');
        }
      } catch (facErr) {
        debugPrint('⚠️ DocumentViewer: FAC submit_document failed → $facErr');
        // Re-throw if it's a permission/validation error (don't silently skip)
        final msg = facErr.toString().toLowerCase();
        if (msg.contains('permission') || msg.contains('validation') ||
            msg.contains('not allowed') || msg.contains('cannot submit')) {
          rethrow;
        }
      }

      if (!submitted) {
        // Fallback: frappe.client.submit
        debugPrint('ℹ️ DocumentViewer: falling back to frappe.client.submit');
        await ApiService.post(
          '/api/method/frappe.client.submit',
          {'doc': jsonEncode(_doc)},
        );
      }

      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _actionLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(l.wfActionFailed(e.toString())),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _handleCancel() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.of(ctx).surface,
        title: Text(l.wfCancelDoc,
            style: TextStyle(color: AppColors.of(ctx).textPrimary)),
        content: Text(l.wfCancelConfirm(widget.docname),
            style: TextStyle(color: AppColors.of(ctx).textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.wfCancelDoc),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _actionLoading = true);
    try {
      await ApiService.post(
        '/api/method/frappe.client.cancel',
        {'doctype': widget.doctype, 'name': widget.docname},
      );
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _actionLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(l.wfActionFailed(e.toString())),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  // ── Smart field selection ─────────────────────────────────────────────────

  // System / internal fields to always skip
  static const _skipFields = {
    'name', 'owner', 'creation', 'modified', 'modified_by',
    'doctype', 'docstatus', 'idx', 'amended_from',
    '__islocal', '__unsaved', '__onload', '__run_link_triggers',
    '_liked_by', '_user_tags', '_comments', '_assign', '_seen',
    'workflow_state', 'naming_series',
  };

  // Priority fields to show first when present
  static const _priorityFields = [
    'title', 'subject', 'description', 'employee_name', 'full_name',
    'customer_name', 'supplier_name', 'item_name',
    'status', 'priority', 'date', 'posting_date', 'transaction_date',
    'from_date', 'to_date', 'start_date', 'end_date',
    'leave_type', 'leave_balance', 'total_leave_days',
    'department', 'company', 'employee', 'approver',
    'grand_total', 'net_total', 'total',
  ];

  List<MapEntry<String, dynamic>> _smartFields() {
    final allEntries = _doc.entries
        .where((e) =>
            !_skipFields.contains(e.key) &&
            !e.key.startsWith('_') &&
            !e.key.startsWith('__') &&
            e.value != null &&
            e.value.toString().isNotEmpty &&
            e.value.toString() != '0')
        .toList();

    // Separate priority fields from rest
    final priority = <MapEntry<String, dynamic>>[];
    final rest = <MapEntry<String, dynamic>>[];

    for (final e in allEntries) {
      if (_priorityFields.contains(e.key)) {
        priority.add(e);
      } else {
        rest.add(e);
      }
    }

    // Sort priority by their order in _priorityFields
    priority.sort((a, b) =>
        _priorityFields.indexOf(a.key) - _priorityFields.indexOf(b.key));

    // Combine and limit to 12 fields
    return [...priority, ...rest].take(12).toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Color helpers (module-level, used by multiple widgets)
// ─────────────────────────────────────────────────────────────────────────────

Color workflowStateColor(String state) {
  final s = state.toLowerCase();
  if (s.contains('approv') ||
      s.contains('active') ||
      s.contains('complet') ||
      s.contains('accept') ||
      s.contains('verified') ||
      s.contains('confirm')) {
    return AppColors.success;
  }
  if (s.contains('reject') ||
      s.contains('cancel') ||
      s.contains('deny') ||
      s.contains('refused') ||
      s.contains('close')) {
    return AppColors.error;
  }
  if (s.contains('pending') ||
      s.contains('open') ||
      s.contains('review') ||
      s.contains('wait') ||
      s.contains('hold') ||
      s.contains('draft')) {
    return AppColors.warning;
  }
  return const Color(0xFF3B82F6);
}

Color _actionColor(String action) {
  final a = action.toLowerCase();
  if (a.contains('approv') ||
      a.contains('accept') ||
      a.contains('confirm') ||
      a.contains('submit') ||
      a.contains('complete')) {
    return AppColors.success;
  }
  if (a.contains('reject') ||
      a.contains('deny') ||
      a.contains('cancel') ||
      a.contains('refuse') ||
      a.contains('decline')) {
    return AppColors.error;
  }
  if (a.contains('request') ||
      a.contains('clarif') ||
      a.contains('more info') ||
      a.contains('return') ||
      a.contains('send back')) {
    return AppColors.warning;
  }
  return const Color(0xFF3B82F6);
}

String _fieldLabel(String key) => key
    .replaceAll('_', ' ')
    .split(' ')
    .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  final AppColors c;
  const _SectionLabel(this.text, this.c);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          color: c.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      );
}

// ── Document header ───────────────────────────────────────────────────────────

class _DocHeader extends StatelessWidget {
  final String doctype;
  final String docname;
  final String state;
  final WorkflowInfo? workflow;
  final int docstatus;
  final AppColors c;
  final AppLocalizations l;

  const _DocHeader({
    required this.doctype,
    required this.docname,
    required this.state,
    required this.workflow,
    required this.docstatus,
    required this.c,
    required this.l,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.surfaceHigh),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.description_outlined, color: c.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  docname,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  doctype,
                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          // State badge
          if (state.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: workflowStateColor(state).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color:
                        workflowStateColor(state).withValues(alpha: 0.4)),
              ),
              child: Text(
                state,
                style: TextStyle(
                  color: workflowStateColor(state),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else if (workflow == null)
            _DocstatusChip(docstatus: docstatus, l: l),
        ],
      ),
    );
  }
}

class _DocstatusChip extends StatelessWidget {
  final int docstatus;
  final AppLocalizations l;
  const _DocstatusChip({required this.docstatus, required this.l});

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;
    switch (docstatus) {
      case 0:
        label = l.wfDraft;
        color = AppColors.warning;
        break;
      case 1:
        label = l.wfSubmitted;
        color = AppColors.success;
        break;
      case 2:
        label = l.wfCancelled;
        color = AppColors.error;
        break;
      default:
        label = docstatus.toString();
        color = const Color(0xFF3B82F6);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

// ── Field grid ────────────────────────────────────────────────────────────────

class _FieldGrid extends StatelessWidget {
  final List<MapEntry<String, dynamic>> fields;
  final AppColors c;
  const _FieldGrid({required this.fields, required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.surfaceHigh),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: fields.length,
        separatorBuilder: (ctx, i) =>
            Divider(height: 1, color: c.surfaceHigh),
        itemBuilder: (_, i) {
          final e = fields[i];
          return Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: Text(
                    _fieldLabel(e.key),
                    style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    e.value?.toString() ?? '',
                    style:
                        TextStyle(color: c.textPrimary, fontSize: 13),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Workflow state badge ───────────────────────────────────────────────────────

class _WorkflowStateBadge extends StatelessWidget {
  final String state;
  final String workflowName;
  final AppColors c;
  const _WorkflowStateBadge({
    required this.state,
    required this.workflowName,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    final color = workflowStateColor(state);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.account_tree_rounded, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state,
                  style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  workflowName,
                  style: TextStyle(color: c.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action bar at the bottom ───────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  final WorkflowInfo? workflow;
  final List<WorkflowTransition> transitions;
  final int docstatus;
  final bool loading;
  final AppColors c;
  final AppLocalizations l;
  final Future<void> Function(String) onAction;
  final Future<void> Function() onSave;
  final Future<void> Function() onSubmit;
  final Future<void> Function() onCancel;

  const _ActionBar({
    required this.workflow,
    required this.transitions,
    required this.docstatus,
    required this.loading,
    required this.c,
    required this.l,
    required this.onAction,
    required this.onSave,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        color: c.surface,
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text(l.wfExecutingAction,
                style: TextStyle(color: c.textSecondary, fontSize: 13)),
          ],
        ),
      );
    }

    // ── Workflow buttons ────────────────────────────────────────────────────
    if (workflow != null) {
      if (transitions.isEmpty) {
        return Container(
          color: c.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded,
                  color: c.textSecondary, size: 16),
              const SizedBox(width: 6),
              Text(
                l.wfNoActionsAvailable,
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
            ],
          ),
        );
      }

      return Container(
        color: c.surface,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hint text
            Text(
              l.wfChooseAction,
              style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            // Wrap so multiple buttons flow nicely
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: transitions.map((t) {
                final color = _actionColor(t.action);
                return ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: Icon(_actionIcon(t.action), size: 16),
                  label: Text(t.action,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  onPressed: () => onAction(t.action),
                );
              }).toList(),
            ),
          ],
        ),
      );
    }

    // ── Fallback: docstatus-based buttons (no workflow) ─────────────────────
    return Container(
      color: c.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          // Draft → can submit
          if (docstatus == 0) ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.save_outlined, size: 16),
              label: Text(l.save),
              onPressed: onSave,
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white),
              icon: const Icon(Icons.check_rounded, size: 16),
              label: Text(l.wfSubmitDoc),
              onPressed: onSubmit,
            ),
          ],
          // Submitted → can cancel
          if (docstatus == 1)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white),
              icon: const Icon(Icons.cancel_outlined, size: 16),
              label: Text(l.wfCancelDoc),
              onPressed: onCancel,
            ),
          // Cancelled → read only
          if (docstatus == 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.block_rounded,
                      color: c.textSecondary, size: 16),
                  const SizedBox(width: 6),
                  Text(l.wfCancelled,
                      style: TextStyle(
                          color: c.textSecondary, fontSize: 13)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  IconData _actionIcon(String action) {
    final a = action.toLowerCase();
    if (a.contains('approv') || a.contains('accept') || a.contains('confirm')) {
      return Icons.check_circle_outline_rounded;
    }
    if (a.contains('reject') || a.contains('deny') || a.contains('decline')) {
      return Icons.cancel_outlined;
    }
    if (a.contains('return') || a.contains('send back') || a.contains('clarif')) {
      return Icons.undo_rounded;
    }
    if (a.contains('submit')) return Icons.send_rounded;
    if (a.contains('cancel')) return Icons.block_rounded;
    return Icons.arrow_forward_rounded;
  }
}
