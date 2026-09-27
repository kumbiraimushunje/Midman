import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../country_data.dart';
import '../../models/models.dart';
import '../../theme.dart';
import 'audit_log_screen.dart';

const _roleOptions = [
  ('customer', 'Customer'),
  ('staff', 'Staff'),
  ('admin', 'Admin'),
];

const _creatableRoleOptions = [
  ('staff', 'Staff'),
  ('admin', 'Admin'),
];

Color _roleColor(String role) => switch (role) {
      'admin' => MidManColors.danger,
      'staff' => MidManColors.gold,
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

  void _reload() => setState(() {
        _future = _load();
      });

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

  Future<void> _createUser() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _CreateUserScreen()),
    );
    if (created == true) _reload();
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 8, 8),
            child: Row(
              children: [
                const Expanded(child: Text('Users', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
                IconButton(
                  icon: const Icon(Icons.person_add_alt_1),
                  tooltip: 'Add staff or admin user',
                  onPressed: _createUser,
                ),
                IconButton(
                  icon: const Icon(Icons.history),
                  tooltip: 'Audit log',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuditLogScreen())),
                ),
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

class _CreateUserScreen extends StatefulWidget {
  const _CreateUserScreen();

  @override
  State<_CreateUserScreen> createState() => _CreateUserScreenState();
}

class _CreateUserScreenState extends State<_CreateUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  DateTime? _dob;
  String? _countryName;
  String _dialCode = '+263';
  String _role = 'staff';
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _phone.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 16, now.month, now.day),
      initialDate: DateTime(now.year - 25),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _dob == null || _countryName == null) {
      setState(() => _error = _dob == null
          ? 'Please select a date of birth'
          : _countryName == null
              ? 'Please select a country of residence'
              : null);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ApiService.createStaffUser(
        fullName: _fullName.text.trim(),
        dateOfBirth:
            '${_dob!.year.toString().padLeft(4, '0')}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
        email: _email.text.trim(),
        phone: '$_dialCode${_phone.text.trim()}',
        username: _username.text.trim(),
        password: _password.text,
        countryOfResidence: _countryName!,
        role: _role,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add staff or admin user')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                controller: _fullName,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: _required,
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickDob,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date of birth'),
                  child: Text(_dob == null ? 'Select date' : '${_dob!.day}/${_dob!.month}/${_dob!.year}'),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: DropdownButtonFormField<String>(
                      initialValue: _dialCode,
                      decoration: const InputDecoration(labelText: 'Code'),
                      isExpanded: true,
                      items: kCountries
                          .map((c) => DropdownMenuItem(value: c.dialCode, child: Text(c.dialLabel, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (v) => setState(() => _dialCode = v ?? _dialCode),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone number'),
                      validator: _required,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _username,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: _required,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Temporary password'),
                validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _countryName,
                decoration: const InputDecoration(labelText: 'Country of residence'),
                isExpanded: true,
                items: kCountries.map((c) => DropdownMenuItem(value: c.name, child: Text('${c.flag} ${c.name}'))).toList(),
                onChanged: (v) => setState(() => _countryName = v),
                validator: (v) => v == null ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: _creatableRoleOptions.map((r) => DropdownMenuItem(value: r.$1, child: Text(r.$2))).toList(),
                onChanged: (v) => setState(() => _role = v ?? _role),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: MidManColors.danger)),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
