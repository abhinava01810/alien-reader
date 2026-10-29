import 'package:flutter/material.dart';

import '../../../core/services/auth_service_cloud.dart';
import '../../../core/services/cloud_api_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shapes.dart';
import '../../../core/theme/app_spacing.dart';
import 'widgets/auth_frame.dart';

/// Requests a password-reset email. The confirmation never reveals whether
/// an account exists for the address.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.auth, this.initialEmail = ''});

  final CloudAuthService? auth;
  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const sentMessage = "If an account exists, we've sent a reset link.";

  late final CloudAuthService _auth = widget.auth ?? CloudAuthService();
  late final _email = TextEditingController(text: widget.initialEmail);
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _auth.requestPasswordReset(email);
      if (mounted) setState(() => _sent = true);
    } on CloudApiException catch (e) {
      if (!mounted) return;
      // A server answer (any status) gets the same neutral reply; only a
      // failure to reach the server is reported as an error.
      setState(() {
        if (e.statusCode != null) {
          _sent = true;
        } else {
          _error = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthFrame(
      title: 'Reset your password',
      subtitle: "Enter your email and we'll send you a reset link",
      showBack: true,
      footer: [
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to log in'),
          ),
        ),
      ],
      children: [
        if (_error != null) AuthErrorBanner(_error!),
        if (_sent)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppShapes.cardRadius),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.4),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.mark_email_read_rounded, color: AppColors.success),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    sentMessage,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _send(),
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.email_rounded),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AuthPrimaryButton(
          label: 'Send reset link',
          loading: _loading,
          onPressed: _send,
        ),
      ],
    );
  }
}
