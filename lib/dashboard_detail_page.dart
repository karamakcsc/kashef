import 'dart:async';
import 'dart:convert';
import 'dart:math' show max;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'app_colors.dart';
import 'app_localizations.dart';
import 'fac_mcp_service.dart';

// ═════════════════════════════════════════════════════════════════════════════
// MODELS
// ═════════════════════════════════════════════════════════════════════════════

class _ChartEntry {
  final String chartName;
  final String width; // 'Half' | 'Full'
  const _ChartEntry({required this.chartName, required this.width});
}

class _Dataset {
  final String name;
  final List<double> values;
  const _Dataset({required this.name, required this.values});
}

class _ChartData {
  final String chartType; // Bar | Line | Pie | Donut | Count | Sum | Average
  final List<String> labels;
  final List<_Dataset> datasets;
  final dynamic singleValue;
  final String? fieldtype;
  const _ChartData({
    required this.chartType,
    required this.labels,
    required this.datasets,
    this.singleValue,
    this.fieldtype,
  });
}

class _ChartMeta {
  final String documentType;
  List<List<String>> filters;
  _ChartMeta({required this.documentType, required this.filters});
}

class _CacheEntry {
  final dynamic data;
  final DateTime at;
  _CacheEntry(this.data) : at = DateTime.now();
  bool get isStale => DateTime.now().difference(at) > const Duration(minutes: 5);
}

// ═════════════════════════════════════════════════════════════════════════════
// COLOR PALETTE
// ═════════════════════════════════════════════════════════════════════════════

const _kPalette = [
  Color(0xFF3B82F6), Color(0xFF10B981), Color(0xFFF59E0B),
  Color(0xFFEF4444), Color(0xFF8B5CF6), Color(0xFF06B6D4),
  Color(0xFFEC4899), Color(0xFF84CC16),
];

Color _pal(int i) => _kPalette[i % _kPalette.length];

// ═════════════════════════════════════════════════════════════════════════════
// SAFE PARSING HELPERS (web-safe, no dynamic cast errors)
// ═════════════════════════════════════════════════════════════════════════════

Map<String, dynamic> _safeMap(dynamic v) {
  if (v is Map) {
    return Map<String, dynamic>.fromEntries(
      v.entries.map((e) => MapEntry(e.key.toString(), e.value)),
    );
  }
  return {};
}

List<dynamic> _safeList(dynamic v) => v is List ? v : [];


// ═════════════════════════════════════════════════════════════════════════════
// FAC SERVICE LAYER (FAC-first, ERPNext API fallback)
// ═════════════════════════════════════════════════════════════════════════════

class _DashService {
  static final Map<String, _CacheEntry> _cache = {};

  // ── Fetch chart metadata ──────────────────────────────────────────────────

  static Future<_ChartMeta?> fetchChartMeta(String chartName) async {
    final ck = 'meta:$chartName';
    final cached = _cache[ck];
    if (cached != null && !cached.isStale) return cached.data as _ChartMeta?;

    try {
      final res = await ApiService.get(
        '/api/resource/Dashboard Chart/${Uri.encodeComponent(chartName)}',
      );
      final d = _safeMap(res['data']);
      final docType = (d['document_type'] as String?)?.isNotEmpty == true
          ? d['document_type'] as String
          : (d['doc_type'] as String?) ?? '';

      List<List<String>> filters = [];
      try {
        final raw = d['filters_json'] as String? ?? '[]';
        final parsed = jsonDecode(raw);
        if (parsed is List) {
          for (final f in parsed) {
            if (f is List) {
              if (f.length == 4) {
                filters.add([f[1].toString(), f[2].toString(), f[3].toString()]);
              } else if (f.length == 3) {
                filters.add([f[0].toString(), f[1].toString(), f[2].toString()]);
              }
            }
          }
        }
      } catch (_) {}

      final meta = _ChartMeta(documentType: docType, filters: filters);
      _cache[ck] = _CacheEntry(meta);
      return meta;
    } catch (e) {
      debugPrint('[DASHBOARD] fetchChartMeta error for $chartName: $e');
      return null;
    }
  }

  // ── Fetch chart data ──────────────────────────────────────────────────────

  static Future<_ChartData?> fetchChartData(
    String chartName, {
    required String timespan,
    required String timegrain,
    required bool useDateRange,
    required String fromDate,
    required String toDate,
    required String company,
    List<List<String>> extraFilters = const [],
  }) async {
    final cacheKey = '$chartName:$timespan:$timegrain:$useDateRange:$fromDate:$toDate:$company';
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isStale) return cached.data as _ChartData?;

