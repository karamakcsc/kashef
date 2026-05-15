import 'dart:async';

import 'package:flutter/material.dart';

import 'api_service.dart';
import 'app_colors.dart';
import 'app_drawer.dart';
import 'app_localizations.dart';
import 'dashboard_detail_page.dart';

// ─── Model ───────────────────────────────────────────────────────────────────

class _DashEntry {
  final String name;
  final String module;
  final bool isDefault;
  const _DashEntry({required this.name, required this.module, required this.isDefault});
}

// ─── Page ────────────────────────────────────────────────────────────────────

class DashboardsPage extends StatefulWidget {
  const DashboardsPage({super.key});

  @override
  State<DashboardsPage> createState() => _DashboardsPageState();
}

class _DashboardsPageState extends State<DashboardsPage> {
  static const _refreshInterval = Duration(minutes: 5);

  bool _loading = true;
  String? _error;
  List<_DashEntry> _all = [];
  List<_DashEntry> _filtered = [];
  DateTime? _lastUpdated;
  Timer? _refreshTimer;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _silentLoad());
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Loading ────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService.get(
        '/api/resource/Dashboard?fields=["name","module","is_default"]&limit=100&order_by=module asc, name asc',
      );
      if (!mounted) return;
      final data = _safeList(res['data']);
      final entries = data.map((e) => _DashEntry(
        name: (e['name'] as String?) ?? '',
        module: (e['module'] as String?) ?? '',
        isDefault: e['is_default'] == 1 || e['is_default'] == true,
      )).where((e) => e.name.isNotEmpty).toList();

      setState(() {
        _all = entries;
        _filtered = _applySearch(entries, _searchCtrl.text);
        _loading = false;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).connectionError(e.toString());
        _loading = false;
      });
    }
  }

  Future<void> _silentLoad() async {
    if (!mounted) return;
    try {
      final res = await ApiService.get(
        '/api/resource/Dashboard?fields=["name","module","is_default"]&limit=100&order_by=module asc, name asc',
      );
      if (!mounted) return;
      final data = _safeList(res['data']);
      final entries = data.map((e) => _DashEntry(
        name: (e['name'] as String?) ?? '',
        module: (e['module'] as String?) ?? '',
        isDefault: e['is_default'] == 1 || e['is_default'] == true,
      )).where((e) => e.name.isNotEmpty).toList();

      setState(() {
        _all = entries;
        _filtered = _applySearch(entries, _searchCtrl.text);
        _lastUpdated = DateTime.now();
      });
    } catch (_) {}
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  void _onSearch() {
    setState(() => _filtered = _applySearch(_all, _searchCtrl.text));
  }

  List<_DashEntry> _applySearch(List<_DashEntry> src, String q) {
    if (q.trim().isEmpty) return src;
    final lq = q.toLowerCase();
    return src.where((e) =>
      e.name.toLowerCase().contains(lq) ||
      e.module.toLowerCase().contains(lq)).toList();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _safeList(dynamic v) {
    if (v is List) return v.whereType<Map<String, dynamic>>().toList();
    return [];
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static IconData _iconFor(String module) {
    const map = <String, IconData>{
      'accounts':     Icons.account_balance_rounded,
      'accounting':   Icons.account_balance_rounded,
      'hr':           Icons.people_alt_rounded,
      'human':        Icons.people_alt_rounded,
      'payroll':      Icons.payments_rounded,
      'crm':          Icons.contacts_rounded,
      'selling':      Icons.sell_rounded,
      'buying':       Icons.shopping_cart_rounded,
      'stock':        Icons.inventory_2_rounded,
      'manufacturing':Icons.precision_manufacturing_rounded,
      'projects':     Icons.folder_special_rounded,
      'support':      Icons.support_agent_rounded,
    };
    final m = module.toLowerCase();
    return map.entries
        .firstWhere((e) => m.contains(e.key), orElse: () => const MapEntry('', Icons.dashboard_rounded))
        .value;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = AppColors.of(context);

    return Scaffold(
      backgroundColor: c.background,
      drawer: const AppDrawer(current: DrawerSection.dashboards),
      appBar: AppBar(
        backgroundColor: c.primary,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.2),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.dashboards,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
            if (_lastUpdated != null)
              Text(
                l.updatedAtLine(_formatTime(_lastUpdated!)),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11),
              ),
          ],
        ),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              onPressed: _load,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(child: _buildBody(l, c)),
    );
  }

  Widget _buildBody(AppLocalizations l, AppColors c) {
    return Column(
      children: [
        // ── Search bar ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _searchCtrl,
            style: TextStyle(color: c.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: l.dashSearchHint,
              hintStyle: TextStyle(color: c.textSecondary, fontSize: 14),
              prefixIcon: Icon(Icons.search_rounded, color: c.textSecondary, size: 20),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear_rounded, color: c.textSecondary, size: 18),
                      onPressed: () => _searchCtrl.clear())
                  : null,
              filled: true,
              fillColor: c.surfaceHigh,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        // ── Content ─────────────────────────────────────────────────────────
        Expanded(child: _buildContent(l, c)),
      ],
    );
  }

  Widget _buildContent(AppLocalizations l, AppColors c) {
    // Loading state (first load only)
    if (_loading && _all.isEmpty) {
      return Center(child: CircularProgressIndicator(color: c.primary));
    }

    // Error state
    if (_error != null && _all.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_rounded, color: c.textSecondary, size: 52),
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: c.textSecondary, fontSize: 13),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l.retry),
            ),
          ]),
        ),
      );
    }

    // Empty state
    if (_filtered.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.dashboard_outlined,
              color: c.textSecondary.withValues(alpha: 0.4), size: 56),
          const SizedBox(height: 12),
          Text(
            _all.isEmpty ? l.noDashboards : l.noData,
            style: TextStyle(color: c.textSecondary, fontSize: 14),
          ),
        ]),
      );
    }

    // Group by module
    final grouped = <String, List<_DashEntry>>{};
    for (final e in _filtered) {
      final key = e.module.isNotEmpty ? e.module : 'General';
      (grouped[key] ??= []).add(e);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 700;
        return RefreshIndicator(
          onRefresh: _load,
          color: c.primary,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: [
              // Summary strip
              _SummaryStrip(count: _all.length, modules: grouped.length, c: c, l: l),
              const SizedBox(height: 8),

              // Module sections
              ...grouped.entries.map((g) => _ModuleSection(
                module: g.key,
                entries: g.value,
                isWide: isWide,
                icon: _iconFor(g.key),
                c: c,
                onTap: (name) => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DashboardDetailPage(dashboardName: name),
                  ),
                ),
              )),
            ],
          ),
        );
      },
    );
  }
}

