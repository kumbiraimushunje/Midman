import 'package:flutter/material.dart';

import '../api_service.dart';
import '../country_data.dart';
import 'login_screen.dart';

/// Minimal KYC-on-registration form: full name, DOB, email, phone, password,
/// country of residence, primary purpose. ID/passport document upload and
/// address are collected later in the profile (kept out of the MVP form so
/// signup isn't a wall of fields).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  DateTime? _dob;
  String? _purpose;
  String? _countryName;
  String _dialCode = '+263';
  bool _loading = false;
  String? _error;

  static const _purposes = ['Children', 'Parents', 'Family', 'Property', 'Business', 'Personal', 'Other'];

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 16, now.month, now.day), // must be 16+
      initialDate: DateTime(now.year - 25),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _dob == null || _countryName == null) {
      setState(() => _error = _dob == null
          ? 'Please select your date of birth'
          : _countryName == null
              ? 'Please select your country of residence'
              : null);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ApiService.register(
        fullName: _fullName.text.trim(),
        dateOfBirth:
            '${_dob!.year.toString().padLeft(4, '0')}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
        email: _email.text.trim(),
        phone: '$_dialCode${_phone.text.trim()}',
        password: _password.text,
        countryOfResidence: _countryName!,
        primaryPurpose: _purpose,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created — please sign in.')),
      );
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create your account')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                controller: _fullName,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickDob,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date of birth'),
                  child: Text(_dob == null
                      ? 'Select date'
                      : '${_dob!.day}/${_dob!.month}/${_dob!.year}'),
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
                      decoration: const InputDecoration(labelText: 'Phone number', hintText: 'e.g. 771234567'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
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
                initialValue: _purpose,
                decoration: const InputDecoration(labelText: 'Primary purpose (optional)'),
                items: _purposes.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                onChanged: (v) => setState(() => _purpose = v),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.red)),
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