    try {
      final params = <String, String>{
        'chart_name': chartName,
        'timegrain': timegrain,
        'refresh': '0',
      };
      if (useDateRange && fromDate.isNotEmpty && toDate.isNotEmpty) {
        params['from_date'] = fromDate;
        params['to_date'] = toDate;
        params['timespan'] = 'Custom';
      } else {
        params['timespan'] = timespan;
      }

      List<List<String>> allFilters = List.from(extraFilters);
      if (company.isNotEmpty) {
        allFilters.removeWhere((f) => f.isNotEmpty && f[0].toLowerCase() == 'company');
        allFilters.add(['company', '=', company]);
      }
      if (allFilters.isNotEmpty) {
        params['filters_json'] = jsonEncode(allFilters);
      }

      final baseUrl = await ApiService.getErpNextUrl();
      final headers = await ApiService.getAuthHeaders();
      final base = Uri.parse(baseUrl);
      final uri = Uri(
        scheme: base.scheme, host: base.host,
        port: base.hasPort ? base.port : null,
        path: '/api/method/frappe.desk.doctype.dashboard_chart.dashboard_chart.get',
        queryParameters: params,
      );

      final res = await _httpGet(uri.toString(), headers);
      if (res == null) {
        debugPrint('[DASHBOARD] fetchChartData null for $chartName');
        return null;
      }

      final chart = _parseChartData(res);
      _cache[cacheKey] = _CacheEntry(chart);
      return chart;
    } catch (e) {
      debugPrint('[DASHBOARD] fetchChartData error for $chartName: $e');
      return null;
    }
  }

  // ── Pending approvals count ───────────────────────────────────────────────

  static Future<int> fetchPendingCount() async {
    try {
      // Try FAC first
      final facResult = await FacMcpService().getPendingApprovals();
      if (facResult != null) {
        return facResult.totalPending;
      }
    } catch (_) {}

    // Fallback: ERPNext API
    try {
      final userId = await ApiService.getLoggedUserId();
      final res = await ApiService.postForm(
        '/api/method/frappe.client.get_list',
        {
          'doctype': 'Workflow Action',
          'filters': jsonEncode([['status', '=', 'Open'], ['user', '=', userId]]),
          'fields': '["name"]',
          'limit_page_length': '100',
        },
      );
      return _safeList(res['message']).length;
    } catch (_) {}
    return 0;
  }

  // ── Fetch companies list ──────────────────────────────────────────────────

  static Future<List<String>> fetchCompanies() async {
    const ck = 'companies';
    final cached = _cache[ck];
    if (cached != null && !cached.isStale) return List<String>.from(cached.data as List);

    try {
      final res = await ApiService.get('/api/resource/Company?fields=["name"]&limit=50');
      final list = _safeList(res['data'])
          .map((e) => (e['name'] as String?) ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      _cache[ck] = _CacheEntry(list);
      return list;
    } catch (_) {
      return [];
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Future<dynamic> _httpGet(String url, Map<String, String> headers) async {
    try {
      final import = Uri.parse(url);
      final resp = await ApiService.get(import.path +
          (import.hasQuery ? '?${import.query}' : ''));
      return resp;
    } catch (_) {}
    return null;
  }

  static _ChartData? _parseChartData(dynamic raw) {
    final m = _safeMap(raw);
    final msg = m['message'] ?? m['data'] ?? m;
    if (msg == null) return null;
    final mm = _safeMap(msg);

    final type = (mm['chart_type'] as String?) ??
        (mm['type'] as String?) ?? 'Line';

    // Single-value chart (Count/Sum/Average)
    if (mm.containsKey('value')) {
      return _ChartData(
        chartType: type, labels: [], datasets: [],
        singleValue: mm['value'],
        fieldtype: mm['fieldtype'] as String?,
      );
    }

    final labels = _safeList(mm['labels'])
        .map((l) => l?.toString() ?? '').toList();
    final rawDs = _safeList(mm['datasets']);
    final datasets = rawDs.map((d) {
      final dm = _safeMap(d);
      return _Dataset(
        name: (dm['name'] as String?) ?? '',
        values: _safeList(dm['values'])
            .map((v) => (v as num?)?.toDouble() ?? 0.0)
            .toList(),
      );
    }).toList();

    if (labels.isEmpty && datasets.isEmpty) return null;
    return _ChartData(chartType: type, labels: labels, datasets: datasets);
  }

  static void invalidate() => _cache.clear();
  static void invalidateChart(String name) {
    _cache.removeWhere((k, _) => k.startsWith(name));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PAGE
// ═════════════════════════════════════════════════════════════════════════════

class DashboardDetailPage extends StatefulWidget {
  final String dashboardName;
  const DashboardDetailPage({super.key, required this.dashboardName});

  @override
  State<DashboardDetailPage> createState() => _DashboardDetailPageState();
}

class _DashboardDetailPageState extends State<DashboardDetailPage> {
  // ── State ──────────────────────────────────────────────────────────────────
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<_ChartEntry> _entries = [];
  final Map<String, _ChartData?> _data = {};
  final Map<String, _ChartMeta> _meta = {};
  int _pendingCount = 0;
  DateTime? _lastUpdated;
  Timer? _refreshTimer;

  // ── Filters ────────────────────────────────────────────────────────────────
  String _timespan = 'Last Year';
  String _timegrain = 'Monthly';
  bool _useDateRange = false;
  String _fromDate = '';
  String _toDate = '';
  String _company = '';
  List<String> _companies = [];

  static const _kRefreshInterval = Duration(minutes: 5);

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _init();
    _refreshTimer = Timer.periodic(_kRefreshInterval, (_) {
      if (mounted && !_loading) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    // Restore saved company
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('erpnext_company') ?? '';
      if (mounted) setState(() => _company = saved);
    } catch (_) {}
    await _load();
    // Load companies list in background
    _DashService.fetchCompanies().then((list) {
      if (mounted) setState(() => _companies = list);
    });
    // Load pending count
    _loadPending();
  }

  Future<void> _loadPending() async {
    final count = await _DashService.fetchPendingCount();
    if (mounted) setState(() => _pendingCount = count);
  }

  // ── Loading ────────────────────────────────────────────────────────────────

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    setState(() {
      if (!silent) { _loading = true; _error = null; _data.clear(); }
      else { _refreshing = true; }
    });

    try {
      debugPrint('[DASHBOARD] Loading: ${widget.dashboardName}');
      final res = await ApiService.get(
        '/api/resource/Dashboard/${Uri.encodeComponent(widget.dashboardName)}',
      );
      if (!mounted) return;

      if (res['exc'] != null) {
        final isPermError = res['exc'].toString().contains('PermissionError') ||
            res['exc'].toString().contains('403');
        throw Exception(isPermError
            ? AppLocalizations.of(context).dashNoPermission
            : 'Failed to load (${res['exc']})');
      }

      final doc = _safeMap(res['data']);
      _entries = _safeList(doc['charts']).map((c) {
        final cm = _safeMap(c);
        return _ChartEntry(
          chartName: (cm['chart'] as String?) ?? '',
          width: (cm['width'] as String?) ?? 'Full',
        );
      }).where((e) => e.chartName.isNotEmpty).toList();

      debugPrint('[DASHBOARD] Charts: ${_entries.length}');

      // Fetch meta + data for all charts in parallel
      await Future.wait(_entries.map((e) => _fetchChart(e.chartName)));

      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      debugPrint('[DASHBOARD] Error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _fetchChart(String name) async {
    if (!_meta.containsKey(name)) {
      final meta = await _DashService.fetchChartMeta(name);
      if (meta != null) _meta[name] = meta;
    }
    final data = await _DashService.fetchChartData(
      name,
      timespan: _timespan,
      timegrain: _timegrain,
      useDateRange: _useDateRange,
      fromDate: _fromDate,
      toDate: _toDate,
      company: _company,
      extraFilters: _meta[name]?.filters ?? [],
    );
    if (mounted) setState(() => _data[name] = data);
  }

  Future<void> _reloadChart(String name) async {
    _DashService.invalidateChart(name);
    setState(() => _data[name] = null);
    await _fetchChart(name);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: c.background,
      appBar: _buildAppBar(c, l),
      body: SafeArea(child: _buildBody(c, l)),
    );
  }

  PreferredSizeWidget _buildAppBar(AppColors c, AppLocalizations l) => AppBar(
    backgroundColor: c.primary,
    foregroundColor: Colors.white,
    iconTheme: const IconThemeData(color: Colors.white),
    elevation: 2,
    shadowColor: Colors.black.withValues(alpha: 0.2),
    titleSpacing: 0,
    title: Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.dashboardName,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700,
                  fontSize: 16, letterSpacing: 0.1),
              overflow: TextOverflow.ellipsis),
          if (_lastUpdated != null)
            Text(l.updatedAtLine(_formatTime(_lastUpdated!)),
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75), fontSize: 10)),
        ],
      ),
    ),
    actions: [
      if (_refreshing)
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
      else
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          tooltip: l.refresh,
          onPressed: () => _load(),
        ),
      IconButton(
        icon: const Icon(Icons.tune_rounded, color: Colors.white),
        tooltip: l.changeFilters,
        onPressed: _showFiltersSheet,
      ),
      const SizedBox(width: 4),
    ],
  );

  Widget _buildBody(AppColors c, AppLocalizations l) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: c.primary));
    }

    if (_error != null && _entries.isEmpty) {
      return _ErrorState(error: _error!, onRetry: _load, c: c, l: l);
    }

    if (_entries.isEmpty) {
      return Center(
        child: Text(l.noCharts, style: TextStyle(color: c.textSecondary)),
      );
    }

    return LayoutBuilder(builder: (ctx, constraints) {
      final isWide = constraints.maxWidth >= 768;
      return isWide ? _buildWebLayout(c, l) : _buildMobileLayout(c, l);
    });
  }

  // ── Mobile layout (vertical scroll) ───────────────────────────────────────

  Widget _buildMobileLayout(AppColors c, AppLocalizations l) {
    return RefreshIndicator(
      onRefresh: _load,
      color: c.primary,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _FilterStrip(
            timespan: _timespan, timegrain: _timegrain,
            useDateRange: _useDateRange, fromDate: _fromDate, toDate: _toDate,
            company: _company, onTap: _showFiltersSheet, c: c, l: l,
          )),
          if (_pendingCount > 0)
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _PendingWidget(count: _pendingCount, c: c, l: l),
            )),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            sliver: SliverList(delegate: SliverChildBuilderDelegate(
              (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ChartCardShell(
                  entry: _entries[i],
                  data: _data[_entries[i].chartName],
                  meta: _meta[_entries[i].chartName],
                  onFilterTap: () => _showChartFilters(_entries[i].chartName),
                  c: c, l: l,
                ),
              ),
              childCount: _entries.length,
            )),
          ),
        ],
      ),
    );
  }

  // ── Web layout (grid with sidebar) ────────────────────────────────────────

  Widget _buildWebLayout(AppColors c, AppLocalizations l) {
    return Row(children: [
      // Left sidebar (filters)
      _FilterSidebar(
        timespan: _timespan, timegrain: _timegrain,
        useDateRange: _useDateRange, fromDate: _fromDate, toDate: _toDate,
        company: _company, companies: _companies,
        pendingCount: _pendingCount,
        c: c, l: l,
        onApply: _applyFilters,
      ),

      // Right: chart grid
      Expanded(
        child: LayoutBuilder(builder: (ctx, constraints) {
          final cols = constraints.maxWidth >= 1200 ? 3 : 2;
          return RefreshIndicator(
            onRefresh: _load,
            color: c.primary,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _ChartCardShell(
                        entry: _entries[i],
                        data: _data[_entries[i].chartName],
                        meta: _meta[_entries[i].chartName],
                        onFilterTap: () => _showChartFilters(_entries[i].chartName),
                        c: c, l: l,
                      ),
                      childCount: _entries.length,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: _entries.any((e) =>
                        (_data[e.chartName]?.singleValue != null)) ? 1.8 : 1.3,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    ]);
  }

  // ── Filter actions ─────────────────────────────────────────────────────────

  void _applyFilters({
    String? timespan, String? timegrain, bool? useDateRange,
    String? fromDate, String? toDate, String? company,
  }) {
    setState(() {
      if (timespan != null) _timespan = timespan;
      if (timegrain != null) _timegrain = timegrain;
      if (useDateRange != null) _useDateRange = useDateRange;
      if (fromDate != null) _fromDate = fromDate;
      if (toDate != null) _toDate = toDate;
      if (company != null) _company = company;
    });
    _DashService.invalidate();
    _data.clear();
    _load();
  }

  void _showFiltersSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.of(context).surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _FiltersSheet(
        timespan: _timespan, timegrain: _timegrain,
        useDateRange: _useDateRange, fromDate: _fromDate, toDate: _toDate,
        company: _company, companies: _companies,
        onApply: (ts, tg, useDR, from, to, co) => _applyFilters(
          timespan: ts, timegrain: tg, useDateRange: useDR,
          fromDate: from, toDate: to, company: co,
        ),
      ),
    );
  }

  void _showChartFilters(String chartName) {
    final meta = _meta[chartName];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.of(context).surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ChartFiltersSheet(
        chartName: chartName,
        documentType: meta?.documentType ?? '',
        initialFilters: List<List<String>>.from(
            meta?.filters.map(List<String>.from).toList() ?? []),
        onApply: (filters) {
          if (_meta.containsKey(chartName)) {
            _meta[chartName]!.filters = filters;
          } else {
            _meta[chartName] = _ChartMeta(documentType: '', filters: filters);
          }
          _reloadChart(chartName);
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// CHART CARD SHELL
// ═════════════════════════════════════════════════════════════════════════════

class _ChartCardShell extends StatelessWidget {
  final _ChartEntry entry;
  final _ChartData? data;
  final _ChartMeta? meta;
  final VoidCallback onFilterTap;
  final AppColors c;
  final AppLocalizations l;
  const _ChartCardShell({
    required this.entry, required this.data, required this.meta,
    required this.onFilterTap, required this.c, required this.l,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.surfaceHigh),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
          child: Row(children: [
            Icon(_iconForType(data?.chartType ?? ''),
                size: 14, color: c.primary.withValues(alpha: 0.8)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(entry.chartName,
                  style: TextStyle(
                      color: c.textPrimary, fontSize: 12.5,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ),
            if (data != null)
              _TypeBadge(label: _typeLabel(data!.chartType), c: c),
            if (meta?.filters.isNotEmpty == true) ...[
              const SizedBox(width: 4),
              _FiltersBadge(count: meta!.filters.length, c: c),
            ],
            IconButton(
              icon: Icon(Icons.tune_rounded,
                  size: 16,
                  color: meta?.filters.isNotEmpty == true
                      ? c.primary : c.textSecondary.withValues(alpha: 0.4)),
              onPressed: onFilterTap,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
            ),
          ]),
        ),
        Divider(color: c.surfaceHigh, height: 1),

        // ── Content ─────────────────────────────────────────────────────────
        if (data == null)
          _LoadingOrEmpty(c: c, l: l)
        else
          _ChartBody(data: data!, c: c, l: l),
      ]),
    );
  }

  static IconData _iconForType(String t) {
    switch (t.toLowerCase()) {
      case 'bar':      return Icons.bar_chart_rounded;
      case 'pie':      return Icons.pie_chart_rounded;
      case 'donut':
      case 'percentage': return Icons.donut_large_rounded;
      case 'count':
      case 'sum':
      case 'average':  return Icons.tag_rounded;
      default:         return Icons.show_chart_rounded;
    }
  }

  static String _typeLabel(String t) {
    switch (t.toLowerCase()) {
      case 'bar':    return 'BAR';
      case 'pie':    return 'PIE';
      case 'donut':
      case 'percentage': return 'DONUT';
      case 'count':  return 'COUNT';
      case 'sum':    return 'SUM';
      case 'average':return 'AVG';
      default:       return t.substring(0, min(t.length, 5)).toUpperCase();
    }
  }

  static int min(int a, int b) => a < b ? a : b;
}

class _TypeBadge extends StatelessWidget {
  final String label;
  final AppColors c;
  const _TypeBadge({required this.label, required this.c});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: c.surfaceHigh.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(label,
        style: TextStyle(color: c.textSecondary.withValues(alpha: 0.7), fontSize: 9)),
  );
}

class _FiltersBadge extends StatelessWidget {
  final int count;
  final AppColors c;
  const _FiltersBadge({required this.count, required this.c});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: c.primary.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text('${count}F',
        style: TextStyle(color: c.primary, fontSize: 9, fontWeight: FontWeight.w600)),
  );
}

class _LoadingOrEmpty extends StatelessWidget {
  final AppColors c;
  final AppLocalizations l;
  const _LoadingOrEmpty({required this.c, required this.l});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: Text(l.noData,
          style: TextStyle(color: c.textSecondary.withValues(alpha: 0.5), fontSize: 12)),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// CHART BODY (dispatches to correct chart widget)
// ═════════════════════════════════════════════════════════════════════════════

class _ChartBody extends StatelessWidget {
  final _ChartData data;
  final AppColors c;
  final AppLocalizations l;
  const _ChartBody({required this.data, required this.c, required this.l});

  @override
  Widget build(BuildContext context) {
    // KPI / single value
    if (data.singleValue != null) {
      return _KpiCard(data: data, c: c);
    }

    if (data.labels.isEmpty || data.datasets.isEmpty) {
      return _LoadingOrEmpty(c: c, l: l);
    }

    final type = data.chartType.toLowerCase();

    if (type == 'pie' || type == 'donut' || type == 'percentage') {
      return _PieChartCard(
          data: data, isDonut: type != 'pie', c: c, l: l);
    }

    return Column(children: [
      if (type == 'bar')
        _BarChartCard(data: data, c: c)
      else
        _LineChartCard(data: data, c: c),
      _DataTableCard(data: data, c: c, l: l),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// KPI CARD
// ═════════════════════════════════════════════════════════════════════════════

class _KpiCard extends StatelessWidget {
  final _ChartData data;
  final AppColors c;
  const _KpiCard({required this.data, required this.c});

  String _fmt(dynamic v, String? ft) {
    if (v == null) return '—';
    final d = (v as num).toDouble();
    if (d.abs() >= 1e9) return '${(d / 1e9).toStringAsFixed(2)}B';
    if (d.abs() >= 1e6) return '${(d / 1e6).toStringAsFixed(1)}M';
    if (d.abs() >= 1000) return '${(d / 1000).toStringAsFixed(0)}K';
    if (ft == 'Currency' || ft == 'Float') return d.toStringAsFixed(2);
    return d.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
    child: Row(children: [
      Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: c.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.tag_rounded, color: c.primary, size: 24),
      ),
      const SizedBox(width: 16),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          _fmt(data.singleValue, data.fieldtype),
          style: TextStyle(
            color: c.textPrimary, fontSize: 32,
            fontWeight: FontWeight.w800, letterSpacing: -1,
          ),
        ),
        Text(
          data.chartType.toUpperCase(),
          style: TextStyle(
            color: c.textSecondary.withValues(alpha: 0.6),
            fontSize: 11, letterSpacing: 1.5,
          ),
        ),
      ]),
    ]),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// BAR CHART (fl_chart)
// ═════════════════════════════════════════════════════════════════════════════

class _BarChartCard extends StatefulWidget {
  final _ChartData data;
  final AppColors c;
  const _BarChartCard({required this.data, required this.c});

  @override
  State<_BarChartCard> createState() => _BarChartCardState();
}

class _BarChartCardState extends State<_BarChartCard> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gridColor = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06);
    final labelColor = isDark ? const Color(0x9994A3B8) : const Color(0x99475569);

    final vals = data.datasets.isNotEmpty ? data.datasets.first.values : <double>[];
    final n = vals.length.clamp(0, data.labels.length);
    if (n == 0) return const SizedBox.shrink();

    final maxY = vals.isEmpty ? 1.0 : vals.reduce(max).clamp(0.001, double.infinity);

    // Show every Nth label to avoid overlap
    final skipStep = _skipStep(n);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
      child: SizedBox(
        height: 200,
        child: BarChart(
          BarChartData(
            maxY: maxY * 1.15,
            barTouchData: BarTouchData(
              touchCallback: (ev, resp) {
                setState(() => _touchedIndex =
                    resp?.spot?.touchedBarGroupIndex ?? -1);
              },
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (_, _, rod, _) => BarTooltipItem(
                  _fmtAxis(rod.toY),
                  TextStyle(color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
            barGroups: List.generate(n, (i) {
              final touched = i == _touchedIndex;
              return BarChartGroupData(
                x: i,
                barRods: [BarChartRodData(
                  toY: vals[i].clamp(0, double.infinity),
                  color: touched
                      ? _pal(0).withValues(alpha: 1)
                      : _pal(0).withValues(alpha: 0.8),
                  width: _barWidth(n),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                )],
              );
            }),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= data.labels.length) return const SizedBox.shrink();
                  if (idx % skipStep != 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_shortLabel(data.labels[idx]),
                        style: TextStyle(color: labelColor, fontSize: 9)),
                  );
                },
              )),
              leftTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (v, _) => Text(_fmtAxis(v),
                    style: TextStyle(color: labelColor, fontSize: 9)),
              )),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: gridColor, strokeWidth: 0.8),
            ),
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// LINE CHART (fl_chart)
// ═════════════════════════════════════════════════════════════════════════════

