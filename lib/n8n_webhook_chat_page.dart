// n8n_webhook_chat_page.dart
// Fully isolated n8n chat module — complete rebuild.
// Route: /n8n-webhook-chat   Drawer: DrawerSection.n8nWebhookChat
//
// Architecture: Flutter → direct HTTP → n8n webhook
// Zero dependency on ERPNext / ApiService / AI Assistant / FAC tools.
// All colours via AppColors.of(context), all strings via AppLocalizations.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'app_colors.dart';
import 'app_drawer.dart';
import 'app_localizations.dart';
import 'n8n_chat_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// 1. DATA MODEL
// ═══════════════════════════════════════════════════════════════════════════════

enum _Role { user, bot }

class _Message {
  final String id;
  final _Role  role;
  final String text;
  final bool   isError;

  _Message.user(this.text)
      : id      = '${DateTime.now().microsecondsSinceEpoch}_u',
        role    = _Role.user,
        isError = false;

  _Message.bot(this.text, {this.isError = false})
      : id   = '${DateTime.now().microsecondsSinceEpoch}_b',
        role = _Role.bot;

  bool get isUser => role == _Role.user;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 2. PAGE
// ═══════════════════════════════════════════════════════════════════════════════

class N8nWebhookChatPage extends StatefulWidget {
  const N8nWebhookChatPage({super.key});

  @override
  State<N8nWebhookChatPage> createState() => _N8nWebhookChatPageState();
}

class _N8nWebhookChatPageState extends State<N8nWebhookChatPage> {
  final _svc    = N8nWebhookChatService.instance;
  final _input  = TextEditingController();
  final _scroll = ScrollController();

