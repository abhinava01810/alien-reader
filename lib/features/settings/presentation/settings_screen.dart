import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/section_header.dart';
import '../../device/domain/reader_device.dart';

/// Reader, scanning, audio and about settings.
///
/// Appearance and paired devices live on the Profile tab.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    this.status = ReaderConnectionStatus.disconnected,
    this.statusStream,
    this.wifiNetworkName,
    this.onOpenConnection,
  });

  /// Reader status when the screen opens; [statusStream] keeps it live.
  final ReaderConnectionStatus status;
  final Stream<ReaderConnectionStatus>? statusStream;

  /// Wi-Fi network the reader joined, when known.
  final String? wifiNetworkName;

  /// Opens the Raspberry Pi connection sheet.
  final VoidCallback? onOpenConnection;

  void _showAboutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const SectionHeader(
          title: 'About Naadh',
          icon: Icons.info_rounded,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Naadh v${AppStrings.appVersion}',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'By Alien Innovations',
              style: TextStyle(color: ctx.mutedText),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Document capture, text extraction, summaries and read-aloud '
              'audio for the visually impaired and everyday readers.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: StreamBuilder<ReaderConnectionStatus>(
        stream: statusStream,
        initialData: status,
        builder: (context, snapshot) {
          final current = statusStream == null
              ? status
              : (snapshot.data ?? status);
          final connected =
              current == ReaderConnectionStatus.connected ||
              current == ReaderConnectionStatus.busy;

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _SettingsCard(
                title: 'Reader',
                icon: Icons.devices_rounded,
                tiles: [
                  _SettingsTile(
                    icon: Icons.wifi_rounded,
                    title: 'Wi-Fi Configuration',
                    subtitle: connected
                        ? (wifiNetworkName ?? 'Connected')
                        : 'Not connected',
                    onTap: () => Navigator.of(
                      context,
                    ).pushNamed(AppRoutes.deviceQrScanner),
                  ),
                  _SettingsTile(
                    icon: Icons.link_rounded,
                    title: 'Connection Status',
                    subtitle: connected ? 'Connected' : 'Disconnected',
                    onTap: onOpenConnection,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const _SettingsCard(
                title: 'Scanning',
                icon: Icons.document_scanner_rounded,
                tiles: [
                  _SettingsTile(
                    icon: Icons.camera_rounded,
                    title: 'Capture Preferences',
                    subtitle: 'Multi-page delay and framing',
                  ),
                  _SettingsTile(
                    icon: Icons.translate_rounded,
                    title: 'OCR Language',
                    subtitle: 'English (US)',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const _SettingsCard(
                title: 'Audio',
                icon: Icons.volume_up_rounded,
                tiles: [
                  _SettingsTile(
                    icon: Icons.record_voice_over_rounded,
                    title: 'Text-to-Speech',
                    subtitle: 'Phone Speaker / Headphones',
                  ),
                  _SettingsTile(
                    icon: Icons.speed_rounded,
                    title: 'Speech Rate',
                    subtitle: '1.0x (Normal)',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _SettingsCard(
                title: 'About',
                icon: Icons.info_rounded,
                tiles: [
                  _SettingsTile(
                    icon: Icons.info_outline_rounded,
                    title: 'About Naadh',
                    subtitle: 'By Alien Innovations',
                    onTap: () => _showAboutDialog(context),
                  ),
                  const _SettingsTile(
                    icon: Icons.shield_rounded,
                    title: 'Privacy & Security',
                    subtitle: 'Credentials stored encrypted locally',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: Text(
                  'Naadh v${AppStrings.appVersion}',
                  style: TextStyle(fontSize: 12, color: context.mutedText),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          );
        },
      ),
    );
  }
}

/// One settings group: an [AppCard] with a [SectionHeader], a divider and
/// its tiles, matching the Profile cards.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.tiles,
  });

  final String title;
  final IconData icon;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title, icon: icon),
          const Divider(height: 20),
          ...tiles,
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 22, color: context.accent),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(Icons.chevron_right_rounded, color: context.mutedText),
      onTap: onTap,
    );
  }
}
