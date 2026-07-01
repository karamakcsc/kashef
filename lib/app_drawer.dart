import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'app_colors.dart';
import 'app_localizations.dart';
import 'auth_state.dart';
import 'aurora_widgets.dart';
import 'dashboards_page.dart';
import 'realtime_workflow_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Route identifiers — used to highlight the active item
// ─────────────────────────────────────────────────────────────────────────────
enum DrawerSection { modules, dashboards, aiAssistant, n8nChat, n8nWebhookChat, pendingApprovals, approvedApprovals, settings }

// ─────────────────────────────────────────────────────────────────────────────
// AppDrawer — shared side navigation drawer for all post-login pages
// ─────────────────────────────────────────────────────────────────────────────
class AppDrawer extends StatefulWidget {
  /// Pass the current section so it gets highlighted.
  final DrawerSection current;

  const AppDrawer({super.key, required this.current});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  String _username = '';
  String _url = '';
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUser();
    RealtimeWorkflowService().addListener(_onWorkflowEvent);
  }

  @override
  void dispose() {
    RealtimeWorkflowService().removeListener(_onWorkflowEvent);
    super.dispose();
  }

  void _onWorkflowEvent(Map<String, dynamic> _) {
    if (mounted) {
      setState(() => _pendingCount = RealtimeWorkflowService().pendingCount);
    }
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _username = prefs.getString('erpnext_username') ?? '';
        _url = prefs.getString('erpnext_url') ?? '';
        if (_url.startsWith('https://')) _url = _url.substring(8);
        if (_url.startsWith('http://'))  _url = _url.substring(7);
        _pendingCount = RealtimeWorkflowService().pendingCount;
      });
    }
  }

  Future<void> _logout() async {
    await ApiService.logout();
    AuthState.isLoggedIn = false;
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false);
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _go(DrawerSection target) {
    Navigator.pop(context); // close drawer first

    if (target == widget.current) return; // already here

    switch (target) {
      case DrawerSection.modules:
        Navigator.pushNamedAndRemoveUntil(
            context, '/modules', (r) => false);
        break;
      case DrawerSection.dashboards:
        // Push on top so back button returns to current page
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DashboardsPage()),
        );
        break;
      case DrawerSection.aiAssistant:
        Navigator.pushNamed(context, '/ai-assistant');
        break;
      case DrawerSection.n8nChat:
        Navigator.pushNamed(context, '/n8n-chat');
        break;
      case DrawerSection.n8nWebhookChat:
        Navigator.pushNamed(context, '/n8n-webhook-chat');
        break;
      case DrawerSection.pendingApprovals:
        Navigator.pushNamed(context, '/pending-approvals');
        break;
      case DrawerSection.approvedApprovals:
        Navigator.pushNamed(context, '/approved-approvals');
        break;
      case DrawerSection.settings:
        Navigator.pushNamed(context, '/settings');
        break;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Drawer(
      backgroundColor: AppColors.of(context).surface,
      child: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            _DrawerHeader(username: _username, url: _url),

            const SizedBox(height: 8),
            Divider(color: AppColors.of(context).surfaceHigh, height: 1),
            const SizedBox(height: 8),

            // ── Nav items ───────────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // dashboards — hidden (route + files preserved, re-enable by un-commenting)
                  // _NavItem(
                  //   icon: Icons.dashboard_rounded,
                  //   label: l.dashboards,
                  //   active: widget.current == DrawerSection.dashboards,
                  //   onTap: () => _go(DrawerSection.dashboards),
                  // ),
                  const _SectionDivider(label: 'AI'),
                  _NavItem(
                    icon: Icons.approval_rounded,
                    label: AppLocalizations.of(context).wfPendingApprovals,
                    active: widget.current == DrawerSection.pendingApprovals,
                    badge: _pendingCount,
                    onTap: () => _go(DrawerSection.pendingApprovals),
                  ),
                  _NavItem(
                    icon: Icons.check_circle_outline_rounded,
                    label: AppLocalizations.of(context).wfApprovedApprovals,
                    active: widget.current == DrawerSection.approvedApprovals,
                    onTap: () => _go(DrawerSection.approvedApprovals),
                  ),
                  _NavItem(
                    icon: Icons.smart_toy_rounded,
                    label: l.aiAssistant,
                    active: widget.current == DrawerSection.aiAssistant,
                    onTap: () => _go(DrawerSection.aiAssistant),
                  ),
                  _NavItem(
                    icon: Icons.account_tree_rounded,
                    label: 'n8n Dashboard',
                    active: widget.current == DrawerSection.n8nChat,
                    onTap: () => _go(DrawerSection.n8nChat),
                  ),
                  _NavItem(
                    icon: Icons.support_agent_rounded,
                    label: AppLocalizations.of(context).n8nChatTitle,
                    active: widget.current == DrawerSection.n8nWebhookChat,
                    onTap: () => _go(DrawerSection.n8nWebhookChat),
                  ),
                ],
              ),
            ),

            Divider(color: AppColors.of(context).surfaceHigh, height: 1),

            // ── Footer ──────────────────────────────────────────────────────
            _NavItem(
              icon: Icons.settings_outlined,
              label: l.settings,
              active: widget.current == DrawerSection.settings,
              onTap: () => _go(DrawerSection.settings),
            ),
            _NavItem(
              icon: Icons.logout_rounded,
              label: l.logout,
              active: false,
              destructive: true,
              onTap: _logout,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drawer header — avatar + user info
// ─────────────────────────────────────────────────────────────────────────────
class _DrawerHeader extends StatelessWidget {
  final String username;
  final String url;
  const _DrawerHeader({required this.username, required this.url});

  @override
  Widget build(BuildContext context) {
    return GradientHeader(
      height: 90,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Row(
        children: [
          // Avatar circle — white border on gradient background
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 1.5),
            ),
            child: Center(
              child: Text(
                username.isNotEmpty ? username[0].toUpperCase() : '?',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  username.isEmpty ? '—' : username,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                if (url.isNotEmpty)
                  Text(
                    url,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75), fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single navigation tile
// ─────────────────────────────────────────────────────────────────────────────
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool destructive;
  final int badge;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.destructive = false,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? AppColors.error
        : active
            ? AppColors.of(context).primary
            : AppColors.of(context).textSecondary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: active
            ? AppColors.of(context).primary.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        leading: Icon(icon, color: color, size: 22),
        title: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.of(context).textPrimary : color,
            fontSize: 14,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        trailing: badge > 0 && !active
            ? _BadgeChip(count: badge)
            : active
                ? Container(
                    width: 3,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.of(context).primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  )
                : null,
        onTap: onTap,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pending count badge chip
// ─────────────────────────────────────────────────────────────────────────────
class _BadgeChip extends StatelessWidget {
  final int count;
  const _BadgeChip({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: AppColors.warning,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section divider with label
// ─────────────────────────────────────────────────────────────────────────────
class _SectionDivider extends StatelessWidget {
  final String label;
  const _SectionDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(children: [
        Text(
          label,
          style: TextStyle(
              color: AppColors.of(context).textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: AppColors.of(context).surfaceHigh)),
      ]),
    );
  }
}
