import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../country_data.dart';
import '../../models/models.dart';
import '../../theme.dart';

class _EmployeesData {
  final MidManUser me;
  final Company company;
  final List<MidManUser> employees;
  _EmployeesData(this.me, this.company, this.employees);
}

/// Business admin's team screen - list employees, add new ones with a
/// fixed role, change a role, or remove someone. Only an Administrator can
/// do any of that; other roles see the team read-only.
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  late Future<_EmployeesData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_EmployeesData> _load() async {
    final me = await ApiService.me();
    final company = await ApiService.myCompany();
    final employees = await ApiService.listEmployees();
    return _EmployeesData(me, company, employees);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _addEmployee() async {
    final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const _AddEmployeeScreen()));
    if (added == true) _reload();
  }

  Future<void> _editEmployee(MidManUser employee) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EmployeeActionsSheet(employee: employee),
    );
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Team')),
      body: SafeArea(
        child: FutureBuilder<_EmployeesData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('${snapshot.error}'));
            }
            final data = snapshot.data!;
            final canManage = userCanManageEmployees(data.me);
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: MidManColors.ink, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data.company.legalName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(data.company.businessId, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 8),
                        _CompanyStatusChip(status: data.company.kycStatus),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text('${data.employees.length} employee${data.employees.length == 1 ? '' : 's'}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (canManage)
                        TextButton.icon(
                          onPressed: _addEmployee,
                          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                          label: const Text('Add employee'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...data.employees.map((e) => _EmployeeTile(
                        employee: e,
                        isSelf: e.id == data.me.id,
                        onTap: canManage && e.id != data.me.id ? () => _editEmployee(e) : null,
                      )),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CompanyStatusChip extends StatelessWidget {
  final String status;
  const _CompanyStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'verified' => ('Verified', MidManColors.success),
      'rejected' => ('Verification declined', MidManColors.danger),
      _ => ('Verification pending', MidManColors.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _EmployeeTile extends StatelessWidget {
  final MidManUser employee;
  final bool isSelf;
  final VoidCallback? onTap;

  const _EmployeeTile({required this.employee, required this.isSelf, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${employee.fullName}${isSelf ? ' (you)' : ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('${employee.memberId} · ${employee.email}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFFF1EEE7), borderRadius: BorderRadius.circular(20)),
                child: Text(businessRoleLabel(employee.businessRole),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              if (onTap != null) ...[const SizedBox(width: 4), const Icon(Icons.chevron_right, color: Colors.grey)],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeActionsSheet extends StatefulWidget {
  final MidManUser employee;
  const _EmployeeActionsSheet({required this.employee});

  @override
  State<_EmployeeActionsSheet> createState() => _EmployeeActionsSheetState();
}

class _EmployeeActionsSheetState extends State<_EmployeeActionsSheet> {
  late String _role = widget.employee.businessRole ?? 'requester';
  bool _busy = false;
  String? _error;

  Future<void> _saveRole() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService.updateEmployeeRole(userId: widget.employee.id, businessRole: _role);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${widget.employee.fullName}?'),
        content: const Text('They will lose access to this Business account immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: MidManColors.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ApiService.removeEmployee(widget.employee.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.employee.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: kBusinessRoles.map((r) => DropdownMenuItem(value: r.value, child: Text(r.label))).toList(),
            onChanged: (v) => setState(() => _role = v ?? _role),
          ),
          const SizedBox(height: 4),
          Text(kBusinessRoles.firstWhere((r) => r.value == _role).description,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: MidManColors.danger, fontSize: 12)),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _busy ? null : _saveRole,
            child: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save role'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _remove,
            icon: const Icon(Icons.person_remove_outlined, color: MidManColors.danger),
            label: const Text('Remove from company', style: TextStyle(color: MidManColors.danger)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: MidManColors.danger.withValues(alpha: 0.4))),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _AddEmployeeScreen extends StatefulWidget {
  const _AddEmployeeScreen();

  @override
  State<_AddEmployeeScreen> createState() => _AddEmployeeScreenState();
}

class _AddEmployeeScreenState extends State<_AddEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  DateTime? _dob;
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String _dialCode = '+263';
  String _role = 'requester';
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _phone.dispose();
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
    if (!_formKey.currentState!.validate() || _dob == null) {
      setState(() => _error = _dob == null ? 'Please select a date of birth' : null);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ApiService.createEmployee(
        fullName: _fullName.text.trim(),
        dateOfBirth:
            '${_dob!.year.toString().padLeft(4, '0')}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
        email: _email.text.trim(),
        phone: '$_dialCode${_phone.text.trim()}',
        password: _password.text,
        businessRole: _role,
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
      appBar: AppBar(title: const Text('Add employee')),
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
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Temporary password'),
                validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: kBusinessRoles.map((r) => DropdownMenuItem(value: r.value, child: Text(r.label))).toList(),
                onChanged: (v) => setState(() => _role = v ?? _role),
              ),
              const SizedBox(height: 4),
              Text(kBusinessRoles.firstWhere((r) => r.value == _role).description,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Add employee'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
