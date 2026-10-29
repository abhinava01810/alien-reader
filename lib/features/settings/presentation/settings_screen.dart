import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/pi_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/section_header.dart';

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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.xxl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  title: 'Appearance & Theme',
                  icon: Icons.palette_rounded,
                ),
                const SizedBox(height: AppSpacing.md),
                ListTile(
                  leading: Icon(
                    Icons.brightness_auto_rounded,
                    color: context.accent,
                  ),
                  title: const Text('System Default'),
                  subtitle: const Text('Adapts to phone system theme'),
                  trailing: current == ThemeMode.system
                      ? Icon(Icons.check_rounded, color: context.accent)
                      : null,
                  onTap: () async {
                    await ThemeController.instance.setThemeMode(
                      ThemeMode.system,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.light_mode_rounded,
                    color: context.accent,
                  ),
                  title: const Text('Light Theme'),
                  subtitle: const Text(
                    'Clean white background with purple accents',
                  ),
                  trailing: current == ThemeMode.light
                      ? Icon(Icons.check_rounded, color: context.accent)
                      : null,
                  onTap: () async {
                    await ThemeController.instance.setThemeMode(
                      ThemeMode.light,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.dark_mode_rounded, color: context.accent),
                  title: const Text('Dark Theme'),
                  subtitle: const Text(
                    'Rich charcoal background with purple accents',
                  ),
                  trailing: current == ThemeMode.dark
                      ? Icon(Icons.check_rounded, color: context.accent)
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
            Text('Version ${AppStrings.appVersion}'),
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
        title: Row(
          children: [
            Icon(Icons.memory_rounded, color: context.accent),
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
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: 'Device', icon: Icons.memory_rounded),
                const Divider(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.qr_code_scanner_rounded,
                    size: 22,
                    color: context.accent,
                  ),
                  title: const Text('Add Device (QR Setup)'),
                  subtitle: const Text('Scan QR code on your Naadh reader'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: context.mutedText,
                  ),
                  onTap: () {
                    Navigator.of(context).pushNamed(AppRoutes.deviceQrScanner);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.info_outline_rounded,
                    size: 22,
                    color: context.accent,
                  ),
                  title: const Text('Device Information'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: context.mutedText,
                  ),
                  onTap: () => _showDeviceInfoDialog(context),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.wifi_rounded,
                    size: 22,
                    color: context.accent,
                  ),
                  title: const Text('Wi-Fi Configuration'),
                  subtitle: const Text('Configure reader wireless network'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: context.mutedText,
                  ),
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
                SectionHeader(
                  title: 'Appearance & Theme',
                  icon: Icons.palette_rounded,
                ),
                const Divider(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                    size: 22,
                    color: context.accent,
                  ),
                  title: const Text('Theme Mode'),
                  subtitle: Text(switch (ThemeController.instance.themeMode) {
                    ThemeMode.system => 'System Default',
                    ThemeMode.light => 'Light Theme',
                    ThemeMode.dark => 'Dark Theme',
                  }),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: context.mutedText,
                  ),
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
                SectionHeader(
                  title: 'Scanning & Processing',
                  icon: Icons.document_scanner_rounded,
                ),
                const Divider(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.camera_alt_rounded,
                    size: 22,
                    color: context.accent,
                  ),
                  title: const Text('Capture Preferences'),
                  subtitle: const Text('Multi-page delay and framing guides'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: context.mutedText,
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.text_snippet_rounded,
                    size: 22,
                    color: context.accent,
                  ),
                  title: const Text('OCR Recognition'),
                  subtitle: const Text('Language: English (US)'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: context.mutedText,
                  ),
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
                SectionHeader(
                  title: 'Audio & Synthesis',
                  icon: Icons.graphic_eq_rounded,
                ),
                const Divider(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.volume_up_rounded,
                    size: 22,
                    color: context.accent,
                  ),
                  title: const Text('Text-to-Speech Output'),
                  subtitle: const Text('Phone Speaker / Headphones'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: context.mutedText,
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.speed_rounded,
                    size: 22,
                    color: context.accent,
                  ),
                  title: const Text('Speech Rate'),
                  subtitle: const Text('1.0x (Normal)'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: context.mutedText,
                  ),
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
                SectionHeader(title: 'About', icon: Icons.info_rounded),
                const Divider(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.business_rounded,
                    size: 22,
                    color: context.accent,
                  ),
                  title: const Text('About Alien Innovations'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: context.mutedText,
                  ),
                  onTap: () => _showAboutDialog(context),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.shield_rounded,
                    size: 22,
                    color: context.accent,
                  ),
                  title: const Text('Privacy & Security'),
                  subtitle: const Text('Credentials stored encrypted locally'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: context.mutedText,
                  ),
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
