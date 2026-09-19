import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api_service.dart';
import '../../models/models.dart';
import '../../theme.dart';

/// Staff verification queue - individuals (id/passport) and Business
/// accounts (company registration documents) share this screen as two tabs
/// since they're the same review workflow applied to two kinds of accounts.
class KycReviewScreen extends StatefulWidget {
  const KycReviewScreen({super.key});

  @override
  State<KycReviewScreen> createState() => _KycReviewScreenState();
}

class _KycReviewScreenState extends State<KycReviewScreen> {
  bool _sendingReminders = false;

  /// Manual stand-in for the real cron trigger the Property Inspection
  /// reminder feature still needs before launch (see app/reminders.py) -
  /// lets staff process due reminders on demand until that's wired up.
  Future<void> _runDueReminders() async {
    setState(() => _sendingReminders = true);
    try {
      final sent = await ApiService.runDueInspectionReminders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sent == 0 ? 'No reminders were due.' : 'Sent $sent reminder${sent == 1 ? '' : 's'}.')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _sendingReminders = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  const Expanded(child: Text('KYC Review', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
                  IconButton(
                    onPressed: _sendingReminders ? null : _runDueReminders,
                    tooltip: 'Send due property inspection reminders',
                    icon: _sendingReminders
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.notifications_active_outlined, color: MidManColors.gold),
                  ),
                ],
              ),
            ),
            const TabBar(
              tabs: [Tab(text: 'Individuals'), Tab(text: 'Businesses')],
            ),
            const Expanded(
              child: TabBarView(children: [_IndividualsTab(), _BusinessesTab()]),
            ),
          ],
        ),
      ),
    );
  }
}

class _IndividualsTab extends StatefulWidget {
  const _IndividualsTab();

  @override
  State<_IndividualsTab> createState() => _IndividualsTabState();
}

class _IndividualsTabState extends State<_IndividualsTab> {
  late Future<List<KYCReview>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = ApiService.pendingKycReviews();
  }

  void _reload() => setState(() {
        _future = ApiService.pendingKycReviews();
      });

  Future<void> _decide(KYCReview review, bool approve) async {
    String? reason;
    if (!approve) {
      final controller = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Decline verification'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Reason (shown to the customer)'),
            maxLines: 2,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Decline')),
          ],
        ),
      );
      if (confirmed != true) return;
      reason = controller.text.trim().isEmpty ? null : controller.text.trim();
    }

    setState(() => _busy = true);
    try {
      await ApiService.decideKyc(userId: review.id, approve: approve, reason: reason);
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: FutureBuilder<List<KYCReview>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final reviews = snapshot.data ?? [];
          if (reviews.isEmpty) {
            return ListView(children: const [
              Padding(padding: EdgeInsets.all(48), child: Center(child: Text('No documents waiting for review.'))),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: reviews.length,
            separatorBuilder: (_, index) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final r = reviews[i];
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text('${r.memberId} · ${r.email} · ${r.countryOfResidence}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => launchUrl(Uri.parse(r.documentUrl), mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('View submitted document'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy ? null : () => _decide(r, false),
                            child: const Text('Decline'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _busy ? null : () => _decide(r, true),
                            child: const Text('Approve'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _BusinessesTab extends StatefulWidget {
  const _BusinessesTab();

  @override
  State<_BusinessesTab> createState() => _BusinessesTabState();
}

class _BusinessesTabState extends State<_BusinessesTab> {
  late Future<List<CompanyKYCReview>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = ApiService.pendingCompanyReviews();
  }

  void _reload() => setState(() {
        _future = ApiService.pendingCompanyReviews();
      });

  Future<void> _decide(CompanyKYCReview review, bool approve) async {
    String? reason;
    if (!approve) {
      final controller = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Decline verification'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Reason (shown to the company)'),
            maxLines: 2,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Decline')),
          ],
        ),
      );
      if (confirmed != true) return;
      reason = controller.text.trim().isEmpty ? null : controller.text.trim();
    }

    setState(() => _busy = true);
    try {
      await ApiService.decideCompanyKyc(companyId: review.id, approve: approve, reason: reason);
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: FutureBuilder<List<CompanyKYCReview>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final reviews = snapshot.data ?? [];
          if (reviews.isEmpty) {
            return ListView(children: const [
              Padding(padding: EdgeInsets.all(48), child: Center(child: Text('No Business accounts waiting for review.'))),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: reviews.length,
            separatorBuilder: (_, index) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final r = reviews[i];
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.legalName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text('${r.businessId} · Reg #${r.registrationNumber} · ${r.country}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    Text('${r.email} · ${r.phone}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 8),
                    Text(
                      r.documentCount == 0
                          ? 'No documents uploaded yet'
                          : '${r.documentCount} document${r.documentCount == 1 ? '' : 's'} uploaded',
                      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy ? null : () => _decide(r, false),
                            child: const Text('Decline'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _busy ? null : () => _decide(r, true),
                            child: const Text('Approve'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
