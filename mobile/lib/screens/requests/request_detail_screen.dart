import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api_service.dart';
import '../../models/models.dart';
import '../../theme.dart';

class RequestDetailScreen extends StatefulWidget {
  final String requestId;
  const RequestDetailScreen({super.key, required this.requestId});

  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  late Future<ServiceRequest?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ServiceRequest?> _load() => ApiService.getRequest(widget.requestId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order Tracking')),
      body: SafeArea(
        child: FutureBuilder<ServiceRequest?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final req = snapshot.data;
            if (req == null) return const Center(child: Text('Request not found'));

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(req.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(req.requestNumber, style: const TextStyle(color: Colors.grey)),
                if (req.amount != null) ...[
                  const SizedBox(height: 8),
                  Text('${req.currency} ${req.amount}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ],
                if (req.fraudRiskLevel != null) ...[
                  const SizedBox(height: 12),
                  Chip(label: Text('Risk: ${req.fraudRiskLevel}')),
                ],
                const SizedBox(height: 24),
                const Text('Timeline', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                ...req.events.map((e) => _TimelineTile(event: e)),
                if (req.evidence.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text('Evidence & documents', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  ...req.evidence.map((e) => _EvidenceTile(evidence: e)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final RequestEvent event;
  const _TimelineTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final label = customerStageLabel(event.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: statusColor(event.status), shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(DateFormat('d MMM yyyy, HH:mm').format(event.createdAt.toLocal()),
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                if (event.note != null && event.note!.isNotEmpty) Text(event.note!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  final EvidenceOut evidence;
  const _EvidenceTile({required this.evidence});

  @override
  Widget build(BuildContext context) {
    final url = ApiService.resolveFileUrl(evidence.fileUrl);
    final isPhoto = evidence.fileType == 'photo';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: isPhoto
                    ? Image.network(url, width: 48, height: 48, fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 48))
                    : Container(
                        width: 48,
                        height: 48,
                        color: const Color(0xFFF1EEE7),
                        child: const Icon(Icons.description_outlined),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(evidence.caption?.isNotEmpty == true ? evidence.caption! : evidence.fileType,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(DateFormat('d MMM yyyy, HH:mm').format(evidence.createdAt.toLocal()),
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, size: 18, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
