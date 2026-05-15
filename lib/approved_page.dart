import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_service.dart';
import 'app_colors.dart';
import 'app_localizations.dart';
import 'fac_mcp_service.dart' show FacMcpService;
import 'realtime_workflow_service.dart';
import 'workflow_service.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Model
// ═════════════════════════════════════════════════════════════════════════════

class _Doc {
  final String name;       // reference_name (document name)
  final String state;      // workflow_state after approval
  final String creation;   // formatted date
  const _Doc({required this.name, required this.state, required this.creation});
}

// ═════════════════════════════════════════════════════════════════════════════
// Page
// ═════════════════════════════════════════════════════════════════════════════

class ApprovedApprovalsPage extends StatefulWidget {
  const ApprovedApprovalsPage({super.key});

  @override
  State<ApprovedApprovalsPage> createState() => _State();
}

class _State extends State<ApprovedApprovalsPage> {

  // ── State ─────────────────────────────────────────────────────────────────
  bool   _loading    = true;
  bool   _refreshing = false;
  bool   _busy       = false;
  String _error      = '';

  Map<String, List<_Doc>> _data          = {};
  String                  _search        = '';
  String                  _filterDoctype = '';
  int                     _days          = 30; // date window

  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  late WorkflowEventCallback _rtCb; // realtime workflow events

  // ── Derived ───────────────────────────────────────────────────────────────

  int get _total => _data.values.fold(0, (s, l) => s + l.length);

  Map<String, List<_Doc>> get _display {
    var src = _data;
    if (_filterDoctype.isNotEmpty) {
      src = {if (src.containsKey(_filterDoctype)) _filterDoctype: src[_filterDoctype]!};
    }
    if (_search.isNotEmpty) {
      final q   = _search.toLowerCase();
      final out = <String, List<_Doc>>{};
      src.forEach((dt, docs) {
        final hits = docs.where((d) =>
            d.name.toLowerCase().contains(q) ||
            d.state.toLowerCase().contains(q)).toList();
        if (hits.isNotEmpty) out[dt] = hits;
      });
      return out;
    }
    return src;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load();
    // Listen for workflow events from pending page → auto-refresh approved list
    _rtCb = (ev) {
      debugPrint('[Approved] 📡 Realtime event: $ev — refreshing');
      if (mounted) _load(silent: true);
    };
    RealtimeWorkflowService().addListener(_rtCb);
  }

