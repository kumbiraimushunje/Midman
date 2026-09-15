import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api_service.dart';
import '../../models/models.dart';
import '../../theme.dart';

const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'heic'};

const _allStatuses = [
  'requested',
  'arranging',
  'approval_required',
  'payment_pending',
  'in_progress',
  'completed',
  'verified',
  'closed',
  'rejected',
  'cancelled',
];

class StaffRequestDetailScreen extends StatefulWidget {
  final String requestId;
  const StaffRequestDetailScreen({super.key, required this.requestId});

  @override
  State<StaffRequestDetailScreen> createState() => _StaffRequestDetailScreenState();
}

class _StaffRequestDetailScreenState extends State<StaffRequestDetailScreen> {
  late Future<ServiceRequest> _future;
  String? _selectedStatus;
  final _noteController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = ApiService.getRequest(widget.requestId);
  }

  void _reload() => setState(() {
        _future = ApiService.getRequest(widget.requestId);
        _selectedStatus = null;
        _noteController.clear();
      });

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(bool approve) => _runAction(() => ApiService.decideRequest(
        requestId: widget.requestId,
        approve: approve,
        comment: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      ));

  Future<void> _updateStatus() {
    final status = _selectedStatus;
    if (status == null) return Future.value();
    return _runAction(() => ApiService.updateRequestStatus(
          requestId: widget.requestId,
          status: status,
          note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        ));
  }

  Future<void> _attachEvidence() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf', 'doc', 'docx'],
    );
    if (files.isEmpty) return;
    final file = files.first;
    final bytes = await file.readAsBytes();

    final ext = (file.extension ?? '').toLowerCase();
    await _runAction(() => ApiService.uploadEvidence(
          requestId: widget.requestId,
          bytes: bytes,
          filename: file.name,
          fileType: _imageExtensions.contains(ext) ? 'photo' : 'receipt',
          caption: 'Uploaded by staff',
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request Detail')),
      body: SafeArea(
        child: FutureBuilder<ServiceRequest>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('${snapshot.error}')));
            }
            final req = snapshot.data!;

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(req.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(req.requestNumber, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 12),
                _InfoRow(label: 'Requester', value: '${req.requester.fullName} (${req.requester.memberId})'),
                _InfoRow(label: 'Contact', value: '${req.requester.email} · ${req.requester.phone}'),
                if (req.beneficiary != null)
                  _InfoRow(label: 'For', value: '${req.beneficiary!.fullName} (${req.beneficiary!.relationshipType})'),
                _InfoRow(label: 'Category', value: req.category.replaceAll('_', ' ')),
                if (req.amount != null) _InfoRow(label: 'Amount', value: '${req.currency} ${req.amount}'),
                if (req.description != null && req.description!.isNotEmpty)
                  _InfoRow(label: 'Details', value: req.description!),
                if (req.fraudRiskLevel != null) ...[
                  const SizedBox(height: 8),
                  Chip(
                    label: Text('Fraud risk: ${req.fraudRiskLevel} (${req.fraudRiskScore ?? '?'})'),
                    backgroundColor: statusColor(req.fraudRiskLevel == 'high' ? 'rejected' : 'requested').withValues(alpha: 0.15),
                  ),
                ],
                const SizedBox(height: 24),
                const Text('Timeline', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                ...req.events.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${e.status.replaceAll('_', ' ')} · ${DateFormat('d MMM, HH:mm').format(e.createdAt.toLocal())}'
                        '${e.note != null && e.note!.isNotEmpty ? ' — ${e.note}' : ''}',
                      ),
                    )),
                if (req.evidence.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Evidence & documents', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  ...req.evidence.map((e) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.description_outlined),
                        title: Text(e.caption?.isNotEmpty == true ? e.caption! : e.fileType),
                        subtitle: Text(DateFormat('d MMM yyyy, HH:mm').format(e.createdAt.toLocal())),
                        trailing: const Icon(Icons.open_in_new, size: 18),
                        onTap: () => launchUrl(Uri.parse(ApiService.resolveFileUrl(e.fileUrl)), mode: LaunchMode.externalApplication),
                      )),
                ],
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _attachEvidence,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Attach evidence (photo / receipt / document)'),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                const Text('Actions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteController,
                  decoration: const InputDecoration(labelText: 'Note / comment (optional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                if (req.status == 'approval_required')
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => _decide(false),
                          child: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _busy ? null : () => _decide(true),
                          child: const Text('Approve'),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedStatus,
                  decoration: const InputDecoration(labelText: 'Move to status'),
                  items: _allStatuses.map((s) => DropdownMenuItem(value: s, child: Text(s.replaceAll('_', ' ')))).toList(),
                  onChanged: (v) => setState(() => _selectedStatus = v),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _busy || _selectedStatus == null ? null : _updateStatus,
                  child: _busy
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Update status'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
