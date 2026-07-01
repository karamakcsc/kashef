import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';
import 'app_theme.dart';
import 'app_localizations.dart';
import 'auth_state.dart';
import 'background_service.dart';
import 'login_page.dart';
import 'accounting_dashboard.dart';
import 'company_selection_page.dart';
import 'modules_page.dart';
import 'settings_page.dart' show SettingsPage, buildLogoWidget;
import 'ai_assistant_page.dart';
import 'document_viewer_page.dart';
import 'n8n_chat_page.dart';
import 'n8n_webhook_chat_page.dart';
import 'approved_page.dart';
import 'pending_approvals_page.dart';
import 'realtime_workflow_service.dart' show workflowNavigatorKey;
import 'web_mobile_frame.dart';

// Re-export for backward compat with background_service.dart
final navigatorKey = workflowNavigatorKey;

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Background polling + local notifications (Android / iOS only)
  if (!kIsWeb) {
    await initBackgroundService();

    // If the app was launched by tapping a notification, navigate there.
    final route = await getInitialNotificationRoute();
    if (route != null && route.isNotEmpty) {
      // Defer until the widget tree is ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.pushNamed(route);
      });
    }
  }

  runApp(const MyApp());
}

// ---------------------------------------------------------------------------
// Root widget — StatefulWidget to support locale switching
// ---------------------------------------------------------------------------
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static void setLocale(BuildContext context, Locale locale) {
    context.findAncestorStateOfType<_MyAppState>()?.setLocale(locale);
  }

  static void setThemeMode(BuildContext context, ThemeMode mode) {
    context.findAncestorStateOfType<_MyAppState>()?.setThemeMode(mode);
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Locale    _locale    = const Locale('en');
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final code  = prefs.getString('app_language') ?? 'en';
    final theme = prefs.getString('app_theme_mode') ?? 'light';
    if (mounted) {
      setState(() {
        _locale    = Locale(code);
        _themeMode = _parseThemeMode(theme);
      });
    }
  }

  static ThemeMode _parseThemeMode(String s) {
    switch (s) {
      case 'light':  return ThemeMode.light;
      case 'system': return ThemeMode.system;
      default:       return ThemeMode.dark;
    }
  }

  void setLocale(Locale locale) => setState(() => _locale = locale);

  void setThemeMode(ThemeMode mode) => setState(() => _themeMode = mode);

  @override
  Widget build(BuildContext context) {
    return WebMobileFrame(
      child: MaterialApp(
        navigatorKey: workflowNavigatorKey,
        title: 'Kashef',
        debugShowCheckedModeBanner: false,

        // ── Localisation ─────────────────────────────────────────────────
        locale: _locale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],

        // ── RTL / LTR + MediaQuery override for desktop web ──────────────
        builder: (context, child) {
          Widget content = child!;
          // On desktop web: override MediaQuery width so all pages measure
          // themselves against the mobile frame width, not the full window.
          if (kIsWeb) {
            final mq = MediaQuery.of(context);
            if (mq.size.width > kWebBreakpoint) {
              content = MediaQuery(
                data: mq.copyWith(size: Size(kWebMobileWidth, mq.size.height)),
                child: content,
              );
            }
          }
          return Directionality(
            textDirection: _locale.languageCode == 'ar'
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: content,
          );
        },

        // ── Theme ────────────────────────────────────────────────────────
        theme:     AppTheme.light, // Aurora Live — unified across all platforms
        darkTheme: AppTheme.dark,
        themeMode: _themeMode,

        // ── Routes ───────────────────────────────────────────────────────
        initialRoute: '/',
        onGenerateRoute: _generateRoute,
      ),
    );
  }

  static Route<dynamic> _generateRoute(RouteSettings settings) {
    const protectedRoutes = {'/dashboard', '/company-selection', '/modules'};

    if (protectedRoutes.contains(settings.name) && !AuthState.isLoggedIn) {
      return MaterialPageRoute(
        builder: (_) => const LoginPage(),
        settings: const RouteSettings(name: '/login'),
      );
    }

    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const HomePage());
      case '/login':
        return MaterialPageRoute(builder: (_) => const LoginPage());
      case '/modules':
        return MaterialPageRoute(builder: (_) => const ModulesPage());
      case '/company-selection':
        return MaterialPageRoute(builder: (_) => const CompanySelectionPage());
      case '/dashboard':
        return MaterialPageRoute(builder: (_) => const AccountingDashboard());
      case '/settings':
        return MaterialPageRoute(builder: (_) => const SettingsPage());
      case '/ai-assistant':
        return MaterialPageRoute(builder: (_) => const AiAssistantPage());
      case '/n8n-chat':
        return MaterialPageRoute(builder: (_) => const N8nChatPage());
      case '/n8n-webhook-chat':
        return MaterialPageRoute(builder: (_) => const N8nWebhookChatPage());
      case '/pending-approvals':
        return MaterialPageRoute(builder: (_) => const PendingApprovalsPage());
      case '/approved-approvals':
        return MaterialPageRoute(builder: (_) => const ApprovedApprovalsPage());
      case '/document-viewer':
        final args = settings.arguments as Map<String, String>? ?? {};
        return MaterialPageRoute(
          builder: (_) => DocumentViewerPage(
            doctype: args['doctype'] ?? '',
            docname: args['docname'] ?? '',
          ),
        );
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(child: Text('No route defined for ${settings.name}')),
          ),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Home / splash page
// ---------------------------------------------------------------------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _customLogoPath = '';

  @override
  void initState() {
    super.initState();
    _loadLogoPath();
  }

  Future<void> _loadLogoPath() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _customLogoPath = prefs.getString('custom_logo_path') ?? '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (AuthState.isLoggedIn) {
        Navigator.pushReplacementNamed(context, '/ai-assistant');
      }
    });

    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l.settings,
            onPressed: () async {
              await Navigator.pushNamed(context, '/settings');
              _loadLogoPath();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: buildLogoWidget(path: _customLogoPath, height: 100),
                ),
                const SizedBox(height: 28),
                Text(
                  l.welcome,
                  style: TextStyle(
                    fontSize: 22,
                    color: c.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l.tapToContinue,
                  style: TextStyle(color: c.textSecondary, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pushNamed(context, '/login'),
                    child: Text(l.login),
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
