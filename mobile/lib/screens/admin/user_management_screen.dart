import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../models/models.dart';
import '../../theme.dart';

const _roleOptions = [
  ('customer', 'Customer'),
  ('staff', 'Staff'),
  ('approver', 'Approver'),
  ('admin', 'Admin'),
];

Color _roleColor(String role) => switch (role) {
      'admin' => MidManColors.danger,
      'staff' => MidManColors.gold,
      'approver' => MidManColors.navy,
      _ => MidManColors.textMuted,
    };

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  late Future<List<MidManUser>> _future;
  final _searchController = TextEditingController();
  String? _roleFilter;
  bool _includeInactive = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<MidManUser>> _load() => ApiService.listAdminUsers(
        role: _roleFilter,
        search: _searchController.text.trim(),
        includeInactive: _includeInactive,
      );

  void _reload() => setState(() => _future = _load());

  Future<void> _manage(MidManUser user) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ManageUserSheet(
        user: user,
        busy: _busy,
        onChangeRole: (role) => _changeRole(user, role),
        onToggleActive: () => _toggleActive(user),
      ),
    );
  }

  Future<void> _changeRole(MidManUser user, String role) async {
    Navigator.of(context).pop();
    setState(() => _busy = true);
    try {
      await ApiService.changeUserRole(userId: user.id, role: role);
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleActive(MidManUser user) async {
    Navigator.of(context).pop();
    setState(() => _busy = true);
    try {
      if (user.isActive) {
        await ApiService.deactivateUser(user.id);
      } else {
        await ApiService.reactivateUser(user.id);
      }
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
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
                Expanded(child: Text('Users', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search name, email, or member ID',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _reload),
              ),
              onSubmitted: (_) => _reload(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _FilterChip(label: 'All roles', selected: _roleFilter == null, onTap: () {
                  setState(() => _roleFilter = null);
                  _reload();
                }),
                for (final (value, label) in _roleOptions)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _FilterChip(
                      label: label,
                      selected: _roleFilter == value,
                      onTap: () {
                        setState(() => _roleFilter = value);
                        _reload();
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _FilterChip(
                    label: 'Include inactive',
                    selected: _includeInactive,
                    onTap: () {
                      setState(() => _includeInactive = !_includeInactive);
                      _reload();
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _reload(),
              child: FutureBuilder<List<MidManUser>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final users = snapshot.data ?? [];
                  if (users.isEmpty) {
                    return ListView(children: const [
                      Padding(padding: EdgeInsets.all(48), child: Center(child: Text('No matching users.'))),
                    ]);
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    itemCount: users.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final u = users[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _busy ? null : () => _manage(u),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: u.isActive ? null : Border.all(color: MidManColors.danger.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(u.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                    const SizedBox(height: 2),
                                    Text('${u.memberId} · ${u.email}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: _roleColor(u.role).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(u.role.toUpperCase(),
                                              style: TextStyle(color: _roleColor(u.role), fontSize: 11, fontWeight: FontWeight.w600)),
                                        ),
                                        if (!u.isActive) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: MidManColors.danger.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Text('INACTIVE',
                                                style: TextStyle(color: MidManColors.danger, fontSize: 11, fontWeight: FontWeight.w600)),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: Colors.grey),
                            ],
                          ),
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

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: MidManColors.gold.withValues(alpha: 0.25),
      labelStyle: TextStyle(color: selected ? MidManColors.goldDark : MidManColors.textMuted, fontWeight: FontWeight.w600),
      side: BorderSide.none,
      backgroundColor: const Color(0xFFF1EEE7),
    );
  }
}

class _ManageUserSheet extends StatelessWidget {
  final MidManUser user;
  final bool busy;
  final ValueChanged<String> onChangeRole;
  final VoidCallback onToggleActive;

  const _ManageUserSheet({
    required this.user,
    required this.busy,
    required this.onChangeRole,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            Text('${user.memberId} · ${user.email}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 20),
            const Text('Role', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final (value, label) in _roleOptions)
                  ChoiceChip(
                    label: Text(label),
                    selected: user.role == value,
                    onSelected: busy || user.role == value ? null : (_) => onChangeRole(value),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy ? null : onToggleActive,
                icon: Icon(user.isActive ? Icons.block : Icons.check_circle_outline),
                label: Text(user.isActive ? 'Deactivate account' : 'Reactivate account'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: user.isActive ? MidManColors.danger : MidManColors.success,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
