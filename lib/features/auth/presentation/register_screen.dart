import 'package:flutter/material.dart';

import '../../../core/services/auth_service_cloud.dart';
import '../../../core/services/cloud_api_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import 'verify_email_screen.dart';
import 'widgets/auth_frame.dart';

/// Creates an account, asks for the 6-digit code from the verification
/// email, then signs in. Leaving the code screen returns to login with the
/// email filled in (pop result).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.auth, this.onLoggedIn});

  final CloudAuthService? auth;

  /// Signs the new account in once its email is verified. Without it the
  /// screen returns to login with the email filled in.
  final ValueChanged<CloudUser>? onLoggedIn;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  /// Matches the backend rule (RegisterIn.password min_length).
  static const _minPasswordLength = 10;

  late final CloudAuthService _auth = widget.auth ?? CloudAuthService();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Enter your name.';
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      return 'Enter a valid email address.';
    }
    if (_password.text.length < _minPasswordLength) {
      return 'Password must be at least $_minPasswordLength characters.';
    }
    if (_password.text != _confirm.text) return 'Passwords do not match.';
    return null;
  }

  Future<void> _register() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    final email = _email.text.trim();
    try {
      await _auth.register(_name.text, email, _password.text);
    } on CloudApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted) return;

    // Ask for the 6-digit code from the verification email.
    var verified = false;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VerifyEmailScreen(
          email: email,
          auth: _auth,
          onVerified: (_) async {
            verified = true;
            await _signInAfterVerify(email);
          },
        ),
      ),
    );
    // Left the code screen without verifying: back to login as before.
    if (!verified && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your email is not verified yet. After you log in, choose '
            'Verify now at the top of the app.',
          ),
        ),
      );
      Navigator.of(context).pop(email);
    }
  }

  /// Verified: sign straight in with the details just entered.
  Future<void> _signInAfterVerify(String email) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final onLoggedIn = widget.onLoggedIn;
    if (onLoggedIn != null) {
      try {
        final user = await _auth.login(email, _password.text);
        _password.clear();
        _confirm.clear();
        navigator.popUntil((route) => route.isFirst);
        onLoggedIn(user);
        return;
      } on CloudApiException {
        // Verified, but signing in failed (e.g. offline): log in by hand.
      }
    }
    _password.clear();
    _confirm.clear();
    navigator.pop(); // the code screen
    messenger.showSnackBar(
      const SnackBar(content: Text('Email verified. Log in to continue.')),
    );
    if (mounted) navigator.pop(email);
  }

  @override
  Widget build(BuildContext context) {
    final length = _password.text.length;
    final longEnough = length >= _minPasswordLength;

    return AuthFrame(
      title: 'Create your account',
      subtitle: 'Sign up to pair your Naadh reader',
      showBack: true,
      footer: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Already have an account?',
              style: TextStyle(color: context.mutedText),
            ),
            TextButton(
              onPressed: _loading ? null : () => Navigator.of(context).pop(),
              child: const Text('Log in'),
            ),
          ],
        ),
      ],
      children: [
        if (_error != null) AuthErrorBanner(_error!),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Name',
            prefixIcon: Icon(Icons.person_rounded),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
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
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_rounded),
            helperText: longEnough
                ? 'Length looks good'
                : 'At least $_minPasswordLength characters'
                      '${length > 0 ? ' (${_minPasswordLength - length} more)' : ''}',
            helperStyle: TextStyle(
              color: longEnough ? AppColors.success : context.mutedText,
            ),
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
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _confirm,
          obscureText: _obscure,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _register(),
          decoration: const InputDecoration(
            labelText: 'Confirm password',
            prefixIcon: Icon(Icons.lock_reset_rounded),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AuthPrimaryButton(
          label: 'Register',
          loading: _loading,
          onPressed: _register,
        ),
      ],
    );
  }
}
