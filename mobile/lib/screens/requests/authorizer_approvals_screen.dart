import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../models/models.dart';

/// Requests raised by a beneficiary who has the current user listed as
/// their authorizer - each needs the authorizer's sign-off before MidMan
/// reviews it.
class AuthorizerApprovalsScreen extends StatefulWidget {
  const AuthorizerApprovalsScreen({super.key});

  @override
  State<AuthorizerApprovalsScreen> createState() => _AuthorizerApprovalsScreenState();
}

class _AuthorizerApprovalsScreenState extends State<AuthorizerApprovalsScreen> {
  late Future<List<ServiceRequest>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.pendingMyAuthorization();
  }

  void _reload() => setState(() => _future = ApiService.pendingMyAuthorization());

  Future<void> _decide(ServiceRequest request, bool approve) async {
    final commentController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Approve request' : 'Decline request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('From ${request.requester.fullName}: "${request.title}"'),
            const SizedBox(height: 12),
            TextField(
              controller: commentController,
              decoration: const InputDecoration(labelText: 'Comment (optional)'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: Text(approve ? 'Approve' : 'Decline')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiService.authorizerDecideRequest(
        requestId: request.id,
        approve: approve,
        comment: commentController.text.trim().isEmpty ? null : commentController.text.trim(),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Requests to approve')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _reload(),
          child: FutureBuilder<List<ServiceRequest>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final requests = snapshot.data ?? [];
              if (requests.isEmpty) {
                return ListView(children: const [
                  Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Nothing waiting for your approval.')))
                ]);
              }
              return ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: requests.length,
                separatorBuilder: (_, index) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final r = requests[i];
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text('${r.requestNumber} · From ${r.requester.fullName}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        if (r.description != null && r.description!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(r.description!, style: const TextStyle(fontSize: 13)),
                        ],
                        if (r.amount != null) ...[
                          const SizedBox(height: 8),
                          Text('${r.currency} ${r.amount}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _decide(r, false),
                                child: const Text('Decline'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => _decide(r, true),
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
        ),
      ),
    );
  }
}
