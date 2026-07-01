import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';
import 'app_localizations.dart';
import 'aurora_widgets.dart';

class CompanySelectionPage extends StatefulWidget {
  const CompanySelectionPage({super.key});

  @override
  State<CompanySelectionPage> createState() => _CompanySelectionPageState();
}

class _CompanySelectionPageState extends State<CompanySelectionPage> {
  bool _isLoading = true;
  String _companyName = '';

  @override
  void initState() {
    super.initState();
    _loadCompany();
  }

  Future<void> _loadCompany() async {
    final prefs = await SharedPreferences.getInstance();
    final company = prefs.getString('erpnext_company') ?? '';
    setState(() {
      _companyName = company;
      _isLoading = false;
    });
  }

  void _proceed() {
    final l = AppLocalizations.of(context);
    if (_companyName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.noCompany),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    Navigator.pushNamedAndRemoveUntil(
      context,
      '/dashboard',
      (route) => false,
      arguments: {'name': _companyName, 'abbr': ''},
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text(l.company),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l.settings,
            onPressed: () async {
              await Navigator.pushNamed(context, '/settings');
              _loadCompany();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: c.primary))
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.business, size: 64, color: c.textSecondary),
                    const SizedBox(height: 24),

                    Text(
                      l.selectedCompany,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),

                    // Readonly company name field
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 18),
                      decoration: BoxDecoration(
                        color: c.surfaceHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: c.primary.withValues(alpha: 0.18)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline,
                              color: c.textSecondary.withValues(alpha: 0.7),
                              size: 18),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _companyName.isEmpty
                                  ? l.notConfigured
                                  : _companyName,
                              style: TextStyle(
                                color: _companyName.isEmpty
                                    ? c.textSecondary.withValues(alpha: 0.5)
                                    : c.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),
                    Text(
                      l.companyInSettings,
                      style: TextStyle(
                          color: c.textSecondary.withValues(alpha: 0.7),
                          fontSize: 11),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 40),

                    GradientButton(
                      onPressed: _companyName.isEmpty ? null : _proceed,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l.continueToModules),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward,
                              color: Colors.white, size: 18),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/settings'),
                      child: Text(l.changeCompany),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