  @override
  void dispose() {
    RealtimeWorkflowService().removeListener(_rtCb);
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Load ─────────────────────────────────────────────────────────────────

  Future<void> _load({bool silent = false}) async {
    if (!mounted || _busy) return;
    _busy = true;
    if (!silent && mounted) setState(() { _loading = true; _error = ''; });

    try {
      final data = await _fetchApproved();
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      debugPrint('[Approved] load error: $e');
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
    _busy = false;
  }

  Future<void> _manualRefresh() async {
    if (_refreshing) return;
    if (mounted) setState(() => _refreshing = true);
    _busy = false;
    await _load();
    if (mounted) setState(() => _refreshing = false);
  }

  // ── Fetch submitted docs (docstatus=1) from active-workflow doctypes ─────────
  //
  // Architecture: Instead of relying on Workflow Action records (which only
  // cover actions taken by the CURRENT user), we query each doctype that has
  // an active ERPNext workflow and filter server-side by docstatus=1.
  //
  // This ensures:
  //   • ALL submitted docs visible to the user appear (not just ones they approved)
  //   • No dependency on Workflow Action completion status
  //   • docstatus=1 is the single authoritative filter — no text-based state matching
  //   • frappe.client.get_list respects user permissions automatically

  Future<Map<String, List<_Doc>>> _fetchApproved() async {
    final cutoff  = DateTime.now().subtract(Duration(days: _days));
    final dateStr = '${cutoff.year}-'
        '${cutoff.month.toString().padLeft(2, '0')}-'
        '${cutoff.day.toString().padLeft(2, '0')}';

    debugPrint('[Approved] ── Fetching submitted docs (docstatus=1) ──');
    debugPrint('[Approved] Date window: last $_days days (>= $dateStr)');

    // Step 1: Discover active workflows → get target doctypes + state field
    final List<Map<String, dynamic>> workflows;
    try {
      final wfRes = await ApiService.get(
        '/api/resource/Workflow'
        '?filters=${Uri.encodeComponent(jsonEncode([["is_active", "=", 1]]))}'
        '&fields=${Uri.encodeComponent(jsonEncode(["name", "document_type", "workflow_state_field"]))}'
        '&limit=50',
      );
      workflows = ((wfRes['data'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      debugPrint('[Approved] Found ${workflows.length} active workflows: '
          '${workflows.map((w) => w["document_type"]).join(", ")}');
    } catch (e) {
      debugPrint('[Approved] Failed to fetch active workflows: $e');
      return {};
    }

    if (workflows.isEmpty) return {};

    // Step 2: For each doctype, query submitted docs (docstatus=1) in parallel
    // frappe.client.get_list respects user permissions — safe, no bypass.
    final result = <String, List<_Doc>>{};

    await Future.wait(workflows.map((wf) async {
      final dt         = (wf['document_type']      ?? '').toString();
      final stateField = (wf['workflow_state_field'] ?? 'workflow_state').toString();
      if (dt.isEmpty) return;

      try {
        final res = await ApiService.postForm(
          '/api/method/frappe.client.get_list',
          {
            'doctype': dt,
            'fields':  jsonEncode(['name', stateField, 'modified']),
            'filters': jsonEncode([
              ['docstatus', '=',  1],
              ['modified',  '>=', dateStr],  // use 'modified' to catch recently-submitted older docs
            ]),
            'order_by':          'modified desc',
            'limit_page_length': '50',
          },
        );

        final rawList = (res['message'] as List?) ?? [];
        final docs = rawList.map<_Doc?>((e) {
          if (e is! Map) return null;
          final dn    = (e['name']      ?? '').toString();
          final state = (e[stateField]  ?? '').toString();
          final mod   = (e['modified']  ?? '').toString();
          if (dn.isEmpty) return null;

          debugPrint('[Approved] $dt  doc=$dn  state=$state  docstatus=1  modified=$mod  visible=true');
          return _Doc(name: dn, state: state, creation: _shortDate(mod));
        }).whereType<_Doc>().toList();

        if (docs.isNotEmpty) {
          result[dt] = docs;
          debugPrint('[Approved] $dt: ${docs.length} submitted docs visible to user');
        } else {
          debugPrint('[Approved] $dt: 0 submitted docs (none visible or none in window)');
        }
      } catch (e) {
        // Permission denied on this doctype → skip silently (correct ERPNext behavior)
        debugPrint('[Approved] $dt: skipped — $e');
      }
    }));

    debugPrint('[Approved] ── Final result: '
        '${result.map((k, v) => MapEntry(k, v.length))} ──');
    return result;
  }

  // ── Cancel document ───────────────────────────────────────────────────────

  Future<void> _cancelDoc(String dt, String dn) async {
    final c = AppColors.of(context);
    final l = AppLocalizations.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l.wfCancelConfirmTitle,
            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dn,  style: TextStyle(color: c.textPrimary,   fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(dt,  style: TextStyle(color: c.textSecondary, fontSize: 13)),
            ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel, style: TextStyle(color: c.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.wfCancelDoc,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final sm = ScaffoldMessenger.of(context);
    sm.showSnackBar(SnackBar(
        content: Text('${l.wfCancelDoc}…'),
        duration: const Duration(seconds: 60)));

    try {
      // Step 1: Fetch full document (needed for getTransitions)
      final docRes = await ApiService.get('/api/resource/$dt/$dn');
      final raw    = docRes is Map ? (docRes['data'] ?? docRes) : {};
      final docMap = Map<String, dynamic>.from(raw as Map);

      // Step 2: Check for a cancel/reject-like workflow transition
      final transitions = await WorkflowService().getTransitions(docMap);
      const cancelKeywords = ['cancel', 'reject', 'deny', 'refuse', 'إلغاء', 'رفض'];
      final cancelT = transitions.where((t) {
        final a = t.action.toLowerCase();
        return cancelKeywords.any((k) => a.contains(k));
      }).firstOrNull;

      bool done = false;

      if (cancelT != null) {
        // CASE 1 — Workflow has a cancel/reject transition → use FAC run_workflow
        debugPrint('[Cancel] Workflow Cancel Exists: true');
        debugPrint('[Cancel] Using run_workflow: ${cancelT.action}');
        debugPrint('[Cancel] Found transition: "${cancelT.action}" → "${cancelT.nextState}"');
        try {
          final r = await FacMcpService().runWorkflow(docMap, cancelT.action);
          if (r != null) {
            done = true;
            debugPrint('[Cancel] ✅ FAC run_workflow "${cancelT.action}" succeeded');
          }
        } catch (facErr) {
          debugPrint('[Cancel] FAC run_workflow failed: $facErr — fallback safeApplyWorkflow');
          final msg = facErr.toString().toLowerCase();
          if (msg.contains('permission') || msg.contains('not allowed')) { rethrow; }
        }
        if (!done) {
          await WorkflowService().safeApplyWorkflow(docMap, cancelT.action);
          done = true;
          debugPrint('[Cancel] ✅ safeApplyWorkflow "${cancelT.action}" succeeded');
        }
      } else {
        // CASE 2 — No workflow cancel transition → ERPNext direct cancel
        debugPrint('[Cancel] Workflow Cancel Exists: false');
        debugPrint('[Cancel] Using ERPNext Cancel API');
        debugPrint('[Cancel] Doctype: $dt  Name: $dn');

        // Safety check 1: only submitted documents (docstatus=1) can be cancelled
        final docstatus = (docMap['docstatus'] as num?)?.toInt() ?? -1;
        debugPrint('[Cancel] Current Docstatus: $docstatus');
        if (docstatus != 1) {
          throw Exception(
              'Cannot cancel: document must be submitted (docstatus=1), '
              'current docstatus=$docstatus');
        }

        // Safety check 2: verify the user has cancel permission on this document
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
          debugPrint('[Cancel] Permission check error: $permErr');
        }
        debugPrint('[Cancel] Has Cancel Permission: $hasCancelPermission');
        if (!hasCancelPermission) {
          throw Exception(
              'You do not have permission to cancel $dn. '
              'Contact your ERPNext administrator.');
        }

        // frappe.client.cancel(doctype, name) — correct Frappe API signature
        debugPrint('[Cancel] Payload → doctype=$dt  name=$dn');
        final cancelRes = await ApiService.postForm(
          '/api/method/frappe.client.cancel',
          {'doctype': dt, 'name': dn},
        );
        debugPrint('[Cancel] API Response: $cancelRes');

        if (cancelRes['exc'] != null) {
          final srvMsg = cancelRes['_server_messages']?.toString() ?? '';
          final exc    = cancelRes['exc'].toString();
          debugPrint('[Cancel] Server error: $exc');
          throw Exception(srvMsg.isNotEmpty ? srvMsg : exc);
        }
        debugPrint('[Cancel] ✅ frappe.client.cancel succeeded — $dt/$dn');
        done = true;
      }

      if (mounted) {
        sm.hideCurrentSnackBar();
        sm.showSnackBar(SnackBar(
          content: Text('${l.wfCancelled} ✓ — $dn'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 3),
        ));
        debugPrint('[Approved] Cancel: $dt/$dn → docstatus=2, removing from Approved');
        _removeDoc(dt, dn);
        RealtimeWorkflowService().broadcastLocal({
          'reference_doctype': dt,
          'reference_name':    dn,
          'action':            'Cancel',
          'docstatus':         2,
        });
        _busy = false;
        _load(silent: true);
      }
    } catch (e) {
      if (mounted) {
        sm.hideCurrentSnackBar();
        sm.showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
        ));
      }
    }
  }

  void _removeDoc(String dt, String dn) {
    if (!mounted) return;
    setState(() {
      final docs = _data[dt];
      if (docs == null) return;
      final remaining = docs.where((d) => d.name != dn).toList();
      remaining.isEmpty ? _data.remove(dt) : _data[dt] = remaining;
    });
  }

  Future<void> _openDoc(String dt, String dn) async {
    await Navigator.pushNamed(context, '/document-viewer',
        arguments: {'doctype': dt, 'docname': dn});
    if (mounted) _load(silent: true);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _shortDate(String s) => s.length >= 10 ? s.substring(0, 10) : s;

  // ═══════════════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: c.background,
      appBar: _appBar(c, l),
      body: SafeArea(
        child: Column(children: [
          _searchBar(c, l),
          _dateRow(c, l),
          _filterRow(c, l),
          Expanded(child: _body(c, l)),
        ]),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _appBar(AppColors c, AppLocalizations l) => AppBar(
    backgroundColor: AppColors.success,
    foregroundColor: Colors.white,
    elevation: 0,
    title: Row(children: [
      Flexible(
        child: Text(l.wfApprovedApprovals,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis),
      ),
      if (_total > 0) ...[
        const SizedBox(width: 8),
        _CountBadge(n: _total),
      ],
    ]),
    actions: [
      if (_refreshing)
        const Padding(padding: EdgeInsets.all(14),
          child: SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
      else
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          onPressed: _manualRefresh,
        ),
    ],
  );

  // ── Search bar ────────────────────────────────────────────────────────────

  Widget _searchBar(AppColors c, AppLocalizations l) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
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
        filled: true, fillColor: c.surface,
        border:        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.surfaceHigh, width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.success, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onChanged: (v) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 300),
            () { if (mounted) setState(() => _search = v.trim()); });
      },
    ),
  );

  // ── Date range chips ──────────────────────────────────────────────────────

  Widget _dateRow(AppColors c, AppLocalizations l) => SizedBox(
    height: 40,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      children: [
        _DateChip(label: l.wfLast7,  days: 7,  selected: _days == 7,  onTap: () => _setDays(7)),
        _DateChip(label: l.wfLast30, days: 30, selected: _days == 30, onTap: () => _setDays(30)),
        _DateChip(label: l.wfLast90, days: 90, selected: _days == 90, onTap: () => _setDays(90)),
      ],
    ),
  );

