import 'package:flutter/material.dart';

import '../account/account_screen.dart';
import '../staff/kyc_review_screen.dart';
import '../staff/reports_screen.dart';
import '../staff/staff_approvals_screen.dart';
import '../staff/staff_queue_screen.dart';
import 'user_management_screen.dart';

class AdminHomeShell extends StatefulWidget {
  const AdminHomeShell({super.key});

  @override
  State<AdminHomeShell> createState() => _AdminHomeShellState();
}

class _AdminHomeShellState extends State<AdminHomeShell> {
  int _index = 0;

  final _screens = const [
    StaffQueueScreen(),
    StaffApprovalsScreen(),
    KycReviewScreen(),
    UserManagementScreen(),
    ReportsScreen(),
    AccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.list_alt_outlined), label: 'Queue'),
          BottomNavigationBarItem(icon: Icon(Icons.fact_check_outlined), label: 'Approvals'),
          BottomNavigationBarItem(icon: Icon(Icons.badge_outlined), label: 'KYC'),
          BottomNavigationBarItem(icon: Icon(Icons.manage_accounts_outlined), label: 'Users'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), label: 'Reports'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Account'),
        ],
      ),
    );
  }
}