  final List<_Message> _messages  = [];
  bool   _thinking      = false;
  bool   _urlConfigured = true;  // false = show setup screen
  String _sessionId     = '';
  String? _lastUserText; // stored for retry

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _initSession() async {
    final url = await N8nWebhookChatService.getWebhookUrl();
    final id  = await N8nWebhookChatService.loadOrCreateSession();
    if (mounted) {
      setState(() {
        _urlConfigured = url.isNotEmpty;
        _sessionId     = id;
      });
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _send([String? override]) async {
    final text = (override ?? _input.text).trim();
    if (text.isEmpty || _thinking || _sessionId.isEmpty) return;

    _input.clear();
    setState(() {
      _messages.add(_Message.user(text));
      _thinking     = true;
      _lastUserText = text;
    });
    _scrollToBottom();

    try {
      final l     = AppLocalizations.of(context);
      final reply = await _svc.sendMessage(
        message:   text,
        sessionId: _sessionId,
        language:  l.isArabic ? 'ar' : 'en',
      );
      if (!mounted) return;
      setState(() {
        _messages.add(_Message.bot(reply));
        _thinking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_Message.bot(
          AppLocalizations.of(context).n8nChatError,
          isError: true,
        ));
        _thinking = false;
      });
    }
    _scrollToBottom();
  }

  void _retry() {
    if (_lastUserText == null) return;
    if (_messages.isNotEmpty && _messages.last.isError) {
      setState(() => _messages.removeLast());
    }
    _send(_lastUserText);
  }

  Future<void> _newChat() async {
    final l  = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   Text(l.n8nNewChat),
        content: Text(l.n8nNewChatConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.isArabic ? 'تأكيد' : 'Confirm'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final id = await N8nWebhookChatService.resetSession();
    setState(() {
      _messages.clear();
      _sessionId    = id;
      _lastUserText = null;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve:    Curves.easeOut,
        );
      }
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: c.background,
      drawer: const AppDrawer(current: DrawerSection.n8nWebhookChat),
      appBar: _buildAppBar(c, l),
      body: SafeArea(
        child: !_urlConfigured
            ? _NotConfiguredBanner(c: c, l: l)
            : Column(
          children: [
            // ── Messages ────────────────────────────────────────────────────
            Expanded(
              child: _messages.isEmpty
                  ? _EmptyState(c: c, l: l, onSend: _send)
                  : ListView.builder(
                      controller:   _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      itemCount:    _messages.length,
                      itemBuilder:  (_, i) => _BubbleWidget(
                        msg:     _messages[i],
                        c:       c,
                        onRetry: _messages[i].isError ? _retry : null,
                      ),
                    ),
            ),

            // ── Typing indicator ─────────────────────────────────────────────
            if (_thinking) _TypingIndicator(c: c, l: l),

            // ── Input bar ────────────────────────────────────────────────────
            _InputBar(
              ctrl:    _input,
              loading: _thinking,
              onSend:  _send,
              c:       c,
              l:       l,
            ),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar(AppColors c, AppLocalizations l) {
    return AppBar(
      titleSpacing: 4,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize:        MainAxisSize.min,
        children: [
          Text(
            l.n8nChatTitle,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          Text(
            'n8n Agent',
            style: TextStyle(
              fontSize: 11,
              color:    c.textSecondary,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
      actions: [
        if (_messages.isNotEmpty)
          IconButton(
            icon:    const Icon(Icons.add_comment_outlined),
            tooltip: l.n8nNewChat,
            onPressed: _newChat,
          ),
        const SizedBox(width: 4),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 3. MESSAGE BUBBLE
// ═══════════════════════════════════════════════════════════════════════════════

class _BubbleWidget extends StatelessWidget {
  final _Message     msg;
  final AppColors    c;
  final VoidCallback? onRetry;

  const _BubbleWidget({
    required this.msg,
    required this.c,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isRtl  = _detectRtl(msg.text);
    final bgColor = msg.isUser
        ? c.userBubble
        : msg.isError
            ? AppColors.error.withValues(alpha: 0.1)
            : c.surface;
    final textColor = msg.isUser ? Colors.white : c.textPrimary;
    final align = msg.isUser
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: msg.text));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:  Text('Copied'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: align,
          children: [
            // ── Bubble ────────────────────────────────────────────────────
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color:  bgColor,
                  borderRadius: BorderRadius.only(
                    topLeft:     const Radius.circular(16),
                    topRight:    const Radius.circular(16),
                    bottomLeft:  Radius.circular(msg.isUser ? 16 : 4),
                    bottomRight: Radius.circular(msg.isUser ? 4 : 16),
                  ),
                  border: msg.isUser
                      ? null
                      : Border.all(
                          color: msg.isError
                              ? AppColors.error.withValues(alpha: 0.4)
                              : c.surfaceHigh,
                        ),
                ),
                child: Text(
                  msg.text,
                  textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                  style: TextStyle(
                    color:    textColor,
                    fontSize: 14,
                    height:   1.55,
                  ),
                ),
              ),
            ),

            // ── Retry button (error only) ──────────────────────────────────
            if (onRetry != null) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: onRetry,
                icon:  const Icon(Icons.refresh_rounded, size: 14),
                label: const Text('Retry', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.error,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize:    Size.zero,
                  tapTargetSize:  MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static bool _detectRtl(String text) {
    if (text.isEmpty) return false;
    final code = text.runes.first;
    return (code >= 0x0590 && code <= 0x08FF) ||
           (code >= 0xFB1D && code <= 0xFDFF) ||
           (code >= 0xFE70 && code <= 0xFEFF);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 4. TYPING INDICATOR
// ═══════════════════════════════════════════════════════════════════════════════

class _TypingIndicator extends StatelessWidget {
  final AppColors        c;
  final AppLocalizations l;
  const _TypingIndicator({required this.c, required this.l});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        children: [
          Container(
            padding:    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: const BorderRadius.only(
                topLeft:     Radius.circular(16),
                topRight:    Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft:  Radius.circular(4),
              ),
              border: Border.all(color: c.surfaceHigh),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.n8nThinking,
                  style: TextStyle(color: c.textSecondary, fontSize: 13),
                ),
                const SizedBox(width: 6),
                _AnimatedDots(c: c),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedDots extends StatefulWidget {
  final AppColors c;
  const _AnimatedDots({required this.c});

  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder:   (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final phase   = (_ctrl.value + i * 0.33) % 1.0;
          final opacity = (phase < 0.5 ? phase * 2 : (1 - phase) * 2)
              .clamp(0.2, 1.0);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Opacity(
              opacity: opacity,
              child: Container(
                width:  6,
                height: 6,
                decoration: BoxDecoration(
                  color: widget.c.textSecondary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 5. INPUT BAR
// ═══════════════════════════════════════════════════════════════════════════════

class _InputBar extends StatelessWidget {
  final TextEditingController      ctrl;
  final bool                       loading;
  final void Function([String?])   onSend;
  final AppColors                  c;
  final AppLocalizations           l;

  const _InputBar({
    required this.ctrl,
    required this.loading,
    required this.onSend,
    required this.c,
    required this.l,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + bottom),
      decoration: BoxDecoration(
        color:  c.surface,
        border: Border(top: BorderSide(color: c.surfaceHigh)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Text field ──────────────────────────────────────────────────
          Expanded(
            child: TextField(
              controller:      ctrl,
              enabled:         !loading,
              maxLines:        5,
              minLines:        1,
              textInputAction: TextInputAction.send,
              onSubmitted:     loading ? null : (_) => onSend(),
              style: TextStyle(color: c.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText:  l.n8nChatPlaceholder,
                hintStyle: TextStyle(color: c.textSecondary),
                filled:    true,
                fillColor: c.surfaceHigh,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical:   10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide:   BorderSide.none,
                ),
                isDense: true,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // ── Send / Loading button ────────────────────────────────────────
          Material(
            color:  loading ? c.surfaceHigh : c.primary,
            shape:  const CircleBorder(),
            child: InkWell(
              onTap:       loading ? null : () => onSend(),
              customBorder: const CircleBorder(),
              child: SizedBox(
                width:  44,
                height: 44,
                child: Center(
                  child: loading
                      ? SizedBox(
                          width:  18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth:  2,
                            valueColor: AlwaysStoppedAnimation(c.onPrimary),
                          ),
                        )
                      : Icon(Icons.send_rounded, color: c.onPrimary, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 6. NOT CONFIGURED BANNER
// ═══════════════════════════════════════════════════════════════════════════════

class _NotConfiguredBanner extends StatelessWidget {
  final AppColors        c;
  final AppLocalizations l;
  const _NotConfiguredBanner({required this.c, required this.l});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68, height: 68,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.settings_ethernet_rounded,
                  color: AppColors.warning, size: 32),
            ),
            const SizedBox(height: 20),
            Text(
              l.isArabic ? 'n8n غير مُهيَّأ' : 'n8n Not Configured',
              style: TextStyle(
                color: c.textPrimary, fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l.isArabic
                  ? 'الرجاء إدخال رابط n8n Webhook في صفحة الإعدادات'
                  : 'Please set the n8n Webhook URL in Settings.',
              style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/settings'),
                icon:  const Icon(Icons.settings_rounded, size: 18),
                label: Text(l.isArabic ? 'فتح الإعدادات' : 'Open Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 7. EMPTY STATE
// ═══════════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final AppColors                c;
  final AppLocalizations         l;
  final void Function([String?]) onSend;

  const _EmptyState({
    required this.c,
    required this.l,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Icon ──────────────────────────────────────────────────────
            Container(
              width:  68,
              height: 68,
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.support_agent_rounded, color: c.primary, size: 32),
            ),
            const SizedBox(height: 16),

            // ── Title ─────────────────────────────────────────────────────
            Text(
              l.n8nChatTitle,
              style: TextStyle(
                color:      c.textPrimary,
                fontSize:   20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.n8nChatEmpty,
              style: TextStyle(color: c.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),

            // ── Suggestion chips ──────────────────────────────────────────
            _SuggestionChip(label: l.n8nSuggestion1, c: c, onTap: () => onSend(l.n8nSuggestion1)),
            const SizedBox(height: 8),
            _SuggestionChip(label: l.n8nSuggestion2, c: c, onTap: () => onSend(l.n8nSuggestion2)),
            const SizedBox(height: 8),
            _SuggestionChip(label: l.n8nSuggestion3, c: c, onTap: () => onSend(l.n8nSuggestion3)),
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String       label;
  final AppColors    c;
  final VoidCallback onTap;

  const _SuggestionChip({
    required this.label,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon:  Icon(Icons.bolt_rounded, size: 16, color: c.primary),
        label: Text(label, style: TextStyle(color: c.textPrimary, fontSize: 13)),
        style: OutlinedButton.styleFrom(
          side:             BorderSide(color: c.primary.withValues(alpha: 0.35)),
          padding:          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          alignment:        AlignmentDirectional.centerStart,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