  void _setDays(int d) {
    if (_days == d) return;
    setState(() { _days = d; _loading = true; });
    _busy = false;
    _load();
  }

  // ── DocType filter chips ──────────────────────────────────────────────────

  Widget _filterRow(AppColors c, AppLocalizations l) => SizedBox(
    height: 44,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      children: [
        _Chip(
          label: l.wfAllTypes, selected: _filterDoctype.isEmpty,
          onTap: () => setState(() => _filterDoctype = ''),
        ),
        ..._data.keys.map((dt) => _Chip(
          label: dt, selected: _filterDoctype == dt,
          onTap: () => setState(() =>
              _filterDoctype = _filterDoctype == dt ? '' : dt),
        )),
      ],
    ),
  );

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _body(AppColors c, AppLocalizations l) {
    if (_loading) return _skeleton(c);
    if (_error.isNotEmpty) return _errState(c, l);

    final disp  = _display;
    final total = disp.values.fold(0, (s, list) => s + list.length);

    if (disp.isEmpty) return _emptyState(c, l);

    // Build flat list: header + cards + spacer
    final items = <_Item>[];
    disp.forEach((dt, docs) {
      items.add(_Item.header(dt, docs.length));
      for (final d in docs) { items.add(_Item.doc(dt, d)); }
      items.add(_Item.spacer());
    });
    debugPrint('[Approved] rendering $total docs in ${disp.length} groups');

    return RefreshIndicator(
      onRefresh: _manualRefresh,
      color: AppColors.success,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final item = items[i];
          if (item.isHeader) return _SectionHdr(doctype: item.doctype!, count: item.count!, c: c);
          if (item.isDoc) {
            return _ApprovedCard(
              doc:      item.doc!,
              c:        c,
              l:        l,
              onTap:    () => _openDoc(item.doctype!, item.doc!.name),
              onCancel: () => _cancelDoc(item.doctype!, item.doc!.name),
            );
          }
          return const SizedBox(height: 12);
        },
      ),
    );
  }

  Widget _skeleton(AppColors c) => ListView.builder(
    padding: const EdgeInsets.all(12),
    itemCount: 4,
    itemBuilder: (ctx, idx) => _SkeletonCard(c: c),
  );

  Widget _errState(AppColors c, AppLocalizations l) => Center(
    child: Padding(padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline_rounded, size: 56, color: AppColors.error),
        const SizedBox(height: 16),
        Text(_error, textAlign: TextAlign.center,
            style: TextStyle(color: c.textSecondary, fontSize: 13),
            maxLines: 6, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 20),
        _RefreshBtn(onPressed: _manualRefresh, c: c),
      ])),
  );

  Widget _emptyState(AppColors c, AppLocalizations l) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.check_circle_outline_rounded, size: 72,
          color: AppColors.success.withValues(alpha: 0.7)),
      const SizedBox(height: 16),
      Text(l.wfNoApproved,
          style: TextStyle(fontSize: 18, color: c.textSecondary,
              fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      Text(
        l.wfLastNDays(_days),
        style: TextStyle(fontSize: 13, color: c.textSecondary),
      ),
      const SizedBox(height: 24),
      _RefreshBtn(onPressed: _manualRefresh, c: c),
    ]),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Flat list item model
