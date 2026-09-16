import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../models/models.dart';
import '../../theme.dart';

/// Lets a customer switch membership tier. No payment gateway wired up yet -
/// pricing for each tier hasn't been set ("Subscriptions fees right amounts
/// will be added later"), so this just records the choice.
class SubscriptionScreen extends StatefulWidget {
  final String currentAccountType;
  const SubscriptionScreen({super.key, required this.currentAccountType});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _busy = false;

  Future<void> _select(String tier) async {
    if (tier == widget.currentAccountType) return;
    setState(() => _busy = true);
    try {
      await ApiService.changeSubscription(tier);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Membership')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: const Color(0xFFF1EEE7), borderRadius: BorderRadius.circular(14)),
              child: const Text(
                "🎉 During testing and our first month of launch, every plan includes all features free of charge - "
                'including saving beneficiaries and your full request history. The differences below take effect after that.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            const Text(
              'Pricing for each plan is coming soon - for now, pick the plan that fits how you want to use MidMan.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ...kSubscriptionTiers.map((tier) {
              final isCurrent = tier.value == widget.currentAccountType;
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isCurrent ? MidManColors.ink : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: isCurrent ? null : Border.all(color: const Color(0xFFE5E0D6)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          tier.label,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isCurrent ? Colors.white : MidManColors.textDark,
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: 8),
                          const Chip(
                            label: Text('Current plan', style: TextStyle(fontSize: 11)),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: MidManColors.gold,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...tier.features.map((f) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.check, size: 16, color: isCurrent ? MidManColors.gold : MidManColors.gold),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  f,
                                  style: TextStyle(color: isCurrent ? Colors.white70 : Colors.black87, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        )),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: isCurrent
                          ? OutlinedButton(
                              onPressed: null,
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.white54),
                              child: const Text('Selected'),
                            )
                          : ElevatedButton(
                              onPressed: _busy ? null : () => _select(tier.value),
                              child: Text('Switch to ${tier.label}'),
                            ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
