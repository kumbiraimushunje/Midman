import 'package:flutter/material.dart';

import '../api_service.dart';
import 'home_shell.dart';
import 'staff/staff_home_shell.dart';

const _staffRoles = {'staff', 'admin', 'approver'};

/// Resolves the logged-in user's role and shows the customer or staff shell
/// accordingly. Used both at app startup (already-logged-in session) and
/// right after a successful login.
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
        if (role != null && _staffRoles.contains(role)) {
          return const StaffHomeShell();
        }
        return const HomeShell();
      },
    );
  }
}