// ═════════════════════════════════════════════════════════════════════════════

class _Item {
  final bool    isHeader;
  final bool    isDoc;
  final String? doctype;
  final int?    count;
  final _Doc?   doc;
  const _Item._({required this.isHeader, required this.isDoc,
      this.doctype, this.count, this.doc});
  factory _Item.header(String dt, int n) =>
      _Item._(isHeader: true, isDoc: false, doctype: dt, count: n);
  factory _Item.doc(String dt, _Doc d) =>
      _Item._(isHeader: false, isDoc: true, doctype: dt, doc: d);
  factory _Item.spacer() =>
      _Item._(isHeader: false, isDoc: false);
}

// ═════════════════════════════════════════════════════════════════════════════
// Sub-widgets
// ═════════════════════════════════════════════════════════════════════════════

// ── Count badge ───────────────────────────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  final int n;
  const _CountBadge({required this.n});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
    child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
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
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    margin: const EdgeInsets.only(bottom: 10, top: 4),
    decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(12)),
    child: Row(children: [
      Expanded(child: Text(doctype,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
        child: Text('$count',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    ]),
  );
}

// ── Approved card ─────────────────────────────────────────────────────────────

class _ApprovedCard extends StatelessWidget {
  final _Doc         doc;
  final AppColors    c;
  final AppLocalizations l;
  final VoidCallback onTap;
  final VoidCallback onCancel;
  const _ApprovedCard({required this.doc, required this.c, required this.l,
      required this.onTap, required this.onCancel});

  @override
  Widget build(BuildContext context) => Card(
    elevation: 2,
    color:  c.surface,
    margin: const EdgeInsets.only(bottom: 10),
    shape:  RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: AppColors.success.withValues(alpha: 0.35), width: 1),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Name + open icon
          Row(children: [
            Expanded(child: Text(doc.name,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c.textPrimary))),
            Icon(Icons.open_in_new_rounded, color: c.textSecondary, size: 18),
          ]),

          const SizedBox(height: 10),

          // State badge + date
          Row(children: [
            _StateBadge(state: doc.state),
            const Spacer(),
            Icon(Icons.calendar_today_outlined, size: 12, color: c.textSecondary),
            const SizedBox(width: 4),
            Text(doc.creation, style: TextStyle(color: c.textSecondary, fontSize: 12)),
          ]),

          // Cancel button
          const SizedBox(height: 14),
          Divider(height: 1, color: c.surfaceHigh),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(color: AppColors.error.withValues(alpha: 0.6)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              onPressed: onCancel,
              icon: const Icon(Icons.cancel_outlined, size: 16),
              label: Text(l.wfCancelDoc),
            ),
          ),
        ]),
      ),
    ),
  );
}

