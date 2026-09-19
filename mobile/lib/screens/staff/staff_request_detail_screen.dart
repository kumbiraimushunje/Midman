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
  late Future<QuoteComparison?> _comparisonFuture;
  String? _selectedStatus;
  final _noteController = TextEditingController();
  bool _busy = false;
  bool _comparing = false;

  @override
  void initState() {
    super.initState();
    _future = ApiService.getRequest(widget.requestId);
    _comparisonFuture = ApiService.getQuoteComparison(widget.requestId);
  }

  void _reload() => setState(() {
        _future = ApiService.getRequest(widget.requestId);
        _comparisonFuture = ApiService.getQuoteComparison(widget.requestId);
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

  Future<void> _addSupplierQuote() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'],
    );
    if (files.isEmpty) return;
    final file = files.first;

    if (!mounted) return;
    final controller = TextEditingController();
    final supplierName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supplier name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'e.g. BuildMart Hardware'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Add quote'),
          ),
        ],
      ),
    );
    if (supplierName == null || supplierName.isEmpty) return;

    final bytes = await file.readAsBytes();
    await _runAction(() => ApiService.uploadEvidence(
          requestId: widget.requestId,
          bytes: bytes,
          filename: file.name,
          fileType: 'quote',
          supplierName: supplierName,
        ));
  }

  Future<void> _generateComparison() async {
    setState(() => _comparing = true);
    try {
      final result = await ApiService.generateQuoteComparison(widget.requestId);
      if (mounted) {
        setState(() {
          _comparisonFuture = Future.value(result);
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _comparing = false);
    }
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
            final quotes = req.evidence.where((e) => e.fileType == 'quote').toList();
            final otherEvidence = req.evidence.where((e) => e.fileType != 'quote').toList();

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
                if (req.serviceType != null) _InfoRow(label: 'Service', value: req.serviceType!),
                if (req.city != null || req.country != null)
                  _InfoRow(label: 'Location', value: [req.city, req.country].where((s) => s != null).join(', ')),
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
                if (otherEvidence.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Evidence & documents', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  ...otherEvidence.map((e) => ListTile(
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
                const Text('Supplier quotes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                if (quotes.isEmpty)
                  const Text('No supplier quotes attached yet.', style: TextStyle(color: Colors.grey))
                else
                  ...quotes.map((q) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.request_quote_outlined),
                        title: Text(q.supplierName ?? 'Unnamed supplier'),
                        subtitle: Text(DateFormat('d MMM yyyy, HH:mm').format(q.createdAt.toLocal())),
                        trailing: const Icon(Icons.open_in_new, size: 18),
                        onTap: () => launchUrl(Uri.parse(ApiService.resolveFileUrl(q.fileUrl)), mode: LaunchMode.externalApplication),
                      )),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _addSupplierQuote,
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Add a supplier quote'),
                ),
                const SizedBox(height: 16),
                FutureBuilder<QuoteComparison?>(
                  future: _comparisonFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox.shrink();
                    }
                    final comparison = snapshot.data;
                    return _QuoteComparisonSection(
                      comparison: comparison,
                      canGenerate: quotes.length >= 2,
                      busy: _comparing,
                      onGenerate: _generateComparison,
                    );
                  },
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

class _QuoteComparisonSection extends StatelessWidget {
  final QuoteComparison? comparison;
  final bool canGenerate;
  final bool busy;
  final VoidCallback onGenerate;

  const _QuoteComparisonSection({
    required this.comparison,
    required this.canGenerate,
    required this.busy,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    final c = comparison;
    if (c == null) {
      if (!canGenerate) return const SizedBox.shrink();
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: busy ? null : onGenerate,
          icon: busy
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.compare_arrows),
          label: const Text('Compare quotes'),
        ),
      );
    }

    final sorted = [...c.suppliers]..sort((a, b) {
        if (a.amount == null) return 1;
        if (b.amount == null) return -1;
        return a.amount!.compareTo(b.amount!);
      });

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: MidManColors.ink, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.compare_arrows, color: MidManColors.gold, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Quote comparison', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
              Text(
                DateFormat('d MMM, HH:mm').format(c.generatedAt.toLocal()),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(c.summary, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          if (c.recommendation != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: MidManColors.gold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.workspace_premium_outlined, color: MidManColors.gold, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(c.recommendation!, style: const TextStyle(color: Colors.white, fontSize: 12.5))),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          ...sorted.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.supplierName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                          if (s.notes != null)
                            Text(s.notes!, style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
                        ],
                      ),
                    ),
                    Text(
                      s.amount != null ? '\$${s.amount}' : '—',
                      style: const TextStyle(color: MidManColors.gold, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ],
                ),
              )),
          if (canGenerate) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: busy ? null : onGenerate,
                icon: busy
                    ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
                    : const Icon(Icons.refresh, size: 16, color: Colors.white70),
                label: const Text('Regenerate', style: TextStyle(color: Colors.white70)),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
