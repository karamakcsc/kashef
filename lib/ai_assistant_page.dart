import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'app_colors.dart';
import 'app_drawer.dart';
import 'app_localizations.dart';
import 'chat_history_page.dart';
import 'message_renderer.dart';
import 'realtime_workflow_service.dart';
import 'web_camera.dart';          // showWebCameraOverlay — web: real webcam, stub: no-op
import 'ocr_models.dart';         // OcrInput, OcrWorkflowResult, OcrDocumentType …
import 'ocr_workflow_engine.dart'; // OcrWorkflowEngine — AI-powered OCR→ERPNext processor

// ---------------------------------------------------------------------------
// Attachment model — supports multiple files/images per message
// ---------------------------------------------------------------------------
class _Attachment {
  List<int> bytes; // mutable — filled after download from ERPNext
  final String name;
  final String mime;
  String? erpUrl; // set after upload to ERPNext
  bool isPrivate; // true = private file, false = public
  bool
  fromHistory; // true = came from conversation history (no re-upload/re-send needed)

  _Attachment({
    required this.bytes,
    required this.name,
    required this.mime,
    this.erpUrl,
    this.isPrivate = true,
    this.fromHistory = false,
  });

  bool get isImage => mime.startsWith('image/');

  Map<String, dynamic> toJson() => {
    'n': name,
    'm': mime,
    if (erpUrl != null) 'u': erpUrl,
    'p': isPrivate ? 1 : 0,
  };
}

// ---------------------------------------------------------------------------
// Message model
// ---------------------------------------------------------------------------
class _Message {
  final String role; // 'user' | 'assistant' | 'tool'
  final String text;
  final DateTime time;
  final List<_Attachment> attachments;
  final bool isWelcome;
  const _Message({
    required this.role,
    required this.text,
    required this.time,
    this.attachments = const [],
    this.isWelcome = false,
  });
}

