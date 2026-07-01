import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'app_colors.dart';
import 'aurora_widgets.dart';
import 'report_view_page.dart';

// ---------------------------------------------------------------------------
// Report entry model
// ---------------------------------------------------------------------------
class _ReportEntry {
  final String name;
  final String reportType;
  final String refDoctype;

  const _ReportEntry({
    required this.name,
    required this.reportType,
    required this.refDoctype,
  });
}

// ---------------------------------------------------------------------------
// ModuleReportsPage
// ---------------------------------------------------------------------------
class ModuleReportsPage extends StatefulWidget {
  final String workspaceName;
  final String? moduleName;
  final IconData workspaceIcon;

  const ModuleReportsPage({
    super.key,
    required this.workspaceName,
    required this.moduleName,
    required this.workspaceIcon,
  });

  @override
  State<ModuleReportsPage> createState() => _ModuleReportsPageState();
}

class _ModuleReportsPageState extends State<ModuleReportsPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<_ReportEntry> _reports = [];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final baseUrl = await ApiService.getErpNextUrl();
      final headers = await ApiService.getAuthHeaders();
      final base = Uri.parse(baseUrl);

      Uri buildUri(String path, Map<String, String> params) => Uri(
            scheme: base.scheme,
            host: base.host,
            port: base.hasPort ? base.port : null,
            path: path,
            queryParameters: params,
          );

      // ── Step 1: fetch all reports for this module ──────────────────────
      // No is_standard filter — include all active reports for the module.
      final module = widget.moduleName ?? widget.workspaceName;
      final reportsRes = await http
          .get(
            buildUri('/api/resource/Report', {
              'fields': '["name","report_name","report_type","ref_doctype"]',
              'filters': '[["module","=","$module"],["disabled","!=","1"]]',
              'limit': '200',
              'order_by': 'report_name asc',
            }),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      if (reportsRes.statusCode != 200) {
        setState(() {
          _errorMessage = 'Failed to load reports (${reportsRes.statusCode})';
          _isLoading = false;
        });
        return;
      }

      final rawReports =
          (jsonDecode(reportsRes.body)['data'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

      if (rawReports.isEmpty) {
        setState(() {
          _reports = [];
          _isLoading = false;
        });
        return;
      }

      // ── Step 2: check read permission per unique ref_doctype ───────────
      // Strategy: attempt GET /api/resource/{doctype}?limit=1
      //   → 200  : user has read permission
      //   → other: no permission
      // This is the most reliable method — it uses the same permission layer
      // that ERPNext itself uses when loading list views.
      final refDoctypes = rawReports
          .map((r) => r['ref_doctype'] as String? ?? '')
          .where((d) => d.isNotEmpty)
          .toSet();

      final permChecks = await Future.wait(
        refDoctypes.map((doctype) async {
          try {
            final res = await http
                .get(
                  buildUri('/api/resource/$doctype', {
                    'fields': '["name"]',
                    'limit': '1',
                  }),
                  headers: headers,
                )
                .timeout(const Duration(seconds: 10));
            return MapEntry(doctype, res.statusCode == 200);
          } catch (_) {
            return MapEntry(doctype, false);
          }
        }),
      );

      final permMap = Map<String, bool>.fromEntries(permChecks);

      // ── Step 3: keep only reports the user can access ──────────────────
      final permitted = rawReports
          .where((r) {
            final ref = r['ref_doctype'] as String? ?? '';
            // If no ref_doctype, include by default (e.g. some script reports)
            if (ref.isEmpty) return true;
            return permMap[ref] == true;
          })
          .map((r) => _ReportEntry(
                name: r['report_name'] as String? ??
                    r['name'] as String? ??
                    '',
                reportType: r['report_type'] as String? ?? '',
                refDoctype: r['ref_doctype'] as String? ?? '',
              ))
          .toList();

      setState(() {
        _reports = permitted;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      appBar: GradientAppBar(
        title: Text(widget.workspaceName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadReports,
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white54, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadReports,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.workspaceIcon, size: 64, color: Colors.white38),
            const SizedBox(height: 16),
            const Text(
              'No accessible reports found for this module.',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadReports,
      color: AppColors.of(context).primary,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Count badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_open,
                    color: Colors.greenAccent, size: 18),
                const SizedBox(width: 8),
                Text(
                  '${_reports.length} accessible report${_reports.length == 1 ? '' : 's'}',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ..._reports.map((r) => _ReportTile(report: r)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Report list tile
// ---------------------------------------------------------------------------
class _ReportTile extends StatelessWidget {
  final _ReportEntry report;

  const _ReportTile({required this.report});

  static IconData _typeIcon(String type) {
    switch (type) {
      case 'Report Builder':
        return Icons.table_chart;
      case 'Query Report':
        return Icons.manage_search;
      case 'Script Report':
        return Icons.bar_chart;
      case 'Custom Report':
        return Icons.tune;
      default:
        return Icons.description;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Colors.greenAccent.withValues(alpha: 0.35)),
      ),
      child: ListTile(
        leading:
            Icon(_typeIcon(report.reportType), color: Colors.white70),
        title: Text(
          report.name,
          style: TextStyle(color: Colors.white, fontSize: 13),
        ),
        subtitle: Text(
          '${report.reportType}  ·  ${report.refDoctype}',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        trailing: const Icon(Icons.arrow_forward_ios,
            color: Colors.white38, size: 14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReportViewPage(
              reportName: report.name,
              reportType: report.reportType,
            ),
          ),
        ),
      ),
    );
  }
}