class _LineChartCard extends StatelessWidget {
  final _ChartData data;
  final AppColors c;
  const _LineChartCard({required this.data, required this.c});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gridColor = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06);
    final labelColor = isDark ? const Color(0x9994A3B8) : const Color(0x99475569);

    final n = data.labels.length;
    if (n < 2) return const SizedBox.shrink();

    double maxY = 0.001;
    for (final ds in data.datasets) {
      if (ds.values.isNotEmpty) maxY = max(maxY, ds.values.reduce(max));
    }

    final skipStep = _skipStep(n);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
      child: SizedBox(
        height: 200,
        child: LineChart(
          LineChartData(
            minX: 0, maxX: (n - 1).toDouble(),
            minY: 0, maxY: maxY * 1.15,
            lineBarsData: List.generate(
              data.datasets.length.clamp(0, _kPalette.length),
              (di) {
                final ds = data.datasets[di];
                final color = _pal(di);
                return LineChartBarData(
                  spots: List.generate(
                    ds.values.length.clamp(0, n),
                    (i) => FlSpot(i.toDouble(), ds.values[i].clamp(0, double.infinity)),
                  ),
                  color: color,
                  barWidth: 2.5,
                  isCurved: true,
                  curveSmoothness: 0.3,
                  dotData: FlDotData(
                    show: n <= 12,
                    getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                      radius: 3, color: color,
                      strokeColor: c.surface, strokeWidth: 1.5,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: data.datasets.length == 1,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0)],
                    ),
                  ),
                );
              },
            ),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, reservedSize: 28,
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= data.labels.length) return const SizedBox.shrink();
                  if (idx % skipStep != 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_shortLabel(data.labels[idx]),
                        style: TextStyle(color: labelColor, fontSize: 9)),
                  );
                },
              )),
              leftTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, reservedSize: 44,
                getTitlesWidget: (v, _) => Text(_fmtAxis(v),
                    style: TextStyle(color: labelColor, fontSize: 9)),
              )),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: FlGridData(
              show: true, drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: gridColor, strokeWidth: 0.8),
            ),
            borderData: FlBorderData(show: false),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                  _fmtAxis(s.y),
                  const TextStyle(color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w600),
                )).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PIE / DONUT CHART (fl_chart)
