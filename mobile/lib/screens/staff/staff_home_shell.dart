import 'package:flutter/material.dart';

import '../account/account_screen.dart';
import 'kyc_review_screen.dart';
import 'reports_screen.dart';
import 'staff_approvals_screen.dart';
import 'staff_queue_screen.dart';

class StaffHomeShell extends StatefulWidget {
  const StaffHomeShell({super.key});

  @override
  State<StaffHomeShell> createState() => _StaffHomeShellState();
}

class _StaffHomeShellState extends State<StaffHomeShell> {
  int _index = 0;

  final _screens = const [
    StaffQueueScreen(),
    StaffApprovalsScreen(),
    KycReviewScreen(),
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
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.list_alt_outlined), label: 'Queue'),
          BottomNavigationBarItem(icon: Icon(Icons.fact_check_outlined), label: 'Approvals'),
          BottomNavigationBarItem(icon: Icon(Icons.badge_outlined), label: 'KYC'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), label: 'Reports'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Account'),
        ],
      ),
    );
  }
}
