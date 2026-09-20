import 'package:flutter/material.dart';

import '../api_service.dart';
import 'admin/admin_home_shell.dart';
import 'home_shell.dart';
import 'staff/staff_home_shell.dart';

const _staffRoles = {'staff', 'approver'};

/// Resolves the logged-in user's role and shows the customer, staff, or
/// admin shell accordingly. Used both at app startup (already-logged-in
/// session) and right after a successful login.
///
/// Staff and approver share a day-to-day work-queue shell (requests, KYC
/// review, reports). Admin gets a distinct shell with everything staff has
/// plus system-level user/role management - it isn't just another staff
/// role, it controls the application itself.
class RoleHomeShell extends StatelessWidget {
  const RoleHomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: ApiService.me(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final role = snapshot.data?.role;
        if (role == 'admin') {
          return const AdminHomeShell();
        }
        if (role != null && _staffRoles.contains(role)) {
          return StaffHomeShell(role: role);
        }
        return const HomeShell();
      },
    );
  }
}