// ═════════════════════════════════════════════════════════════════════════════

class _PieChartCard extends StatefulWidget {
  final _ChartData data;
  final bool isDonut;
  final AppColors c;
  final AppLocalizations l;
  const _PieChartCard({
    required this.data, required this.isDonut,
    required this.c, required this.l,
  });

  @override
  State<_PieChartCard> createState() => _PieChartCardState();
}

class _PieChartCardState extends State<_PieChartCard> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final c = widget.c;

    final vals = data.datasets.isNotEmpty
        ? data.datasets.first.values
        : <double>[];
    final n = vals.length.clamp(0, data.labels.length);
    if (n == 0) return _LoadingOrEmpty(c: c, l: widget.l);

    final total = vals.fold(0.0, (a, b) => a + b);

    return Column(children: [
      SizedBox(
        height: 200,
        child: PieChart(
          PieChartData(
            pieTouchData: PieTouchData(
              touchCallback: (ev, resp) => setState(() =>
                  _touchedIndex = resp?.touchedSection?.touchedSectionIndex ?? -1),
            ),
            sections: List.generate(n, (i) {
              final touched = i == _touchedIndex;
              final pct = total > 0 ? vals[i] / total * 100 : 0.0;
              return PieChartSectionData(
                value: vals[i],
                color: _pal(i),
                radius: widget.isDonut
                    ? (touched ? 58 : 50)
                    : (touched ? 90 : 80),
                title: pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
                titleStyle: const TextStyle(
                    color: Colors.white, fontSize: 11,
                    fontWeight: FontWeight.w600),
              );
            }),
            centerSpaceRadius: widget.isDonut ? 48 : 0,
            sectionsSpace: 2,
          ),
        ),
      ),
      // Legend
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Wrap(spacing: 12, runSpacing: 6,
          children: List.generate(n, (i) => Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10,
                decoration: BoxDecoration(color: _pal(i), shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(_shortLabel(data.labels[i]),
                style: TextStyle(color: c.textSecondary, fontSize: 10)),
          ])),
        ),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// DATA TABLE
// ═════════════════════════════════════════════════════════════════════════════

class _DataTableCard extends StatefulWidget {
  final _ChartData data;
  final AppColors c;
  final AppLocalizations l;
  const _DataTableCard({required this.data, required this.c, required this.l});

  @override
  State<_DataTableCard> createState() => _DataTableCardState();
}

class _DataTableCardState extends State<_DataTableCard> {
  bool _expanded = false;
  static const _kMaxRows = 5;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final c = widget.c;
    final l = widget.l;

    final n = data.labels.length;
    final rowCount = _expanded ? n : n.clamp(0, _kMaxRows);
    final hasMore = n > _kMaxRows;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Divider(color: c.surfaceHigh, height: 1),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 32,
          dataRowMinHeight: 28,
          dataRowMaxHeight: 32,
          columnSpacing: 16,
          headingTextStyle: TextStyle(
              color: c.textSecondary.withValues(alpha: 0.7),
              fontSize: 10, fontWeight: FontWeight.w600),
          dataTextStyle: TextStyle(color: c.textPrimary, fontSize: 11),
          columns: [
            DataColumn(label: Text(l.period)),
            ...data.datasets.map((ds) => DataColumn(
              label: Text(ds.name.isNotEmpty ? ds.name : l.value),
              numeric: true,
            )),
          ],
          rows: List.generate(rowCount, (i) => DataRow(
            color: WidgetStateProperty.resolveWith((states) =>
                i.isEven ? c.surfaceHigh.withValues(alpha: 0.25) : Colors.transparent),
            cells: [
              DataCell(Text(data.labels[i],
                  style: TextStyle(color: c.textSecondary, fontSize: 10))),
              ...data.datasets.map((ds) => DataCell(Text(
                i < ds.values.length ? _fmtAxis(ds.values[i]) : '—',
                style: TextStyle(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w500, fontSize: 11),
              ))),
            ],
          )),
        ),
      ),
      if (hasMore)
        TextButton(
          onPressed: () => setState(() => _expanded = !_expanded),
          child: Text(
            _expanded ? l.showLess : '+ ${n - _kMaxRows} more',
            style: TextStyle(color: c.primary, fontSize: 11),
          ),
        ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PENDING APPROVALS WIDGET
// ═════════════════════════════════════════════════════════════════════════════

class _PendingWidget extends StatelessWidget {
  final int count;
  final AppColors c;
  final AppLocalizations l;
  const _PendingWidget({required this.count, required this.c, required this.l});

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.warning.withValues(alpha: 0.1),
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: () => Navigator.pushNamed(context, '/pending-approvals'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.approval_rounded,
                color: AppColors.warning, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.wfPendingApprovals,
                  style: TextStyle(color: c.textPrimary,
                      fontSize: 13, fontWeight: FontWeight.w600)),
              Text(
                l.isArabic ? '$count بند في الانتظار' : '$count pending',
                style: const TextStyle(color: AppColors.warning,
                    fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ]),
          ),
          Icon(Icons.chevron_right_rounded,
              color: AppColors.warning.withValues(alpha: 0.7), size: 18),
        ]),
      ),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// FILTER STRIP (mobile — compact bar under AppBar)
