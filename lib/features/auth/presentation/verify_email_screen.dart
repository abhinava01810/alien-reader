import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/auth_service_cloud.dart';
import '../../../core/services/cloud_api_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import 'widgets/auth_frame.dart';

/// After registering: enter the 6-digit code that was emailed, or ask for a
/// new one. Built to work well with TalkBack: one clearly labelled field,
/// errors and confirmations announced as they appear.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    super.key,
    required this.email,
    required this.onVerified,
    this.auth,
  });

  final String email;

  /// Called once the server accepts the code.
  final Future<void> Function(CloudUser user) onVerified;
  final CloudAuthService? auth;

  static const codeLength = 6;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  late final CloudAuthService _auth = widget.auth ?? CloudAuthService();
  final _code = TextEditingController();
  final _focus = FocusNode();

  bool _verifying = false;
  bool _resending = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != VerifyEmailScreen.codeLength) {
      setState(() {
        _error = 'Enter all 6 digits of the code from your email.';
        _notice = null;
      });
      _focus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _verifying = true;
      _error = null;
      _notice = null;
    });
    try {
      final user = await _auth.confirmEmailVerification(widget.email, code);
      if (!mounted) return;
      await widget.onVerified(user);
    } on CloudApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      _code.clear();
      _focus.requestFocus();
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
      _notice = null;
    });
    try {
      await _auth.requestEmailVerification(widget.email);
      if (!mounted) return;
      _code.clear();
      setState(() => _notice = 'A new code was sent to ${widget.email}.');
    } on CloudApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _verifying || _resending;
    return AuthFrame(
      title: 'Check your email',
      subtitle: 'We sent a 6-digit code to ${widget.email}.',
      showBack: true,
      footer: [
        Center(
          child: TextButton(
            onPressed: busy ? null : _resend,
            child: Text(_resending ? 'Sending a new code…' : 'Resend code'),
          ),
        ),
      ],
      children: [
        if (_error != null) AuthErrorBanner(_error!),
        if (_notice != null) _Notice(_notice!),
        TextField(
          controller: _code,
          focusNode: _focus,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            // Pasted codes like "123 456" keep only the digits.
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(VerifyEmailScreen.codeLength),
          ],
          style: const TextStyle(fontSize: 24, letterSpacing: 6),
          onSubmitted: (_) => _verify(),
          decoration: InputDecoration(
            // No placeholder digits: TalkBack would read them as the value.
            labelText: '6-digit code',
            helperText: 'The code is in the email from Naadh.',
            // Red outline only; the message itself is the banner above,
            // announced once on its own rather than repeated by the field.
            error: _error == null ? null : const SizedBox.shrink(),
            prefixIcon: const Icon(Icons.pin_rounded),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AuthPrimaryButton(
          label: 'Verify',
          loading: _verifying,
          onPressed: busy ? null : _verify,
        ),
      ],
    );
  }
}

/// A confirmation line that TalkBack reads out when it appears.
class _Notice extends StatelessWidget {
  const _Notice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.mark_email_read_rounded, color: AppColors.success),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
