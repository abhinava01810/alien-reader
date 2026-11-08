import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// Shown above the app while the account's email is unverified, with a way
/// back to the code screen. One accessibility node for the message, and a
/// separate, clearly labelled button.
class VerifyEmailBanner extends StatelessWidget {
  const VerifyEmailBanner({
    super.key,
    required this.email,
    required this.onVerifyNow,
  });

  final String email;
  final VoidCallback onVerifyNow;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.orange.withValues(alpha: 0.12),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              const ExcludeSemantics(
                child: Icon(
                  Icons.mark_email_unread_rounded,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Semantics(
                  container: true,
                  child: Text(
                    'Verify your email ($email) to pair a reader.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              TextButton(
                onPressed: onVerifyNow,
                child: const Text('Verify now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
