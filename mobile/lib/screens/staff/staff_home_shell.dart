import 'package:flutter/material.dart';

import '../account/account_screen.dart';
import 'kyc_review_screen.dart';
import 'reports_screen.dart';
import 'staff_approvals_screen.dart';
import 'staff_queue_screen.dart';

class StaffHomeShell extends StatefulWidget {
  final String role; // 'staff' or 'approver'
  const StaffHomeShell({super.key, required this.role});

  @override
  State<StaffHomeShell> createState() => _StaffHomeShellState();
}

class _StaffHomeShellState extends State<StaffHomeShell> {
  int _index = 0;

  /// Plain 'staff' gets Queue/KYC/Reports/Account - Approvals stays
  /// approver-only until staff picks that up too.
  bool get _isPlainStaff => widget.role == 'staff';

  List<Widget> get _screens => _isPlainStaff
      ? const [StaffQueueScreen(), KycReviewScreen(), ReportsScreen(), AccountScreen()]
      : const [StaffQueueScreen(), StaffApprovalsScreen(), KycReviewScreen(), ReportsScreen(), AccountScreen()];

  List<BottomNavigationBarItem> get _items => _isPlainStaff
      ? const [
          BottomNavigationBarItem(icon: Icon(Icons.list_alt_outlined), label: 'Queue'),
          BottomNavigationBarItem(icon: Icon(Icons.badge_outlined), label: 'KYC'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), label: 'Reports'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Account'),
        ]
      : const [
          BottomNavigationBarItem(icon: Icon(Icons.list_alt_outlined), label: 'Queue'),
          BottomNavigationBarItem(icon: Icon(Icons.fact_check_outlined), label: 'Approvals'),
          BottomNavigationBarItem(icon: Icon(Icons.badge_outlined), label: 'KYC'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), label: 'Reports'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Account'),
        ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        items: _items,
      ),
    );
  }
}
