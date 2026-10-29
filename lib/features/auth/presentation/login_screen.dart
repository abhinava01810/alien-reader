import 'package:flutter/material.dart';

import '../../../core/services/auth_service_cloud.dart';
import '../../../core/services/cloud_api_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';
import 'widgets/auth_frame.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onLoggedIn, this.auth});

  final ValueChanged<CloudUser> onLoggedIn;
  final CloudAuthService? auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final CloudAuthService _auth = widget.auth ?? CloudAuthService();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await _auth.login(email, _password.text);
      if (!mounted) return;
      _password.clear();
      widget.onLoggedIn(user);
    } on CloudApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openRegister() async {
    final email = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => RegisterScreen(auth: _auth)),
    );
    if (email != null && mounted) {
      _email.text = email;
      setState(() => _error = null);
    }
  }

  void _openForgot() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ForgotPasswordScreen(auth: _auth, initialEmail: _email.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthFrame(
      title: 'Welcome back',
      subtitle: 'Log in to your Naadh account',
      footer: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('New to Naadh?', style: TextStyle(color: context.mutedText)),
            TextButton(
              onPressed: _loading ? null : _openRegister,
              child: const Text('Create account'),
            ),
          ],
        ),
      ],
      children: [
        if (_error != null) AuthErrorBanner(_error!),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.email_rounded),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _password,
          obscureText: _obscure,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _login(),
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_rounded),
            suffixIcon: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
              tooltip: _obscure ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _loading ? null : _openForgot,
            child: const Text('Forgot password?'),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        AuthPrimaryButton(
          label: 'Log in',
          loading: _loading,
          onPressed: _login,
        ),
      ],
    );
  }
}
