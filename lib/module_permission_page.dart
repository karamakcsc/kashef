import 'package:flutter/material.dart';
import 'app_colors.dart';

class ModulePermissionPage extends StatelessWidget {
  final String moduleName;
  final IconData icon;
  final bool hasPermission;
  final String reason;

  const ModulePermissionPage({
    super.key,
    required this.moduleName,
    required this.icon,
    required this.hasPermission,
    required this.reason,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = hasPermission ? Colors.greenAccent : Colors.redAccent;
    final statusIcon = hasPermission ? Icons.check_circle : Icons.cancel;
    final statusText =
        hasPermission ? 'Access Granted' : 'Access Denied';

    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      appBar: AppBar(
        title: Text(moduleName),
        leading: const BackButton(),
      ),
      body: SafeArea(
        child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Module icon
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 64, color: Colors.white),
              ),

              const SizedBox(height: 24),

              // Module name
              Text(
                moduleName,
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              // Permission status icon
              Icon(statusIcon, size: 80, color: statusColor),

              const SizedBox(height: 16),

              // Status text
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 20,
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Reason
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  reason,
                  style: TextStyle(color: statusColor, fontSize: 14),
                  textAlign: TextAlign.center,
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
