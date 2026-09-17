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

  void _reload() => setState(() {
        _future = _load();
      });

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
                if (req.serviceType != null) ...[
                  const SizedBox(height: 4),
                  Text(req.serviceType!, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
                if (req.amount != null) ...[
                  const SizedBox(height: 8),
                  Text('${req.currency} ${req.amount}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ],
                if (req.fraudRiskLevel != null) ...[
                  const SizedBox(height: 12),
                  Chip(label: Text('Risk: ${req.fraudRiskLevel}')),
                ],
                if (req.status == 'payment_pending') ...[
                  const SizedBox(height: 20),
                  _PaymentSection(request: req, onPaid: _reload),
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

class _PaymentSection extends StatefulWidget {
  final ServiceRequest request;
  final VoidCallback onPaid;
  const _PaymentSection({required this.request, required this.onPaid});

  @override
  State<_PaymentSection> createState() => _PaymentSectionState();
}

class _PaymentSectionState extends State<_PaymentSection> {
  Future<Payment?>? _latestFuture;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _latestFuture = ApiService.getLatestPayment(widget.request.id);
  }

  bool get _isZimbabwe => (widget.request.requester.countryOfResidence ?? '').toLowerCase() == 'zimbabwe';

  Future<void> _pay(String provider) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final payment = await ApiService.initiatePayment(requestId: widget.request.id, provider: provider);
      if (payment.checkoutUrl != null) {
        await launchUrl(Uri.parse(payment.checkoutUrl!), mode: LaunchMode.externalApplication);
      }
      if (mounted) {
        setState(() {
          _latestFuture = Future.value(payment);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkStatus() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final payment = await ApiService.checkPayment(widget.request.id);
      if (mounted) {
        setState(() {
          _latestFuture = Future.value(payment);
        });
      }
      if (payment.status == 'paid') widget.onPaid();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Payment?>(
      future: _latestFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        final latest = snapshot.data;
        final awaitingConfirmation = latest != null && latest.status == 'pending';

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: MidManColors.ink, borderRadius: BorderRadius.circular(18)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Payment required', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                '${widget.request.currency} ${widget.request.amount}',
                style: const TextStyle(color: MidManColors.gold, fontWeight: FontWeight.w700, fontSize: 22),
              ),
              const SizedBox(height: 16),
              if (awaitingConfirmation) ...[
                const Text(
                  "If you've completed payment in the browser tab that opened, tap below to confirm.",
                  style: TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _checkStatus,
                    icon: _busy
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                    label: const Text("I've paid - check now"),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _latestFuture = Future.value(null);
                            }),
                    style: TextButton.styleFrom(foregroundColor: Colors.white70, padding: EdgeInsets.zero),
                    child: const Text('Try a different payment method'),
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: _PayButton(
                        label: 'Mobile Money /\nLocal Card',
                        highlighted: _isZimbabwe,
                        busy: _busy,
                        onPressed: () => _pay('paynow'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PayButton(
                        label: 'International\nCard',
                        highlighted: !_isZimbabwe,
                        busy: _busy,
                        onPressed: () => _pay('flutterwave'),
                      ),
                    ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: MidManColors.danger, fontSize: 12)),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PayButton extends StatelessWidget {
  final String label;
  final bool highlighted;
  final bool busy;
  final VoidCallback onPressed;

  const _PayButton({required this.label, required this.highlighted, required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    if (highlighted) {
      return ElevatedButton(
        onPressed: busy ? null : onPressed,
        child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, height: 1.3)),
      );
    }
    return OutlinedButton(
      onPressed: busy ? null : onPressed,
      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
      child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, height: 1.3)),
    );
  }
}
