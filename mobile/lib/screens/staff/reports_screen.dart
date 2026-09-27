import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../models/models.dart';
import '../../theme.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late Future<DashboardReport> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.dashboardReport();
  }

  void _reload() => setState(() {
        _future = ApiService.dashboardReport();
      });

  String _categoryLabel(String value) {
    for (final c in kServiceCategories) {
      if (c.value == value) return c.label;
    }
    return value;
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
                Expanded(child: Text('Reports', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _reload(),
              child: FutureBuilder<DashboardReport>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return ListView(children: [
                      Padding(padding: const EdgeInsets.all(32), child: Center(child: Text('${snapshot.error}'))),
                    ]);
                  }
                  final report = snapshot.data!;

                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.6,
                        children: [
                          _StatCard(label: 'Total requests', value: '${report.totalRequests}'),
                          _StatCard(label: 'Total customers', value: '${report.totalCustomers}'),
                          _StatCard(label: 'New (30 days)', value: '${report.newCustomersLast30Days}'),
                          _StatCard(
                            label: 'Pending approval',
                            value: '${report.pendingApprovalCount}',
                            accent: report.pendingApprovalCount > 0,
                          ),
                          _StatCard(
                            label: 'High-risk flags',
                            value: '${report.highRiskRequests}',
                            accent: report.highRiskRequests > 0,
                            accentColor: MidManColors.danger,
                          ),
                          _StatCard(
                            label: 'Requested total',
                            value: report.totalAmountRequested.toStringAsFixed(0),
                            prefix: '\$',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: MidManColors.ink, borderRadius: BorderRadius.circular(16)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _AmountColumn(label: 'Requested', value: report.totalAmountRequested),
                            Container(width: 1, height: 32, color: Colors.white24),
                            _AmountColumn(label: 'Completed', value: report.totalAmountCompleted),
                          ],
                        ),
                      ),
                      _BreakdownSection(
                        title: 'Requests by status',
                        counts: report.requestsByStatus,
                        labelFor: customerStageLabel,
                        colorFor: statusColor,
                      ),
                      _BreakdownSection(
                        title: 'Requests by category',
                        counts: report.requestsByCategory,
                        labelFor: _categoryLabel,
                      ),
                      const SizedBox(height: 20),
                    ],
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

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String prefix;
  final bool accent;
  final Color accentColor;

  const _StatCard({
    required this.label,
    required this.value,
    this.prefix = '',
    this.accent = false,
    this.accentColor = MidManColors.gold,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$prefix$value',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: accent ? accentColor : MidManColors.textDark),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _AmountColumn extends StatelessWidget {
  final String label;
  final num value;
  const _AmountColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        Text('\$${value.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _BreakdownSection extends StatelessWidget {
  final String title;
  final Map<String, int> counts;
  final String Function(String) labelFor;
  final Color Function(String)? colorFor;

  const _BreakdownSection({required this.title, required this.counts, required this.labelFor, this.colorFor});

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) return const SizedBox.shrink();
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: entries.map((e) {
                final fraction = total == 0 ? 0.0 : e.value / total;
                final color = colorFor?.call(e.key) ?? MidManColors.gold;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(labelFor(e.key), style: const TextStyle(fontSize: 13)),
                          Text('${e.value}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 6,
                          backgroundColor: const Color(0xFFF1EEE7),
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
