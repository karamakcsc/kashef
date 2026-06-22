import 'package:flutter/material.dart';
import 'api_service.dart';
import 'app_colors.dart';

class AccountingDashboard extends StatefulWidget {
  const AccountingDashboard({super.key});

  @override
  State<AccountingDashboard> createState() => _AccountingDashboardState();
}

class _AccountingDashboardState extends State<AccountingDashboard> {
  bool isLoading = true;
  Map<String, dynamic>? dashboardData;
  String? errorMessage;
  Map<String, String>? selectedCompany;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Get company data from route arguments
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, String>) {
      selectedCompany = args;
    }
    if (selectedCompany != null && dashboardData == null) {
      loadDashboardData();
    }
  }

  Future<void> loadDashboardData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final companyData = await ApiService.get('/api/resource/Company');
      final companies = companyData['data'] ?? [];
      setState(() {
        dashboardData = {
          'companies': companies,
          'totalCompanies': (companies as List).length,
        };
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Connection error: $e';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounting Dashboard'),
        titleTextStyle: TextStyle(
          fontSize: 24,
          color: AppColors.of(context).onPrimary,
          fontWeight: FontWeight.bold,
        ),
        backgroundColor: AppColors.of(context).primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadDashboardData,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
            },
            tooltip: 'Logout',
          ),
        ],
      ),
      backgroundColor: AppColors.of(context).background,
      body: SafeArea(
        child: Container(
        color: AppColors.of(context).background,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.white,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        errorMessage!,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: loadDashboardData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.of(context).primary,
                          foregroundColor: AppColors.of(context).onPrimary,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Welcome Section
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome to ERPNext',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              selectedCompany != null
                                  ? 'Company: ${selectedCompany!['name']} (${selectedCompany!['abbr']})'
                                  : 'Accounting Dashboard',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white70,
                              ),
                            ),
                            if (selectedCompany != null)
                              const Text(
                                'Accounting Dashboard',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white54,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Quick Stats
                      const Text(
                        'Quick Stats',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              'Companies',
                              dashboardData?['totalCompanies']?.toString() ??
                                  '0',
                              Icons.business,
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildStatCard(
                              'Active',
                              '1',
                              Icons.check_circle,
                              Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Menu Items
                      const Text(
                        'Accounting Modules',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildMenuGrid(),
                    ],
                  ),
                ),
        ),
      ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(fontSize: 14, color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMenuGrid() {
    final menuItems = [
      {
        'title': 'Chart of Accounts',
        'icon': Icons.account_tree,
        'color': Colors.orange,
      },
      {'title': 'Journal Entries', 'icon': Icons.book, 'color': Colors.purple},
      {
        'title': 'General Ledger',
        'icon': Icons.table_chart,
        'color': Colors.teal,
      },
      {'title': 'Trial Balance', 'icon': Icons.balance, 'color': Colors.indigo},
      {
        'title': 'Financial Reports',
        'icon': Icons.bar_chart,
        'color': Colors.red,
      },
      {
        'title': 'Bank Reconciliation',
        'icon': Icons.account_balance,
        'color': Colors.green,
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.2,
      ),
      itemCount: menuItems.length,
      itemBuilder: (context, index) {
        final item = menuItems[index];
        return _buildMenuItem(
          item['title'] as String,
          item['icon'] as IconData,
          item['color'] as Color,
        );
      },
    );
  }

  Widget _buildMenuItem(String title, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
