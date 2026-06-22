import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'app_colors.dart';
import 'app_drawer.dart';
import 'app_localizations.dart';
import 'auth_state.dart';
import 'dashboards_page.dart';
import 'module_permission_page.dart';
import 'module_reports_page.dart';

// ---------------------------------------------------------------------------
// Internal model — one entry per workspace
// ---------------------------------------------------------------------------
class _WorkspaceEntry {
  final String name;
  final String? module;
  final IconData icon;
  final bool permitted;
  final String reason;

  const _WorkspaceEntry({
    required this.name,
    required this.module,
    required this.icon,
    required this.permitted,
    required this.reason,
  });
}

// ---------------------------------------------------------------------------
// ModulesPage
// ---------------------------------------------------------------------------
class ModulesPage extends StatefulWidget {
  const ModulesPage({super.key});

  @override
  State<ModulesPage> createState() => _ModulesPageState();
}

class _ModulesPageState extends State<ModulesPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<_WorkspaceEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadModules();
  }

  Future<void> _loadModules() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final baseUrl = await ApiService.getErpNextUrl();
      final headers = await ApiService.getAuthHeaders();

      // Use Frappe's official API — filters workspaces server-side
      // based on the logged-in user's roles and permissions.
      final res = await http
          .get(
            Uri.parse(
                '$baseUrl/api/method/frappe.desk.desktop.get_workspace_sidebar_items'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        setState(() {
          _errorMessage = 'Failed to load workspaces (${res.statusCode})';
          _isLoading = false;
        });
        return;
      }

      final message = jsonDecode(res.body)['message'] as Map? ?? {};
      final pages = (message['pages'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final entries = pages.map((ws) {
        final name = ws['name'] as String? ?? '';
        final mod  = ws['module'] as String?;
        return _WorkspaceEntry(
          name:      name,
          module:    mod,
          icon:      _iconFor(mod ?? name),
          permitted: true,
          reason:    '__full__',
        );
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    await ApiService.logout();
    AuthState.isLoggedIn = false;
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  void _openPermissionPage(_WorkspaceEntry entry) {
    final l = AppLocalizations.of(context);
    if (entry.permitted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ModuleReportsPage(
            workspaceName: entry.name,
            moduleName: entry.module,
            workspaceIcon: entry.icon,
          ),
        ),
      );
    } else {
      // Translate the reason token
      String reason;
      if (entry.reason == '__blocked__') {
        reason = l.moduleBlocked;
      } else if (entry.reason.startsWith('__roles__:')) {
        reason = l.requiredRoles(entry.reason.substring(10));
      } else {
        reason = entry.reason;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ModulePermissionPage(
            moduleName: entry.name,
            icon: entry.icon,
            hasPermission: false,
            reason: reason,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      drawer: const AppDrawer(current: DrawerSection.modules),
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).modules),
        actions: [
          IconButton(
            icon: const Icon(Icons.smart_toy_outlined),
            tooltip: AppLocalizations.of(context).aiAssistant,
            onPressed: () => Navigator.pushNamed(context, '/ai-assistant'),
          ),
          IconButton(
            icon: const Icon(Icons.chat_outlined),
            tooltip: 'n8n Chat',
            onPressed: () => Navigator.pushNamed(context, '/n8n-chat'),
          ),
          IconButton(
            icon: const Icon(Icons.dashboard_outlined),
            tooltip: AppLocalizations.of(context).dashboards,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DashboardsPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AppLocalizations.of(context).refresh,
            onPressed: _isLoading ? null : _loadModules,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: AppLocalizations.of(context).logout,
            onPressed: _logout,
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
                onPressed: _loadModules,
                icon: const Icon(Icons.refresh),
                label: Text(AppLocalizations.of(context).retry),
              ),
            ],
          ),
        ),
      );
    }

    if (_entries.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).noModules,
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadModules,
      color: AppColors.of(context).primary,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.15,
        ),
        itemCount: _entries.length,
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return _ModuleCard(
            entry: entry,
            onTap: () => _openPermissionPage(entry),
          );
        },
      ),
    );
  }

  static IconData _iconFor(String module) {
    const map = <String, IconData>{
      'Accounts': Icons.account_balance,
      'Accounting': Icons.account_balance,
      'HR': Icons.people,
      'Human Resources': Icons.people,
      'Payroll': Icons.payments,
      'CRM': Icons.contacts,
      'Selling': Icons.sell,
      'Buying': Icons.shopping_cart,
      'Purchase': Icons.shopping_cart,
      'Stock': Icons.inventory_2,
      'Inventory': Icons.inventory_2,
      'Manufacturing': Icons.precision_manufacturing,
      'Projects': Icons.folder_special,
      'Support': Icons.support_agent,
      'Assets': Icons.business_center,
      'Quality': Icons.verified,
      'Loan Management': Icons.monetization_on,
      'ERPNext': Icons.apps,
      'Core': Icons.settings,
      'Website': Icons.language,
    };
    return map.entries
            .where((e) => module.toLowerCase().contains(e.key.toLowerCase()))
            .firstOrNull
            ?.value ??
        Icons.apps;
  }
}

// ---------------------------------------------------------------------------
// Module card with permission indicator
// ---------------------------------------------------------------------------
class _ModuleCard extends StatelessWidget {
  final _WorkspaceEntry entry;
  final VoidCallback onTap;

  const _ModuleCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final permitted = entry.permitted;
    final borderColor =
        permitted ? Colors.greenAccent : Colors.redAccent;

    return Card(
      color: Colors.white.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor.withValues(alpha: 0.6), width: 1.4),
      ),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          child: Stack(
            children: [
              // Permission badge — top-right corner
              Positioned(
                top: 0,
                right: 0,
                child: Icon(
                  permitted ? Icons.check_circle : Icons.cancel,
                  color: borderColor,
                  size: 18,
                ),
              ),

              // Card content
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(entry.icon, size: 40, color: Colors.white),
                    const SizedBox(height: 8),
                    Text(
                      entry.name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