// ═════════════════════════════════════════════════════════════════════════════

class _FilterStrip extends StatelessWidget {
  final String timespan, timegrain, fromDate, toDate, company;
  final bool useDateRange;
  final VoidCallback onTap;
  final AppColors c;
  final AppLocalizations l;
  const _FilterStrip({
    required this.timespan, required this.timegrain,
    required this.useDateRange, required this.fromDate, required this.toDate,
    required this.company, required this.onTap,
    required this.c, required this.l,
  });

  @override
  Widget build(BuildContext context) {
    final label = useDateRange && fromDate.isNotEmpty && toDate.isNotEmpty
        ? '$fromDate → $toDate'
        : l.timespanLabel(timespan);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: c.surfaceHigh.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.surfaceHigh),
        ),
        child: Row(children: [
          Icon(Icons.date_range_rounded,
              size: 14, color: c.textSecondary.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label  ·  ${l.timegrainLabel(timegrain)}',
              style: TextStyle(
                  color: c.textSecondary.withValues(alpha: 0.7), fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (company.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(company,
                  style: TextStyle(color: c.primary, fontSize: 10,
                      fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
          ],
          Icon(Icons.tune_rounded, size: 14,
              color: c.textSecondary.withValues(alpha: 0.5)),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// FILTER SIDEBAR (web — left panel)
// ═════════════════════════════════════════════════════════════════════════════

class _FilterSidebar extends StatefulWidget {
  final String timespan, timegrain, fromDate, toDate, company;
  final bool useDateRange;
  final List<String> companies;
  final int pendingCount;
  final AppColors c;
  final AppLocalizations l;
  final void Function({
    String? timespan, String? timegrain, bool? useDateRange,
    String? fromDate, String? toDate, String? company,
  }) onApply;

  const _FilterSidebar({
    required this.timespan, required this.timegrain,
    required this.useDateRange, required this.fromDate, required this.toDate,
    required this.company, required this.companies,
    required this.pendingCount,
    required this.c, required this.l, required this.onApply,
  });

  @override
  State<_FilterSidebar> createState() => _FilterSidebarState();
}

class _FilterSidebarState extends State<_FilterSidebar> {
  late String _timespan, _timegrain, _fromDate, _toDate, _company;
  late bool _useDateRange;
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _timespan   = widget.timespan;
    _timegrain  = widget.timegrain;
    _useDateRange = widget.useDateRange;
    _fromDate   = widget.fromDate;
    _toDate     = widget.toDate;
    _company    = widget.company;
  }

  void _apply() => widget.onApply(
    timespan: _timespan, timegrain: _timegrain,
    useDateRange: _useDateRange, fromDate: _fromDate,
    toDate: _toDate, company: _company,
  );

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final l = widget.l;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _collapsed ? 48 : 220,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(right: BorderSide(color: c.surfaceHigh)),
      ),
      child: _collapsed
          ? _buildCollapsed(c, l)
          : _buildExpanded(c, l),
    );
  }

  Widget _buildCollapsed(AppColors c, AppLocalizations l) => Column(children: [
    IconButton(
      icon: Icon(Icons.menu_open_rounded, color: c.primary),
      onPressed: () => setState(() => _collapsed = false),
      tooltip: l.changeFilters,
    ),
  ]);

  Widget _buildExpanded(AppColors c, AppLocalizations l) => Column(children: [
    // Header
    Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
      child: Row(children: [
        Icon(Icons.tune_rounded, size: 16, color: c.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(l.changeFilters,
            style: TextStyle(color: c.textPrimary, fontSize: 13,
                fontWeight: FontWeight.w600))),
        IconButton(
          icon: Icon(Icons.chevron_left_rounded, color: c.textSecondary),
          onPressed: () => setState(() => _collapsed = true),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
    ),
    Divider(color: c.surfaceHigh, height: 1),

    // Pending approvals shortcut
    if (widget.pendingCount > 0) ...[
      Padding(
        padding: const EdgeInsets.all(10),
        child: _PendingWidget(count: widget.pendingCount, c: c, l: l),
      ),
      Divider(color: c.surfaceHigh, height: 1),
    ],

    // Filters content (scrollable)
    Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Company
          if (widget.companies.isNotEmpty) ...[
            Text(l.dashCompany, style: _sectionLabel(c)),
            const SizedBox(height: 6),
            _CompanyDropdown(
              company: _company, companies: widget.companies, c: c,
              onChanged: (v) { setState(() => _company = v); _apply(); },
            ),
            const SizedBox(height: 14),
          ],

          // Timespan
          Text(l.timespan, style: _sectionLabel(c)),
          const SizedBox(height: 6),
          _TimespanGroup(
            timespan: _timespan, c: c,
            onChanged: (v) { setState(() { _timespan = v; _useDateRange = false; }); _apply(); },
          ),
          const SizedBox(height: 14),

          // Timegrain
          Text(l.timegrain, style: _sectionLabel(c)),
          const SizedBox(height: 6),
          _TimegrainGroup(
            timegrain: _timegrain, c: c,
            onChanged: (v) { setState(() => _timegrain = v); _apply(); },
          ),
        ]),
      ),
    ),
  ]);

  TextStyle _sectionLabel(AppColors c) => TextStyle(
    color: c.textSecondary.withValues(alpha: 0.6),
    fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2,
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// FILTERS BOTTOM SHEET (mobile)
// ═════════════════════════════════════════════════════════════════════════════

class _FiltersSheet extends StatefulWidget {
  final String timespan, timegrain, fromDate, toDate, company;
  final bool useDateRange;
  final List<String> companies;
  final void Function(String, String, bool, String, String, String) onApply;

  const _FiltersSheet({
    required this.timespan, required this.timegrain,
    required this.useDateRange, required this.fromDate, required this.toDate,
    required this.company, required this.companies, required this.onApply,
  });

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late String _timespan, _timegrain, _fromDate, _toDate, _company;
  late bool _useDateRange;

  @override
  void initState() {
    super.initState();
    _timespan   = widget.timespan;
    _timegrain  = widget.timegrain;
    _useDateRange = widget.useDateRange;
    _fromDate   = widget.fromDate;
    _toDate     = widget.toDate;
    _company    = widget.company;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l = AppLocalizations.of(context);
    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.4,
      builder: (_, ctrl) => Column(children: [
        // Handle
        Center(child: Container(
          width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: c.surfaceHigh, borderRadius: BorderRadius.circular(2)),
        )),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: Text(l.changeFilters,
                style: TextStyle(color: c.textPrimary, fontSize: 16,
                    fontWeight: FontWeight.w700))),
            TextButton(
              onPressed: () {
                setState(() {
                  _timespan = 'Last Year'; _timegrain = 'Monthly';
                  _useDateRange = false; _fromDate = ''; _toDate = ''; _company = '';
                });
              },
              child: Text(l.relative,
                  style: TextStyle(color: c.textSecondary, fontSize: 12)),
            ),
          ]),
        ),
        Divider(color: c.surfaceHigh),

        Expanded(
          child: ListView(controller: ctrl, padding: const EdgeInsets.all(16),
            children: [
              // Company
              if (widget.companies.isNotEmpty) ...[
                _sheetSection(l.dashCompany, c),
                const SizedBox(height: 6),
                _CompanyDropdown(
                  company: _company, companies: widget.companies, c: c,
                  onChanged: (v) => setState(() => _company = v),
                ),
                const SizedBox(height: 16),
              ],

              // Filter mode
              _sheetSection(l.filterMode, c),
              const SizedBox(height: 8),
              _ModeToggle(
                useDateRange: _useDateRange, c: c, l: l,
                onChanged: (v) => setState(() => _useDateRange = v),
              ),
              const SizedBox(height: 16),

              if (!_useDateRange) ...[
                _sheetSection(l.timespan, c),
                const SizedBox(height: 8),
                _TimespanGroup(
                  timespan: _timespan, c: c,
                  onChanged: (v) => setState(() => _timespan = v),
                ),
                const SizedBox(height: 16),
              ] else ...[
                _sheetSection(l.dateRange, c),
                const SizedBox(height: 8),
                _DateRow(
                  fromDate: _fromDate, toDate: _toDate, c: c, l: l,
                  onFromChanged: (v) => setState(() => _fromDate = v),
                  onToChanged: (v) => setState(() => _toDate = v),
                ),
                const SizedBox(height: 16),
              ],

              // Timegrain
              _sheetSection(l.timegrain, c),
              const SizedBox(height: 8),
              _TimegrainGroup(
                timegrain: _timegrain, c: c,
                onChanged: (v) => setState(() => _timegrain = v),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),

        // Apply button
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 16),
          child: SizedBox(width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: c.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(context);
                widget.onApply(_timespan, _timegrain, _useDateRange,
                    _fromDate, _toDate, _company);
              },
              child: Text(l.changeFilters, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _sheetSection(String label, AppColors c) => Text(
    label,
    style: TextStyle(color: c.textSecondary.withValues(alpha: 0.6),
        fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// PER-CHART FILTERS SHEET
// ═════════════════════════════════════════════════════════════════════════════

class _ChartFiltersSheet extends StatefulWidget {
  final String chartName, documentType;
  final List<List<String>> initialFilters;
  final void Function(List<List<String>>) onApply;
  const _ChartFiltersSheet({
    required this.chartName, required this.documentType,
    required this.initialFilters, required this.onApply,
  });

  @override
  State<_ChartFiltersSheet> createState() => _ChartFiltersSheetState();
}

class _ChartFiltersSheetState extends State<_ChartFiltersSheet> {
  late List<List<String>> _filters;

  @override
  void initState() {
    super.initState();
    _filters = widget.initialFilters.map(List<String>.from).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l = AppLocalizations.of(context);
    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.7, maxChildSize: 0.95, minChildSize: 0.4,
      builder: (_, ctrl) => Column(children: [
        Center(child: Container(
          width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: c.surfaceHigh,
              borderRadius: BorderRadius.circular(2)),
        )),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: Text(widget.chartName,
                style: TextStyle(color: c.textPrimary, fontSize: 15,
                    fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis)),
            if (_filters.isNotEmpty)
              TextButton(
                onPressed: () => setState(() => _filters.clear()),
                child: Text(l.relative,
                    style: TextStyle(color: AppColors.error, fontSize: 12)),
              ),
          ]),
        ),
        Divider(color: c.surfaceHigh),

        Expanded(
          child: ListView(controller: ctrl, padding: const EdgeInsets.all(16),
            children: [
              ..._filters.asMap().entries.map((en) => _FilterRow(
                filter: en.value,
                onDelete: () => setState(() => _filters.removeAt(en.key)),
                c: c, l: l,
              )),
              OutlinedButton.icon(
                onPressed: () => setState(() => _filters.add(['', '=', ''])),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(l.relative),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.primary,
                  side: BorderSide(color: c.primary.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),

        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 16),
          child: SizedBox(width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: c.primary, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(context);
                widget.onApply(_filters.where((f) =>
                    f.length == 3 && f[0].isNotEmpty).toList());
              },
              child: Text(l.changeFilters, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final List<String> filter;
  final VoidCallback onDelete;
  final AppColors c;
  final AppLocalizations l;
  const _FilterRow({required this.filter, required this.onDelete, required this.c, required this.l});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Expanded(flex: 3, child: _smallField(filter.isNotEmpty ? filter[0] : '', l.period, c,
          (v) { if (filter.isNotEmpty) filter[0] = v; })),
      const SizedBox(width: 6),
      SizedBox(width: 60, child: _smallField(filter.length > 1 ? filter[1] : '=', '=', c,
          (v) { if (filter.length > 1) filter[1] = v; })),
      const SizedBox(width: 6),
      Expanded(flex: 3, child: _smallField(filter.length > 2 ? filter[2] : '', l.value, c,
          (v) { if (filter.length > 2) filter[2] = v; })),
      IconButton(
        icon: Icon(Icons.close_rounded, size: 16, color: c.textSecondary),
        onPressed: onDelete,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(),
      ),
    ]),
  );

  Widget _smallField(String init, String hint, AppColors c, void Function(String) onChanged) =>
      TextFormField(
        initialValue: init,
        onChanged: onChanged,
        style: TextStyle(color: c.textPrimary, fontSize: 12),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: c.textSecondary, fontSize: 12),
          filled: true, fillColor: c.surfaceHigh,
          isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// SHARED FILTER WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

class _CompanyDropdown extends StatelessWidget {
  final String company;
  final List<String> companies;
  final AppColors c;
  final void Function(String) onChanged;
  const _CompanyDropdown({required this.company, required this.companies,
      required this.c, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    decoration: BoxDecoration(
      color: c.surfaceHigh, borderRadius: BorderRadius.circular(10)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: companies.contains(company) ? company : null,
        isExpanded: true,
        hint: Text('—', style: TextStyle(color: c.textSecondary, fontSize: 13)),
        style: TextStyle(color: c.textPrimary, fontSize: 13),
        dropdownColor: c.surface,
        items: [
          DropdownMenuItem(value: '', child: Text('—', style: TextStyle(color: c.textSecondary))),
          ...companies.map((co) => DropdownMenuItem(value: co, child: Text(co))),
        ],
        onChanged: (v) => onChanged(v ?? ''),
      ),
    ),
  );
}

class _ModeToggle extends StatelessWidget {
  final bool useDateRange;
  final AppColors c;
  final AppLocalizations l;
  final void Function(bool) onChanged;
  const _ModeToggle({required this.useDateRange, required this.c, required this.l,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: _ModeBtn(
      label: l.relative, active: !useDateRange, c: c,
      onTap: () => onChanged(false),
    )),
    const SizedBox(width: 8),
    Expanded(child: _ModeBtn(
      label: l.dateRangeShort, active: useDateRange, c: c,
      onTap: () => onChanged(true),
    )),
  ]);
}

class _ModeBtn extends StatelessWidget {
  final String label;
  final bool active;
  final AppColors c;
  final VoidCallback onTap;
  const _ModeBtn({required this.label, required this.active, required this.c, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: active ? c.primary : c.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(child: Text(label,
          style: TextStyle(
            color: active ? Colors.white : c.textSecondary,
            fontSize: 12, fontWeight: FontWeight.w600))),
    ),
  );
}

class _TimespanGroup extends StatelessWidget {
  static const _options = ['Last Week', 'Last Month', 'Last Quarter', 'Last Year'];
  final String timespan;
  final AppColors c;
  final void Function(String) onChanged;
  const _TimespanGroup({required this.timespan, required this.c, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Wrap(spacing: 6, runSpacing: 6,
      children: _options.map((o) => _ChoiceChip(
        label: l.timespanLabel(o), selected: timespan == o, c: c,
        onTap: () => onChanged(o),
      )).toList(),
    );
  }
}

class _TimegrainGroup extends StatelessWidget {
  static const _options = ['Daily', 'Weekly', 'Monthly', 'Quarterly', 'Yearly'];
  final String timegrain;
  final AppColors c;
  final void Function(String) onChanged;
  const _TimegrainGroup({required this.timegrain, required this.c, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Wrap(spacing: 6, runSpacing: 6,
      children: _options.map((o) => _ChoiceChip(
        label: l.timegrainLabel(o), selected: timegrain == o, c: c,
        onTap: () => onChanged(o),
      )).toList(),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final AppColors c;
  final VoidCallback onTap;
  const _ChoiceChip({required this.label, required this.selected,
      required this.c, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? c.primary : Colors.transparent,
        border: Border.all(color: selected ? c.primary : c.surfaceHigh, width: 1.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
            color: selected ? Colors.white : c.textSecondary,
            fontSize: 12, fontWeight: FontWeight.w600,
          )),
    ),
  );
}

class _DateRow extends StatelessWidget {
  final String fromDate, toDate;
  final AppColors c;
  final AppLocalizations l;
  final void Function(String) onFromChanged, onToChanged;
  const _DateRow({required this.fromDate, required this.toDate,
      required this.c, required this.l,
      required this.onFromChanged, required this.onToChanged});

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: _DatePickerButton(
      label: l.from, date: fromDate, c: c, l: l,
      onPicked: onFromChanged,
    )),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text('→', style: TextStyle(color: c.textSecondary)),
    ),
    Expanded(child: _DatePickerButton(
      label: l.to, date: toDate, c: c, l: l,
      onPicked: onToChanged,
    )),
  ]);
}

class _DatePickerButton extends StatelessWidget {
  final String label, date;
  final AppColors c;
  final AppLocalizations l;
  final void Function(String) onPicked;
  const _DatePickerButton({required this.label, required this.date,
      required this.c, required this.l, required this.onPicked});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: date.isNotEmpty ? DateTime.tryParse(date) ?? DateTime.now() : DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        builder: (ctx, child) => Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.fromSeed(seedColor: c.primary),
          ),
          child: child!,
        ),
      );
      if (picked != null) {
        onPicked('${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
      }
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surfaceHigh, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(
            color: c.textSecondary.withValues(alpha: 0.6), fontSize: 9,
            fontWeight: FontWeight.w600, letterSpacing: 0.8)),
        const SizedBox(height: 2),
        Text(date.isEmpty ? l.selectDate : date,
            style: TextStyle(color: date.isEmpty ? c.textSecondary : c.textPrimary,
                fontSize: 12, fontWeight: FontWeight.w500)),
      ]),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// ERROR STATE
// ═════════════════════════════════════════════════════════════════════════════

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  final AppColors c;
  final AppLocalizations l;
  const _ErrorState({required this.error, required this.onRetry, required this.c, required this.l});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.cloud_off_rounded, color: c.textSecondary, size: 52),
        const SizedBox(height: 12),
        Text(error, style: TextStyle(color: c.textSecondary, fontSize: 13),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l.retry),
        ),
      ]),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// FORMATTING HELPERS
// ═════════════════════════════════════════════════════════════════════════════

String _fmtAxis(double v) {
  if (v.abs() >= 1e9) return '${(v / 1e9).toStringAsFixed(1)}B';
  if (v.abs() >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
  if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
  if (v == v.truncateToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(1);
}

String _shortLabel(String s) {
  if (s.length <= 10) return s;
  // Try to extract year or short part
  final parts = s.split('-');
  if (parts.length >= 2) return parts.sublist(0, 2).join('-');
  return s.substring(0, 8);
}

double _barWidth(int n) {
  if (n <= 6)  return 24;
  if (n <= 12) return 16;
  if (n <= 24) return 10;
  return 6;
}

int _skipStep(int n) {
  if (n <= 12) return 1;
  if (n <= 24) return 2;
  if (n <= 52) return 4;
  return (n / 10).ceil();
}
