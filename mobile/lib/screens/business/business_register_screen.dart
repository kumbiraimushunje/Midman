import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../country_data.dart';
import '../login_screen.dart';
import '../role_home_shell.dart';

/// Registers a MidMen Business account: the company itself (legal name,
/// registration number, addresses, industry, contacts, tax details - the
/// same due-diligence detail an individual gives, scaled up to a company)
/// plus the registrant as its first employee with the Administrator role.
/// They land straight in the app and can start adding Sarah, John, Mary,
/// Peter etc. from the Employees screen under Account.
class BusinessRegisterScreen extends StatefulWidget {
  const BusinessRegisterScreen({super.key});

  @override
  State<BusinessRegisterScreen> createState() => _BusinessRegisterScreenState();
}

class _BusinessRegisterScreenState extends State<BusinessRegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  // Registrant (becomes Administrator).
  final _fullName = TextEditingController();
  DateTime? _dob;
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  String _dialCode = '+263';

  // Company.
  final _legalName = TextEditingController();
  final _tradingName = TextEditingController();
  final _registrationNumber = TextEditingController();
  String? _country;
  final _registeredAddress = TextEditingController();
  final _businessAddress = TextEditingController();
  final _industry = TextEditingController();
  final _authorizedRep = TextEditingController();
  final _companyEmail = TextEditingController();
  final _companyPhone = TextEditingController();
  final _taxDetails = TextEditingController();

  // Contacts (optional).
  final _billingName = TextEditingController();
  final _billingEmail = TextEditingController();
  final _billingPhone = TextEditingController();
  final _opsName = TextEditingController();
  final _opsEmail = TextEditingController();
  final _opsPhone = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _fullName, _email, _phone, _username, _password, _legalName, _tradingName, _registrationNumber,
      _registeredAddress, _businessAddress, _industry, _authorizedRep, _companyEmail, _companyPhone,
      _taxDetails, _billingName, _billingEmail, _billingPhone, _opsName, _opsEmail, _opsPhone,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      initialDate: DateTime(now.year - 30),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _dob == null || _country == null) {
      setState(() => _error = _dob == null
          ? 'Please select your date of birth'
          : _country == null
              ? 'Please select the company\'s country'
              : null);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ApiService.registerBusiness(
        fullName: _fullName.text.trim(),
        dateOfBirth:
            '${_dob!.year.toString().padLeft(4, '0')}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
        email: _email.text.trim(),
        phone: '$_dialCode${_phone.text.trim()}',
        username: _username.text.trim(),
        password: _password.text,
        legalName: _legalName.text.trim(),
        tradingName: _tradingName.text.trim().isEmpty ? null : _tradingName.text.trim(),
        registrationNumber: _registrationNumber.text.trim(),
        country: _country!,
        registeredAddress: _registeredAddress.text.trim(),
        businessAddress: _businessAddress.text.trim().isEmpty ? null : _businessAddress.text.trim(),
        industry: _industry.text.trim(),
        authorizedRepresentativeName: _authorizedRep.text.trim().isEmpty ? _fullName.text.trim() : _authorizedRep.text.trim(),
        companyEmail: _companyEmail.text.trim(),
        companyPhone: _companyPhone.text.trim(),
        billingContactName: _billingName.text.trim().isEmpty ? null : _billingName.text.trim(),
        billingContactEmail: _billingEmail.text.trim().isEmpty ? null : _billingEmail.text.trim(),
        billingContactPhone: _billingPhone.text.trim().isEmpty ? null : _billingPhone.text.trim(),
        operationsContactName: _opsName.text.trim().isEmpty ? null : _opsName.text.trim(),
        operationsContactEmail: _opsEmail.text.trim().isEmpty ? null : _opsEmail.text.trim(),
        operationsContactPhone: _opsPhone.text.trim().isEmpty ? null : _opsPhone.text.trim(),
        taxDetails: _taxDetails.text.trim().isEmpty ? null : _taxDetails.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const RoleHomeShell()), (route) => false);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create a Business Account')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text('Your details', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const Text("You'll be the company's first Administrator - you can add your team afterwards.",
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
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
                decoration: const InputDecoration(labelText: 'Your email'),
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
                      decoration: const InputDecoration(labelText: 'Your phone number', hintText: 'e.g. 771234567'),
                      validator: _required,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _username,
                decoration: const InputDecoration(labelText: 'Username', hintText: 'You can sign in with this instead of your email'),
                validator: _required,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
              ),
              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 12),
              const Text('Company details', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _legalName,
                decoration: const InputDecoration(labelText: 'Company legal name'),
                validator: _required,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tradingName,
                decoration: const InputDecoration(labelText: 'Trading name (optional)'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _registrationNumber,
                decoration: const InputDecoration(labelText: 'Registration number'),
                validator: _required,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _country,
                decoration: const InputDecoration(labelText: 'Country'),
                isExpanded: true,
                items: kCountries.map((c) => DropdownMenuItem(value: c.name, child: Text('${c.flag} ${c.name}'))).toList(),
                onChanged: (v) => setState(() => _country = v),
                validator: (v) => v == null ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _registeredAddress,
                decoration: const InputDecoration(labelText: 'Registered address'),
                validator: _required,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _businessAddress,
                decoration: const InputDecoration(labelText: 'Business address (if different, optional)'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _industry,
                decoration: const InputDecoration(labelText: 'Industry'),
                validator: _required,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _authorizedRep,
                decoration: const InputDecoration(labelText: 'Authorized representative (defaults to your name)'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _companyEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Company email'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _companyPhone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Company phone'),
                validator: _required,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _taxDetails,
                decoration: const InputDecoration(labelText: 'Tax / VAT details (optional)'),
              ),
              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 12),
              const Text('Billing contact (optional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 16),
              TextFormField(controller: _billingName, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 16),
              TextFormField(controller: _billingEmail, decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 16),
              TextFormField(controller: _billingPhone, decoration: const InputDecoration(labelText: 'Phone')),
              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 12),
              const Text('Operations contact (optional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 16),
              TextFormField(controller: _opsName, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 16),
              TextFormField(controller: _opsEmail, decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 16),
              TextFormField(controller: _opsPhone, decoration: const InputDecoration(labelText: 'Phone')),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              const Text(
                "You'll get a Business ID once you submit. MidMen staff review the company's details before "
                "it's fully verified - you can add employees and use the app straight away in the meantime.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create Business Account'),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen())),
                  child: const Text('Already have an account? Sign in'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
