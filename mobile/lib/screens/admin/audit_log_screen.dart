import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_service.dart';
import '../../models/models.dart';
import '../../theme.dart';

const _entityFilters = [
  (null, 'All'),
  ('user', 'Users'),
  ('service_request', 'Requests'),
];

(IconData, Color) _iconFor(String action) {
  if (action.startsWith('request.approve')) return (Icons.check_circle_outline, MidManColors.success);
  if (action.startsWith('request.reject')) return (Icons.cancel_outlined, MidManColors.danger);
  if (action.startsWith('request.')) return (Icons.sync_alt, MidManColors.gold);
  if (action == 'kyc.decision') return (Icons.badge_outlined, MidManColors.navy);
  if (action == 'user.role_change') return (Icons.manage_accounts_outlined, MidManColors.navy);
  if (action == 'user.deactivate') return (Icons.block, MidManColors.danger);
  if (action == 'user.reactivate') return (Icons.check_circle_outline, MidManColors.success);
  if (action == 'user.register') return (Icons.person_add_alt_outlined, MidManColors.gold);
  if (action == 'user.self_delete') return (Icons.person_remove_outlined, MidManColors.danger);
  if (action == 'user.subscription_change') return (Icons.workspace_premium_outlined, MidManColors.gold);
  return (Icons.history, MidManColors.textMuted);
}

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  late Future<List<AuditLogEntry>> _future;
  String? _entityFilter;

  @override
  void initState() {
    super.initState();
    _future = ApiService.listAuditLog(entityType: _entityFilter);
  }

  void _reload() => setState(() {
        _future = ApiService.listAuditLog(entityType: _entityFilter);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audit Log')),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  for (final (value, label) in _entityFilters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _entityFilter == value,
                        onSelected: (_) {
                          setState(() => _entityFilter = value);
                          _reload();
                        },
                        selectedColor: MidManColors.gold.withValues(alpha: 0.25),
                        labelStyle: TextStyle(
                          color: _entityFilter == value ? MidManColors.goldDark : MidManColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                        side: BorderSide.none,
                        backgroundColor: const Color(0xFFF1EEE7),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _reload(),
                child: FutureBuilder<List<AuditLogEntry>>(
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
                    final entries = snapshot.data ?? [];
                    if (entries.isEmpty) {
                      return ListView(children: const [
                        Padding(padding: EdgeInsets.all(48), child: Center(child: Text('No activity recorded yet.'))),
                      ]);
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      itemCount: entries.length,
                      separatorBuilder: (_, index) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        final (icon, color) = _iconFor(e.action);
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                                child: Icon(icon, color: color, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(e.summary, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${e.actorRole.toUpperCase()} · ${DateFormat('d MMM yyyy, HH:mm').format(e.createdAt.toLocal())}',
                                      style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                                    ),
                                  ],
                                ),
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
          ],
        ),
      ),
    );
  }
}
