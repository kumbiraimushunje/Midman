import 'package:flutter/material.dart';

import 'account/account_screen.dart';
import 'family/family_screen.dart';
import 'home/home_screen.dart';
import 'requests/requests_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  final _screens = const [
    HomeScreen(),
    RequestsScreen(),
    FamilyScreen(),
    AccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), label: 'Requests'),
          BottomNavigationBarItem(icon: Icon(Icons.people_outline), label: 'Family'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Account'),
        ],
      ),
    );
  }
}
