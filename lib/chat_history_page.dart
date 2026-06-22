import 'dart:convert';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'app_colors.dart';
import 'app_localizations.dart';

// ---------------------------------------------------------------------------
// ChatHistoryPage — browse & load saved AI conversations from ERPNext Notes
// ---------------------------------------------------------------------------
class ChatHistoryPage extends StatefulWidget {
  const ChatHistoryPage({super.key});

  @override
  State<ChatHistoryPage> createState() => _ChatHistoryPageState();
}

class _ChatHistoryPageState extends State<ChatHistoryPage> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  // ── Fetch list of saved sessions — filtered by current user ─────────────
  Future<void> _loadSessions() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Get current username to filter notes by owner (multi-device privacy)
      final creds = await ApiService.getCredentials();
      final username = Uri.encodeComponent(creds['username'] ?? '');
      final ownerFilter = username.isNotEmpty
          ? ',["owner","=","$username"]'
          : '';

      final result = await ApiService.get(
        '/api/resource/Note'
        '?filters=[["title","like","AI Chat — %"]$ownerFilter]'
        '&fields=["name","title","creation","modified"]'
        '&order_by=modified desc'
        '&limit=100',
      );
      final data = (result['data'] as List? ?? []).cast<Map<String, dynamic>>();
      setState(() { _sessions = data; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Load full session data from a Note ───────────────────────────────────
  Future<Map<String, dynamic>?> _fetchSession(String name) async {
    try {
      final result = await ApiService.get('/api/resource/Note/$name');
      final note = result['data'] as Map<String, dynamic>?;
      if (note == null) return null;
      final raw = note['content'] as String? ?? '';
      return _parseContent(raw);
    } catch (_) {
      return null;
    }
  }

  // ── Extract JSON from Note content (between AICHAT markers) ─────────────
  static Map<String, dynamic>? _parseContent(String raw) {
    const start = '<!-- AICHAT_V1 -->';
    const end   = '<!-- /AICHAT_V1 -->';
    final s = raw.indexOf(start);
    final e = raw.indexOf(end);
    if (s != -1 && e != -1) {
      final json = raw.substring(s + start.length, e).trim();
      try { return jsonDecode(json) as Map<String, dynamic>; } catch (_) {}
    }
    // Fallback: try parsing full content as JSON
    try { return jsonDecode(raw) as Map<String, dynamic>; } catch (_) {}
    return null;
  }

  // ── Delete a session ─────────────────────────────────────────────────────
  Future<void> _deleteSession(String name, String title) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.of(context).surface,
        title: Text(l10n.deleteConversation,
            style: TextStyle(color: AppColors.of(context).textPrimary)),
        content: Text('${ l10n.deleteConvConfirm}\n\n"$title"',
            style: TextStyle(color: AppColors.of(context).textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel,
                style: TextStyle(color: AppColors.of(context).textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.deleteConversation,
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.delete('/api/resource/Note/$name');
      if (mounted) {
        setState(() => _sessions.removeWhere((s) => s['name'] == name));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.conversationDeleted),
            backgroundColor: AppColors.of(context).surface,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  // ── Tap a session → confirm → return data to AI page ────────────────────
  Future<void> _openSession(Map<String, dynamic> session) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.of(context).surface,
        title: Text(l10n.loadConversation,
            style: TextStyle(color: AppColors.of(context).textPrimary)),
        content: Text(l10n.loadSessionConfirm,
            style: TextStyle(color: AppColors.of(context).textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel,
                style: TextStyle(color: AppColors.of(context).textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.loadConversation,
                style: TextStyle(color: AppColors.of(context).primary)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final data = await _fetchSession(session['name'] as String);
    if (!mounted) return;
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not load conversation'),
            backgroundColor: AppColors.error),
      );
      return;
    }
    Navigator.pop(context, {
      'name'  : session['name'],
      'title' : session['title'],
      'data'  : data,
    });
  }

  // ── Format date string for display ──────────────────────────────────────
  String _formatDate(String raw) {
    if (raw.length < 16) return raw;
    return raw.substring(0, 16).replaceAll('-', '/');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      appBar: AppBar(
        backgroundColor: AppColors.of(context).surface,
        iconTheme: IconThemeData(color: AppColors.of(context).textPrimary),
        title: Text(l10n.chatHistory,
            style: TextStyle(color: AppColors.of(context).textPrimary,
                fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AppColors.of(context).textSecondary),
            onPressed: _loadSessions,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? Center(
                child: CircularProgressIndicator(color: AppColors.of(context).primary))
            : _error != null
                ? _ErrorView(error: _error!, onRetry: _loadSessions)
                : _sessions.isEmpty
                    ? _EmptyView(label: l10n.noSavedChats)
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _sessions.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final s = _sessions[i];
                          final title    = s['title'] as String? ?? '';
                          final modified = s['modified'] as String? ?? '';
                          final name     = s['name'] as String? ?? '';
                          // Strip "AI Chat — " prefix for cleaner display
                          final displayTitle = title.startsWith('AI Chat — ')
                              ? title.substring('AI Chat — '.length)
                              : title;
                          return _SessionTile(
                            title      : displayTitle,
                            date       : _formatDate(modified),
                            onTap      : () => _openSession(s),
                            onDelete   : () => _deleteSession(name, displayTitle),
                          );
                        },
                      ),
      ),
    );
  }
}

// ── Session tile ─────────────────────────────────────────────────────────────
class _SessionTile extends StatelessWidget {
  final String title;
  final String date;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SessionTile({
    required this.title,
    required this.date,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.of(context).surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: AppColors.of(context).primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.chat_bubble_outline_rounded,
                    color: AppColors.of(context).primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.of(context).textPrimary,
                            fontWeight: FontWeight.w500,
                            fontSize: 14)),
                    const SizedBox(height: 3),
                    Text(date,
                        style: TextStyle(
                            color: AppColors.of(context).textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    color: AppColors.error, size: 20),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyView extends StatelessWidget {
  final String label;
  const _EmptyView({required this.label});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 72,
                color: AppColors.of(context).textSecondary),
            const SizedBox(height: 16),
            Text(label,
                style: TextStyle(
                    color: AppColors.of(context).textSecondary, fontSize: 16)),
          ],
        ),
      );
}

// ── Error view ────────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  color: AppColors.error, size: 48),
              const SizedBox(height: 12),
              Text(error,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.of(context).textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onRetry,
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      );
}
