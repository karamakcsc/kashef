// n8n_chat_page.dart
// Route '/n8n-chat' — class name N8nChatPage preserved for routing compatibility.
// All n8n REST API calls (workflows, executions, statistics) removed.
// This page is now a static placeholder — no HTTP calls, no polling.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import 'app_colors.dart';
import 'app_drawer.dart';
import 'app_localizations.dart';

class N8nChatPage extends StatelessWidget {
  const N8nChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: c.background,
      drawer: const AppDrawer(current: DrawerSection.n8nChat),
      appBar: AppBar(
        systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'n8n Dashboard',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            Text(
              'Workflow automation',
              style: TextStyle(
                fontSize: 11,
                color: c.textSecondary,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Icon ──────────────────────────────────────────────────
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: c.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.account_tree_rounded,
                      color: c.primary,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Title ─────────────────────────────────────────────────
                  Text(
                    'n8n Automation',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l.isArabic
                        ? 'استخدم واجهة الدردشة للتواصل مع\nخدمات الأتمتة عبر n8n'
                        : 'Use the chat interface to communicate\nwith your n8n automation workflows.',
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 36),

                  // ── Open Chat button ──────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/n8n-webhook-chat'),
                      icon: const Icon(Icons.support_agent_rounded, size: 20),
                      label: Text(
                        l.isArabic ? 'فتح دردشة n8n' : 'Open n8n Chat',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