// ── State badge ───────────────────────────────────────────────────────────────

class _StateBadge extends StatelessWidget {
  final String state;
  const _StateBadge({required this.state});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color:  AppColors.success.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
    ),
    child: Text(state,
        style: TextStyle(color: AppColors.success,
            fontWeight: FontWeight.bold, fontSize: 12)),
  );
}

// ── Date chip ─────────────────────────────────────────────────────────────────

class _DateChip extends StatelessWidget {
  final String label;
  final int    days;
  final bool   selected;
  final VoidCallback onTap;
  const _DateChip({required this.label, required this.days,
      required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color:        selected ? AppColors.success : Colors.transparent,
          border:       Border.all(color: AppColors.success, width: 1.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
              color:      selected ? Colors.white : AppColors.success,
              fontWeight: FontWeight.w600, fontSize: 13,
            )),
      ),
    ),
  );
}

// ── DocType filter chip ───────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final bool   selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color:        selected ? c.primary : Colors.transparent,
            border:       Border.all(color: c.primary, width: 1.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(
                color:      selected ? c.onPrimary : c.primary,
                fontWeight: FontWeight.w600, fontSize: 13,
              )),
        ),
      ),
    );
  }
}

// ── Refresh button ────────────────────────────────────────────────────────────

class _RefreshBtn extends StatelessWidget {
  final VoidCallback onPressed;
  final AppColors c;
  const _RefreshBtn({required this.onPressed, required this.c});
  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.success,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    ),
    onPressed: onPressed,
    icon:  const Icon(Icons.refresh_rounded),
    label: Text(AppLocalizations.of(context).refresh),
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
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
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
      builder: (ctx, child) => Opacity(
        opacity: 0.35 + _anim.value * 0.45,
        child: Card(
          elevation: 1, color: c.surface,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: c.surfaceHigh, width: 1)),
          child: Padding(padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _box(c, double.infinity, 16),
              const SizedBox(height: 12),
              Row(children: [_box(c, 90, 24), const Spacer(), _box(c, 70, 14)]),
              const SizedBox(height: 16),
              Align(alignment: Alignment.centerRight, child: _box(c, 100, 32)),
            ])),
        ),
      ),
    );
  }

  Widget _box(AppColors c, double w, double h) => Container(
    width: w, height: h,
    decoration: BoxDecoration(color: c.surfaceHigh, borderRadius: BorderRadius.circular(6)),
  );
}