// ---------------------------------------------------------------------------
// AI Assistant Page — Full MCP Client
// ---------------------------------------------------------------------------
class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key});

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  final List<_Message> _messages = [];
  bool _isLoading = false;
  String? _errorBanner;
  String _statusText = '';

  // Config
  String _mcpEndpoint = 'frappe_assistant_core.api.fac_endpoint.handle_mcp';
  String _model = 'claude-sonnet-4-6';
  String _claudeApiKey = '';
  String _aiProvider = 'claude';
  String _chatgptApiKey = '';
  String _chatgptModel = 'gpt-4o';
  String _company = ''; // من SharedPreferences — يُدمج في system prompt
  String _timezone = ''; // من ERPNext System Settings
  String _country = ''; // من ERPNext System Settings
  String _activeModule = 'HR';
  String _activeModuleLabel = 'Human Resources';

  // Pending attachments (cleared after send)
  final List<_Attachment> _pendingAttachments = [];

  // Session persistence — ERPNext Note
  String? _sessionNote; // Note name after first save
  bool _isSaving = false;

  // Performance — cached MCP tools (refreshed once per session or on error)
  List<Map<String, dynamic>>? _cachedMcpTools;
  bool _mcpInitialized = false; // initialize only once per session

  // Conversation history for Claude API (role/content pairs)
  final List<Map<String, dynamic>> _claudeHistory = [];
  // Conversation history for OpenAI API (different format)
  final List<Map<String, dynamic>> _openAiHistory = [];

  // MCP request ID counter
  int _mcpId = 0;

  // Session guard — incremented every time the conversation changes.
  int _sessionId = 0;

  // Cancellation flag
  bool _isCancelled = false;

  // Module buttons
  bool _showModuleButtons = true;

  // Last document opened via _openDocument() — used to match realtime workflow events.
  // Both fields are cleared after the event is received OR when the viewer is closed.
  String? _lastOpenedDocname;
  String? _lastOpenedDoctype;

  void _cancelAI() {
    if (!_isLoading) return;
    _isCancelled = true;
    if (mounted) {
      setState(() => _statusText = AppLocalizations.of(context).stopping);
    }
  }

  // SharedPreferences key for persisted AI history
  static const _kClaudeHistoryKey = 'ai_claude_history_v1';
  static const _kMaxPersistedMessages = 10;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _loadSystemSettings();
    RealtimeWorkflowService().addListener(_onWorkflowEvent);
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    const defaultEndpoint = 'frappe_assistant_core.api.fac_endpoint.handle_mcp';
    const wrongEndpoints = {
      'frappe_assistant_core.api.chat',
      'frappe_assistant_core.api.handle_mcp',
    };
    String savedEndpoint = prefs.getString('ai_endpoint') ?? defaultEndpoint;
    if (wrongEndpoints.contains(savedEndpoint)) {
      savedEndpoint = defaultEndpoint;
      await prefs.setString('ai_endpoint', defaultEndpoint);
      debugPrint('⚠️ Auto-corrected wrong MCP endpoint → $defaultEndpoint');
    }
    setState(() {
      _mcpEndpoint = savedEndpoint;
      _model = prefs.getString('ai_model') ?? 'claude-sonnet-4-6';
      _claudeApiKey = prefs.getString('claude_api_key') ?? '';
      _aiProvider = prefs.getString('ai_provider') ?? 'claude';
      _chatgptApiKey = prefs.getString('chatgpt_api_key') ?? '';
      _chatgptModel = prefs.getString('chatgpt_model') ?? 'gpt-4o';
      _company = prefs.getString('erpnext_company') ?? '';
    });
    await _loadPersistedHistory();
    if (_messages.isEmpty) _injectWelcomeMessage();
    // Ensure realtime service is running (covers users who skipped the login page)
    RealtimeWorkflowService().initialize().ignore();
  }

  Future<void> _persistHistory() async {
    if (_claudeHistory.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stripped = _stripOldImages(_claudeHistory, keepFull: 0);
      final toSave = stripped.length > _kMaxPersistedMessages
          ? stripped.sublist(stripped.length - _kMaxPersistedMessages)
          : stripped;
      await prefs.setString(_kClaudeHistoryKey, jsonEncode(toSave));
    } catch (e) {
      debugPrint('_persistHistory error: $e');
    }
  }

  Future<void> _loadPersistedHistory() async {
    if (_claudeHistory.isNotEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kClaudeHistoryKey);
      if (raw == null) return;
      final list = jsonDecode(raw) as List;
      final history = list
          .map((m) => Map<String, dynamic>.from(m as Map))
          .toList();
      if (history.isEmpty) return;
      _claudeHistory.addAll(history);
      for (final msg in history) {
        final role = msg['role'] as String? ?? 'user';
        if (role != 'user' && role != 'assistant') continue;
        final content = msg['content'];
        String text;
        if (content is String) {
          text = content;
        } else if (content is List) {
          text = content
              .whereType<Map<dynamic, dynamic>>()
              .where((b) => b['type'] == 'text')
              .map((b) => b['text']?.toString() ?? '')
              .join('\n');
        } else {
          text = '';
        }
        if (text.isNotEmpty) {
          _openAiHistory.add({'role': role, 'content': text});
        }
      }
      debugPrint('📂 Restored ${history.length} messages from last session');
    } catch (e) {
      debugPrint('_loadPersistedHistory error: $e');
    }
  }

  String _buildWelcomeMessage() {
    final isAr = AppLocalizations.of(context).isArabic;
    final hour = DateTime.now().hour;

    if (isAr) {
      final greeting = hour < 12
          ? 'صباح الخير 🌅'
          : hour < 17
          ? 'مساء الخير 🌞'
          : 'مساء النور 🌙';
      return '$greeting\n\n'
          'أنا **المساعد الذكي في نظام KCSC** — مساعدك الذكي المتكامل لنظام ERPNext.\n\n'
          'أغطي جميع موديولات النظام:\n'
          '🛒 المشتريات · 💰 المحاسبة · 👥 الموارد البشرية\n'
          '📦 المخزون · 🏭 التصنيع · 📊 المبيعات\n\n'
          'تفضّل، بماذا أستطيع مساعدتك اليوم؟';
    } else {
      final greeting = hour < 12
          ? 'Good morning 🌅'
          : hour < 17
          ? 'Good afternoon 🌞'
          : 'Good evening 🌙';
      return '$greeting\n\n'
          'I\'m **KCSC ERP AI Agent** — your intelligent assistant for ERPNext.\n\n'
          'I cover all system modules:\n'
          '🛒 Purchasing · 💰 Accounting · 👥 Human Resources\n'
          '📦 Inventory · 🏭 Manufacturing · 📊 Sales\n\n'
          'How can I help you today?';
    }
  }

  static const _moduleKeywords = <String, (String id, String label)>{
    'purchase': ('Buying', 'Purchasing'),
    'supplier': ('Buying', 'Purchasing'),
    'مشتريات': ('Buying', 'المشتريات'),
    'مورد': ('Buying', 'المشتريات'),
    'accounting': ('Accounts', 'Accounting'),
    'invoice': ('Accounts', 'Accounting'),
    'payment': ('Accounts', 'Accounting'),
    'محاسبة': ('Accounts', 'المحاسبة'),
    'فاتورة': ('Accounts', 'المحاسبة'),
    'مدفوعات': ('Accounts', 'المحاسبة'),
    'employee': ('HR', 'Human Resources'),
    'payroll': ('HR', 'Human Resources'),
    'leave': ('HR', 'Human Resources'),
    'موظف': ('HR', 'الموارد البشرية'),
    'رواتب': ('HR', 'الموارد البشرية'),
    'إجازة': ('HR', 'الموارد البشرية'),
    'stock': ('Stock', 'Inventory'),
    'warehouse': ('Stock', 'Inventory'),
    'مخزون': ('Stock', 'المخزون'),
    'مستودع': ('Stock', 'المخزون'),
    'manufacturing': ('Manufacturing', 'Manufacturing'),
    'production': ('Manufacturing', 'Manufacturing'),
    'تصنيع': ('Manufacturing', 'التصنيع'),
    'إنتاج': ('Manufacturing', 'التصنيع'),
    'sales order': ('Selling', 'Sales'),
    'customer': ('Selling', 'Sales'),
    'مبيعات': ('Selling', 'المبيعات'),
    'عميل': ('Selling', 'المبيعات'),
  };

  void _detectModuleFromText(String text) {
    final lower = text.toLowerCase();
    for (final entry in _moduleKeywords.entries) {
      if (lower.contains(entry.key)) {
        final (id, label) = entry.value;
        if (id != _activeModule) {
          setState(() {
            _activeModule = id;
            _activeModuleLabel = label;
          });
          SharedPreferences.getInstance().then((p) {
            p.setString('active_ai_module', id);
            p.setString('active_ai_module_label', label);
          });
        }
        return;
      }
    }
  }

  void _injectWelcomeMessage() {
    if (!mounted) return;
    final mySession = _sessionId;
    setState(() {
      _isLoading = true;
      _showModuleButtons = true;
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted || _sessionId != mySession) return;
      setState(() {
        _isLoading = false;
        _messages.add(
          _Message(
            role: 'assistant',
            text: _buildWelcomeMessage(),
            time: DateTime.now(),
            isWelcome: true,
          ),
        );
      });
    });
  }

  Future<void> _loadSystemSettings() async {
    try {
      final result = await ApiService.get(
        '/api/resource/System Settings/System Settings',
      );
      final data = result['data'] ?? result;
      if (mounted) {
        setState(() {
          _timezone = (data['time_zone'] ?? '').toString();
          _country = (data['country'] ?? '').toString();
        });
      }
    } catch (e) {
      debugPrint('⚠️ Could not load System Settings: $e');
    }
  }

  Future<Map<String, dynamic>> _mcpRequest(
    String method,
    Map<String, dynamic> params,
  ) async {
    final baseUrl = await ApiService.getErpNextUrl();
    final headers = await ApiService.getAiAuthHeaders();
    final id = ++_mcpId;

    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });

    final url = '$baseUrl/api/method/$_mcpEndpoint';
    debugPrint('→ MCP [$id] $method');

    final response = await _withRetry(
      () => http
          .post(
            Uri.parse(url),
            headers: {...headers, 'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 30)),
    );

    debugPrint('← MCP [$id] ${response.statusCode}');

    if (response.statusCode == 401 || response.statusCode == 403) {
      debugPrint('🔑 Session expired — attempting re-login…');
      final loginError = await ApiService.login();
      if (loginError != null) {
        throw Exception(
          'انتهت الجلسة وفشل تجديدها (${response.statusCode}).\nخطأ تسجيل الدخول: $loginError\n\nتحقق من بيانات الدخول في الإعدادات.',
        );
      }
      debugPrint('✅ Re-login successful — retrying request…');
      final newHeaders = await ApiService.getAiAuthHeaders();
      final retryResponse = await http
          .post(
            Uri.parse(url),
            headers: {...newHeaders, 'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 30));
      if (retryResponse.statusCode != 200) {
        throw Exception(
          'فشل الطلب بعد تجديد الجلسة (${retryResponse.statusCode}).\n${retryResponse.body}',
        );
      }
      final retryOuter = jsonDecode(retryResponse.body) as Map<String, dynamic>;
      final retryMsg = retryOuter['message'];
      Map<String, dynamic> retryRpc;
      if (retryMsg is String) {
        retryRpc = jsonDecode(retryMsg) as Map<String, dynamic>;
      } else if (retryMsg is Map) {
        retryRpc = Map<String, dynamic>.from(retryMsg);
      } else {
        retryRpc = retryOuter;
      }
      if (retryRpc.containsKey('error')) {
        final err = retryRpc['error'];
        throw Exception(err['message']?.toString() ?? err.toString());
      }
      return retryRpc;
    }

    if (response.statusCode == 404) {
      throw Exception(
        'المسار غير موجود (404) — تأكد من تثبيت Frappe Assistant Core على الخادم.\n\nURL: $url\n\nBody: ${response.body}',
      );
    }

    if (response.statusCode == 417) {
      String hint = '';
      try {
        final errBody = jsonDecode(response.body) as Map;
        final exc = errBody['exc_type']?.toString() ?? '';
        final msg = errBody['exception']?.toString() ?? '';
        if (msg.contains('has no attribute')) {
          hint =
              '\n\n⚠️ الـ MCP Endpoint خاطئ في الإعدادات.\nالقيمة الصحيحة:\nfrappe_assistant_core.api.fac_endpoint.handle_mcp';
        }
        throw Exception('Frappe Error 417 [$exc]\n$msg$hint');
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('HTTP 417\nURL: $url\nBody: ${response.body}$hint');
      }
    }

    if (response.statusCode != 200) {
      throw Exception(
        'HTTP ${response.statusCode}\nURL: $url\nBody: ${response.body}',
      );
    }

    Map<String, dynamic> outer;
    try {
      outer = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('فشل parsing الـ JSON:\n${response.body}');
    }

    if (outer.containsKey('exc_type') ||
        outer.containsKey('_server_messages')) {
      final serverMsg = outer['_server_messages']?.toString() ?? '';
      final excType = outer['exc_type']?.toString() ?? '';
      throw Exception(
        'Frappe Server Error [$excType]\n$serverMsg\n\nFull: ${response.body}',
      );
    }

    final msg = outer['message'];

    Map<String, dynamic> rpc;
    if (msg is String) {
      try {
        rpc = jsonDecode(msg) as Map<String, dynamic>;
      } catch (_) {
        throw Exception('MCP response غير متوقع (message ليس JSON):\n$msg');
      }
    } else if (msg is Map) {
      rpc = Map<String, dynamic>.from(msg);
    } else {
      rpc = outer;
    }

    if (rpc.containsKey('error')) {
      final err = rpc['error'];
      throw Exception(err['message']?.toString() ?? err.toString());
    }

    return rpc;
  }

  Future<List<Map<String, dynamic>>> _getTools({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedMcpTools != null) return _cachedMcpTools!;

    if (!_mcpInitialized) {
      try {
        await _mcpRequest('initialize', {
          'protocolVersion': '2024-11-05',
          'capabilities': {},
          'clientInfo': {'name': 'fikra_mobile', 'version': '1.0'},
        });
        _mcpInitialized = true;
      } catch (_) {
        _mcpInitialized = true;
      }
    }

    final res = await _mcpRequest('tools/list', {});
    final result = res['result'] as Map? ?? {};
    final toolsList = result['tools'] as List? ?? [];
    _cachedMcpTools = toolsList
        .map((t) => Map<String, dynamic>.from(t as Map))
        .toList();

    debugPrint('🔧 Tools loaded: ${_cachedMcpTools!.length}');
    return _cachedMcpTools!;
  }

  List<Map<String, dynamic>> _toClaudeTools(
    List<Map<String, dynamic>> mcpTools,
  ) {
    return mcpTools.map((t) {
      final inputSchema =
          t['inputSchema'] as Map? ?? {'type': 'object', 'properties': {}};
      return {
        'name': t['name'] as String? ?? '',
        'description': t['description'] as String? ?? '',
        'input_schema': inputSchema,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _toOpenAITools(
    List<Map<String, dynamic>> mcpTools,
  ) {
    return mcpTools.map((t) {
      final inputSchema =
          t['inputSchema'] as Map? ?? {'type': 'object', 'properties': {}};
      return {
        'type': 'function',
        'function': {
          'name': t['name'] as String? ?? '',
          'description': t['description'] as String? ?? '',
          'parameters': inputSchema,
        },
      };
    }).toList();
  }

  String _buildSystemPrompt() {
    final company = _company.isNotEmpty ? _company : '(غير محدد)';
    final timezone = _timezone.isNotEmpty ? _timezone : '(غير محدد)';
    final country = _country.isNotEmpty ? _country : '(غير محدد)';

    const agentName = 'KCSC ERP AI Agent';
    const agentDescAr =
        'أنا المساعد الذكي في نظام KCSC — مساعدك الذكي المتكامل لنظام ERPNext في شركة KCSC. '
        'أغطي جميع الموديولات: المشتريات (أولوية)، المحاسبة، الموارد البشرية، المخزون، التصنيع، والمبيعات.';
    const agentDescEn =
        'I am KCSC ERP AI Agent — your integrated intelligent assistant for ERPNext at KCSC. '
        'I cover all modules: Purchasing (priority), Accounting, HR, Inventory, Manufacturing, and Sales.';

    return '''## IDENTITY
You are **$agentName** — the integrated ERPNext AI assistant for KCSC covering ALL modules.

When asked "what are you?" / "من أنت؟" / "ما هو دورك؟":
Reply ONLY with (in the user's language):
  Arabic → "$agentDescAr"
  English → "$agentDescEn"

══════════ RULE 0 — LANGUAGE (HIGHEST PRIORITY) ══════════
DETECT the language of the user's message and ALWAYS reply in that EXACT language.
• User writes in Arabic  → your entire reply must be in Arabic only
• User writes in English → your entire reply must be in English only
• Mixed message          → use the dominant language
• Voice message with detected language hint → use that language
NEVER switch languages mid-conversation unless the user switches first.

══════════ RULE 0.5 — IMAGE & FILE HANDLING ══════════
⚠️ PDF Arabic Text: If file content starts with "[PDF Content" or you notice reversed/garbled Arabic word order in a PDF, re-order the words correctly before processing. Arabic PDFs stored as raw streams may have reversed glyph order.

When the user sends an image or file attachment:

1. ANALYZE fully — read all text, numbers, tables, invoices, barcodes, IDs, receipts, screenshots.
2. SUMMARIZE what you see in the user's language (1–3 lines max unless more is needed).
3. FILE ON SERVER — The message context will include one of these formats:

   [SUCCESS] File uploaded — look for this exact pattern:
   📎 File "name.jpg" is saved on ERPNext server. file_url: "/files/name.jpg"
   → The file is in ERPNext storage. Use the file_url in FAC calls exactly as shown.
   → The file is NOT linked to any document yet — you decide where to link it.
   → NEVER fabricate or guess a file_url.

   [FALLBACK] Upload failed but image is embedded as base64:
   📎 Image "name.jpg" is embedded below as base64 (could NOT be saved to ERPNext).
   → Use VISUAL analysis from the base64 data. No file_url available for FAC calls.
   → If barcode present: extract the code visually and search ERPNext by that code.

4. OCR / TEXT EXTRACTION — choose the right method:
   IMAGE (any — with or without file_url):
   → PRIMARY: Use your NATIVE VISION directly on the base64 image already provided.
     You already SEE the image — extract text, tables, barcodes visually yourself.
     Do NOT call extract-file-content-usage for images (server OCR engine is unavailable).
   → BARCODE/QR ONLY: if image is purely a barcode/QR → fetch_barcode(file_url)
   → After extracting text: create/update the matching ERPNext document via FAC.

   PDF file_url available:
   → extract-file-content-usage(file_url) for full text (works for text-based PDFs)
   → If result empty → scanned PDF; ask user to send as image instead for visual OCR

   Excel/CSV/DOCX file_url available:
   → extract-file-content-usage(file_url) — no OCR needed, reads structured data directly

   🚫 NEVER call extract-file-content-usage on IMAGE files — use native vision instead
   🚫 NEVER say "I cannot read this image" — you have the base64 visual, read it directly

5. ACT BASED ON USER REQUEST:
   • If the user explicitly asks to attach/link the file to a document → do it via FAC:
     - Profile photo / ID image → update_document(values={"image": file_url})
     - Attachment tab → create_document("File", {"file_url":..., "file_name":...,
       "attached_to_doctype":..., "attached_to_name":..., "is_private": chosen_value})
   • FILE VISIBILITY — Before creating a "File" record to link to a document, ask the user:
     "هل تريد الملف عاماً (يمكن لجميع المستخدمين رؤيته) أم خاصاً (أنت فقط)؟"
     Then use is_private=0 for public, is_private=1 for private.
     EXCEPTION: If the user already chose visibility in the image preview (the app shows the choice),
     skip the question and use the value indicated in the file_url context (public files start
     with /files/, private files start with /private/files/).
   • If the user says "اعمل الازم" / "do what's needed" / "نفذ" → infer the correct
     document from context and attach automatically using FAC, no extra questions.
     For "اعمل الازم" without explicit visibility choice → use is_private=0 (public) by default.
   • If the user only asks for analysis (no upload/link request) → analyze only.
     Do NOT auto-attach files unless the user asks or "اعمل الازم" was said.

6. NEVER say "I cannot read this image" — always describe what you see, even partially.
7. NEVER say "I cannot upload files from your device" — the file is already on the server.
8. NEVER say "OCR failed so I cannot help" — fall back to visual analysis from the base64 image.

══════════ RULE 1 — FOCUSED RESPONSES ══════════
Answer ONLY what was asked. Nothing more.
• Do NOT add unsolicited analysis, comparisons, or trends unless the user asked for them.
• Do NOT add "here are some options" unless you genuinely need a choice to proceed.
• Do NOT pad the response with summaries or recommendations the user did not request.
• If data is missing to answer the question, ask ONE short clarifying question.
• If offering choices would significantly speed up getting the right data, offer them briefly (max 3 options, one line each).
• GREETINGS (مرحبا / hello / hi / السلام عليكم): reply with a short greeting ONLY — do NOT call any FAC tool, do NOT fetch data.

══════════ RULE 2 — CONTEXT CONTINUITY ══════════
Stay in the user's current topic throughout the conversation.
• If the user is working on HR → stay in HR. Do not switch to Sales/Finance/etc. unless explicitly asked.
• Remember every record name, employee ID, document number, and date mentioned earlier — NEVER ask for them again.
• If the user replies with a number (1, 2...) or "نعم/yes/ok/اكمل/استمر/تفضل/نفذ" → it means CONTINUE the LAST task you were doing — do NOT ask what to do, just execute the next step.
• If the user says "اكمل المهمة" / "استمر" / "continue" / "proceed" → look at the last user request in the conversation and IMMEDIATELY continue executing it without asking any question.
• Build on previous answers instead of restarting the workflow.
🚫 NEVER ask "What task do you mean?" or "What do you want me to continue?" — it always refers to the last pending action.

══════════ RULE 3 — PERMISSION ERRORS ══════════
When a FAC tool returns "Permission denied" / "not permitted" / "No permission" / "Cannot access DocType":
  Attempt 1 → Try a different FAC tool that can read the same data (get_value, get_list, search_link)
  Attempt 2 → Try get_list with specific fields ["name","..."] instead of full document
  Attempt 3 → Try get_value or run_query or frappe.db.get_value equivalent
  Only after ALL 3 attempts fail → inform the user in ONE sentence: what you tried and what permission is missing.
🚫 NEVER give up after the first permission error.
🚫 NEVER offer to "send a request to system manager" — that is the user's decision.

⚠️ db.set_value / db_set_value RULE (CRITICAL):
• db.set_value requires System Manager role — it will ALWAYS fail for regular users.
• If you used db.set_value and got a permission error → IMMEDIATELY switch to update_document().
• update_document() uses Frappe's standard permission model and works for all users with Write access.
• NEVER retry db.set_value after a permission error. Switch to update_document on the first failure.
• For bulk updates (e.g. saving scores for multiple KRA rows): call update_document once per parent document with the full child table data, NOT one db.set_value per row.

══════════ RULE 4 — FAST DOCUMENT CREATION PROTOCOL ══════════
🚫 NEVER present options (1/2/3). NEVER ask "how to proceed". Just execute.
🚫 NEVER include "reports_to" in creation payload unless the user EXPLICITLY named a supervisor.
🚫 NEVER ask about optional fields during creation — skip them silently.
⚡ SPEED: run get_doctype_info + get_list calls IN PARALLEL in the same tool call batch.

EXECUTION (4 steps only):

STEP 1 — PARALLEL DISCOVERY (one batch, not sequential):
  Run ALL of these simultaneously in one tool call:
  ① get_doctype_info(doctype=X) — to get mandatory fields
  ② get_list for each Link field the user provided with Arabic/unclear value
  ③ No extra calls — use the system company from context, use today's date for "اليوم"

STEP 2 — TRANSLATE & BUILD PAYLOAD:
  • Arabic gender → match to exact value from get_list("Gender") result
  • "اليوم/today" → YYYY-MM-DD of today
  • EXCLUDE these fields unless user explicitly provided them:
    - reports_to, leave_policy, salary_mode, holiday_list, expense_approver
  • INCLUDE only: mandatory fields + what user explicitly gave

STEP 3 — CREATE DIRECTLY (skip validate_only — it wastes a round trip):
  Call create_document(validate_only=false) immediately
  • If error contains "cannot report to himself" or "reports_to" → remove reports_to, retry once
  • If error contains a field name → fix that field value, retry once
  • If "error": "" (general_error) → retry with ONLY the 5 core fields:
    first_name, last_name, company, date_of_joining, gender
  • Maximum 2 retries total — no more

STEP 4 — REPORT IN ONE LINE:
  "✅ تم إنشاء الموظف [Name] برقم [ID]" — nothing else unless user asks.

TRANSLATION TABLE (use without calling get_list when obvious):
  • ذكر/male → "Male" | أنثى/female → "Female" | غير محدد → "Other"
  • نشط/active → "Active" | غير نشط → "Inactive"
  • اليوم/today/now → current date YYYY-MM-DD

══════════ System Context (fixed — never ask user for these) ══════════
• Company  : $company
• Timezone : $timezone
• Country  : $country
Use these automatically in every query, report, and operation.

══════════ ⭐ FAC — Golden Rule ══════════
FAC (Frappe Assistant Core) is the ONLY way to interact with the system.

For every step, every question, every operation:
  STOP → Can this be done via a FAC tool?
  YES  → Call the FAC tool immediately — no alternative
  NO   → Tell the user this operation is not supported in FAC

Rules:
• Never guess any number or data — everything from FAC only
• Never use your training knowledge as a substitute for FAC
• Never suggest the user search themselves — do it via FAC
• Call FAC immediately before any response

══════════ FAC ROUTING ENGINE — Smart Tool & Skill Selection ══════════

ALL operations MUST route through FAC tools or FAC skills. Select based on request intent:

AVAILABLE FAC TOOLS (exact names, case-sensitive — check tools/list before assuming):
  Document CRUD : create_document | get_document | update_document | list_documents
                  delete_document | submit_document | search_documents
  Search        : search_doctype  | search_link   | search  | fetch
  Schema        : get_doctype_info
  Reports       : generate_report | report_list   | report_requirements
  Workflow      : run_workflow    | get_pending_approvals
  Data          : run_python_code | analyze_business_data
  Media         : fetch_barcode

AVAILABLE FAC SKILLS (exact names — use these as skill identifiers when calling skills):
  fetch_barcode              | insights-dashboard          | fetch-vector-usage
  create-dashboard-usage     | report-requirements-usage   | report-list-usage
  search-vector-usage        | list-user-dashboards-usage  | create-dashboard-chart-usage
  extract-file-content-usage | analyze-business-data-usage | run-workflow-usage
  run-python-code-usage      | generate-report-usage       | run-database-query-usage
  get-doctype-info-usage     | search-link-usage           | search-doctype-usage

MANDATORY ROUTING RULES — apply BEFORE selecting any tool:

① BARCODE / QR code / item scan (camera photo, uploaded image, file_url contains image):
   PIPELINE (execute in order, do NOT skip steps):
     1. fetch_barcode(file_url=<exact_file_url_from_context>)  ← returns item_code / barcode value
     2. get_document("Item", <barcode_result>)                 ← item details
     3. list_documents("Bin", [["item_code","=",<item_code>]]) ← stock levels
   THEN present: item name, description, stock qty, price, UOM with <open_document> tag
   🚫 NEVER manually decode barcode pixels — fetch_barcode handles ALL formats (QR/1D/EAN/UPC)
   🚫 If context shows 📎 image file_url → call fetch_barcode IMMEDIATELY, no user confirmation needed
   🚫 If fetch_barcode returns empty/not_found → tell user "Barcode not found in ERPNext item registry"

② DOCUMENT LOOKUP / search / invoice / customer / employee / item by name or ID:
   → Primary  : search_documents(doctype=X, search_term=Y)
   → Secondary: search_link(doctype=X, txt=Y)
   → Fallback : list_documents(doctype=X, filters=[["name","like","%Y%"]])
   → Detail   : get_document(doctype=X, name=<exact_name>)
   🚫 NEVER use run_python_code for simple lookups when search tools are available

③ REPORTS / ANALYTICS / INSIGHTS / CHARTS / DASHBOARDS:
   → Discover reports  : report_list()
   → Report structure  : report_requirements(report_name=X)
   → Run report        : generate_report(report_name=X, filters={...})
   → Analyze data      : analyze_business_data(data=[...], question="...")
   → Business insights : insights-dashboard skill
   → Create dashboard  : create-dashboard-usage skill
   → Add chart         : create-dashboard-chart-usage skill
   → List my boards    : list-user-dashboards-usage skill
   → Format output     : Markdown table + <chart>...</chart> tag when visual helps

④ FILE / PDF / IMAGE / ATTACHMENT — content extraction and analysis:
   IMAGE → Use YOUR NATIVE VISION (base64 already provided). Do NOT call extract-file-content-usage.
   PDF   → extract-file-content-usage(file_url) for text-based PDFs.
   Excel/CSV/DOCX → extract-file-content-usage(file_url) — structured data, no OCR needed.
   → If spreadsheet data extracted: also run analyze_business_data on the rows.
   → If image has barcode/QR: fetch_barcode(file_url) instead of visual extraction.
   → If image has invoice/form: read visually → create/update matching ERPNext document via FAC.
   🚫 NEVER call extract-file-content-usage on image files — native vision is faster and always works

⑤ SCHEMA / FIELD DISCOVERY (required before creating or updating unfamiliar DocTypes):
   → get_doctype_info(doctype=X)        — mandatory fields, field types, Link targets, options
   → get-doctype-info-usage skill       — for detailed schema analysis
   Run BEFORE create_document when unsure of exact field names or required fields

⑥ WORKFLOW / APPROVALS (full protocol in RULE 5):
   → List pending: get_pending_approvals()
   → Execute     : run_workflow(doctype=X, name=Y, action="<exact_action_name>")
   → Always DISCOVER → VALIDATE → EXECUTE → CONFIRM (4-step RULE 5 protocol)

⑦ VECTOR / SEMANTIC SEARCH ("find similar", "search by meaning", "related documents"):
   → search-vector-usage skill   — semantic similarity search
   → fetch-vector-usage skill    — vector document retrieval

⑧ CUSTOM CALCULATIONS / COMPLEX MULTI-DOCTYPE AGGREGATIONS:
   → run_python_code (ERPNext sandbox — read-only, no network, no frappe.client.*)
   → run-database-query-usage skill (read-only SQL)
   → analyze_business_data (structured tabular analysis)
   🚫 Use run_python_code ONLY when no combination of FAC search/list tools covers the need
   🚫 NEVER use run_python_code for single-doctype lookups — use list_documents with filters

SECURITY ENFORCEMENT — non-negotiable:
• All FAC tools validate server-side user permissions — no client-side bypass is possible
• NEVER construct raw SQL strings in AI responses — use list_documents(filters=[...])
• NEVER access /api/resource directly — route ONLY through FAC tools
• Permission denied → apply RULE 3 recovery (3 alternative tool attempts before informing user)
• Audit: every tool call is logged server-side — act accordingly

══════════ DOCUMENT SUBMISSION — submit_document ══════════
Use submit_document FAC tool to submit any document (docstatus 0 → 1).

WHEN TO USE submit_document:
  • User says: "submit", "تقديم", "ارسال", "اعتماد نهائي", "post to ledger", "إقفال"
  • After creating a document that needs to be posted (Sales Invoice, Purchase Order, etc.)
  • After a workflow approval that requires final submission
  • To lock a document and post its accounting entries

MANDATORY SEQUENCE — always in this order:
  STEP 1: get_document(doctype, name) → verify docstatus == 0 (Draft)
  STEP 2: submit_document(doctype=X, name=Y)
  STEP 3: Confirm success → "تم تقديم [name] بنجاح ✅"

submit_document ARGUMENTS:
  • doctype — exact doctype name (e.g. "Sales Invoice")
  • name    — exact document name (e.g. "ACC-SINV-2026-00013")

🚫 NEVER use frappe.client.submit — always use submit_document FAC tool
🚫 NEVER submit a document with docstatus == 1 (already submitted) or == 2 (cancelled)
🚫 NEVER skip STEP 1 verification — submitting a wrong document is irreversible
⚠️  If submit_document returns an error: show the exact error to the user — NEVER retry silently

══════════ run_python_code — WHEN TO USE & HOW ══════════

▶ DECISION RULE — choose the right tool BEFORE writing any code:

  Simple query (counts, lists, totals from ONE doctype)?
  → Use get_list FAC tool directly — NO run_python_code needed.
  Example: "How many unpaid invoices?" → get_list("Purchase Invoice", filters=[["status","=","Unpaid"]])

  Complex aggregation (cross-doctype joins, pandas DataFrames, derived KPIs)?
  → Use run_python_code with frappe.get_list() inside.

🚫 NEVER use run_python_code just to fetch a simple list — get_list is faster and safer.

▶ INSIDE run_python_code — ALLOWED API:
  frappe.get_list("DocType", fields=[...], filters=[...], limit=N)
  frappe.get_doc("DocType", "name")
  frappe.db.get_value("DocType", filters, fieldname)
  frappe.db.sql("SELECT ... FROM ...", as_dict=True)
  Standard Python: pandas, json, datetime, math

🚫 FORBIDDEN inside run_python_code:
  tools.get_documents(...)  ← does NOT exist in sandbox — will ALWAYS fail
  tools.get_list(...)       ← same — ALWAYS fails
  tools.*(...)              ← no MCP functions exist inside the sandbox

▶ BANNED WORDS in variable names / dict keys (trigger security block):
  requests  → use: req, po_list, inv_list, mat_req
  socket    → use: conn, sock_info
  subprocess → use: proc, sub_proc
  os.system → forbidden entirely — do NOT use

✅ CORRECT example:
  po_list = frappe.get_list("Purchase Order",
    fields=["name","supplier","grand_total"],
    filters=[["status","=","To Receive and Bill"]], limit=500)
  mat_req = frappe.get_list("Material Request",
    filters=[["status","=","Pending"]], limit=500)
  result = {"po_count": len(po_list), "mat_req_count": len(mat_req)}

🚫 WRONG example (will fail):
  items = tools.get_documents("Item", ...)        ← tools.* forbidden
  d = {"material_requests_count": len(mreq)}      ← "requests" triggers security block

══════════ RULE 5 — WORKFLOW & DOCUMENT VIEWER ══════════

MANDATORY WORKFLOW EXECUTION PROTOCOL — follow ALL steps in order:

STEP 1 — DISCOVER (always first, never skip):
  • Call get_document(doctype, name) → read current docstatus + workflow_state
  • docstatus=0 → Draft, docstatus=1 → Submitted, docstatus=2 → Cancelled
  • If docstatus=2: tell the user the document is ALREADY cancelled — STOP, do NOT act.
  • If document is already in the requested state: tell the user — STOP, do NOT re-execute.

STEP 2 — VALIDATE TRANSITIONS (before acting):
  • Check: is the requested action valid for the CURRENT workflow state?
  • If unsure: call list_documents or get_document to confirm state before proceeding.
  • NEVER execute a workflow action on a stale/cached assumption — always fetch fresh.
  • NEVER approve a document already in Approved/Submitted state.
  • NEVER reject a document already Cancelled or Rejected.
  • NEVER cancel a Draft document (docstatus=0) via direct cancel — use workflow action only.

STEP 3 — EXECUTE via FAC (mandatory, FAC first always):
  • Check available FAC tools first — discover dynamically, NEVER assume tool names.
  • If run_workflow tool exists:
      run_workflow(doctype=X, name=Y, action="<exact action name>")
      — action must match EXACTLY the ERPNext workflow action name (case-sensitive).
      — args: use "name", NOT "docname" (confirmed correct field name).
  • If run_workflow NOT available:
      → embed <open_document doctype="X" docname="Y"/> so user can act in the viewer.
      → NEVER attempt frappe.client.cancel or frappe.client.submit as substitutes.

STEP 4 — CONFIRM (after action, always verify):
  • Call get_document(doctype, name) again → read updated docstatus + workflow_state.
  • Report the ACTUAL new state to the user — never assume success.
  • docstatus=1 after action → "✅ تم الاعتماد/التقديم — الحالة: [state]"
  • docstatus=2 after action → "🚫 تم الإلغاء — الحالة: [state]"
  • docstatus=0 new state  → "↩️ تم تغيير الحالة إلى [state]"

CANCELLATION RULES — CRITICAL:
  • ONLY docstatus=1 (Submitted) documents can be cancelled via ERPNext cancel API.
  • Draft documents (docstatus=0) can ONLY be cancelled via a workflow "Cancel" transition.
  • ALWAYS use run_workflow with the cancel/reject action name — NEVER frappe.client.cancel.
  • If no cancel action is available in the workflow, tell the user and embed <open_document>.

DUPLICATE ACTION PREVENTION:
  • Before acting: compare the requested outcome with the CURRENT workflow_state.
  • If already in that state: "المستند في الحالة [X] بالفعل — لا داعي لتنفيذ الإجراء."
  • Log: "[WF] Action skipped — document already in target state: [state]"

ERROR HANDLING:
  • run_workflow returns isError=true → show the EXACT error message to user — NEVER retry silently.
  • Permission denied → "ليس لديك صلاحية لتنفيذ هذا الإجراء على [docname]."
  • FAC tool not found → embed <open_document> as fallback — tell user to act in the viewer.
  • Network error → "حدث خطأ في الاتصال. يرجى المحاولة مرة أخرى."
  • Stale state (action no longer valid) → refetch document and report current state.

OPEN_DOCUMENT TAG — use whenever mentioning a SPECIFIC document by name:
  • Format: <open_document doctype="DocType" docname="document-name"/>
  • Self-closing tag only — NO inner content — one tag per document.
  • ALWAYS embed the tag so the user can open it with one tap.
  • Example single: "Leave request HR-LAV-0001: <open_document doctype="Leave Application" docname="HR-LAV-0001"/>"
  • Example list:   "• فاتورة ACC-SINV-0012 <open_document doctype="Sales Invoice" docname="ACC-SINV-0012"/>"

══════════ HR MODULE — CRITICAL FIELD RULES ══════════
⚠️ NEVER fetch 'workflow_state' from any of these DocTypes — the column does NOT exist in the database:
   Leave Application | Salary Slip | Attendance | Employee Checkin | Leave Allocation | Leave Encashment | Payroll Entry

✅ CORRECT filter for PENDING Leave Applications:
   filters: [["docstatus","=",0],["status","=","Open"]]
   fields:  ["name","employee","employee_name","leave_type","from_date","to_date",
             "total_leave_days","status","docstatus","description"]
   ⚠️ NEVER add "workflow_state" to the fields list — it will cause a DB column error.

✅ CORRECT filter for Salary Slip status:
   • Draft (pending):    filters: [["docstatus","=",0]]
   • Submitted (paid):   filters: [["docstatus","=",1]]
   • Cancelled:          filters: [["docstatus","=",2]]
   ⚠️ Do NOT filter by "status" on Salary Slip — use "docstatus" only.

✅ For Attendance status, use "status" field (values: "Present","Absent","On Leave","Half Day").
   ⚠️ NEVER use "workflow_state" or "docstatus" as an attendance filter.

✅ Leave Allocation: use "docstatus" (0=draft, 1=allocated) — no "workflow_state".

══════════ MODULE EXPERTISE — FAC-Powered KPIs ══════════
When the user asks about ANY ERPNext module, IMMEDIATELY call FAC to fetch live data.
NEVER estimate or assume — always use real system data via FAC.

★★★ PRIORITY ORDER: Purchasing > Accounting > HR > Inventory > Manufacturing > Sales ★★★

🟧 PURCHASING (HIGHEST PRIORITY — focus here first):
  KPIs: get_list("Purchase Order",filters=[["status","=","To Receive and Bill"]]) → pending POs
        get_list("Purchase Order",filters=[["status","=","To Bill"]]) → received, awaiting invoice
        get_list("Material Request",filters=[["status","=","Pending"]]) → pending requests
        get_list("Request for Quotation",filters=[["status","=","Submitted"]]) → open RFQs
        get_list("Supplier Quotation",filters=[["status","=","Submitted"]]) → supplier quotes
        get_list("Purchase Invoice",filters=[["status","=","Unpaid"]]) → unpaid payables
  Operations: Material Request → RFQ → Supplier Quotation → PO → GRN → Purchase Invoice → Payment
  Key reports: "Purchase Order Items to be Received", "Accounts Payable", "Purchase Analytics"

🟩 ACCOUNTING / FINANCE:
  KPIs: get_list("Sales Invoice",filters=[["status","=","Unpaid"]]) → receivables
        get_list("Purchase Invoice",filters=[["status","=","Unpaid"]]) → payables
        get_value("Account","Cash",["balance"]) → cash balance
  Operations: journal entries, reconciliation, budgets, trial balance, financial reports

🟦 HR / HUMAN RESOURCES:
  KPIs: get_list("Employee",filters=[["status","=","Active"]]) → headcount
        get_list("Leave Application",filters=[["docstatus","=",0],["status","=","Open"]]) → pending leaves
        get_list("Salary Slip",filters=[["docstatus","=",0]]) → draft payroll slips
  Operations: full lifecycle via RULE 4 + HR ONBOARDING AGENT sections above

🟥 STOCK / INVENTORY / WAREHOUSE:
  KPIs: get_list("Item",filters=[["reorder_level",">",0]]) → reorder alerts
        run_query to get stock value by warehouse
        get_list("Stock Entry",filters=[["docstatus","=",0]]) → pending stock entries
  Operations: stock entries, transfers, stocktaking, reorder rules, item valuation

⬛ MANUFACTURING:
  KPIs: get_list("Work Order",filters=[["status","=","In Process"]]) → active WOs
        get_list("Production Plan",filters=[["status","=","Submitted"]]) → plans
        get_list("Work Order",filters=[["status","=","Not Started"]]) → queued WOs
  Operations: BOM, production plan, work order, quality inspection, subcontracting

🟨 SALES / CRM:
  KPIs: get_list("Sales Order",filters=[["status","in",["To Deliver and Bill","To Bill"]]]) → open orders
        get_list("Customer",filters=[["creation",">","month_start"]]) → new customers
  Operations: quotes → orders → invoices → collections → CRM pipeline

🟪 PROJECTS:
  KPIs: get_list("Project",filters=[["status","=","Open"]]) → active projects
        get_list("Task",filters=[["status","=","Overdue"]]) → overdue tasks
  Operations: project setup, tasks, timesheets, cost tracking, milestones

🔵 ASSETS:
  KPIs: get_list("Asset",filters=[["status","=","Submitted"]]) → active assets
  Operations: asset purchase, depreciation schedule, disposal, maintenance

⚪ QUALITY:
  KPIs: get_list("Quality Inspection",filters=[["status","=","Pending"]]) → pending QC
  Operations: inspection templates, quality alerts, NCR management

For ANY OTHER module: use get_list / get_doctype_info / run_query to discover
available data and present the most relevant KPIs automatically.

══════════ HR ONBOARDING AGENT — Full Lifecycle ══════════
When the user asks to onboard an employee (or says "استقبل موظف" / "أنشئ onboarding" / "onboard"), activate this workflow and track progress internally:

INTERNAL STATE (maintain throughout conversation):
  employee | job_applicant | job_offer | onboarding_record | onboarding_stage | completed_steps[] | pending_steps[]

EXECUTION FLOW (12 steps — execute in order, use FAC for every action):

STEP 0 — LOAD CONTEXT
  • fetch Employee record via FAC
  • retrieve linked Job Applicant + Job Offer if they exist

STEP 1 — VALIDATE RECRUITMENT PIPELINE
  • if Job Applicant or Job Offer is missing → ask user: link existing OR continue without
  • do NOT block onboarding if user chooses to continue without

STEP 2 — VALIDATE EMPLOYEE RECORD
  Required fields: Employee Name, Company, Date of Joining, Department, Designation, Employment Type, Status
  • if any missing → tell user exactly: "HR → Employee → [Name] → Edit → update [field] → Save"
  • fix via FAC (update_document) if user confirms

STEP 3 — CREATE / VALIDATE EMPLOYEE ONBOARDING
  • check via FAC if an Employee Onboarding record already exists for this employee:
    get_list("Employee Onboarding", filters=[["employee","=","<employee_id>"]], fields=["name","docstatus","boarding_status"])
  • if a submitted record (docstatus=1) exists → continue from it, do NOT create a duplicate
  • if a draft record (docstatus=0) exists → offer: submit it OR delete and recreate
  • if none → create a NEW record via FAC with these EXACT fields:
      employee_name  : "<employee_name>"
      employee       : "<employee_id>"
      company        : "<company>"
      date_of_joining: "<YYYY-MM-DD>"
      onboarding_begins_on: "<YYYY-MM-DD>"

STEP 4 — APPLY ONBOARDING TEMPLATE
  LISTING templates:
  • call get_list("Employee Onboarding Template", fields=["name","department","designation","description"])
  VIEWING template activities:
  • call get_document(doctype="Employee Onboarding Template", name="<template_name>")
  APPLYING template:
  • call update_document(doctype="Employee Onboarding", name="<record_name>",
      values={"onboarding_template": "<template_name>"})
  • if NO template exists → ask: "Create template (recommended) OR continue manual?"

STEP 5 — GENERATE TASKS (submit onboarding)
  • Before submitting, call get_document("Employee Onboarding", name="<record>") to confirm
  • Submit via FAC: submit_document(doctype="Employee Onboarding", name="<record>")
  • Verify: call get_list("Task", filters=[["project","=","<project_name>"]], fields=["name","subject","status","assigned_to"])

STEP 6 — VALIDATE TASK STRUCTURE
  Check tasks include: document collection, background check, NDA, equipment, account setup
  • if missing → create the missing tasks via FAC (do NOT ask — just create and report)

STEP 7 — USER ACCOUNT CREATION
  • check if a User is linked to the Employee
  • if NOT → create User via FAC: email, full name, Enabled=Yes, Send Welcome Email=Yes
  • assign roles: Employee + any department-specific roles

STEP 8 — SYSTEM ACCESS CONTROL
  • check Role Profile and module access via FAC
  • if unclear → ask user once: "Which modules?"

STEP 9 — HR CONFIGURATION
  Check via FAC: Salary Structure, Leave Policy, Holiday List
  • if missing → ask: "Assign existing OR create new?" for each missing item

STEP 10 — DOCUMENT COLLECTION
  Check attachments on Employee record: ID Proof, Address Proof, Certificates
  • if missing → tell user: "Upload via Employee → Attachments"

STEP 11 — TASK TRACKING
  • check all onboarding task statuses via FAC
  • if pending → ask: "Notify employee / Notify task owners / Wait?"

STEP 12 — FINALIZATION
  Conditions: all tasks complete + documents uploaded + user active + HR setup done
  • set Employee Status = Active via FAC (update_document)
  • set Onboarding Status = Completed via FAC
  • report: "✅ Onboarding Completed — [Employee Name] is now fully active."

══════════ Human Resources — Full Module ══════════
You act as ALL of the following HR roles simultaneously — answer from the most relevant perspective:

👤 HR MANAGER
• Employee lifecycle: hire, transfer, promote, terminate
• Organization chart, departments, designations, grades, branches
• Policy setup: leave policies, attendance rules, shift assignments, holiday lists
• Payroll setup: salary structures, components (basic/HRA/allowances/deductions), payroll periods
• Run & submit payroll (Salary Slip, Payroll Entry) — single employee or bulk
• Full-cycle appraisals: KRA, goals, ratings, final scores
• Disciplinary actions, warning letters, exit interviews, full & final settlement
• Compliance: statutory deductions (GOSI/PIFSS/social security per country), tax slabs
• HR KPIs: headcount, turnover rate, average salary, cost per hire, absenteeism %

👥 HR EMPLOYEE (HR Staff — Daily Operations)
• Create & update employee records (personal info, emergency contact, family, education, experience)
• Process joining & onboarding documents
• Manage leave applications: approve / reject / cancel, carry-forward balances
• Attendance: mark, correct, import bulk, generate monthly summaries
• Process expense claims and advances
• Generate offer letters, appointment letters, experience certificates
• Handle loan applications, disbursements, repayment schedules
• Track training programs, skill matrix, certifications

🎓 HR CONSULTANT
• Diagnose HR gaps: high turnover, absenteeism spikes, overtime anomalies
• Recommend policy adjustments based on data trends
• Benchmark salary structures against market or internal grades
• Workforce planning: headcount projections, budget vs actual headcount
• Advise on ERPNext HR configuration best practices
• Identify missing setups (e.g. no shift assigned, no leave policy linked)

🙋 EMPLOYEE (Self-Service)
• View own payslips, YTD earnings, deductions
• Apply for leave, check leave balance by type
• Submit attendance regularization requests
• Submit expense claims with details
• View and acknowledge appraisal scores
• Check loan balance and repayment schedule
• Update personal / contact / bank details

📊 HR ANALYST
• Headcount reports: by department, designation, location, gender, nationality
• Payroll analytics: salary distribution, component-wise cost, MoM/YoY comparison
• Attendance analytics: late arrivals, absences, overtime hours, shift utilization
• Leave analytics: leave type utilization, pending approvals, encashment amounts
• Attrition analysis: joining vs leaving trend, tenure distribution, exit reasons
• Cost analysis: total payroll cost, benefit cost ratio, cost per department
• Appraisal summary: rating distribution, top performers, improvement list
• Always present HR data in structured Markdown tables with totals row where applicable

══════════ File Export (PDF / Excel / CSV) ══════════
Every data table automatically has built-in visible buttons:
   [PDF] [Save PDF] [Excel] [Save Excel] [Send by Email]

When the user requests export or email with attachment:
  Step 1 → Search FAC tools for: export_report | generate_pdf | export_to_excel | print_format
  Step 2 → If found → call immediately
  Step 3 → If not found → display data in Markdown table
            (user clicks the appropriate built-in button)

🚫 Never claim to export Excel/PDF yourself — always show data in a table.
🚫 Never ask the user to send email themselves — the "Send by Email" button is on every table.

══════════ Sending Email ══════════
🚫 NEVER say:
  ✗ "I'm unable to send emails directly"
  ✗ "I cannot send emails"
  ✗ "You may download the data manually and send it"
  ✗ "send it through your email provider"

✅ Only allowed action — execute in order:
  Step 1 → Search FAC tools for: send_email | send_mail | send_notification | frappe.sendmail | notify
  Step 2 → If found → call immediately with (recipient, subject, body)
  Step 3 → If no FAC email tool → send from system directly:
            <system_email to="RECIPIENT_EMAIL" subject="SUBJECT">BODY_TEXT</system_email>
  Step 4 → If system send fails:
            <send_email to="RECIPIENT_EMAIL" subject="SUBJECT">BODY_TEXT</send_email>

══════════ Mandatory Workflow ══════════
For every request:
  1. Call FAC tool to get data or execute the action
  2. Display results clearly (table or chart as requested — not both)
  3. If export requested → follow "File Export" section above
  4. If email requested → follow "Sending Email" section above
  5. Inform user of the final result

══════════ 🚫 Strict Refusal ══════════
If the question has nothing to do with ERPNext or company data:
Refuse immediately with one sentence only (in the user's language). No explanation, no apology, no exception.

══════════ Charts ══════════
• If user specified chart type and you have data → generate immediately
• If type not specified → ask once only: "Bar / Line / Pie?"
Format:
<chart>{"type":"bar","title":"Title","labels":["A","B"],"datasets":[{"label":"Series","data":[100,200],"color":"#4CAF50"}]}</chart>
Rules: bar/line/pie only — pure JSON inside tag — no code block

══════════ Tables ══════════
| Col 1 | Col 2 | Col 3 |
|-------|-------|-------|
| val   | val   | val   |
Rule: never combine a chart and a table in the same reply.''';
  }

  static List<Map<String, dynamic>> _stripOldImages(
    List<Map<String, dynamic>> messages, {
    int keepFull = 1,
  }) {
    if (messages.length <= keepFull) return messages;
    final result = <Map<String, dynamic>>[];
    final keepFrom = messages.length - keepFull;
    for (var i = 0; i < messages.length; i++) {
      if (i >= keepFrom) {
        result.add(messages[i]);
        continue;
      }
      final msg = messages[i];
      final content = msg['content'];
      if (content is List) {
        bool hasImage = content.any((b) {
          if (b is! Map) return false;
          final t = b['type'] as String? ?? '';
          return t == 'image' || t == 'image_url';
        });
        if (hasImage) {
          final stripped = content.map((b) {
            if (b is! Map) return b;
            final t = b['type'] as String? ?? '';
            if (t == 'image') {
              final mediaType = (b['source'] as Map?)?['media_type'] ?? 'image';
              return {
                'type': 'text',
                'text': '[Image: $mediaType — content was processed earlier]',
              };
            }
            if (t == 'image_url') {
              final url = (b['image_url'] as Map?)?['url'] as String? ?? '';
              final isData = url.startsWith('data:');
              return {
                'type': 'text',
                'text': isData
                    ? '[Image: was processed in a previous turn]'
                    : '[Image URL: $url]',
              };
            }
            return b;
          }).toList();
          result.add({...msg, 'content': stripped});
          continue;
        }
      }
      result.add(msg);
    }
    return result;
  }

  bool _isDnsError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('failed host lookup') ||
        msg.contains('no address associated') ||
        msg.contains('errno = 7') ||
        msg.contains('network is unreachable') ||
        msg.contains('errno = 101') ||
        msg.contains('errno = 111');
  }

  bool _isRetryableError(Object e) {
    if (_isDnsError(e)) return false;
    final msg = e.toString().toLowerCase();
    return msg.contains('connection abort') ||
        msg.contains('connection reset') ||
        msg.contains('software caused') ||
        msg.contains('broken pipe') ||
        msg.contains('clientexception') ||
        msg.contains('timeoutexception') ||
        msg.contains('connection closed');
  }

  Exception _friendlyError(Object e) {
    if (_isDnsError(e)) {
      return Exception(
        'لا يوجد اتصال بالإنترنت أو تعذّر الوصول إلى الخادم.\n'
        'تحقق من اتصال Wi-Fi أو البيانات وأعد المحاولة.',
      );
    }
    final msg = e.toString().toLowerCase();
    if (msg.contains('timeoutexception')) {
      return Exception(
        'انتهت مهلة الاتصال — الخادم لا يستجيب.\nتحقق من الاتصال وأعد المحاولة.',
      );
    }
    return e is Exception ? e : Exception(e.toString());
  }

  Future<T> _withRetry<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e) {
      if (_isRetryableError(e)) {
        debugPrint('⚠️ Connection error — retrying once: $e');
        await Future.delayed(const Duration(seconds: 2));
        try {
          return await fn();
        } catch (e2) {
          throw _friendlyError(e2);
        }
      }
      throw _friendlyError(e);
    }
  }

  Future<Map<String, dynamic>> _callChatGPT(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  ) async {
    if (_chatgptApiKey.isEmpty) {
      throw Exception('ChatGPT API Key غير مضبوط — أضفه في الإعدادات');
    }

    debugPrint(
      '→ ChatGPT $_chatgptModel | tools:${tools.length} history:${messages.length}',
    );

    final body = {
      'model': _chatgptModel,
      'max_completion_tokens': 4096,
      'messages': [
        {'role': 'system', 'content': _buildSystemPrompt()},
        ...messages,
      ],
      if (tools.isNotEmpty) 'tools': tools,
      if (tools.isNotEmpty) 'tool_choice': 'auto',
    };

    final response = await _withRetry(
      () => http
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $_chatgptApiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 120)),
    );

    if (response.statusCode != 200) {
      debugPrint(
        '❌ ChatGPT API error ${response.statusCode}: ${response.body}',
      );
      Map<String, dynamic> err;
      try {
        err = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw Exception('ChatGPT API error ${response.statusCode}');
      }
      final msg =
          (err['error'] as Map?)?['message'] ??
          'ChatGPT API error ${response.statusCode}';
      throw Exception(msg);
    }

    final result = jsonDecode(response.body) as Map<String, dynamic>;
    debugPrint(
      '← ChatGPT finish:${(result['choices'] as List?)?.first?['finish_reason']}',
    );

    return result;
  }

  Future<String> _runChatGPTLoop(
    String text,
    List<Map<String, dynamic>> openAiTools, {
    List<Map<String, dynamic>>? openAiUserContent,
  }) async {
    final l10n = AppLocalizations.of(context);

    _openAiHistory.add({
      'role': 'user',
      'content':
          openAiUserContent ??
          [
            {'type': 'text', 'text': text},
          ],
    });

    List<Map<String, dynamic>> buildHistory() {
      const maxHistory = 60;
      var list = _openAiHistory.length > maxHistory
          ? _openAiHistory.sublist(_openAiHistory.length - maxHistory)
          : List<Map<String, dynamic>>.from(_openAiHistory);

      while (list.isNotEmpty && list.first['role'] != 'user') {
        list = list.sublist(1);
      }

      while (list.isNotEmpty) {
        final firstAssistantIdx = list.indexWhere(
          (m) => m['role'] == 'assistant',
        );
        if (firstAssistantIdx == -1) break;
        final assistantMsg = list[firstAssistantIdx];
        final hasToolCalls =
            (assistantMsg['tool_calls'] as List?)?.isNotEmpty == true;
        final hasFollowingTool =
            firstAssistantIdx + 1 < list.length &&
            list[firstAssistantIdx + 1]['role'] == 'tool';
        if (hasFollowingTool && !hasToolCalls) {
          int cutTo = firstAssistantIdx + 1;
          while (cutTo < list.length && list[cutTo]['role'] == 'tool') {
            cutTo++;
          }
          list = list.sublist(cutTo);
          while (list.isNotEmpty && list.first['role'] != 'user') {
            list = list.sublist(1);
          }
          continue;
        }
        break;
      }

      return list;
    }

    final currentMessages = _stripOldImages(buildHistory());
    String finalReply = '';

    for (int turn = 0; turn < 20; turn++) {
      if (_isCancelled) return l10n.stoppedByUser;
      final result = await _callChatGPT(currentMessages, openAiTools);
      final choices = result['choices'] as List? ?? [];
      if (choices.isEmpty) break;

      final choice = choices.first as Map<String, dynamic>;
      final message = Map<String, dynamic>.from(
        choice['message'] as Map<String, dynamic>,
      );
      final finishReason = choice['finish_reason'] as String? ?? 'stop';

      if (message['content'] == null && (message['tool_calls'] == null)) {
        message['content'] = '';
      }

      currentMessages.add(message);

      if (finishReason == 'stop') {
        finalReply = message['content'] as String? ?? '';
        if (finalReply.isEmpty && turn < 19) {
          final nudge = {
            'role': 'user',
            'content':
                'Based on all the tool results above, write your final answer to the user NOW. Do NOT call any more tools. Do NOT say you cannot help. Just write the answer directly.',
          };
          currentMessages.add(nudge);
          _openAiHistory.add(nudge);
          continue;
        }
        _openAiHistory.add(message);
        break;
      }

      _openAiHistory.add(message);

      if (finishReason == 'tool_calls') {
        final toolCalls = (message['tool_calls'] as List?) ?? [];

        final parsed = toolCalls.map((tc) {
          final call = tc as Map<String, dynamic>;
          final fn = call['function'] as Map<String, dynamic>;
          Map<String, dynamic> input;
          try {
            input =
                jsonDecode(fn['arguments'] as String? ?? '{}')
                    as Map<String, dynamic>;
          } catch (_) {
            input = {};
          }
          return (
            id: call['id'] as String? ?? '',
            name: fn['name'] as String? ?? '',
            input: input,
          );
        }).toList();

        setState(
          () => _statusText = l10n.executingTool(
            parsed.map((p) => p.name).join(', '),
          ),
        );

        final results = await Future.wait(
          parsed.map((p) async {
            try {
              return await _executeTool(p.name, p.input);
            } catch (e) {
              return 'خطأ: $e';
            }
          }),
        );

        for (var i = 0; i < parsed.length; i++) {
          final toolMsg = {
            'role': 'tool',
            'tool_call_id': parsed[i].id,
            'content': results[i],
          };
          currentMessages.add(toolMsg);
          _openAiHistory.add(toolMsg);
        }

        setState(() => _statusText = l10n.processingResults);
        continue;
      }

      break;
    }

    return finalReply.isEmpty ? l10n.noReplyReceived : finalReply;
  }

  Future<Map<String, dynamic>> _callClaude(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  ) async {
    if (_claudeApiKey.isEmpty) {
      throw Exception('Claude API Key غير مضبوط — أضفه في الإعدادات');
    }

    debugPrint(
      '→ Claude $_model | tools:${tools.length} history:${messages.length}',
    );

    final body = {
      'model': _model,
      'max_tokens': 4096,
      'system': _buildSystemPrompt(),
      'messages': messages,
      if (tools.isNotEmpty) 'tools': tools,
    };

    final response = await _withRetry(
      () => http
          .post(
            Uri.parse('https://api.anthropic.com/v1/messages'),
            headers: {
              'x-api-key': _claudeApiKey,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 120)),
    );

    if (response.statusCode != 200) {
      debugPrint('❌ Claude API error ${response.statusCode}: ${response.body}');
      final err = jsonDecode(response.body);
      final msg =
          err['error']?['message'] ?? 'Claude API error ${response.statusCode}';
      throw Exception(msg);
    }

    final result = jsonDecode(response.body) as Map<String, dynamic>;
    debugPrint('← Claude stop:${result['stop_reason']}');

    return result;
  }

  Future<String> _executeTool(
    String toolName,
    Map<String, dynamic> toolInput,
  ) async {
    debugPrint('╔══ TOOL CALL ═══════════════════════════════');
    debugPrint('║ Tool  : $toolName');
    debugPrint('║ Input : ${jsonEncode(toolInput)}');
    debugPrint('╚════════════════════════════════════════════');

    final res = await _mcpRequest('tools/call', {
      'name': toolName,
      'arguments': toolInput,
    });

    final result = res['result'] as Map? ?? {};
    final content = result['content'] as List? ?? [];
    final isError = result['isError'] == true;

    String output;
    if (content.isNotEmpty) {
      output = content
          .map((c) => (c as Map)['text']?.toString() ?? c.toString())
          .join('\n');
    } else if (result.isEmpty || result.keys.every((k) => k == 'isError')) {
      output = isError
          ? 'Tool execution failed (no details)'
          : 'Done — tool executed successfully.';
    } else {
      output = result.toString();
    }

    if (isError) {
      output = 'Tool error: $output';
    }

    const maxChars = 12000;
    if (output.length > maxChars) {
      output =
          '${output.substring(0, maxChars)}\n\n[... Result truncated — ${output.length} chars → $maxChars chars shown]';
      debugPrint(
        '⚠️ Tool result truncated: ${output.length} → $maxChars chars',
      );
    }

    debugPrint('╔══ TOOL RESULT ═════════════════════════════');
    debugPrint('║ $output');
    debugPrint('╚════════════════════════════════════════════');

    return output;
  }

  Future<String> _runClaudeLoop(
    String text,
    List<Map<String, dynamic>> claudeTools, {
    dynamic claudeUserContent,
  }) async {
    final l10n = AppLocalizations.of(context);

    _claudeHistory.add({'role': 'user', 'content': claudeUserContent ?? text});

    List<Map<String, dynamic>> buildSendList() {
      const maxHistory = 60;
      var list = _claudeHistory.length > maxHistory
          ? _claudeHistory.sublist(_claudeHistory.length - maxHistory)
          : List<Map<String, dynamic>>.from(_claudeHistory);

      while (list.isNotEmpty && list.first['role'] != 'user') {
        list = list.sublist(1);
      }

      while (list.isNotEmpty) {
        final first = list.first;
        final content = first['content'];
        final isToolResult =
            content is List &&
            content.isNotEmpty &&
            (content.first as Map)['type'] == 'tool_result';
        if (!isToolResult) break;
        list = list.sublist(1);
        while (list.isNotEmpty && list.first['role'] != 'user') {
          list = list.sublist(1);
        }
      }

      return list;
    }

    debugPrint('📋 Claude history size: ${_claudeHistory.length}');

    final currentMessages = _stripOldImages(buildSendList());
    String finalReply = '';

    for (int turn = 0; turn < 20; turn++) {
      if (_isCancelled) return l10n.stoppedByUser;
      final claudeRes = await _callClaude(currentMessages, claudeTools);

      final stopReason = claudeRes['stop_reason'] as String? ?? 'end_turn';
      final content = claudeRes['content'] as List? ?? [];

      final assistantMsg = {'role': 'assistant', 'content': content};
      currentMessages.add(assistantMsg);

      if (stopReason == 'end_turn' || stopReason == 'stop_sequence') {
        for (final block in content) {
          if ((block as Map)['type'] == 'text') {
            finalReply += block['text']?.toString() ?? '';
          }
        }
        if (finalReply.isEmpty && turn < 19) {
          final nudge = {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text':
                    'Based on all the tool results above, write your final answer to the user NOW. Do NOT call any more tools. Do NOT say you cannot help. Just write the answer directly.',
              },
            ],
          };
          currentMessages.add(nudge);
          _claudeHistory.add(nudge);
          continue;
        }
        _claudeHistory.add(assistantMsg);
        break;
      }

      _claudeHistory.add(assistantMsg);

      if (stopReason == 'tool_use') {
        final toolUseBlocks = content
            .map((b) => b as Map)
            .where((b) => b['type'] == 'tool_use')
            .toList();

        setState(
          () => _statusText = l10n.executingTool(
            toolUseBlocks.map((b) => b['name']).join(', '),
          ),
        );

        final results = await Future.wait(
          toolUseBlocks.map((b) async {
            final name = b['name'] as String? ?? '';
            final input = Map<String, dynamic>.from(b['input'] as Map? ?? {});
            try {
              return (result: await _executeTool(name, input), isError: false);
            } catch (e) {
              return (result: 'خطأ: $e', isError: true);
            }
          }),
        );

        final toolResults = <Map<String, dynamic>>[];
        for (var i = 0; i < toolUseBlocks.length; i++) {
          toolResults.add({
            'type': 'tool_result',
            'tool_use_id': toolUseBlocks[i]['id'] as String? ?? '',
            'content': results[i].result,
            if (results[i].isError) 'is_error': true,
          });
        }

        final toolMsg = {'role': 'user', 'content': toolResults};
        currentMessages.add(toolMsg);
        _claudeHistory.add(toolMsg);

        setState(() => _statusText = l10n.processingResults);
        continue;
      }

      break;
    }

    return finalReply.isEmpty ? l10n.noReplyReceived : finalReply;
  }

  Future<void> _sendMessage([
    String? languageHint,
    String? overrideText,
  ]) async {
    final text = overrideText ?? _inputController.text.trim();
    if (text.isEmpty || _isLoading) return;

    final l10n = AppLocalizations.of(context);

    final mySession = _sessionId;
    _isCancelled = false;

    await _loadConfig();
    if (overrideText == null) _inputController.clear();

    final attachments = List<_Attachment>.from(_pendingAttachments);
    setState(() => _pendingAttachments.clear());

    final aiText = languageHint != null
        ? '[Voice message — detected language: $languageHint. You MUST reply in $languageHint only.]\n$text'
        : text;

    setState(() {
      _showModuleButtons = false;
      _messages.add(
        _Message(
          role: 'user',
          text: text,
          time: DateTime.now(),
          attachments: attachments,
        ),
      );
      _isLoading = true;
      _errorBanner = null;
      _statusText = l10n.connectingServer;
    });
    _scrollToBottom();

    _autoSave();

    try {
      setState(() => _statusText = l10n.loadingTools);
      List<Map<String, dynamic>> mcpTools;
      try {
        mcpTools = await _getTools();
      } catch (e) {
        throw Exception(
          'تعذر الاتصال بـ MCP Server في ERPNext:\n$e\n\nتحقق من الـ URL وبيانات الدخول في الإعدادات.',
        );
      }

      if (mcpTools.isEmpty) {
        throw Exception(
          'MCP Server لم يُرجع أي أدوات. تأكد من تثبيت Frappe Assistant Core على الخادم.',
        );
      }

      setState(() => _statusText = l10n.toolsLoaded(mcpTools.length));

      final claudeTools = _toClaudeTools(mcpTools);
      final openAiTools = _toOpenAITools(mcpTools);

      final freshAttachments = attachments
          .where((a) => !a.fromHistory)
          .toList();
      if (freshAttachments.isNotEmpty) await _ensureBytes(freshAttachments);

      String normMime(String mime) => _normMime(mime);

      final claudeImageBlocks = <Map<String, dynamic>>[];
      final openAiImageBlocks = <Map<String, dynamic>>[];

      for (final a in attachments) {
        if (a.fromHistory) continue;
        if (a.isImage && a.bytes.isNotEmpty) {
          claudeImageBlocks.add({
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': normMime(a.mime),
              'data': base64Encode(a.bytes),
            },
          });
          openAiImageBlocks.add({
            'type': 'image_url',
            'image_url': {
              'url': 'data:${normMime(a.mime)};base64,${base64Encode(a.bytes)}',
              'detail': 'high',
            },
          });
        } else if (!a.isImage) {
          final txt = _extractFileText(a.bytes, a.name, a.mime);
          final block = {
            'type': 'text',
            'text': txt != null
                ? '📎 File: ${a.name}\n\n```\n$txt\n```'
                : '📎 File: ${a.name} (binary)',
          };
          claudeImageBlocks.add(block);
          openAiImageBlocks.add(block);
        }
      }

      if (attachments.isNotEmpty) {
        setState(() => _statusText = l10n.uploadingFiles);
        await _uploadAttachmentsToErpNext(attachments);
      }

      String fileUrlContext = '';
      for (final a in attachments) {
        if (a.erpUrl != null) {
          // Phrase "is saved on ERPNext server" is referenced in RULE 0.5 — keep it verbatim
          fileUrlContext +=
              '📎 File "${a.name}" is saved on ERPNext server. '
              'file_url: "${a.erpUrl}"\n'
              '   MIME: ${a.mime} | Size: ~${(a.bytes.length / 1024).round()} KB\n'
              '   Use this EXACT file_url in FAC calls — NEVER fabricate a URL.\n'
              '${_facRoutingHint(a.name, a.mime)}\n';
          debugPrint('[OCR] ✅ file_url ready: ${a.erpUrl}  (${a.bytes.length} bytes, ${a.mime})');
        } else if (a.isImage && a.bytes.isNotEmpty) {
          fileUrlContext +=
              '📎 Image "${a.name}" is embedded below as base64 (could NOT be saved to ERPNext).\n'
              '   MIME: ${a.mime} | Use VISUAL analysis only — no file_url available.\n'
              '   If barcode suspected → extract from the visual, then search ERPNext by code.\n\n';
          debugPrint('[OCR] ⚠️ Image "${a.name}" sent as base64 only (upload failed)');
        } else {
          fileUrlContext +=
              '📎 File "${a.name}" could not be uploaded to ERPNext (${a.bytes.length} bytes).\n\n';
          debugPrint('[OCR] ❌ Upload failed for "${a.name}"');
        }
      }
      final aiTextWithFiles = fileUrlContext.isEmpty
          ? aiText
          : '$fileUrlContext--- USER MESSAGE ---\n$aiText';

      for (final a in attachments) {
        if (a.isImage && a.bytes.isEmpty && a.erpUrl != null) {
          claudeImageBlocks.add({
            'type': 'text',
            'text': '📎 Image: ${a.name} (available at ${a.erpUrl})',
          });
          openAiImageBlocks.add({
            'type': 'text',
            'text': '📎 Image: ${a.name} (available at ${a.erpUrl})',
          });
        }
      }

      List<Map<String, dynamic>>? claudeUserContent;
      List<Map<String, dynamic>>? openAiUserContent;

      if (attachments.isNotEmpty) {
        final textBlock = aiTextWithFiles.isEmpty
            ? 'Please analyze the attached content.'
            : aiTextWithFiles;
        claudeUserContent = [
          ...claudeImageBlocks,
          {'type': 'text', 'text': textBlock},
        ];
        openAiUserContent = [
          {'type': 'text', 'text': textBlock},
          ...openAiImageBlocks,
        ];
      }

      setState(() => _statusText = l10n.thinking);

      String reply;

      switch (_aiProvider) {
        case 'chatgpt':
          reply = await _runChatGPTLoop(
            aiTextWithFiles,
            openAiTools,
            openAiUserContent: openAiUserContent,
          );

        case 'claude_first':
          try {
            setState(() => _statusText = l10n.tryingProvider('Claude'));
            reply = await _runClaudeLoop(
              aiTextWithFiles,
              claudeTools,
              claudeUserContent: claudeUserContent,
            );
            if (reply == l10n.noReplyReceived) {
              throw Exception('Claude returned no response — trying ChatGPT');
            }
          } catch (e) {
            debugPrint('⚠️ Claude failed ($e) — falling back to ChatGPT');
            setState(() => _statusText = l10n.fallbackToProvider('ChatGPT'));
            reply = await _runChatGPTLoop(
              aiTextWithFiles,
              openAiTools,
              openAiUserContent: openAiUserContent,
            );
          }

        case 'chatgpt_first':
          try {
            setState(() => _statusText = l10n.tryingProvider('ChatGPT'));
            reply = await _runChatGPTLoop(
              aiTextWithFiles,
              openAiTools,
              openAiUserContent: openAiUserContent,
            );
            if (reply == l10n.noReplyReceived) {
              throw Exception('ChatGPT returned no response — trying Claude');
            }
          } catch (e) {
            debugPrint('⚠️ ChatGPT failed ($e) — falling back to Claude');
            setState(() => _statusText = l10n.fallbackToProvider('Claude'));
            reply = await _runClaudeLoop(
              aiTextWithFiles,
              claudeTools,
              claudeUserContent: claudeUserContent,
            );
          }

        default:
          reply = await _runClaudeLoop(
            aiTextWithFiles,
            claudeTools,
            claudeUserContent: claudeUserContent,
          );
      }

      if (_sessionId != mySession || !mounted) return;

      if (reply.isNotEmpty) {
        setState(() {
          _messages.add(
            _Message(role: 'assistant', text: reply, time: DateTime.now()),
          );
        });
        _detectModuleFromText(reply);
        _autoSave();
        // Trigger OCR Workflow Engine when image + scan keywords detected
        _maybeRunOcrWorkflow(
          userMessage: text,
          attachments: attachments,
          aiResponse:  reply,
          session:     mySession,
        ).ignore();
      }
    } catch (e) {
      if (_sessionId != mySession || !mounted) return;
      setState(() => _errorBanner = e.toString());
    } finally {
      _isCancelled = false;
      _freeUploadedBytes();
      if (_sessionId == mySession && mounted) {
        setState(() {
          _isLoading = false;
          _statusText = '';
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearChat() {
    setState(() {
      _sessionId++;
      _isCancelled = true;
      _showModuleButtons = true;
      _messages.clear();
      _claudeHistory.clear();
      _openAiHistory.clear();
      _errorBanner = null;
      _sessionNote = null;
    });
    SharedPreferences.getInstance().then((p) => p.remove(_kClaudeHistoryKey));
    Future.delayed(const Duration(milliseconds: 50)).then((_) {
      if (mounted) setState(() => _isCancelled = false);
    });
  }

  Future<void> _newChat() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.of(context).surface,
        title: Text(
          l10n.newChatSession,
          style: TextStyle(color: AppColors.of(context).textPrimary),
        ),
        content: Text(
          l10n.newChatConfirm,
          style: TextStyle(color: AppColors.of(context).textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              l10n.cancel,
              style: TextStyle(color: AppColors.of(context).textSecondary),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: Icon(Icons.add_comment_outlined, size: 16),
            label: Text(l10n.newChatSession),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _sessionId++;
      _isCancelled = true;
      _messages.clear();
      _claudeHistory.clear();
      _openAiHistory.clear();
      _errorBanner = null;
      _sessionNote = null;
    });
    SharedPreferences.getInstance().then((p) => p.remove(_kClaudeHistoryKey));
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      setState(() => _isCancelled = false);
      _injectWelcomeMessage();
    });
  }

  Future<void> _autoSave() async {
    if (_messages.isEmpty || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final firstUser =
          _messages
              .where((m) => m.role == 'user')
              .map((m) => m.text)
              .firstOrNull ??
          '';
      final truncated = firstUser.length > 60
          ? '${firstUser.substring(0, 60)}…'
          : firstUser;
      final title = 'AI Chat — $truncated';

      final payload = jsonEncode({
        'v': 2,
        'messages': _messages
            .map(
              (m) => {
                'r': m.role,
                't': m.text,
                'ts': m.time.toIso8601String(),
                if (m.attachments.isNotEmpty)
                  'at': m.attachments
                      .where((a) => a.erpUrl != null)
                      .map((a) => a.toJson())
                      .toList(),
              },
            )
            .toList(),
      });
      final content = '<!-- AICHAT_V1 -->\n$payload\n<!-- /AICHAT_V1 -->';

      if (_sessionNote == null) {
        final result = await ApiService.post('/api/resource/Note', {
          'title': title,
          'content': content,
          'public': 0,
        });
        _sessionNote = result['data']?['name'] as String?;
      } else {
        await ApiService.put('/api/resource/Note/$_sessionNote', {
          'content': content,
        });
      }
    } catch (e) {
      debugPrint('Auto-save error: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
    await _persistHistory();
  }

  Future<void> _openHistory() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const ChatHistoryPage()),
    );
    if (result == null || !mounted) return;

    final data = result['data'] as Map<String, dynamic>?;
    if (data == null) return;

    final msgs = data['messages'] as List? ?? [];
    setState(() {
      _sessionId++;
      _isCancelled = true;
      _showModuleButtons = false;
      _messages.clear();
      _claudeHistory.clear();
      _openAiHistory.clear();
      _errorBanner = null;
      _sessionNote = result['name'] as String?;
      for (final m in msgs) {
        final ats = m['at'] as List? ?? [];
        final restoredAttachments = ats
            .map(
              (a) => _Attachment(
                bytes: const [],
                name: a['n'] as String? ?? '',
                mime: a['m'] as String? ?? 'application/octet-stream',
                erpUrl: a['u'] as String?,
                isPrivate: (a['p'] as int? ?? 0) == 1,
                fromHistory: true,
              ),
            )
            .toList();
        _messages.add(
          _Message(
            role: m['r'] as String? ?? 'user',
            text: m['t'] as String? ?? '',
            time: DateTime.tryParse(m['ts'] as String? ?? '') ?? DateTime.now(),
            attachments: restoredAttachments,
          ),
        );
      }
    });
    Future.delayed(const Duration(milliseconds: 50)).then((_) {
      if (mounted) setState(() => _isCancelled = false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  // ── OCR Workflow Engine integration ─────────────────────────────────────────

  /// Keywords that trigger the OCR Workflow Engine after an AI response.
  static const _kOcrTriggers = {
    'scan', 'invoice', 'receipt', 'extract', 'ocr', 'bill',
    'فاتورة', 'إيصال', 'استخرج', 'قرأ', 'بيانات الفاتورة', 'امسح', 'مستند',
  };

  static bool _isOcrTrigger(String message) {
    final lower = message.toLowerCase();
    return _kOcrTriggers.any((k) => lower.contains(k));
  }

  /// Called after the main AI response when image attachments were present.
  /// Runs the OCR Workflow Engine on the AI's visual analysis text and injects
  /// a structured result card as a follow-up assistant message.
  Future<void> _maybeRunOcrWorkflow({
    required String userMessage,
    required List<_Attachment> attachments,
    required String aiResponse,
    required int session,
  }) async {
    if (!_isOcrTrigger(userMessage)) return;
    final hasImages = attachments.any((a) => a.isImage && a.bytes.isNotEmpty);
    if (!hasImages || aiResponse.trim().isEmpty) return;
    if (_sessionId != session || !mounted) return;

    debugPrint('[OCR-Trigger] Image + scan intent detected — running OcrWorkflowEngine');

    try {
      final l    = AppLocalizations.of(context);
      final lang = l.isArabic ? 'ar' : 'en';

      // Use the AI's visual analysis as the OCR text source — Claude already
      // read the image content; the engine structures it deterministically.
      final result = await OcrWorkflowEngine().processText(
        aiResponse,
        confidence: 0.80,
        engine:     'claude_vision',
        language:   lang,
      );

      debugPrint('[OCR-Trigger] Result: ${result.status.name} '
          'type=${result.documentType.key} intent=${result.intent.key}');

      if (_sessionId != session || !mounted) return;

      // Only inject the card when there's actionable structured data
      if (result.isFailed && result.failReason == 'invalid_ocr_input') return;

      setState(() {
        _messages.add(_Message(
          role: 'assistant',
          text: _formatOcrResult(result, l),
          time: DateTime.now(),
        ));
      });
      _scrollToBottom();
      _autoSave();
    } catch (e) {
      debugPrint('[OCR-Trigger] Engine error: $e');
    }
  }

  /// Formats an [OcrWorkflowResult] as a Markdown string for display in chat.
  static String _formatOcrResult(OcrWorkflowResult result, AppLocalizations l) {
    final buf  = StringBuffer();
    final isAr = l.isArabic;

    buf.writeln('## ${result.documentType.icon} ${isAr ? "نتيجة تحليل المستند" : "Document Analysis"}');
    buf.writeln();

    final statusLine = switch (result.status) {
      OcrStatus.success     => isAr ? '✅ اكتمل الاستخراج البنيوي' : '✅ Structured extraction complete',
      OcrStatus.needsReview => isAr ? '⚠️ يتطلب مراجعة بشرية (ثقة منخفضة)' : '⚠️ Needs human review (low confidence)',
      OcrStatus.failed      => isAr ? '❌ فشل المعالجة' : '❌ Processing failed',
    };
    buf.writeln('**${isAr ? "الحالة" : "Status"}:** $statusLine');

    if (result.isFailed) {
      buf.writeln('**${isAr ? "السبب" : "Reason"}:** ${result.failReason}');
      return buf.toString();
    }

    buf.writeln('**${isAr ? "نوع المستند" : "Document Type"}:** '
        '${result.documentType.icon} ${result.documentType.label}');
    buf.writeln('**${isAr ? "الإجراء المقترح" : "Intent"}:** ${result.intent.label}');
    buf.writeln('**${isAr ? "الثقة" : "Confidence"}:** '
        '${(result.confidence * 100).toStringAsFixed(0)}%');
    buf.writeln();

    // Extracted entities table
    final rows = result.entities.nonNullEntries.toList();
    if (rows.isNotEmpty) {
      buf.writeln('### 📋 ${isAr ? "البيانات المستخرجة" : "Extracted Entities"}');
      buf.writeln('| ${isAr ? "الحقل" : "Field"} | ${isAr ? "القيمة" : "Value"} |');
      buf.writeln('|-------|-------|');
      for (final e in rows) {
        buf.writeln('| **${e.key}** | ${e.value} |');
      }
      buf.writeln();
    }

    // Recommended ERPNext action
    if (result.fac != null && result.erpnext != null) {
      buf.writeln('### 🚀 ${isAr ? "إجراء ERPNext" : "ERPNext Action"}');
      buf.writeln('| | |');
      buf.writeln('|---|---|');
      buf.writeln('| FAC Skill | `${result.fac!.skill}` |');
      buf.writeln('| FAC Tool  | `${result.fac!.tool}` |');
      buf.writeln('| DocType   | `${result.erpnext!.doctype}` |');
      buf.writeln('| ${isAr ? "العملية" : "Operation"} | `${result.erpnext!.operation}` |');
      buf.writeln();
    }

    if (result.isNeedsReview) {
      buf.writeln('> ⚠️ ${isAr ? "ثقة منخفضة — تحقق من القيم قبل التنفيذ." : "Low confidence — verify values before executing."}');
    }

    if (result.canExecute) {
      final hint = isAr
          ? 'قل **"أنشئ المستند"** لتنفيذ هذا الإجراء في ERPNext عبر FAC.'
          : 'Say **"Create the document"** to execute this action in ERPNext via FAC.';
      buf.writeln('> 💡 $hint');
    }

    buf.writeln();
    buf.writeln('---');
    buf.writeln('*${isAr ? "تحليل المحرك" : "Engine reasoning"}: ${result.reasoning}*');

    return buf.toString();
  }

  // ── Document viewer navigation ────────────────────────────────────────────

  // Navigate to DocumentViewerPage when AI embeds <open_document> tag.
  // Awaits the route so we can clear tracking if the user closes without acting.
  Future<void> _openDocument(String doctype, String docname) async {
    _lastOpenedDoctype = doctype;
    _lastOpenedDocname = docname;

    debugPrint('[AI-WF] Opening document viewer: $doctype / $docname');

    await Navigator.pushNamed(
      context,
      '/document-viewer',
      arguments: {'doctype': doctype, 'docname': docname},
    );

    // If _onWorkflowEvent already consumed the tracking (action taken in viewer),
    // both fields are already null. Otherwise the user closed without acting — clear.
    if (mounted && _lastOpenedDocname != null) {
      debugPrint('[AI-WF] Viewer closed without workflow action — clearing tracking');
      _lastOpenedDoctype = null;
      _lastOpenedDocname = null;
    }
  }

  Future<void> _createDashboardChart(Map<String, dynamic> chartData) async {
    final l10n = AppLocalizations.of(context);
    final title = chartData['title'] as String? ?? l10n.chartFromAssistant;
    final type = (chartData['type'] as String? ?? 'bar').toLowerCase();
    final labels =
        (chartData['labels'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final datasets =
        (chartData['datasets'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.of(context).surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(
              Icons.add_chart_rounded,
              color: AppColors.of(context).primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              l10n.saveChart,
              style: TextStyle(
                color: AppColors.of(context).textPrimary,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow(Icons.label_outline, l10n.chartName, title),
            const SizedBox(height: 6),
            _infoRow(Icons.bar_chart_rounded, l10n.chartType, type),
            const SizedBox(height: 6),
            _infoRow(
              Icons.category_outlined,
              l10n.chartCategories,
              l10n.categoriesCount(labels.length),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.chartWillCreate,
              style: TextStyle(
                color: AppColors.of(context).textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('إلغاء'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.of(context).primary,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: Icon(Icons.save_rounded, size: 16),
            label: Text('حفظ'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final frappeDatasets = datasets
        .map(
          (d) => {
            'name': d['label'] as String? ?? '',
            'values': (d['data'] as List? ?? [])
                .map((v) => v is num ? v : double.tryParse(v.toString()) ?? 0)
                .toList(),
          },
        )
        .toList();

    final customOptions = jsonEncode({
      'data': {'labels': labels, 'datasets': frappeDatasets},
      'type': type,
    });

    final erpType = type == 'line'
        ? 'Line'
        : type == 'pie'
        ? 'Pie'
        : 'Bar';

    try {
      setState(() => _statusText = l10n.savingChart);
      await ApiService.post('/api/resource/Dashboard Chart', {
        'chart_name': title,
        'chart_type': 'Custom',
        'type': erpType,
        'custom_options': customOptions,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.chartSaved(title)),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.chartSaveFailed(e.toString())),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _statusText = '');
    }
  }

  Future<void> _sendEmailViaSystem(
    String to,
    String subject,
    String htmlBody,
    Uint8List? pdfBytes,
  ) async {
    try {
      setState(() => _statusText = 'جارٍ إرسال البريد...');

      String attachmentsJson = '[]';
      if (pdfBytes != null && pdfBytes.isNotEmpty) {
        setState(() => _statusText = 'جارٍ رفع المرفق...');
        final fileUrl = await _uploadEmailAttachment(pdfBytes, 'report.pdf');
        if (fileUrl != null) {
          attachmentsJson = jsonEncode([
            {'file_url': fileUrl, 'file_name': 'report.pdf'},
          ]);
        }
      }

      setState(() => _statusText = 'جارٍ إرسال البريد...');
      await ApiService.postForm(
        '/api/method/frappe.core.doctype.communication.email.make',
        {
          'recipients': to,
          'subject': subject,
          'content': htmlBody,
          'send_email': '1',
          'sent_or_received': 'Sent',
          'communication_medium': 'Email',
          'communication_type': 'Communication',
          if (attachmentsJson != '[]') 'attachments': attachmentsJson,
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pdfBytes != null
                ? '✅ تم إرسال البريد مع المرفق إلى $to'
                : '✅ تم إرسال البريد إلى $to',
          ),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ فشل إرسال البريد: $e'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _statusText = '');
    }
  }

  Future<String?> _uploadEmailAttachment(
    Uint8List bytes,
    String filename,
  ) async {
    try {
      final baseUrl = await ApiService.getErpNextUrl();
      final headers = await ApiService.getAiAuthHeaders();
      final request =
          http.MultipartRequest(
              'POST',
              Uri.parse('$baseUrl/api/method/upload_file'),
            )
            ..headers.addAll(headers)
            ..fields['is_private'] = '1'
            ..files.add(
              http.MultipartFile.fromBytes('file', bytes, filename: filename),
            );

      final streamed = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final body = await streamed.stream.bytesToString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      return (json['message'] as Map?)?['file_url'] as String?;
    } catch (e) {
      debugPrint('⚠️ Attachment upload failed: $e');
      return null;
    }
  }

  static String _normMime(String mime) =>
      mime == 'image/jpg' ? 'image/jpeg' : mime;

  /// Generates FAC routing hints for a given attachment.
  /// Injected into fileUrlContext — guides AI to the correct pipeline per file type.
  /// Hints are SUGGESTIONS, not mandatory: the AI decides based on user intent + image content.
  static String _facRoutingHint(String name, String mime) {
    final ext   = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final isImg = mime.startsWith('image/');
    if (isImg) {
      // Image: AI already has the visual via base64 — use native vision directly, NOT FAC OCR
      return '   💡 IMAGE: Use YOUR NATIVE VISION on the base64 already provided.\n'
          '      • Text/invoice/form/ID → extract text visually yourself (no FAC OCR needed)\n'
          '      • Barcode/QR code      → fetch_barcode(file_url) then get_document("Item", code)\n'
          '      🚫 Do NOT call extract-file-content-usage — server OCR engine is unavailable.\n';
    }
    if (ext == 'pdf') {
      return '   💡 PDF: run extract-file-content-usage(file_url) for full text.\n'
          '      If result is empty/error → inform user the PDF may be scanned/image-based.\n';
    }
    if ({'xlsx', 'xls', 'csv'}.contains(ext)) {
      return '   💡 Spreadsheet: run extract-file-content-usage(file_url)\n'
          '      Then analyze_business_data on extracted rows.\n';
    }
    if ({'docx', 'doc', 'odt'}.contains(ext)) {
      return '   💡 Document: run extract-file-content-usage(file_url).\n'
          '      Summarize content; if structured data → offer to import into ERPNext.\n';
    }
    return '   💡 Run extract-file-content-usage(file_url) to analyze this file.\n';
  }

  void _freeUploadedBytes() {
    for (final msg in _messages) {
      for (final a in msg.attachments) {
        if (a.erpUrl != null && a.bytes.isNotEmpty) {
          a.bytes = [];
        }
      }
    }
  }

  Future<void> _uploadAttachmentsToErpNext(
    List<_Attachment> attachments,
  ) async {
    for (final a in attachments) {
      if (a.fromHistory) continue;
      if (a.bytes.isEmpty) {
        debugPrint('[OCR] ⏭ Skip "${a.name}" — bytes empty');
        continue;
      }
      if (a.erpUrl != null) {
        debugPrint('[OCR] ⏭ Skip "${a.name}" — already at ${a.erpUrl}');
        continue;
      }

      debugPrint('[OCR] ── Upload pipeline ─────────────────────────────');
      debugPrint('[OCR] [A] file="${a.name}" mime=${a.mime} bytes=${a.bytes.length} private=${a.isPrivate}');

      try {
        final baseUrl     = await ApiService.getErpNextUrl();
        final authHeaders = await ApiService.getAiAuthHeaders();
        if (baseUrl.isEmpty) {
          debugPrint('[OCR] ❌ ERPNext URL empty — check Settings');
          continue;
        }

        final mimeStr = _normMime(a.mime);
        final parts   = mimeStr.split('/');
        final ct      = MediaType(
          parts[0],
          parts.length > 1 ? parts[1] : 'octet-stream',
        );
        debugPrint('[OCR] [B] POST $baseUrl/api/method/upload_file  ct=$mimeStr');

        final request = http.MultipartRequest(
              'POST', Uri.parse('$baseUrl/api/method/upload_file'))
            ..headers.addAll(authHeaders)
            ..fields['is_private'] = a.isPrivate ? '1' : '0'
            ..files.add(http.MultipartFile.fromBytes(
              'file', a.bytes,
              filename: a.name, contentType: ct,
            ));

        if (authHeaders.containsKey('Cookie')) {
          final prefs = await SharedPreferences.getInstance();
          final csrf  = prefs.getString('erpnext_csrf_token') ?? '';
          if (csrf.isNotEmpty) request.headers['X-Frappe-CSRF-Token'] = csrf;
        }

        final streamed = await request.send().timeout(const Duration(seconds: 30));
        final body     = await streamed.stream.bytesToString();
        debugPrint('[OCR] [C] HTTP=${streamed.statusCode} body=${body.substring(0, body.length.clamp(0, 300))}');

        if (streamed.statusCode != 200) {
          debugPrint('[OCR] ❌ HTTP ${streamed.statusCode} — '
              'check Nginx client_max_body_size, CORS, and session auth');
          continue;
        }

        late Map<String, dynamic> json;
        try {
          json = jsonDecode(body) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('[OCR] ❌ JSON parse failed: $e');
          continue;
        }

        if (json.containsKey('exc_type') || json.containsKey('_server_messages')) {
          debugPrint('[OCR] ❌ Frappe error: ${json["exc_type"]} — ${json["_server_messages"]}');
          continue;
        }

        final fileUrl = json['message']?['file_url'] as String?;
        if (fileUrl != null) {
          a.erpUrl = fileUrl;
          debugPrint('[OCR] ✅ Upload OK → file_url=$fileUrl');
        } else {
          debugPrint('[OCR] ⚠️ No file_url in response — message keys: ${(json["message"] as Map?)?.keys}');
        }
      } catch (e) {
        debugPrint('[OCR] ❌ Upload exception for "${a.name}": $e');
      }
      debugPrint('[OCR] ── Upload pipeline end ─────────────────────────');
    }
    _autoSave();
  }

  Future<void> _ensureBytes(List<_Attachment> attachments) async {
    final prefs   = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('erpnext_url') ?? '';
    final cookie  = prefs.getString('erpnext_session_cookie') ?? '';
    for (final a in attachments) {
      if (a.bytes.isNotEmpty || a.erpUrl == null) continue;
      debugPrint('[OCR] _ensureBytes: downloading "${a.name}" from ${a.erpUrl}');
      try {
        final url  = a.erpUrl!.startsWith('http') ? a.erpUrl! : '$baseUrl${a.erpUrl}';
        final resp = await http
            .get(Uri.parse(url), headers: {'Cookie': cookie})
            .timeout(const Duration(seconds: 20));
        if (resp.statusCode == 200) {
          a.bytes = List<int>.from(resp.bodyBytes);
          debugPrint('[OCR] _ensureBytes: ✅ ${a.bytes.length} bytes downloaded for "${a.name}"');
        } else {
          debugPrint('[OCR] _ensureBytes: ❌ HTTP ${resp.statusCode} for "${a.name}"');
        }
      } catch (e) {
        debugPrint('[OCR] _ensureBytes: ❌ exception for "${a.name}": $e');
      }
    }
  }

  String? _extractFileText(List<int> bytes, String name, String mime) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';

    const textExts = {
      'txt',
      'csv',
      'json',
      'xml',
      'html',
      'htm',
      'md',
      'yaml',
      'yml',
      'dart',
      'py',
      'js',
      'ts',
      'java',
      'kt',
      'swift',
      'c',
      'cpp',
      'h',
      'cs',
      'go',
      'rb',
      'php',
      'sql',
      'sh',
      'bat',
      'ini',
      'cfg',
      'conf',
      'log',
    };
    if (textExts.contains(ext) || mime.startsWith('text/')) {
      try {
        final text = utf8.decode(bytes, allowMalformed: true).trim();
        return text.isEmpty ? null : text;
      } catch (_) {
        return null;
      }
    }

    if (bytes.length > 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04) {
      return _extractZipOfficeText(bytes, ext);
    }

    if (ext == 'pdf' || mime == 'application/pdf') {
      return _extractPdfText(bytes);
    }

    return null;
  }

  String? _extractZipOfficeText(List<int> bytes, String ext) {
    try {
      final archive = ZipDecoder().decodeBytes(Uint8List.fromList(bytes));

      String? readXml(String path) {
        final f = archive.findFile(path);
        if (f == null) return null;
        try {
          return utf8.decode(f.content as List<int>, allowMalformed: true);
        } catch (_) {
          return null;
        }
      }

      if (ext == 'docx' || ext == 'odt') {
        final xml = readXml('word/document.xml') ?? readXml('content.xml');
        if (xml == null) return null;
        final buf = StringBuffer();
        for (final m in RegExp(r'<w:t[^>]*>([\s\S]*?)</w:t>').allMatches(xml)) {
          final s = m.group(1) ?? '';
          if (s.isNotEmpty) buf.write(s);
        }
        if (buf.isEmpty) {
          for (final m in RegExp(
            r'<text:p[^>]*>([\s\S]*?)</text:p>',
          ).allMatches(xml)) {
            final s = m.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '') ?? '';
            if (s.trim().isNotEmpty) buf.writeln(s.trim());
          }
        }
        final result = buf.toString().trim();
        return result.length > 30 ? result : null;
      }

      if (ext == 'xlsx' || ext == 'ods') {
        final xml = readXml('xl/sharedStrings.xml') ?? readXml('content.xml');
        if (xml == null) return null;
        final texts = RegExp(r'<(?:t|text:p)[^>]*>([\s\S]*?)</(?:t|text:p)>')
            .allMatches(xml)
            .map(
              (m) =>
                  (m.group(1) ?? '').replaceAll(RegExp(r'<[^>]+>'), '').trim(),
            )
            .where((s) => s.isNotEmpty)
            .toList();
        return texts.isNotEmpty ? texts.join(' | ') : null;
      }

      if (ext == 'pptx') {
        final buf = StringBuffer();
        for (final file in archive.files) {
          if (file.isFile &&
              file.name.startsWith('ppt/slides/slide') &&
              file.name.endsWith('.xml')) {
            try {
              final xml = utf8.decode(
                file.content as List<int>,
                allowMalformed: true,
              );
              for (final m in RegExp(
                r'<a:t[^>]*>([\s\S]*?)</a:t>',
              ).allMatches(xml)) {
                final s = m.group(1) ?? '';
                if (s.trim().isNotEmpty) buf.write('$s ');
              }
            } catch (_) {}
          }
        }
        final result = buf.toString().trim();
        return result.length > 30 ? result : null;
      }
    } catch (e) {
      debugPrint('ZIP text extraction error: $e');
    }
    return null;
  }

  String? _extractPdfText(List<int> bytes) {
    try {
      final raw = latin1.decode(bytes, allowInvalid: true);
      final buf = StringBuffer();
      for (final block in RegExp(r'BT([\s\S]*?)ET').allMatches(raw)) {
        final bt = block.group(1)!;
        for (final m in RegExp(r'\(([^)]{1,300})\)\s*Tj').allMatches(bt)) {
          final s = m.group(1)!.trim();
          if (s.isNotEmpty) buf.write('$s ');
        }
      }
      final result = buf.toString().trim();
      if (result.length > 30) {
        final printable = result.codeUnits
            .where((c) => (c >= 32 && c <= 126) || (c >= 0x0600 && c <= 0x06FF))
            .length;
        if (printable / result.length > 0.4) return result;
      }
    } catch (_) {}
    return null;
  }

  String _mimeFromExt(String ext, [String? detectedMime]) {
    if (detectedMime != null &&
        detectedMime.isNotEmpty &&
        detectedMime != 'application/octet-stream') {
      return detectedMime;
    }
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'bmp':
        return 'image/bmp';
      case 'svg':
        return 'image/svg+xml';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      case 'html':
      case 'htm':
        return 'text/html';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'doc':
        return 'application/msword';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'odt':
        return 'application/vnd.oasis.opendocument.text';
      case 'ods':
        return 'application/vnd.oasis.opendocument.spreadsheet';
      case 'odp':
        return 'application/vnd.oasis.opendocument.presentation';
      case 'zip':
        return 'application/zip';
      case 'rar':
        return 'application/x-rar-compressed';
      case '7z':
        return 'application/x-7z-compressed';
      case 'json':
        return 'application/json';
      case 'xml':
        return 'application/xml';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _pickAttachment() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.of(context).surfaceHigh,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.camera_alt_rounded,
                      color: Color(0xFF7C3AED),
                    ),
                  ),
                  title: Text(
                    l.camera,
                    style: TextStyle(color: AppColors.of(context).textPrimary),
                  ),
                  onTap: () => Navigator.pop(ctx, 'camera'),
                ),
                ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.of(
                        context,
                      ).primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.photo_library_rounded,
                      color: AppColors.of(context).primary,
                    ),
                  ),
                  title: Text(
                    l.gallery,
                    style: TextStyle(color: AppColors.of(context).textPrimary),
                  ),
                  subtitle: Text(
                    l.multipleSelection,
                    style: TextStyle(
                      color: AppColors.of(context).textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, 'gallery'),
                ),
                ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.insert_drive_file_rounded,
                      color: AppColors.success,
                    ),
                  ),
                  title: Text(
                    l.document,
                    style: TextStyle(color: AppColors.of(context).textPrimary),
                  ),
                  subtitle: Text(
                    l.multipleSelection,
                    style: TextStyle(
                      color: AppColors.of(context).textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, 'document'),
                ),
                ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.cloud_outlined, color: Color(0xFFF59E0B)),
                  ),
                  title: Text(
                    l.myFilesInSystem,
                    style: TextStyle(color: AppColors.of(context).textPrimary),
                  ),
                  subtitle: Text(
                    l.browseAndSearch,
                    style: TextStyle(
                      color: AppColors.of(context).textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, 'my_files'),
                ),
                ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.of(
                        context,
                      ).primary.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: AppColors.of(context).primary,
                    ),
                  ),
                  title: Text(
                    l.fromConversation,
                    style: TextStyle(color: AppColors.of(context).textPrimary),
                  ),
                  subtitle: Text(
                    l.useExistingImages,
                    style: TextStyle(
                      color: AppColors.of(context).textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, 'from_chat'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (choice == null) return;

    if (choice == 'my_files') {
      await _showMyFilesSheet();
      return;
    }
    if (choice == 'from_chat') {
      await _showConversationImagesSheet();
      return;
    }

    final newAttachments = <_Attachment>[];

    if (choice == 'camera') {
      if (kIsWeb) {
        // Web: open the real webcam via getUserMedia.
        // Returns (bytes, shouldFallback):
        //   bytes != null  → captured successfully
        //   null + false   → user pressed Cancel — do nothing
        //   null + true    → camera unavailable — fall back to file picker
        final (capturedBytes, shouldFallback) = await showWebCameraOverlay();
        if (capturedBytes != null) {
          newAttachments.add(_Attachment(
            bytes: capturedBytes,
            name: 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
            mime: 'image/jpeg',
          ));
        } else if (shouldFallback) {
          // Camera unavailable — open image file picker instead
          final result = await FilePicker.platform.pickFiles(
            type: FileType.image,
            allowMultiple: false,
            withData: true,
          );
          if (result == null || result.files.isEmpty) return;
          final picked = result.files.first;
          final bytes  = picked.bytes;
          if (bytes == null || bytes.isEmpty) return;
          newAttachments.add(_Attachment(
            bytes: List<int>.from(bytes),
            name: picked.name,
            mime: _mimeFromExt((picked.extension ?? 'jpg').toLowerCase()),
          ));
        }
        // else: user cancelled — do nothing
      } else {
        // Mobile: use native camera via ImagePicker
        final picker = ImagePicker();
        final XFile? xfile = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
        if (xfile == null) return;
        final bytes = await xfile.readAsBytes();
        newAttachments.add(_Attachment(
          bytes: List<int>.from(bytes),
          name: xfile.name,
          mime: 'image/${xfile.name.split('.').last.toLowerCase()}',
        ));
      }
    } else if (choice == 'gallery') {
      final picker = ImagePicker();
      final List<XFile> xfiles = await picker.pickMultiImage(imageQuality: 85);
      for (final xf in xfiles) {
        final bytes = await xf.readAsBytes();
        newAttachments.add(
          _Attachment(
            bytes: bytes,
            name: xf.name,
            mime: 'image/${xf.name.split('.').last.toLowerCase()}',
          ),
        );
      }
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: true,
        withReadStream: true,
      );
      if (result == null || result.files.isEmpty) return;
      for (final picked in result.files) {
        late List<int> bytes;
        if (picked.bytes != null) {
          bytes = picked.bytes!;
        } else if (picked.readStream != null) {
          final chunks = <int>[];
          await for (final chunk in picked.readStream!) {
            chunks.addAll(chunk);
          }
          bytes = chunks;
        } else {
          continue;
        }
        final ext = (picked.extension ?? '').toLowerCase();
        newAttachments.add(
          _Attachment(bytes: bytes, name: picked.name, mime: _mimeFromExt(ext)),
        );
      }
    }

    if (newAttachments.isEmpty) return;

    if (choice == 'camera' &&
        newAttachments.length == 1 &&
        newAttachments.first.isImage) {
      await _showImagePreview(
        newAttachments.first.bytes,
        newAttachments.first.name,
        newAttachments.first.mime,
      );
    } else {
      setState(() => _pendingAttachments.addAll(newAttachments));
    }
  }

  Future<void> _showMyFilesSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _MyFilesSheet(
        onSelected: (attachments) {
          setState(() => _pendingAttachments.addAll(attachments));
        },
      ),
    );
  }

  Future<void> _showConversationImagesSheet() async {
    final conversationImages = <_Attachment>[];
    for (final msg in _messages) {
      for (final a in msg.attachments) {
        if (a.isImage || (a.erpUrl != null && a.mime.startsWith('image/'))) {
          conversationImages.add(a);
        }
      }
    }

    if (!mounted) return;
    final l = AppLocalizations.of(context);

    if (conversationImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.noImagesInChat),
          backgroundColor: AppColors.of(context).surfaceHigh,
        ),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ConversationImagesSheet(
        images: conversationImages,
        onSelected: (selected) {
          final refs = selected
              .map(
                (a) => _Attachment(
                  bytes: const [],
                  name: a.name,
                  mime: a.mime,
                  erpUrl: a.erpUrl,
                  fromHistory: true,
                  isPrivate: a.isPrivate,
                ),
              )
              .toList();
          if (mounted) setState(() => _pendingAttachments.addAll(refs));
        },
      ),
    );
  }

  Future<void> _showImagePreview(
    List<int> bytes,
    String name,
    String mime,
  ) async {
    final l = AppLocalizations.of(context);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        bool isPrivate = false;
        return StatefulBuilder(
          builder: (ctx2, setInner) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.9,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (_, sc) => Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).surfaceHigh,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: InteractiveViewer(
                      child: Image.memory(
                        Uint8List.fromList(bytes),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Text(
                      name,
                      style: TextStyle(
                        color: AppColors.of(context).textSecondary,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isPrivate ? Icons.lock_rounded : Icons.public_rounded,
                          size: 16,
                          color: isPrivate
                              ? AppColors.warning
                              : AppColors.success,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isPrivate ? l.filePrivate : l.filePublic,
                            style: TextStyle(
                              color: isPrivate
                                  ? AppColors.warning
                                  : AppColors.success,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setInner(() => isPrivate = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: !isPrivate
                                  ? AppColors.success.withValues(alpha: 0.15)
                                  : AppColors.of(context).surfaceHigh,
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(8),
                              ),
                              border: Border.all(
                                color: !isPrivate
                                    ? AppColors.success
                                    : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              l.filePublic,
                              style: TextStyle(
                                color: !isPrivate
                                    ? AppColors.success
                                    : AppColors.of(context).textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setInner(() => isPrivate = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isPrivate
                                  ? AppColors.warning.withValues(alpha: 0.15)
                                  : AppColors.of(context).surfaceHigh,
                              borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(8),
                              ),
                              border: Border.all(
                                color: isPrivate
                                    ? AppColors.warning
                                    : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              l.filePrivate,
                              style: TextStyle(
                                color: isPrivate
                                    ? AppColors.warning
                                    : AppColors.of(context).textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(
                      left: 12,
                      right: 12,
                      bottom: MediaQuery.of(ctx2).viewInsets.bottom + 12,
                      top: 4,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: AppColors.of(context).textSecondary,
                          ),
                          onPressed: () => Navigator.pop(ctx2),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _inputController,
                            style: TextStyle(
                              color: AppColors.of(context).textPrimary,
                            ),
                            maxLines: 3,
                            minLines: 1,
                            decoration: InputDecoration(
                              hintText: l.addCaption,
                              hintStyle: TextStyle(
                                color: AppColors.of(context).textSecondary,
                              ),
                              filled: true,
                              fillColor: AppColors.of(context).surfaceHigh,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: AppColors.of(context).primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              Navigator.pop(ctx2);
                              setState(
                                () => _pendingAttachments.add(
                                  _Attachment(
                                    bytes: bytes,
                                    name: name,
                                    mime: mime,
                                    isPrivate: isPrivate,
                                  ),
                                ),
                              );
                              _sendMessage(null);
                            },
                            child: const SizedBox(
                              width: 44,
                              height: 44,
                              child: Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _infoRow(IconData icon, String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 14, color: AppColors.of(context).textSecondary),
      const SizedBox(width: 6),
      Text(
        '$label: ',
        style: TextStyle(
          color: AppColors.of(context).textSecondary,
          fontSize: 12,
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: TextStyle(
            color: AppColors.of(context).textPrimary,
            fontSize: 12,
          ),
        ),
      ),
    ],
  );

  @override
  void dispose() {
    RealtimeWorkflowService().removeListener(_onWorkflowEvent);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Inject a confirmation bubble when a workflow action was taken on a doc
  // that was opened from this chat session.
  //
  // Matches on BOTH docname AND doctype (when available) to prevent false
  // positives from other documents with the same name in different doctypes.
  void _onWorkflowEvent(Map<String, dynamic> event) {
    if (!mounted) return;

    final refDoctype = event['reference_doctype']?.toString() ?? '';
    final docname    = event['reference_name']?.toString() ?? '';
    final action     = event['action']?.toString() ?? '';
    final newState   = event['new_state']?.toString() ?? '';
    final docstatus  = (event['docstatus'] as num?)?.toInt() ?? -1;

    debugPrint('[AI-WF] Event received: action=$action docname=$docname '
        'docstatus=$docstatus state=$newState');

    if (docname.isEmpty || action.isEmpty) return;
    if (docname != _lastOpenedDocname) return;

    // If we tracked the doctype, validate it matches — prevents false positives
    if (_lastOpenedDoctype != null &&
        refDoctype.isNotEmpty &&
        refDoctype != _lastOpenedDoctype) {
      debugPrint('[AI-WF] Event doctype mismatch '
          '(expected=$_lastOpenedDoctype got=$refDoctype) — ignoring');
      return;
    }

    final l    = AppLocalizations.of(context);
    final isAr = l.isArabic;

    // Build a context-aware confirmation message based on the resulting docstatus
    final String confirmText;
    if (docstatus == 2) {
      confirmText = isAr
          ? '🚫 تم **إلغاء** المستند `$docname`\nالحالة الجديدة: **$newState**'
          : '🚫 `$docname` was **cancelled**\nNew state: **$newState**';
    } else if (docstatus == 1) {
      confirmText = isAr
          ? '✅ تم **تقديم/اعتماد** `$docname` بنجاح\nالحالة الجديدة: **$newState**'
          : '✅ `$docname` **submitted / approved** successfully\nNew state: **$newState**';
    } else {
      // docstatus == 0 — state changed (reverse, reject to draft, etc.)
      confirmText = l.wfChatConfirmation(action, docname, newState);
    }

    debugPrint('[AI-WF] Injecting confirmation bubble — docstatus=$docstatus');

    setState(() {
      _messages.add(_Message(
        role: 'assistant',
        text: confirmText,
        time: DateTime.now(),
      ));
      // Consume tracking — next event from a different session won't match
      _lastOpenedDocname = null;
      _lastOpenedDoctype = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // false: _InputBar already accounts for keyboard via MediaQuery.viewInsets.bottom.
      // Keeping the default (true) would shrink the body AND add the inset twice,
      // leaving only a few pixels for the message list when the keyboard is open.
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.of(context).background,
      drawer: const AppDrawer(current: DrawerSection.aiAssistant),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.of(
                      context,
                    ).primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.smart_toy_outlined,
                    size: 18,
                    color: AppColors.of(context).primary,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    AppLocalizations.of(context).aiAssistant,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).surfaceHigh,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      switch (_aiProvider) {
                        'chatgpt' => _chatgptModel,
                        'claude_first' =>
                          '${_model.replaceAll('claude-', '')}→GPT',
                        'chatgpt_first' =>
                          'GPT→${_model.replaceAll('claude-', '')}',
                        _ => _model.replaceAll('claude-', ''),
                      },
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.of(context).textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.of(context).primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '⚡ $_activeModuleLabel',
                  style: TextStyle(
                    fontSize: 9,
                    color: AppColors.of(context).primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (_isSaving)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: AppColors.of(context).textSecondary,
                  strokeWidth: 2,
                ),
              ),
            ),
          IconButton(
            icon: Icon(Icons.add_comment_outlined),
            tooltip: AppLocalizations.of(context).newChatSession,
            onPressed: _messages.any((m) => m.role == 'user') ? _newChat : null,
          ),
          IconButton(
            icon: Icon(Icons.history_rounded),
            tooltip: AppLocalizations.of(context).chatHistory,
            onPressed: _openHistory,
          ),
          IconButton(
            icon: Icon(Icons.delete_sweep_outlined),
            tooltip: AppLocalizations.of(context).clearChat,
            onPressed: _messages.any((m) => m.role == 'user')
                ? _clearChat
                : null,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if ((_aiProvider.startsWith('chatgpt')
                    ? _chatgptApiKey
                    : _claudeApiKey)
                .isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.of(context).surface,
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.of(context).surfaceHigh,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      color: AppColors.warning,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context).addAiKey,
                        style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/settings'),
                      child: Text(
                        AppLocalizations.of(context).settings,
                        style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (_errorBanner != null)
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 200),
                color: AppColors.error.withValues(alpha: 0.1),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Colors.redAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context).errorOccurred,
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.copy,
                              color: Colors.redAccent,
                              size: 16,
                            ),
                            tooltip: AppLocalizations.of(context).copyError,
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: _errorBanner!),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    AppLocalizations.of(context).errorCopied,
                                  ),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              color: Colors.redAccent,
                              size: 16,
                            ),
                            onPressed: () =>
                                setState(() => _errorBanner = null),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                        child: SelectableText(
                          _errorBanner!,
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: _messages.isEmpty
                  ? _EmptyState(
                      model: _aiProvider == 'chatgpt' ? _chatgptModel : _model,
                      activeModule: _activeModule,
                      activeModuleLabel: _activeModuleLabel,
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                      itemCount:
                          _messages.length +
                          (_showModuleButtons ? 1 : 0) +
                          (_isLoading ? 1 : 0),
                      itemBuilder: (context, rawIndex) {
                        final int moduleOffset = _showModuleButtons ? 1 : 0;
                        final int loadingStart =
                            _messages.length + moduleOffset;

                        if (rawIndex == loadingStart && _isLoading) {
                          return _TypingIndicator(status: _statusText);
                        }

                        if (_showModuleButtons && rawIndex == 1) {
                          return _InlineModuleGrid();
                        }

                        final msgIndex = rawIndex > 1
                            ? rawIndex - moduleOffset
                            : rawIndex;
                        final msg = _messages[msgIndex];
                        return _MessageBubble(
                          message: msg,
                          onCreateChart: msg.role == 'assistant'
                              ? _createDashboardChart
                              : null,
                          onSendSystemEmail: msg.role == 'assistant'
                              ? (to, subject, body, bytes) =>
                                    _sendEmailViaSystem(
                                      to,
                                      subject,
                                      body,
                                      bytes,
                                    )
                              : null,
                          onOpenDocument: msg.role == 'assistant'
                              ? _openDocument
                              : null,
                        );
                      },
                    ),
            ),

            _InputBar(
              controller: _inputController,
              isLoading: _isLoading,
              onSend: ([lang]) => _sendMessage(lang),
              onStop: _cancelAI,
              onPickAttachment: _pickAttachment,
              pendingAttachments: _pendingAttachments,
              onRemoveAttachment: (i) =>
                  setState(() => _pendingAttachments.removeAt(i)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state — Module Grid
// ---------------------------------------------------------------------------
class _EmptyState extends StatelessWidget {
  final String model;
  final String activeModule;
  final String activeModuleLabel;
  const _EmptyState({
    required this.model,
    this.activeModule = '',
    this.activeModuleLabel = '',
  });


  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isAr = l10n.isArabic;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.of(context).primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.hub_outlined,
              size: 44,
              color: AppColors.of(context).primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isAr ? 'المساعد الذكي في نظام KCSC' : 'KCSC ERP AI Agent',
            style: TextStyle(
              color: AppColors.of(context).textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.poweredBy(model),
            style: TextStyle(
              color: AppColors.of(context).surfaceHigh,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isAr
                ? 'مساعدك الذكي المتكامل لجميع موديولات ERPNext'
                : 'Your integrated AI assistant for all ERPNext modules',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.of(context).textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Module data model
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Inline module grid
// ---------------------------------------------------------------------------
class _InlineModuleGrid extends StatelessWidget {
  const _InlineModuleGrid();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ---------------------------------------------------------------------------
// My Files Sheet
// ---------------------------------------------------------------------------
class _MyFilesSheet extends StatefulWidget {
  final void Function(List<_Attachment>) onSelected;
  const _MyFilesSheet({required this.onSelected});

  @override
  State<_MyFilesSheet> createState() => _MyFilesSheetState();
}

class _MyFilesSheetState extends State<_MyFilesSheet> {
  final searchCtrl = TextEditingController();
  List<Map<String, dynamic>> files = [];
  final Set<int> selected0 = {};
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    loadFiles();
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  Future<void> loadFiles([String search = '']) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final filters = search.isEmpty
          ? '[["is_private","=","1"]]'
          : '[["is_private","=","1"],["file_name","like","%$search%"]]';
      final result = await ApiService.get(
        '/api/resource/File'
        '?filters=${Uri.encodeComponent(filters)}'
        '&fields=${Uri.encodeComponent('["name","file_name","file_url","file_size","creation"]')}'
        '&limit=60&order_by=creation+desc',
      );
      final data = result['data'] as List? ?? [];
      setState(() {
        files = data.cast<Map<String, dynamic>>();
        selected0.clear();
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  bool isImageUrl(String url) {
    final ext = url.split('.').last.toLowerCase().split('?').first;
    return {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'}.contains(ext);
  }

  String mime0(String url) {
    final ext = url.split('.').last.toLowerCase().split('?').first;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> confirm() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('erpnext_url') ?? '';
    final cookie = prefs.getString('erpnext_session_cookie') ?? '';

    final selected = <_Attachment>[];
    for (final idx in selected0) {
      final f = files[idx];
      final fileUrl = f['file_url'] as String? ?? '';
      final fileName = f['file_name'] as String? ?? f['name'] as String? ?? '';
      final mime = mime0(fileUrl);
      final fullUrl = fileUrl.startsWith('http') ? fileUrl : '$baseUrl$fileUrl';

      List<int> bytes = [];
      try {
        final resp = await http
            .get(Uri.parse(fullUrl), headers: {'Cookie': 'sid=$cookie'})
            .timeout(const Duration(seconds: 20));
        if (resp.statusCode == 200) bytes = resp.bodyBytes;
      } catch (_) {}

      selected.add(
        _Attachment(bytes: bytes, name: fileName, mime: mime, erpUrl: fileUrl),
      );
    }

    if (mounted) {
      Navigator.pop(context);
      widget.onSelected(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, sc) => Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.of(context).surfaceHigh,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.cloud_outlined, color: Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.myFilesInSystem,
                    style: TextStyle(
                      color: AppColors.of(context).textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (selected0.isNotEmpty)
                  TextButton.icon(
                    icon: Icon(Icons.check_rounded, size: 18),
                    label: Text('${l.addSelected} (${selected0.length})'),
                    onPressed: confirm,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: searchCtrl,
              style: TextStyle(color: AppColors.of(context).textPrimary),
              decoration: InputDecoration(
                hintText: l.searchFiles,
                hintStyle: TextStyle(
                  color: AppColors.of(context).textSecondary,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: AppColors.of(context).textSecondary,
                ),
                suffixIcon: searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: AppColors.of(context).textSecondary,
                          size: 18,
                        ),
                        onPressed: () {
                          searchCtrl.clear();
                          loadFiles();
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.of(context).surfaceHigh,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: loadFiles,
              onChanged: (v) => setState(() {}),
            ),
          ),
          Expanded(
            child: loading
                ? Center(
                    child: CircularProgressIndicator(
                      color: AppColors.of(context).primary,
                    ),
                  )
                : error != null
                ? Center(
                    child: Text(
                      error!,
                      style: TextStyle(color: AppColors.error),
                    ),
                  )
                : files.isEmpty
                ? Center(
                    child: Text(
                      l.noFilesFound,
                      style: TextStyle(
                        color: AppColors.of(context).textSecondary,
                      ),
                    ),
                  )
                : GridView.builder(
                    controller: sc,
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        ),
                    itemCount: files.length,
                    itemBuilder: (_, i) {
                      final f = files[i];
                      final url = f['file_url'] as String? ?? '';
                      final name =
                          f['file_name'] as String? ??
                          f['name'] as String? ??
                          '';
                      final isImg = isImageUrl(url);
                      final isSelected = selected0.contains(i);
                      return GestureDetector(
                        onTap: () => setState(() {
                          isSelected ? selected0.remove(i) : selected0.add(i);
                        }),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: isImg
                                  ? FutureBuilder<SharedPreferences>(
                                      future: SharedPreferences.getInstance(),
                                      builder: (ctx, snap) {
                                        if (!snap.hasData) {
                                          return Container(
                                            color: AppColors.of(
                                              context,
                                            ).surfaceHigh,
                                          );
                                        }
                                        final base =
                                            snap.data!.getString(
                                              'erpnext_url',
                                            ) ??
                                            '';
                                        final cookie =
                                            snap.data!.getString(
                                              'erpnext_session_cookie',
                                            ) ??
                                            '';
                                        final full = url.startsWith('http')
                                            ? url
                                            : '$base$url';
                                        return Image.network(
                                          full,
                                          fit: BoxFit.cover,
                                          headers: {'Cookie': cookie},
                                          errorBuilder: (_, _, _) => Container(
                                            color: AppColors.of(
                                              context,
                                            ).surfaceHigh,
                                            child: Icon(
                                              Icons.broken_image_rounded,
                                              color: AppColors.of(
                                                context,
                                              ).textSecondary,
                                            ),
                                          ),
                                        );
                                      },
                                    )
                                  : Container(
                                      color: AppColors.of(context).surfaceHigh,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.insert_drive_file_rounded,
                                            color: AppColors.of(
                                              context,
                                            ).primary,
                                            size: 32,
                                          ),
                                          const SizedBox(height: 4),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                            child: Text(
                                              name,
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: AppColors.of(
                                                  context,
                                                ).textSecondary,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                            if (isSelected)
                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.of(
                                    context,
                                  ).primary.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conversation Images Sheet
// ---------------------------------------------------------------------------
class _ConversationImagesSheet extends StatefulWidget {
  final List<_Attachment> images;
  final void Function(List<_Attachment>) onSelected;
  const _ConversationImagesSheet({
    required this.images,
    required this.onSelected,
  });

  @override
  State<_ConversationImagesSheet> createState() =>
      _ConversationImagesSheetState();
}

class _ConversationImagesSheetState extends State<_ConversationImagesSheet> {
  final Set<int> selected = {};

  void confirm() {
    final list = selected.map((i) => widget.images[i]).toList();
    Navigator.pop(context);
    widget.onSelected(list);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, sc) => Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.of(context).surfaceHigh,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: AppColors.of(context).primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.fromConversation,
                    style: TextStyle(
                      color: AppColors.of(context).textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (selected.isNotEmpty)
                  TextButton.icon(
                    icon: Icon(Icons.check_rounded, size: 18),
                    label: Text('${l.addSelected} (${selected.length})'),
                    onPressed: confirm,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              controller: sc,
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: widget.images.length,
              itemBuilder: (_, i) {
                final a = widget.images[i];
                final isSelected = selected.contains(i);
                return GestureDetector(
                  onTap: () => setState(() {
                    isSelected ? selected.remove(i) : selected.add(i);
                  }),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: a.bytes.isNotEmpty
                            ? Image.memory(
                                Uint8List.fromList(a.bytes),
                                fit: BoxFit.cover,
                              )
                            : FutureBuilder<SharedPreferences>(
                                future: SharedPreferences.getInstance(),
                                builder: (ctx, snap) {
                                  if (!snap.hasData) {
                                    return Container(
                                      color: AppColors.of(context).surfaceHigh,
                                    );
                                  }
                                  final base =
                                      snap.data!.getString('erpnext_url') ?? '';
                                  final cookie =
                                      snap.data!.getString(
                                        'erpnext_session_cookie',
                                      ) ??
                                      '';
                                  final full = a.erpUrl!.startsWith('http')
                                      ? a.erpUrl!
                                      : '$base${a.erpUrl}';
                                  return Image.network(
                                    full,
                                    fit: BoxFit.cover,
                                    headers: {'Cookie': cookie},
                                    errorBuilder: (_, _, _) => Container(
                                      color: AppColors.of(context).surfaceHigh,
                                    ),
                                  );
                                },
                              ),
                      ),
                      if (isSelected)
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.of(
                              context,
                            ).primary.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Attachment grid
// ---------------------------------------------------------------------------
class _AttachmentGrid extends StatelessWidget {
  final List<_Attachment> attachments;
  final void Function(_Attachment) onTapImage;

  const _AttachmentGrid({
    required this.attachments,
    required this.onTapImage,
  });

  @override
  Widget build(BuildContext context) {
    final images = attachments
        .where(
          (a) => a.isImage || (a.erpUrl != null && a.mime.startsWith('image/')),
        )
        .toList();
    final files = attachments
        .where(
          (a) =>
              !a.isImage && !(a.erpUrl != null && a.mime.startsWith('image/')),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (images.isNotEmpty) buildImageGrid(context, images),
        ...files.map((f) => buildFileChip(f)),
      ],
    );
  }

  Widget buildImageGrid(BuildContext context, List<_Attachment> imgs) {
    if (imgs.length == 1) {
      return buildImageTile(context, imgs[0], double.infinity, 200);
    }
    if (imgs.length == 2) {
      return Row(
        children: [
          Expanded(
            child: buildImageTile(context, imgs[0], double.infinity, 150),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: buildImageTile(context, imgs[1], double.infinity, 150),
          ),
        ],
      );
    }
    final show = imgs.take(4).toList();
    final extra = imgs.length - 4;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
      childAspectRatio: 1,
      children: List.generate(show.length, (i) {
        if (i == 3 && extra > 0) {
          return Stack(
            fit: StackFit.expand,
            children: [
              buildImageTile(
                context,
                show[i],
                double.infinity,
                double.infinity,
              ),
              Container(
                color: Colors.black54,
                child: Center(
                  child: Text(
                    '+$extra',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        return buildImageTile(
          context,
          show[i],
          double.infinity,
          double.infinity,
        );
      }),
    );
  }

  Widget buildImageTile(
    BuildContext context,
    _Attachment a,
    double w,
    double h,
  ) {
    if (a.bytes.isNotEmpty) {
      return GestureDetector(
        onTap: () => onTapImage(a),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            Uint8List.fromList(a.bytes),
            width: w,
            height: h,
            fit: BoxFit.cover,
            errorBuilder: (ctx, e, st) => Container(
              width: w.isFinite ? w : null,
              height: h.isFinite ? h : 150,
              color: AppColors.of(context).surfaceHigh,
              child: Center(
                child: Icon(
                  Icons.image_not_supported_rounded,
                  color: AppColors.of(context).textSecondary,
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (a.erpUrl != null) {
      return FutureBuilder<SharedPreferences>(
        future: SharedPreferences.getInstance(),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return SizedBox(
              height: h.isFinite ? h : 150,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final base = snap.data!.getString('erpnext_url') ?? '';
          final fullUrl = a.erpUrl!.startsWith('http')
              ? a.erpUrl!
              : '$base${a.erpUrl}';
          return GestureDetector(
            onTap: () => onTapImage(a),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                fullUrl,
                width: w,
                height: h,
                fit: BoxFit.cover,
                headers: {
                  'Cookie':
                      snap.data!.getString('erpnext_session_cookie') ?? '',
                },
                errorBuilder: (ctx, e, st) => Container(
                  color: AppColors.of(context).surfaceHigh,
                  child: Center(
                    child: Icon(
                      Icons.image_not_supported_rounded,
                      color: AppColors.of(context).textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
    return Container(
      height: h.isFinite ? h : 150,
      decoration: BoxDecoration(
        color: AppColors.of(context).surfaceHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.broken_image_rounded,
        color: AppColors.of(context).textSecondary,
      ),
    );
  }

  Widget buildFileChip(_Attachment f) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insert_drive_file_rounded,
            color: Colors.white70,
            size: 18,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              f.name,
              style: TextStyle(color: Colors.white70, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (f.erpUrl != null) ...[
            const SizedBox(width: 6),
            Icon(Icons.cloud_done_rounded, color: Colors.greenAccent, size: 14),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Message bubble
// ---------------------------------------------------------------------------
class _MessageBubble extends StatelessWidget {
  final _Message message;
  final void Function(Map<String, dynamic>)? onCreateChart;
  final void Function(
    String to,
    String subject,
    String htmlBody,
    Uint8List? pdfBytes,
  )?
  onSendSystemEmail;
  final void Function(String doctype, String docname)? onOpenDocument;
  const _MessageBubble({
    required this.message,
    this.onCreateChart,
    this.onSendSystemEmail,
    this.onOpenDocument,
  });

  bool get isUser => message.role == 'user';

  void showFullImage(
    BuildContext context,
    List<int> bytes,
    String name, {
    String? erpUrl,
  }) {
    Widget imageWidget;
    if (bytes.isNotEmpty) {
      imageWidget = Image.memory(
        Uint8List.fromList(bytes),
        fit: BoxFit.contain,
      );
    } else if (erpUrl != null) {
      imageWidget = FutureBuilder<SharedPreferences>(
        future: SharedPreferences.getInstance(),
        builder: (ctx, snap) {
          if (!snap.hasData) return Center(child: CircularProgressIndicator());
          final base = snap.data!.getString('erpnext_url') ?? '';
          final fullUrl = erpUrl.startsWith('http') ? erpUrl : '$base$erpUrl';
          return Image.network(
            fullUrl,
            fit: BoxFit.contain,
            headers: {
              'Cookie': snap.data!.getString('erpnext_session_cookie') ?? '',
            },
          );
        },
      );
    } else {
      imageWidget = Center(
        child: Icon(
          Icons.broken_image_rounded,
          color: Colors.white54,
          size: 64,
        ),
      );
    }

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            InteractiveViewer(child: imageWidget),
            Positioned(
              top: 40,
              right: 16,
              child: IconButton(
                icon: Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            if (name.isNotEmpty)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = AppLocalizations.of(context).isArabic;
    final cairoFont = isArabic ? 'Cairo' : null;
    final interFont = isArabic ? null : 'Inter';
    final c = AppColors.of(context);

    if (message.isWelcome) {
      return _buildWelcomeBubble(context, c, isArabic, cairoFont, interFont);
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: message.text));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).copied),
              duration: const Duration(seconds: 1),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: isUser ? c.userBubble : c.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isUser ? 18 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 18),
            ),
            border: isUser ? null : Border.all(color: c.surfaceHigh),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.smart_toy_outlined,
                        size: 13,
                        color: c.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        AppLocalizations.of(context).aiAssistant,
                        style: TextStyle(
                          color: c.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          fontFamily: cairoFont,
                        ),
                      ),
                    ],
                  ),
                ),

              if (message.attachments.isNotEmpty) ...[
                _AttachmentGrid(
                  attachments: message.attachments,
                  onTapImage: (a) =>
                      showFullImage(context, a.bytes, a.name, erpUrl: a.erpUrl),
                ),
                if (message.text.isNotEmpty) const SizedBox(height: 6),
              ],

              if (message.text.isNotEmpty)
                MessageRenderer(
                  text: message.text,
                  fontFamily: cairoFont,
                  onCreateChart: onCreateChart,
                  onSendSystemEmail: onSendSystemEmail,
                  onOpenDocument: onOpenDocument,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── ✅ UPDATED: _buildWelcomeBubble ─────────────────────────────────────────
  Widget _buildWelcomeBubble(
    BuildContext context,
    AppColors c,
    bool isArabic,
    String? cairoFont,
    String? interFont,
  ) {
    final bodyFont = isArabic ? cairoFont : interFont;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // اسم الـ agent حسب اللغة
    final agentDisplayName = isArabic
        ? 'المساعد الذكي في نظام KCSC'
        : 'KCSC ERP AI Agent';

    // لون العنوان: في الـ dark يكون primary مضيء، في الـ light يكون textPrimary داكن
    final headerTitleColor = isDark ? c.primary : c.textPrimary;

    // لون نص الجسم: صريح ومتكيف مع الـ theme
    final bodyTextColor = isDark ? c.textPrimary : const Color(0xFF1A1A2E);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.92,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: c.primary.withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.12),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(15),
                  topRight: Radius.circular(15),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.smart_toy_outlined, size: 16, color: c.primary),
                  const SizedBox(width: 6),
                  Text(
                    agentDisplayName,
                    style: TextStyle(
                      color: headerTitleColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      fontFamily: isArabic ? cairoFont : interFont,
                      letterSpacing: isArabic ? 0.0 : 0.2,
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontFamily: bodyFont,
                  fontSize: 15,
                  color: bodyTextColor,
                  height: 1.6,
                  fontWeight: FontWeight.w500,
                ),
                child: MessageRenderer(
                  text: message.text,
                  onCreateChart: onCreateChart,
                  onSendSystemEmail: onSendSystemEmail,
                  onOpenDocument: onOpenDocument,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Typing indicator
// ---------------------------------------------------------------------------
class _TypingIndicator extends StatefulWidget {
  final String status;
  const _TypingIndicator({required this.status});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController ctrl;
  late final Animation<double> anim;

  @override
  void initState() {
    super.initState();
    ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    anim = Tween<double>(begin: 0.3, end: 1.0).animate(ctrl);
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.of(context).surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: AppColors.of(context).surfaceHigh),
        ),
        child: FadeTransition(
          opacity: anim,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.smart_toy_outlined,
                size: 13,
                color: AppColors.of(context).primary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.status.isNotEmpty
                    ? widget.status
                    : AppLocalizations.of(context).thinking,
                style: TextStyle(
                  color: AppColors.of(context).textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Input bar
// ---------------------------------------------------------------------------
class _InputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool isLoading;
  final void Function([String?]) onSend;
  final VoidCallback onStop;
  final VoidCallback onPickAttachment;
  final List<_Attachment> pendingAttachments;
  final void Function(int index) onRemoveAttachment;

  const _InputBar({
    required this.controller,
    required this.isLoading,
    required this.onSend,
    required this.onStop,
    required this.onPickAttachment,
    required this.pendingAttachments,
    required this.onRemoveAttachment,
  });

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  final recorder = AudioRecorder();
  bool isRecording = false;
  bool isTranscribing = false;
  String? recordingPath;
  TextDirection textDir = TextDirection.rtl;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(updateTextDir);
  }

  void updateTextDir() {
    final text = widget.controller.text;
    TextDirection dir = TextDirection.rtl;
    for (final rune in text.runes) {
      if (rune > 0x20) {
        dir = (rune >= 0x0590 && rune <= 0x08FF)
            ? TextDirection.rtl
            : TextDirection.ltr;
        break;
      }
    }
    if (dir != textDir) setState(() => textDir = dir);
  }

  @override
  void dispose() {
    widget.controller.removeListener(updateTextDir);
    recorder.dispose();
    super.dispose();
  }

  Future<void> cancelRecord() async {
    if (!isRecording) return;
    await recorder.stop();
    if (!kIsWeb && recordingPath != null) {
      File(recordingPath!).delete().catchError((e) => File(recordingPath!));
      recordingPath = null;
    }
    if (mounted) setState(() => isRecording = false);
  }

  Future<void> toggleRecord() async {
    if (isTranscribing) return;

    if (isRecording) {
      final path = await recorder.stop();
      setState(() {
        isRecording = false;
        isTranscribing = true;
      });
      if (path != null) await transcribeAndSend(path);
      if (mounted) setState(() => isTranscribing = false);
    } else {
      if (kIsWeb) {
        // Web: browser shows permission popup on start(); opus is the only supported format
        try {
          await recorder.start(
            const RecordConfig(encoder: AudioEncoder.opus, sampleRate: 16000),
            path: '',
          );
          setState(() => isRecording = true);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Microphone: $e'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
      } else {
        final hasPermission = await recorder.hasPermission();
        if (!hasPermission) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied')),
          );
          return;
        }
        final dir = await getTemporaryDirectory();
        recordingPath =
            '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000),
          path: recordingPath!,
        );
        setState(() => isRecording = true);
      }
    }
  }

  Future<void> transcribeAndSend(String audioPath) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('openai_api_key')?.trim() ?? '';

    if (apiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).whisperKeyMissing),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    try {
      final List<int> bytes;
      final String filename;
      if (kIsWeb) {
        // audioPath is a blob: URL returned by recorder.stop() on web
        final response = await http.get(Uri.parse(audioPath));
        bytes = response.bodyBytes;
        filename = 'audio.webm';
      } else {
        bytes = await File(audioPath).readAsBytes();
        filename = 'audio.m4a';
      }
      final request =
          http.MultipartRequest(
              'POST',
              Uri.parse('https://api.openai.com/v1/audio/transcriptions'),
            )
            ..headers['Authorization'] = 'Bearer $apiKey'
            ..fields['model'] = 'whisper-1'
            ..fields['response_format'] = 'verbose_json'
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                bytes,
                filename: filename,
              ),
            );

      final streamed = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final body = await streamed.stream.bytesToString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final text = (json['text'] as String? ?? '').trim();
      final detectedLang = (json['language'] as String? ?? '').toLowerCase();
      if (!mounted) return;
      if (text.isNotEmpty) {
        widget.controller.text = text;
        widget.controller.selection = TextSelection.fromPosition(
          TextPosition(offset: text.length),
        );
        final lang = detectedLang.isNotEmpty ? detectedLang : null;
        Future.delayed(
          const Duration(milliseconds: 100),
          () => widget.onSend(lang),
        );
      } else {
        final err = json['error']?['message'] as String? ?? 'Unknown error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Whisper: $err'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (!kIsWeb) {
        File(audioPath).delete().catchError((e) => File(audioPath));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.pendingAttachments;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.of(context).surface,
        border: Border(
          top: BorderSide(color: AppColors.of(context).surfaceHigh),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pending.isNotEmpty)
            Container(
              height: 72,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: pending.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final a = pending[i];
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: a.isImage
                            ? Image.memory(
                                Uint8List.fromList(a.bytes),
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 64,
                                height: 64,
                                color: AppColors.of(context).surfaceHigh,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.insert_drive_file_rounded,
                                      color: AppColors.of(context).primary,
                                      size: 28,
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      child: Text(
                                        a.name.length > 8
                                            ? '${a.name.substring(0, 7)}…'
                                            : a.name,
                                        style: TextStyle(
                                          color: AppColors.of(
                                            context,
                                          ).textSecondary,
                                          fontSize: 8,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      Positioned(
                        top: -4,
                        right: -4,
                        child: GestureDetector(
                          onTap: () => widget.onRemoveAttachment(i),
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

          Row(
            children: [
              if (isRecording)
                IconButton(
                  icon: Icon(Icons.cancel_rounded, color: AppColors.error),
                  onPressed: cancelRecord,
                  tooltip: AppLocalizations.of(context).cancelRecording,
                )
              else
                IconButton(
                  icon: Icon(
                    Icons.attach_file_rounded,
                    color: AppColors.of(context).textSecondary,
                  ),
                  onPressed: widget.isLoading ? null : widget.onPickAttachment,
                  tooltip: AppLocalizations.of(context).attachFile,
                ),

              Expanded(
                child: TextField(
                  controller: widget.controller,
                  style: TextStyle(color: AppColors.of(context).textPrimary),
                  maxLines: 5,
                  minLines: 1,
                  textDirection: textDir,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => widget.onSend(null),
                  decoration: InputDecoration(
                    hintText: isRecording
                        ? AppLocalizations.of(context).listeningWillSend
                        : isTranscribing
                        ? AppLocalizations.of(context).transcribing
                        : AppLocalizations.of(context).typeQuestion,
                    hintStyle: TextStyle(
                      color: AppColors.of(context).textSecondary,
                    ),
                    filled: true,
                    fillColor: isRecording
                        ? AppColors.error.withValues(alpha: 0.08)
                        : AppColors.of(context).surfaceHigh,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: Tooltip(
                      message: isRecording
                          ? AppLocalizations.of(context).tapToStopListening
                          : AppLocalizations.of(context).tapMicToSend,
                      child: isTranscribing
                          ? Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: AppColors.of(context).textSecondary,
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              icon: Icon(
                                isRecording
                                    ? Icons.stop_rounded
                                    : Icons.mic_none_rounded,
                                color: isRecording
                                    ? AppColors.error
                                    : AppColors.of(context).textSecondary,
                              ),
                              onPressed: widget.isLoading ? null : toggleRecord,
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: widget.isLoading
                    ? Tooltip(
                        key: const ValueKey('stop'),
                        message: AppLocalizations.of(context).stopGeneration,
                        child: Material(
                          color: AppColors.error,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: widget.onStop,
                            child: const SizedBox(
                              width: 44,
                              height: 44,
                              child: Icon(
                                Icons.stop_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      )
                    : Material(
                        key: const ValueKey('send'),
                        color: AppColors.of(context).primary,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => widget.onSend(null),
                          child: const SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
