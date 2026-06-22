import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';
import 'app_localizations.dart';

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
          backgroundColor: Colors.orange,
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
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).company),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: AppLocalizations.of(context).settings,
            onPressed: () async {
              await Navigator.pushNamed(context, '/settings');
              _loadCompany(); // Refresh after returning from settings
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.business,
                        size: 64, color: Colors.white54),
                    const SizedBox(height: 24),

                    Text(
                      AppLocalizations.of(context).selectedCompany,
                      style: TextStyle(
                        color: Colors.white54,
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
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline,
                              color: Colors.white38, size: 18),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _companyName.isEmpty
                                  ? AppLocalizations.of(context).notConfigured
                                  : _companyName,
                              style: TextStyle(
                                color: _companyName.isEmpty
                                    ? Colors.white30
                                    : Colors.white,
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
                      AppLocalizations.of(context).companyInSettings,
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 40),

                    ElevatedButton.icon(
                      onPressed: _companyName.isEmpty ? null : _proceed,
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(AppLocalizations.of(context).continueToModules),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),

                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/settings'),
                      child: Text(
                        AppLocalizations.of(context).changeCompany,
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
