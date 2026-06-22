import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_colors.dart';
import 'app_localizations.dart';
import 'main.dart';

/// Returns the widget to display as the app logo.
/// If [path] is non-empty and the file exists → File image.
/// Otherwise → default asset.
Widget buildLogoWidget({required String path, double height = 80}) {
  if (path.isNotEmpty) {
    final f = File(path);
    if (f.existsSync()) {
      return Image.file(
        f,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (ctx, e, st) => Image.asset(
          'images/faheem_logo.png',
          height: height,
          fit: BoxFit.contain,
          errorBuilder: (ctx2, e2, st2) => Icon(
            Icons.business,
            size: height,
            color: AppColors.of(ctx2).primary,
          ),
        ),
      );
    }
  }
  return Image.asset(
    'images/faheem_logo.png',
    height: height,
    fit: BoxFit.contain,
    errorBuilder: (ctx, e, st) =>
        Icon(Icons.business, size: height, color: AppColors.of(ctx).primary),
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();

  // ERPNext
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _companyController = TextEditingController();

  // ERPNext Token Auth
  final _apiKeyController = TextEditingController();
  final _apiSecretController = TextEditingController();

  // AI
  final _aiEndpointController = TextEditingController();
  final _claudeApiKeyController = TextEditingController();
  final _openaiApiKeyController = TextEditingController();
  final _chatgptApiKeyController = TextEditingController();

  // n8n Chat
  final _n8nUrlController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureApiSecret = true;
  bool _obscureApiKey = true;
  bool _obscureOpenAiKey = true;
  bool _obscureChatGptKey = true;
  bool _isSaving = false;
  bool _saved = false;
  String _selectedModel = 'claude-sonnet-4-6';
  String _selectedLang = 'en';
  String _selectedTheme = 'light'; // 'light' | 'dark' | 'system'
  String _selectedProvider = 'claude'; // 'claude' | 'chatgpt'
  String _selectedChatGptModel = 'gpt-4o';
  String _customLogoPath = ''; // path to user-uploaded logo

  // SharedPreferences keys
  static const _keyUrl = 'erpnext_url';
  static const _keyUsername = 'erpnext_username';
  static const _keyPassword = 'erpnext_password';
  static const _keyCompany = 'erpnext_company';
  static const _keyApiKey = 'erpnext_api_key';
  static const _keyApiSecret = 'erpnext_api_secret';
  static const _keyAiEndpoint = 'ai_endpoint';
  static const _keyAiModel = 'ai_model';
  static const _keyClaudeApiKey = 'claude_api_key';
  static const _keyOpenAiApiKey = 'openai_api_key';
  static const _keyChatgptApiKey = 'chatgpt_api_key';
  static const _keyChatgptModel = 'chatgpt_model';
  static const _keyAiProvider = 'ai_provider';
  static const _keyN8nUrl = 'n8n_chat_url';

  static const _claudeModels = [
    'claude-sonnet-4-6',
    'claude-opus-4-6',
    'claude-haiku-4-5',
  ];

  static const _chatgptModels = [
    'gpt-5-mini',
    'gpt-4.5-preview',
    'gpt-4o',
    'gpt-4o-mini',
    'gpt-4-turbo',
    'gpt-3.5-turbo',
    'o1',
    'o3-mini',
  ];

  static ThemeMode _parseThemeMode(String s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _urlController.text = prefs.getString(_keyUrl) ?? '';
      _usernameController.text = prefs.getString(_keyUsername) ?? '';
      _passwordController.text = prefs.getString(_keyPassword) ?? '';
      _companyController.text = prefs.getString(_keyCompany) ?? '';
      _apiKeyController.text = prefs.getString(_keyApiKey) ?? '';
      _apiSecretController.text = prefs.getString(_keyApiSecret) ?? '';
      _aiEndpointController.text =
          prefs.getString(_keyAiEndpoint) ??
          'frappe_assistant_core.api.fac_endpoint.handle_mcp';
      _selectedModel = prefs.getString(_keyAiModel) ?? 'claude-sonnet-4-6';
      _claudeApiKeyController.text = prefs.getString(_keyClaudeApiKey) ?? '';
      _openaiApiKeyController.text = prefs.getString(_keyOpenAiApiKey) ?? '';
      _chatgptApiKeyController.text = prefs.getString(_keyChatgptApiKey) ?? '';
      _selectedChatGptModel = prefs.getString(_keyChatgptModel) ?? 'gpt-4o';
      _selectedProvider = prefs.getString(_keyAiProvider) ?? 'claude';
      _n8nUrlController.text =
          prefs.getString(_keyN8nUrl) ??
          'https://n8n.kcsc.com.jo/webhook/9a85a2f1-e7cb-4285-9dc2-5b482ed38e5d/chat';
      _selectedLang = prefs.getString('app_language') ?? 'en';
      _selectedTheme = prefs.getString('app_theme_mode') ?? 'light';
      _customLogoPath = prefs.getString('custom_logo_path') ?? '';
    });
  }

  /// Pick an image from the device, copy to app docs directory, save path.
  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;

    List<int> bytes;
    if (picked.bytes != null) {
      bytes = picked.bytes!;
    } else if (picked.readStream != null) {
      final allBytes = <int>[];
      await for (final chunk in picked.readStream!) {
        allBytes.addAll(chunk);
      }
      bytes = allBytes;
    } else {
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.noImageContent)),
        );
      }
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/custom_logo.png');
    await file.writeAsBytes(bytes);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_logo_path', file.path);

    if (mounted) {
      final l = AppLocalizations.of(context);
      setState(() => _customLogoPath = file.path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.logoUpdated),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Remove custom logo and revert to default.
  Future<void> _removeLogo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('custom_logo_path');
    final f = File(_customLogoPath);
    if (f.existsSync()) await f.delete();
    if (mounted) setState(() => _customLogoPath = '');
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _saved = false;
    });

    String url = _urlController.text.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUrl, url);
    await prefs.setString(_keyUsername, _usernameController.text.trim());
    await prefs.setString(_keyPassword, _passwordController.text);
    await prefs.setString(_keyCompany, _companyController.text.trim());
    await prefs.setString(_keyApiKey, _apiKeyController.text.trim());
    await prefs.setString(_keyApiSecret, _apiSecretController.text.trim());
    await prefs.setString(_keyAiEndpoint, _aiEndpointController.text.trim());
    await prefs.setString(_keyAiModel, _selectedModel);
    await prefs.setString(
      _keyClaudeApiKey,
      _claudeApiKeyController.text.trim(),
    );
    await prefs.setString(
      _keyOpenAiApiKey,
      _openaiApiKeyController.text.trim(),
    );
    await prefs.setString(
      _keyChatgptApiKey,
      _chatgptApiKeyController.text.trim(),
    );
    await prefs.setString(_keyChatgptModel, _selectedChatGptModel);
    await prefs.setString(_keyAiProvider, _selectedProvider);
    await prefs.setString(_keyN8nUrl, _n8nUrlController.text.trim());
    await prefs.setString('app_language', _selectedLang);
    await prefs.setString('app_theme_mode', _selectedTheme);

    // Apply locale + theme changes immediately
    if (mounted) {
      MyApp.setLocale(context, Locale(_selectedLang));
      MyApp.setThemeMode(context, _parseThemeMode(_selectedTheme));
    }

    if (mounted) {
      setState(() {
        _isSaving = false;
        _saved = true;
      });
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.saveSettings),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// تصدير جميع الإعدادات — يكتب ملف JSON مؤقت ثم يعرض share sheet.
  Future<void> _exportSettings() async {
    // Capture l10n strings before any await to avoid BuildContext across async gap
    final l = AppLocalizations.of(context);
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = <String, String>{
        for (final k in [
          _keyUrl,
          _keyUsername,
          _keyPassword,
          _keyCompany,
          _keyApiKey,
          _keyApiSecret,
          _keyAiEndpoint,
          _keyAiModel,
          _keyClaudeApiKey,
          _keyOpenAiApiKey,
          _keyChatgptApiKey,
          _keyChatgptModel,
          _keyAiProvider,
          _keyN8nUrl,
          'app_language',
        ])
          k: prefs.getString(k) ?? '',
      };

      // كتابة في مجلد cache مؤقت — لا يحتاج صلاحيات، متاح دائماً
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/kcsc_ai_backup.json');
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
      );

      // فتح share sheet — المستخدم يختار (WhatsApp / Drive / Email / Save...)
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: l.backupSubject,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.exportFailed(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// استيراد الإعدادات من ملف JSON — يقبل أي ملف JSON من أي مكان (Downloads, WhatsApp, Drive...).
  Future<void> _importSettings() async {
    final l = AppLocalizations.of(context);
    try {
      // any — يقبل أي نوع ملف لأن بعض التطبيقات (Drive/WhatsApp) لا تُرسل مع MIME صحيح
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
        withReadStream: true,
      );

      if (result == null || result.files.isEmpty) return;

      final picked = result.files.first;

      // قراءة المحتوى — stream أولاً ثم bytes
      List<int> allBytes;
      if (picked.readStream != null) {
        allBytes = [];
        await for (final chunk in picked.readStream!) {
          allBytes.addAll(chunk);
        }
      } else if (picked.bytes != null) {
        allBytes = picked.bytes!;
      } else {
        throw Exception(l.noFileContent);
      }

      final content = utf8.decode(allBytes);

      // تحقق بسيط أن الملف JSON صالح
      final decoded = jsonDecode(content);
      if (decoded is! Map) throw Exception(l.notSettingsFile);
      final data = decoded as Map<String, dynamic>;

      // تحقق أن الملف يحتوي على مفتاح ERPNext واحد على الأقل
      final knownKeys = {
        _keyUrl,
        _keyUsername,
        _keyPassword,
        _keyCompany,
        _keyApiKey,
        _keyApiSecret,
        _keyAiEndpoint,
        _keyAiModel,
        _keyClaudeApiKey,
        _keyOpenAiApiKey,
        _keyChatgptApiKey,
        _keyChatgptModel,
        _keyAiProvider,
        _keyN8nUrl,
        'app_language',
      };
      if (!data.keys.any((k) => knownKeys.contains(k))) {
        throw Exception(l.notKcscSettings);
      }

      final prefs = await SharedPreferences.getInstance();
      for (final entry in data.entries) {
        if (!knownKeys.contains(entry.key)) continue;
        final v = entry.value?.toString() ?? '';
        if (v.isNotEmpty) await prefs.setString(entry.key, v);
      }

      await _loadSettings();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.importSuccess(data.length)),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.importFailed(e.toString())),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _clearSettings() async {
    final clearedMsg = AppLocalizations.of(context).settingsCleared;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dl = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(dl.clearSettingsTitle),
          content: Text(dl.clearSettingsConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(dl.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(dl.clear, style: const TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      for (final k in [
        _keyUrl,
        _keyUsername,
        _keyPassword,
        _keyCompany,
        _keyApiKey,
        _keyApiSecret,
        _keyAiEndpoint,
        _keyAiModel,
        _keyClaudeApiKey,
        _keyOpenAiApiKey,
        _keyChatgptApiKey,
        _keyChatgptModel,
        _keyAiProvider,
        _keyN8nUrl,
      ]) {
        await prefs.remove(k);
      }
      _urlController.clear();
      _usernameController.clear();
      _passwordController.clear();
      _companyController.clear();
      _apiKeyController.clear();
      _apiSecretController.clear();
      _claudeApiKeyController.clear();
      _openaiApiKeyController.clear();
      _chatgptApiKeyController.clear();
      _aiEndpointController.text =
          'frappe_assistant_core.api.fac_endpoint.handle_mcp';
      _n8nUrlController.text =
          'https://n8n.kcsc.com.jo/webhook/9a85a2f1-e7cb-4285-9dc2-5b482ed38e5d/chat';
      if (mounted) {
        setState(() {
          _saved = false;
          _selectedModel = 'claude-sonnet-4-6';
          _selectedChatGptModel = 'gpt-4o';
          _selectedProvider = 'claude';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(clearedMsg)),
        );
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _companyController.dispose();
    _apiKeyController.dispose();
    _apiSecretController.dispose();
    _aiEndpointController.dispose();
    _claudeApiKeyController.dispose();
    _openaiApiKeyController.dispose();
    _chatgptApiKeyController.dispose();
    _n8nUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      appBar: AppBar(
        title: Text(l.settings),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_outlined),
            tooltip: l.exportTooltip,
            onPressed: _exportSettings,
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: l.importTooltip,
            onPressed: _importSettings,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l.clearAllSettings,
            onPressed: _clearSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── App Logo ─────────────────────────────────────────────────
                _SectionHeader(label: l.appLogoSection),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Preview
                    Container(
                      width: 72,
                      height: 72,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.of(context).surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.of(context).surfaceHigh,
                        ),
                      ),
                      child: buildLogoWidget(path: _customLogoPath, height: 56),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _pickLogo,
                            icon: const Icon(Icons.image_outlined, size: 18),
                            label: Text(l.chooseLogo),
                          ),
                          if (_customLogoPath.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _removeLogo,
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 16,
                                color: AppColors.error,
                              ),
                              label: Text(
                                l.removeLogo,
                                style: const TextStyle(
                                  color: AppColors.error,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── Language ─────────────────────────────────────────────────
                _SectionHeader(label: l.language),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _LangButton(
                        label: l.arabic,
                        flag: '🇸🇦',
                        selected: _selectedLang == 'ar',
                        onTap: () => setState(() => _selectedLang = 'ar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LangButton(
                        label: l.english,
                        flag: '🇬🇧',
                        selected: _selectedLang == 'en',
                        onTap: () => setState(() => _selectedLang = 'en'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── Theme ────────────────────────────────────────────────────
                _SectionHeader(label: l.themeMode),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _LangButton(
                        label: l.darkMode,
                        flag: '🌙',
                        selected: _selectedTheme == 'dark',
                        onTap: () => setState(() => _selectedTheme = 'dark'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _LangButton(
                        label: l.lightMode,
                        flag: '☀️',
                        selected: _selectedTheme == 'light',
                        onTap: () => setState(() => _selectedTheme = 'light'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _LangButton(
                        label: l.systemMode,
                        flag: '⚙️',
                        selected: _selectedTheme == 'system',
                        onTap: () => setState(() => _selectedTheme = 'system'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── ERPNext ─────────────────────────────────────────────────
                _SectionHeader(
                  label: l.erpnextConnection,
                ),
                const SizedBox(height: 16),

                _SettingsField(
                  controller: _urlController,
                  label: 'ERPNext URL',
                  hint: 'https://your-site.erpnext.com',
                  icon: Icons.link,
                  keyboardType: TextInputType.url,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return l.urlRequired;
                    final uri = Uri.tryParse(v.trim());
                    if (uri == null || !uri.hasScheme) return l.validUrl;
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                _SettingsField(
                  controller: _usernameController,
                  label: l.username,
                  hint: 'admin or user@example.com',
                  icon: Icons.person_outline,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l.usernameRequired : null,
                ),
                const SizedBox(height: 16),

                _SettingsField(
                  controller: _passwordController,
                  label: l.password,
                  hint: '••••••••',
                  icon: Icons.lock_outline,
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.of(context).textSecondary,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? l.passwordRequired : null,
                ),
                const SizedBox(height: 24),

                // ── ERPNext API Token (optional) ──────────────────────────────
                _SectionHeader(label: l.apiTokenOptional),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.of(context).surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.of(context).surfaceHigh,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.of(context).textSecondary,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.apiTokenInfo,
                          style: TextStyle(
                            color: AppColors.of(context).textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                _SettingsField(
                  controller: _apiKeyController,
                  label: 'API Key',
                  hint: 'a1b2c3d4e5f6...',
                  icon: Icons.key_outlined,
                  validator: (_) => null,
                ),
                const SizedBox(height: 12),

                _SettingsField(
                  controller: _apiSecretController,
                  label: 'API Secret',
                  hint: '••••••••••••',
                  icon: Icons.lock_person_outlined,
                  obscureText: _obscureApiSecret,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureApiSecret
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.of(context).textSecondary,
                    ),
                    onPressed: () =>
                        setState(() => _obscureApiSecret = !_obscureApiSecret),
                  ),
                  validator: (_) => null,
                ),
                const SizedBox(height: 24),

                _SectionHeader(label: l.company),
                const SizedBox(height: 16),

                _SettingsField(
                  controller: _companyController,
                  label: l.companyName,
                  hint: l.companyHint,
                  icon: Icons.business_outlined,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l.companyRequired : null,
                ),
                const SizedBox(height: 32),

                // ── AI Assistant ─────────────────────────────────────────────
                _SectionHeader(label: l.aiProvider),
                const SizedBox(height: 12),

                // Provider selector: 4 options in 2×2 grid
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _LangButton(
                            label: l.providerClaudeOnly,
                            flag: '🤖',
                            selected: _selectedProvider == 'claude',
                            onTap: () =>
                                setState(() => _selectedProvider = 'claude'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _LangButton(
                            label: l.providerChatGptOnly,
                            flag: '💬',
                            selected: _selectedProvider == 'chatgpt',
                            onTap: () =>
                                setState(() => _selectedProvider = 'chatgpt'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _LangButton(
                            label: l.providerClaudeFirst,
                            flag: '🔁',
                            selected: _selectedProvider == 'claude_first',
                            onTap: () => setState(
                              () => _selectedProvider = 'claude_first',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _LangButton(
                            label: l.providerChatGptFirst,
                            flag: '🔁',
                            selected: _selectedProvider == 'chatgpt_first',
                            onTap: () => setState(
                              () => _selectedProvider = 'chatgpt_first',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l.providerDesc(_selectedProvider),
                  style: TextStyle(
                    color: AppColors.of(context).textSecondary,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // ── Claude fields (claude, claude_first, chatgpt_first) ──────────
                if (_selectedProvider != 'chatgpt') ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.of(context).surfaceHigh,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: AppColors.of(context).textSecondary,
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l.aiInfo,
                            style: TextStyle(
                              color: AppColors.of(context).textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  _SettingsField(
                    controller: _claudeApiKeyController,
                    label: l.claudeApiKey,
                    hint: 'sk-ant-api03-…',
                    icon: Icons.vpn_key_outlined,
                    obscureText: _obscureApiKey,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureApiKey
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: AppColors.of(context).textSecondary,
                      ),
                      onPressed: () =>
                          setState(() => _obscureApiKey = !_obscureApiKey),
                    ),
                    validator: (_) => null,
                  ),
                  const SizedBox(height: 16),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _SettingsField(
                          controller: _aiEndpointController,
                          label: 'MCP Endpoint',
                          hint:
                              'frappe_assistant_core.api.fac_endpoint.handle_mcp',
                          icon: Icons.api_outlined,
                          validator: (_) => null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: l.resetToDefault,
                        child: IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.of(context).surfaceHigh,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            minimumSize: const Size(48, 56),
                          ),
                          icon: Icon(
                            Icons.refresh,
                            color: AppColors.of(context).textSecondary,
                          ),
                          onPressed: () => setState(() {
                            _aiEndpointController.text =
                                'frappe_assistant_core.api.fac_endpoint.handle_mcp';
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Claude model selector
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).surfaceHigh,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedModel,
                        isExpanded: true,
                        dropdownColor: AppColors.of(context).surface,
                        icon: Icon(
                          Icons.arrow_drop_down,
                          color: AppColors.of(context).textSecondary,
                        ),
                        style: TextStyle(
                          color: AppColors.of(context).textPrimary,
                          fontSize: 14,
                        ),
                        items: _claudeModels
                            .map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.smart_toy_outlined,
                                      color: AppColors.of(
                                        context,
                                      ).textSecondary,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(m),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _selectedModel = v!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── ChatGPT fields (chatgpt, claude_first, chatgpt_first) ────────
                if (_selectedProvider != 'claude') ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.of(context).surfaceHigh,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: AppColors.of(context).textSecondary,
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l.chatGptInfo,
                            style: TextStyle(
                              color: AppColors.of(context).textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  _SettingsField(
                    controller: _chatgptApiKeyController,
                    label: l.chatgptApiKey,
                    hint: 'sk-proj-…',
                    icon: Icons.vpn_key_outlined,
                    obscureText: _obscureChatGptKey,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureChatGptKey
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: Colors.white54,
                      ),
                      onPressed: () => setState(
                        () => _obscureChatGptKey = !_obscureChatGptKey,
                      ),
                    ),
                    validator: (_) => null,
                  ),
                  const SizedBox(height: 16),

                  // ChatGPT model selector
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).surfaceHigh,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedChatGptModel,
                        isExpanded: true,
                        dropdownColor: AppColors.of(context).surface,
                        icon: Icon(
                          Icons.arrow_drop_down,
                          color: AppColors.of(context).textSecondary,
                        ),
                        style: TextStyle(
                          color: AppColors.of(context).textPrimary,
                          fontSize: 14,
                        ),
                        items: _chatgptModels
                            .map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.smart_toy_outlined,
                                      color: AppColors.of(
                                        context,
                                      ).textSecondary,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(m),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedChatGptModel = v!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _SettingsField(
                          controller: _aiEndpointController,
                          label: 'MCP Endpoint',
                          hint:
                              'frappe_assistant_core.api.fac_endpoint.handle_mcp',
                          icon: Icons.api_outlined,
                          validator: (_) => null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: l.resetToDefault,
                        child: IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.of(context).surfaceHigh,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            minimumSize: const Size(48, 56),
                          ),
                          icon: Icon(
                            Icons.refresh,
                            color: AppColors.of(context).textSecondary,
                          ),
                          onPressed: () => setState(() {
                            _aiEndpointController.text =
                                'frappe_assistant_core.api.fac_endpoint.handle_mcp';
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // ── OpenAI Whisper key (always shown) ─────────────────────────
                _SettingsField(
                  controller: _openaiApiKeyController,
                  label: 'OpenAI API Key (Whisper — Voice)',
                  hint: 'sk-…',
                  icon: Icons.mic_external_on_outlined,
                  obscureText: _obscureOpenAiKey,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureOpenAiKey
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.of(context).textSecondary,
                    ),
                    onPressed: () =>
                        setState(() => _obscureOpenAiKey = !_obscureOpenAiKey),
                  ),
                  validator: (_) => null,
                ),
                const SizedBox(height: 32),

                // ── n8n Chat ─────────────────────────────────────────────────
                _SectionHeader(label: 'n8n Chat'),
                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _SettingsField(
                        controller: _n8nUrlController,
                        label: 'n8n Webhook URL',
                        hint: 'https://n8n.example.com/webhook/.../chat',
                        icon: Icons.webhook_outlined,
                        keyboardType: TextInputType.url,
                        validator: (_) => null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'إعادة تعيين إلى القيمة الافتراضية',
                      child: IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.of(context).surfaceHigh,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          minimumSize: const Size(48, 56),
                        ),
                        icon: Icon(
                          Icons.refresh,
                          color: AppColors.of(context).textSecondary,
                        ),
                        onPressed: () => setState(() {
                          _n8nUrlController.text =
                              'https://n8n.kcsc.com.jo/webhook/9a85a2f1-e7cb-4285-9dc2-5b482ed38e5d/chat';
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),

                // ── Save button ──────────────────────────────────────────────
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveSettings,
                  icon: _isSaving
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            color: AppColors.of(context).onPrimary,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(_saved ? Icons.check : Icons.save_outlined),
                  label: Text(
                    _isSaving
                        ? l.saving
                        : _saved
                        ? l.saved
                        : l.saveSettings,
                  ),
                ),
                const SizedBox(height: 16),

                TextButton(
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, '/login'),
                  child: Text(
                    l.backToLogin,
                    style: TextStyle(
                      color: AppColors.of(context).textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable section header
// ---------------------------------------------------------------------------
class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: AppColors.of(context).textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable styled text field
// ---------------------------------------------------------------------------
class _SettingsField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const _SettingsField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: TextStyle(color: AppColors.of(context).textPrimary),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.of(context).textSecondary),
        suffixIcon: suffixIcon,
        labelStyle: TextStyle(color: AppColors.of(context).textSecondary),
        hintStyle: TextStyle(
          color: AppColors.of(context).textSecondary,
          fontSize: 13,
        ),
        filled: true,
        fillColor: AppColors.of(context).surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.of(context).primary,
            width: 1.5,
          ),
        ),
        errorStyle: TextStyle(color: AppColors.warning),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Language selector button
// ---------------------------------------------------------------------------
class _LangButton extends StatelessWidget {
  final String label;
  final String flag;
  final bool selected;
  final VoidCallback onTap;

  const _LangButton({
    required this.label,
    required this.flag,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.of(context).primary.withValues(alpha: 0.15)
              : AppColors.of(context).surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.of(context).primary
                : AppColors.of(context).surfaceHigh,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(flag, style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? AppColors.of(context).textPrimary
                    : AppColors.of(context).textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 14,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.check_circle,
                color: AppColors.of(context).primary,
                size: 15,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