// ─── Summary strip ────────────────────────────────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  final int count;
  final int modules;
  final AppColors c;
  final AppLocalizations l;
  const _SummaryStrip({required this.count, required this.modules, required this.c, required this.l});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: c.surfaceHigh.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(children: [
      Icon(Icons.dashboard_rounded, color: c.textSecondary.withValues(alpha: 0.5), size: 14),
      const SizedBox(width: 8),
      Text(
        l.dashboardCount(count, modules),
        style: TextStyle(color: c.textSecondary, fontSize: 12),
      ),
    ]),
  );
}

// ─── Module section ───────────────────────────────────────────────────────────

class _ModuleSection extends StatelessWidget {
  final String module;
  final List<_DashEntry> entries;
  final bool isWide;
  final IconData icon;
  final AppColors c;
  final void Function(String) onTap;
  const _ModuleSection({
    required this.module, required this.entries, required this.isWide,
    required this.icon, required this.c, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Module header
      Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Row(children: [
          Icon(icon, color: c.textSecondary.withValues(alpha: 0.45), size: 13),
          const SizedBox(width: 6),
          Text(
            module.toUpperCase(),
            style: TextStyle(
              color: c.textSecondary.withValues(alpha: 0.45),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ]),
      ),

      // Cards — 2-column grid on wide screens, list on narrow
      if (isWide)
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 4.5,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: entries.map((e) => _DashCard(entry: e, c: c, onTap: () => onTap(e.name))).toList(),
        )
      else
        ...entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _DashCard(entry: e, c: c, onTap: () => onTap(e.name)),
        )),

      const SizedBox(height: 16),
    ],
  );
}

// ─── Dashboard card ───────────────────────────────────────────────────────────

class _DashCard extends StatelessWidget {
  final _DashEntry entry;
  final AppColors c;
  final VoidCallback onTap;
  const _DashCard({required this.entry, required this.c, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.surfaceHigh),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.bar_chart_rounded, color: c.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    entry.name,
                    style: TextStyle(
                        color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (entry.isDefault) ...[
                    const SizedBox(height: 2),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.star_rounded, color: Colors.amber, size: 11),
                      const SizedBox(width: 3),
                      Text(l.defaultLabel,
                          style: const TextStyle(color: Colors.amber, fontSize: 10)),
                    ]),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: c.textSecondary.withValues(alpha: 0.4), size: 18),
          ]),
        ),
      ),
    );
  }
}
