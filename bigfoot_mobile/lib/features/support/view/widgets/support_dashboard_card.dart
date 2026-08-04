import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/router/route_names.dart';
import '../../../../data/models/user.dart';
import '../../../auth/viewmodel/auth_viewmodel.dart';
import '../../data/support_api.dart';

/// Dashboard entry point for the support feature.
/// - Admins (owner/office/PM): "Problem reports" inbox with an open-count badge.
/// - Everyone else: "Report a problem" shortcut.
class SupportDashboardCard extends StatefulWidget {
  const SupportDashboardCard({super.key});

  @override
  State<SupportDashboardCard> createState() => _SupportDashboardCardState();
}

class _SupportDashboardCardState extends State<SupportDashboardCard> {
  int _openCount = 0;
  bool get _isAdmin {
    final auth = context.read<AuthViewModel>().state;
    final role = auth is Authenticated ? auth.user.role : null;
    return role == UserRole.owner ||
        role == UserRole.office ||
        role == UserRole.productionManager;
  }

  @override
  void initState() {
    super.initState();
    if (_isAdmin) _loadCount();
  }

  Future<void> _loadCount() async {
    try {
      final c = await SupportApi(context.read<DioClient>()).openCount();
      if (mounted) setState(() => _openCount = c);
    } catch (_) {/* badge just stays 0 */}
  }

  @override
  Widget build(BuildContext context) {
    final admin = _isAdmin;
    final title = admin ? 'Problem reports' : 'Report a problem';
    final subtitle = admin
        ? 'Messages from the team about app problems'
        : 'Something not working? Send it to the admins';
    final icon = admin ? Icons.support_agent : Icons.report_problem_outlined;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          onTap: () {
            context.pushNamed(
              admin ? RouteNames.supportList : RouteNames.supportReport,
            );
          },
          leading: CircleAvatar(
            backgroundColor: AppColors.amber.withValues(alpha: 0.18),
            child: Icon(icon, color: AppColors.amber),
          ),
          title: Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.navy)),
          subtitle: Text(subtitle,
              style: TextStyle(fontSize: 12, color: AppColors.disabled)),
          trailing: (admin && _openCount > 0)
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                  child: Text('$_openCount',
                      style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                )
              : const Icon(Icons.chevron_right, color: AppColors.disabled),
        ),
      ),
    );
  }
}
