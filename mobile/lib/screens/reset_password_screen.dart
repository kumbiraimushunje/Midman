import 'package:flutter/material.dart';

import '../api_service.dart';
import '../widgets/password_field.dart';
import 'role_home_shell.dart';

/// Step 2 of the forgot-password flow: enter the 6-digit code that was
/// emailed and a new password. Success logs the customer straight in with
/// the fresh token the backend returns.
class ResetPasswordScreen extends StatefulWidget {
  final String email;
  const ResetPasswordScreen({super.key, required this.email});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _resetPassword() async {
    final otp = _otpController.text.trim();
    final newPassword = _newPasswordController.text;
    if (otp.isEmpty || newPassword.isEmpty) {
      setState(() => _error = 'Enter the code and a new password');
      return;
    }
    if (newPassword != _confirmPasswordController.text) {
      setState(() => _error = "Passwords don't match");
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ApiService.resetPassword(email: widget.email, otp: otp, newPassword: newPassword);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const RoleHomeShell()), (route) => false);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendCode() async {
    try {
      await ApiService.forgotPassword(widget.email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code sent again - check your email')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enter the code we sent to ${widget.email} and choose a new password.',
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: '6-digit code'),
              ),
              PasswordField(controller: _newPasswordController, labelText: 'New password'),
              const SizedBox(height: 16),
              PasswordField(controller: _confirmPasswordController, labelText: 'Confirm new password'),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _resetPassword,
                  child: _loading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Reset password'),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _resendCode,
                  child: const Text("Didn't get a code? Resend"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
