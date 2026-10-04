import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../models/models.dart';
import '../../theme.dart';
import 'staff_request_detail_screen.dart';

/// Every request a MidMen admin has cleared for staff to work - moves here
/// from the Queue once admin-approved. Requests flagged for a payment/spend
/// sign-off (status == approval_required) get the quick Approve/Reject
/// actions inline for an admin viewer; a staff viewer sees the same list
/// read-only (a status badge instead) since only admin decides those -
/// staff's job here is limited to seeing details, attaching evidence, and
/// moving status forward from Request Detail.
class StaffApprovalsScreen extends StatefulWidget {
  const StaffApprovalsScreen({super.key});

  @override
  State<StaffApprovalsScreen> createState() => _StaffApprovalsScreenState();
}

class _StaffApprovalsScreenState extends State<StaffApprovalsScreen> {
  late Future<List<ServiceRequest>> _future;
  bool? _isAdmin;

  @override
  void initState() {
    super.initState();
    _future = ApiService.allRequests(adminApproved: true);
    _loadMe();
  }

  Future<void> _loadMe() async {
    try {
      final me = await ApiService.me();
      if (mounted) setState(() => _isAdmin = me.role == 'admin');
    } catch (_) {
      if (mounted) setState(() => _isAdmin = false);
    }
  }

  void _reload() => setState(() {
        _future = ApiService.allRequests(adminApproved: true);
      });

  Future<void> _decide(ServiceRequest request, bool approve) async {
    final commentController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Approve request' : 'Reject request'),
        content: TextField(
          controller: commentController,
          decoration: const InputDecoration(labelText: 'Comment (optional)'),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: Text(approve ? 'Approve' : 'Reject')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiService.decideRequest(
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
    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: [
                Expanded(child: Text('Approvals', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
          Expanded(
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
                      Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Nothing admin-approved yet.')))
                    ]);
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: requests.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final r = requests[i];
                      final needsPaymentSignOff = r.status == 'approval_required';
                      final canDecide = needsPaymentSignOff && _isAdmin == true;
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: () async {
                                await Navigator.of(context)
                                    .push(MaterialPageRoute(builder: (_) => StaffRequestDetailScreen(requestId: r.id)));
                                _reload();
                              },
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                        const SizedBox(height: 4),
                                        Text('${r.requestNumber} · ${r.requester.fullName}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                        if (r.amount != null) Text('${r.currency} ${r.amount}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                  if (!canDecide)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: statusColor(r.status).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(r.status.replaceAll('_', ' '),
                                          style: TextStyle(color: statusColor(r.status), fontSize: 12, fontWeight: FontWeight.w600)),
                                    ),
                                ],
                              ),
                            ),
                            if (canDecide) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => _decide(r, false),
                                      child: const Text('Reject'),
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
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
