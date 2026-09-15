import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../models/models.dart';
import '../../theme.dart';
import '../login_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late Future<MidManUser> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.me();
  }

  Future<void> _logout() async {
    await ApiService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<MidManUser>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final user = snapshot.data;
          if (user == null) return const Center(child: Text('Could not load account'));

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  const CircleAvatar(radius: 32, backgroundColor: MidManColors.navy, child: Icon(Icons.person, color: Colors.white, size: 32)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        Text('Member ID: ${user.memberId}', style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: MidManColors.ink,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.workspace_premium, color: MidManColors.gold),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${user.accountType.toUpperCase()} Plan', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          const Text('Manage your membership', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _AccountTile(icon: Icons.badge_outlined, label: 'KYC status', value: user.kycStatus),
              _AccountTile(icon: Icons.email_outlined, label: 'Email', value: user.email),
              _AccountTile(icon: Icons.phone_outlined, label: 'Phone', value: user.phone),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _AccountTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(width: 16),
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
