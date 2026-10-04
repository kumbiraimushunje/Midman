import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api_service.dart';
import '../../models/models.dart';
import '../../theme.dart';
import '../business/employees_screen.dart';
import '../login_screen.dart';
import '../support/support_chat_screen.dart';

// TODO: placeholders - replace with MidMen's real support contact details before launch.
const _supportEmail = 'support@midmen.app';
const _supportPhone = '+263 71 234 5678';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late Future<MidManUser> _future;
  bool _uploadingKyc = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _future = ApiService.me();
  }

  void _reload() => setState(() {
        _future = ApiService.me();
      });

  Future<void> _uploadKycDocument() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'],
    );
    if (result.isEmpty) return;
    final file = result.first;

    setState(() => _uploadingKyc = true);
    try {
      await ApiService.uploadKycDocument(bytes: await file.readAsBytes(), filename: file.name);
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document submitted - we\'ll review it shortly.')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _uploadingKyc = false);
    }
  }

  Future<void> _logout() async {
    await ApiService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  Future<void> _confirmDeleteAccount() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "This is permanent and can't be undone. You'll lose access to your requests, "
              'beneficiaries, and history.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: "Why are you leaving? (optional)"),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: MidManColors.danger),
            child: const Text('Delete my account'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      final reason = reasonController.text.trim();
      await ApiService.deleteAccount(reason: reason.isEmpty ? null : reason);
      await ApiService.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
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
                          Text('Free account', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          Text(
                            'Saved beneficiaries, full request history, and priority service - all included',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (user.isBusinessAccount) ...[
                const SizedBox(height: 24),
                _BusinessSection(user: user),
              ],
              const SizedBox(height: 24),
              _KycSection(user: user, uploading: _uploadingKyc, onUpload: _uploadKycDocument),
              const SizedBox(height: 24),
              _AccountTile(icon: Icons.email_outlined, label: 'Email', value: user.email),
              _AccountTile(icon: Icons.phone_outlined, label: 'Phone', value: user.phone),
              const SizedBox(height: 24),
              const _SupportSection(),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _deleting ? null : _confirmDeleteAccount,
                icon: _deleting
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.delete_outline, color: MidManColors.danger),
                label: const Text('Delete account', style: TextStyle(color: MidManColors.danger)),
                style: OutlinedButton.styleFrom(side: BorderSide(color: MidManColors.danger.withValues(alpha: 0.4))),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _KycSection extends StatelessWidget {
  final MidManUser user;
  final bool uploading;
  final VoidCallback onUpload;

  const _KycSection({required this.user, required this.uploading, required this.onUpload});

  @override
  Widget build(BuildContext context) {
    final (icon, color, title, subtitle) = switch (user.kycStatus) {
      'verified' => (Icons.verified_outlined, MidManColors.success, 'Identity verified', 'Your document has been checked and approved.'),
      'rejected' => (
          Icons.error_outline,
          MidManColors.danger,
          'Verification declined',
          user.kycRejectionReason ?? 'Please upload a clearer copy of your id or passport.',
        ),
      _ => (Icons.hourglass_top_outlined, MidManColors.warning, 'Verification pending', 'Upload your id or passport to verify your identity.'),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          if (user.kycStatus != 'verified') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: uploading ? null : onUpload,
                icon: uploading
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file_outlined),
                label: Text(user.kycStatus == 'rejected' ? 'Upload a new document' : 'Upload id / passport'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BusinessSection extends StatelessWidget {
  final MidManUser user;
  const _BusinessSection({required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.apartment_outlined, color: MidManColors.gold),
              const SizedBox(width: 12),
              const Expanded(child: Text('Business account', style: TextStyle(fontWeight: FontWeight.w600))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFF1EEE7), borderRadius: BorderRadius.circular(20)),
                child: Text(businessRoleLabel(user.businessRole), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmployeesScreen())),
              icon: const Icon(Icons.groups_outlined),
              label: Text(userCanManageEmployees(user) ? 'Manage team' : 'View team'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportSection extends StatelessWidget {
  const _SupportSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.support_agent_outlined, color: MidManColors.gold),
              SizedBox(width: 12),
              Text('Help & Support', style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Need a hand? Reach out any time.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 14),
          InkWell(
            onTap: () => launchUrl(Uri(scheme: 'mailto', path: _supportEmail)),
            child: const _ContactRow(icon: Icons.email_outlined, value: _supportEmail),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => launchUrl(Uri(scheme: 'tel', path: _supportPhone.replaceAll(' ', ''))),
            child: const _ContactRow(icon: Icons.phone_outlined, value: _supportPhone),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SupportChatScreen()),
              ),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Chat with us'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String value;
  const _ContactRow({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 12),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
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
