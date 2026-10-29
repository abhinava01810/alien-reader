import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../core/constants/pi_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../shared/widgets/app_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showThemeDialog(BuildContext context) {
    final current = ThemeController.instance.themeMode;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Appearance & Theme',
                  style: Theme.of(
                    ctx,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.brightness_auto_rounded),
                  title: const Text('System Default'),
                  subtitle: const Text('Adapts to phone system theme'),
                  trailing: current == ThemeMode.system
                      ? const Icon(Icons.check_rounded, color: AppColors.purple)
                      : null,
                  onTap: () async {
                    await ThemeController.instance.setThemeMode(
                      ThemeMode.system,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.light_mode_rounded),
                  title: const Text('Light Theme'),
                  subtitle: const Text(
                    'Clean white background with purple accents',
                  ),
                  trailing: current == ThemeMode.light
                      ? const Icon(Icons.check_rounded, color: AppColors.purple)
                      : null,
                  onTap: () async {
                    await ThemeController.instance.setThemeMode(
                      ThemeMode.light,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.dark_mode_rounded),
                  title: const Text('Dark Theme'),
                  subtitle: const Text(
                    'Rich charcoal background with purple accents',
                  ),
                  trailing: current == ThemeMode.dark
                      ? const Icon(Icons.check_rounded, color: AppColors.purple)
                      : null,
                  onTap: () async {
                    await ThemeController.instance.setThemeMode(ThemeMode.dark);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Image.asset(
              'assets/images/alien_innovations_logo.png',
              width: 32,
              height: 32,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 10),
            const Text('Alien Innovations'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Naadh',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 6),
            Text('Version: 1.0.0+1 (Production Ready)'),
            SizedBox(height: 12),
            Text(
              'AI-powered document capture, OCR text extraction, multi-lingual audio synthesis, and intelligent document summarization for the visually impaired and modern readers.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 12),
            Text(
              '© 2026 Alien Innovations. All rights reserved.',
              style: TextStyle(fontSize: 11, color: context.mutedText),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  void _showDeviceInfoDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.memory_rounded, color: AppColors.purple),
            SizedBox(width: 8),
            Text('Device Info'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Model: Naadh Smart Reader Pi',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text('Base URL: ${PiConfig.baseUrl}'),
            const SizedBox(height: 6),
            Text('Camera Stream: ${PiConfig.streamUrl}'),
            const SizedBox(height: 6),
            const Text('Firmware: v2.4-production'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DEVICE',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: isDark
                        ? AppColors.purpleDarkTint
                        : AppColors.purpleLightTint,
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      size: 20,
                      color: AppColors.purple,
                    ),
                  ),
                  title: const Text(
                    'Add Device (QR Setup)',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.purple,
                    ),
                  ),
                  subtitle: const Text(
                    'Scan QR code on your Naadh reader',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.purple,
                  ),
                  onTap: () {
                    Navigator.of(context).pushNamed(AppRoutes.deviceQrScanner);
                  },
                ),
                const Divider(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline_rounded, size: 22),
                  title: const Text('Device Information'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showDeviceInfoDialog(context),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.wifi_rounded, size: 22),
                  title: const Text('Wi-Fi Configuration'),
                  subtitle: const Text('Configure reader wireless network'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).pushNamed(AppRoutes.deviceQrScanner);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // APPEARANCE SECTION
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'APPEARANCE & THEME',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                    size: 22,
                    color: AppColors.purple,
                  ),
                  title: const Text('Theme Mode'),
                  subtitle: Text(switch (ThemeController.instance.themeMode) {
                    ThemeMode.system => 'System Default',
                    ThemeMode.light => 'Light Theme',
                    ThemeMode.dark => 'Dark Theme',
                  }),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showThemeDialog(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // SCANNING SECTION
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SCANNING & PROCESSING',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.camera_alt_rounded, size: 22),
                  title: const Text('Capture Preferences'),
                  subtitle: const Text('Multi-page delay and framing guides'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.text_snippet_rounded, size: 22),
                  title: const Text('OCR Recognition'),
                  subtitle: const Text('Language: English (US)'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // AUDIO SECTION
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AUDIO & SYNTHESIS',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.volume_up_rounded, size: 22),
                  title: const Text('Text-to-Speech Output'),
                  subtitle: const Text('Phone Speaker / Headphones'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.speed_rounded, size: 22),
                  title: const Text('Speech Rate'),
                  subtitle: const Text('1.0x (Normal)'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ABOUT SECTION
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ABOUT',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.business_rounded, size: 22),
                  title: const Text('About Alien Innovations'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showAboutDialog(context),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.shield_rounded, size: 22),
                  title: const Text('Privacy & Security'),
                  subtitle: const Text('Credentials stored encrypted locally'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
