import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'app_colors.dart';
import 'app_localizations.dart';
import 'auth_state.dart';
import 'realtime_workflow_service.dart';
import 'settings_page.dart' show buildLogoWidget;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading = false;
  bool _hasCredentials = false;
  String? _errorMessage;
  String _configuredUrl  = '';
  String _customLogoPath = '';

  @override
  void initState() {
    super.initState();
    _checkCredentials();
  }

  // Check whether settings have been filled in
  Future<void> _checkCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('erpnext_url') ?? '';
    final username = prefs.getString('erpnext_username') ?? '';
    final password = prefs.getString('erpnext_password') ?? '';

    setState(() {
      _hasCredentials  = url.isNotEmpty && username.isNotEmpty && password.isNotEmpty;
      _configuredUrl   = url;
      _customLogoPath  = prefs.getString('custom_logo_path') ?? '';
    });
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // ApiService.login() returns null on success, or an error string
      final error = await ApiService.login();

      if (!mounted) return;

      if (error == null) {
        // Login successful — mark session as active
        AuthState.isLoggedIn = true;
        RealtimeWorkflowService().initialize().ignore();
        if (mounted) {
          final l = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l.loginSuccessful),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/ai-assistant',
          (route) => false,
        );
      } else {
        setState(() => _errorMessage = error);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Unexpected error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      appBar: AppBar(
        title: Text(l.login),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l.settings,
            onPressed: () async {
              await Navigator.pushNamed(context, '/settings');
              _checkCredentials();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Logo card ─────────────────────────────────────────────
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: buildLogoWidget(path: _customLogoPath, height: 80),
                  ),
                ),
                const SizedBox(height: 28),

                // ── Title ─────────────────────────────────────────────────
                Text(
                  l.signIn,
                  style: TextStyle(
                    fontSize: 24,
                    color: AppColors.of(context).textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),

                // ── Server hint ───────────────────────────────────────────
                if (_configuredUrl.isNotEmpty)
                  Text(
                    _configuredUrl,
                    style: TextStyle(
                        color: AppColors.of(context).textSecondary, fontSize: 13),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),

                const SizedBox(height: 28),

                // ── Banners ───────────────────────────────────────────────
                if (!_hasCredentials)
                  _InfoBanner(
                    icon: Icons.info_outline,
                    color: AppColors.warning,
                    message: l.noCredentials,
                  ),
                if (_errorMessage != null)
                  _InfoBanner(
                    icon: Icons.error_outline,
                    color: AppColors.error,
                    message: _errorMessage!,
                  ),

                const SizedBox(height: 8),

                // ── Login button ──────────────────────────────────────────
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: (_isLoading || !_hasCredentials) ? null : _login,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                          )
                        : Text(l.login),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Settings link ─────────────────────────────────────────
                TextButton.icon(
                  onPressed: () async {
                    await Navigator.pushNamed(context, '/settings');
                    _checkCredentials();
                  },
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: Text(l.configureSettings),
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
// Small banner widget for info / error messages
// ---------------------------------------------------------------------------
class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;

  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.message,
  });

  static TextDirection _detectDir(String text) {
    for (final rune in text.runes) {
      if (rune > 0x20) {
        return (rune >= 0x0590 && rune <= 0x08FF)
            ? TextDirection.rtl
            : TextDirection.ltr;
      }
    }
    return TextDirection.rtl;
  }

  @override
  Widget build(BuildContext context) {
    final dir = _detectDir(message);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 13),
              textDirection: dir,
            ),
          ),
        ],
      ),
    );
  }
}