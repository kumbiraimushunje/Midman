import 'package:flutter/material.dart';

import '../api_service.dart';
import 'reset_password_screen.dart';

/// Step 1 of the forgot-password flow: enter the account's email, get a
/// 6-digit code sent to it, then move on to ResetPasswordScreen.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email address');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ApiService.forgotPassword(email);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResetPasswordScreen(email: email)));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Enter the email on your MidMan account and we'll send you a code to reset your password.",
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _sendCode,
                  child: _loading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Send code'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
