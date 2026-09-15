import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../models/models.dart';
import '../../theme.dart';
import 'new_request_screen.dart';
import 'request_detail_screen.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  late Future<List<ServiceRequest>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.myRequests();
  }

  void _reload() => setState(() {
        _future = ApiService.myRequests();
      });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: [
                const Expanded(child: Text('My Requests', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: MidManColors.gold, size: 30),
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewRequestScreen()));
                    _reload();
                  },
                ),
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
                  if (snapshot.hasError) {
                    return ListView(children: [Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('${snapshot.error}')))]);
                  }
                  final requests = snapshot.data ?? [];
                  if (requests.isEmpty) {
                    return ListView(children: const [
                      Padding(padding: EdgeInsets.all(48), child: Center(child: Text('No requests yet. Tap + to create one.')))
                    ]);
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: requests.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final r = requests[i];
                      return _RequestCard(
                        request: r,
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RequestDetailScreen(requestId: r.id)));
                          _reload();
                        },
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

class _RequestCard extends StatelessWidget {
  final ServiceRequest request;
  final VoidCallback onTap;

  const _RequestCard({required this.request, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final stage = customerStageLabel(request.status);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(request.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(request.requestNumber, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor(request.status).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(stage, style: TextStyle(color: statusColor(request.status), fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
