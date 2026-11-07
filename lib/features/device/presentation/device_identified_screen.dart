import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shapes.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/models/device_qr_payload.dart';

/// Screen displayed after successfully scanning and validating a Naadh device QR code.
class DeviceIdentifiedScreen extends StatelessWidget {
  const DeviceIdentifiedScreen({super.key, required this.payload});

  final DeviceQrPayload payload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Device Setup'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to Application',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildProgressStepper(context, isDark),
              const SizedBox(height: AppSpacing.lg),
              _buildDeviceIdentificationCard(context, isDark),
              const SizedBox(height: AppSpacing.lg),
              _buildStatusCard(context, isDark),
              const SizedBox(height: AppSpacing.lg),
              _buildNextStepNotice(context, isDark),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                height: AppSpacing.buttonHeight,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pushNamed(AppRoutes.devicePairing, arguments: payload);
                  },
                  icon: const Icon(Icons.wifi_rounded),
                  label: const Text('CONFIGURE WI-FI'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    foregroundColor: AppColors.onBrand,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppShapes.buttonRadius,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: AppSpacing.buttonHeight,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.strongText,
                    side: BorderSide(color: context.borderColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppShapes.buttonRadius,
                      ),
                    ),
                  ),
                  child: const Text('Cancel / Return to App'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressStepper(BuildContext context, bool isDark) {
    final steps = [
      _StepInfo('Add Device', isComplete: true, isActive: false),
      _StepInfo('Scan QR', isComplete: true, isActive: false),
      _StepInfo('Identified', isComplete: false, isActive: true),
      _StepInfo(
        'Wi-Fi Setup',
        isComplete: false,
        isActive: false,
        isPending: true,
      ),
    ];

    return Semantics(
      label: 'Setup progress: Step 3 of 4: Device Identified',
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: context.surfaceElevated,
          borderRadius: BorderRadius.circular(AppShapes.cardRadius),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: steps.asMap().entries.map((entry) {
            final idx = entry.key;
            final step = entry.value;

            return Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: step.isComplete
                              ? AppColors.success
                              : (step.isActive
                                    ? AppColors.purple
                                    : (context.borderColor)),
                          child: Icon(
                            step.isComplete
                                ? Icons.check_rounded
                                : (step.isActive
                                      ? Icons.fingerprint_rounded
                                      : Icons.wifi_rounded),
                            size: 16,
                            color: AppColors.onBrand,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          step.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: step.isActive
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: step.isActive
                                ? (context.accent)
                                : (context.mutedText),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (idx < steps.length - 1)
                    Container(
                      width: 14,
                      height: 2,
                      color: steps[idx].isComplete
                          ? AppColors.success
                          : (context.borderColor),
                    ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildDeviceIdentificationCard(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              size: 48,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Device Detected',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: context.strongText,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: context.surfaceElevated,
              borderRadius: BorderRadius.circular(AppShapes.cardRadius),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              children: [
                Text(
                  'SERIAL NUMBER',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: context.mutedText,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                SelectableText(
                  payload.deviceId,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: context.accent,
                  ),
                ),
              ],
            ),
          ),
          if (payload.model != null || payload.version != null) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                if (payload.model != null)
                  Chip(
                    label: Text('Model: ${payload.model}'),
                    backgroundColor: context.surfaceElevated,
                    labelStyle: TextStyle(
                      fontSize: 11,
                      color: context.strongText,
                    ),
                  ),
                if (payload.version != null)
                  Chip(
                    label: Text('v${payload.version}'),
                    backgroundColor: context.surfaceElevated,
                    labelStyle: TextStyle(
                      fontSize: 11,
                      color: context.strongText,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.orange,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Device identified — setup not completed',
                  style: TextStyle(
                    color: context.strongText,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'The device identifier has been verified from the QR code. Tap "Configure Wi-Fi" to connect your Naadh reader to your local wireless network.',
                  style: TextStyle(
                    color: context.mutedText,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextStepNotice(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceElevated,
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.network_wifi_rounded, size: 20, color: context.accent),
              const SizedBox(width: 8),
              Text(
                'Next Step: Pair your reader',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: context.strongText,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Text(
            'Join the NAADH-Setup hotspot, press the button on your reader to confirm it is in your hands, then choose your Wi-Fi network.',
            style: TextStyle(
              fontSize: 12.5,
              color: context.mutedText,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepInfo {
  final String title;
  final bool isComplete;
  final bool isActive;
  final bool isPending;

  _StepInfo(
    this.title, {
    this.isComplete = false,
    this.isActive = false,
    this.isPending = false,
  });
}
