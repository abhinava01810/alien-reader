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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                    Navigator.of(context).pushNamed(
                      AppRoutes.wifiOnboarding,
                      arguments: payload.deviceId,
                    );
                  },
                  icon: const Icon(Icons.wifi_rounded),
                  label: const Text('CONFIGURE WI-FI'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    foregroundColor: Colors.white,
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
                height: 48,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark
                        ? AppColors.darkText
                        : AppColors.charcoal,
                    side: BorderSide(
                      color: isDark ? AppColors.darkBorder : AppColors.gray,
                    ),
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
          color: isDark
              ? AppColors.darkSurfaceElevated
              : AppColors.cloud.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppShapes.cardRadius),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
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
                                    : (isDark
                                          ? AppColors.darkBorder
                                          : AppColors.gray)),
                          child: Icon(
                            step.isComplete
                                ? Icons.check_rounded
                                : (step.isActive
                                      ? Icons.fingerprint_rounded
                                      : Icons.wifi_rounded),
                            size: 16,
                            color: Colors.white,
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
                                ? (isDark
                                      ? AppColors.purpleMid
                                      : AppColors.purple)
                                : (isDark
                                      ? AppColors.darkTextMuted
                                      : AppColors.charcoal),
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
                          : (isDark ? AppColors.darkBorder : AppColors.gray),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        border: Border.all(
          color: isDark
              ? AppColors.purpleMid.withValues(alpha: 0.4)
              : AppColors.purple.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.purple.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.purpleDarkTint
                  : AppColors.purple.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.qr_code_2_rounded,
              size: 48,
              color: isDark ? AppColors.purpleMid : AppColors.purple,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Device Detected',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkText : AppColors.charcoal,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurfaceElevated : AppColors.cloud,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.gray,
              ),
            ),
            child: SelectableText(
              payload.deviceId,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: isDark ? AppColors.purpleMid : AppColors.purple,
              ),
            ),
          ),
          if (payload.model != null || payload.version != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                if (payload.model != null)
                  Chip(
                    label: Text('Model: ${payload.model}'),
                    backgroundColor: isDark
                        ? AppColors.darkSurfaceElevated
                        : AppColors.cloud,
                    labelStyle: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppColors.darkText : AppColors.charcoal,
                    ),
                  ),
                if (payload.version != null)
                  Chip(
                    label: Text('v${payload.version}'),
                    backgroundColor: isDark
                        ? AppColors.darkSurfaceElevated
                        : AppColors.cloud,
                    labelStyle: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppColors.darkText : AppColors.charcoal,
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
                    color: isDark ? AppColors.darkText : AppColors.charcoal,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'The device identifier has been verified from the QR code. Tap "Configure Wi-Fi" to connect your Naadh reader to your local wireless network.',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.charcoal.withValues(alpha: 0.8),
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
        color: isDark
            ? AppColors.darkSurfaceElevated
            : AppColors.cloud.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.gray,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.network_wifi_rounded,
                size: 20,
                color: isDark ? AppColors.purpleMid : AppColors.purpleMid,
              ),
              const SizedBox(width: 8),
              Text(
                'Next Step: Wi-Fi Provisioning',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkText : AppColors.charcoal,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Text(
            'Authenticate with the device-specific PIN/secret printed on your reader, select your local Wi-Fi network, and securely transfer credentials to the device.',
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
