import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../features/auth/data/models/user_account.dart';
import '../../../features/auth/data/services/auth_service.dart';
import '../../../features/device/data/models/saved_device.dart';
import '../../../features/device/data/services/device_storage_service.dart';
import '../../../features/device/domain/reader_device.dart';
import '../../../features/document/data/services/document_storage_service.dart';
import '../../../shared/widgets/app_card.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.userName,
    this.status = ReaderConnectionStatus.disconnected,
    this.pageCount = 0,
    this.sessionActive = false,
    this.onDisconnect,
    this.onSignOut,
  });

  final String? userName;
  final ReaderConnectionStatus status;
  final int pageCount;
  final bool sessionActive;
  final VoidCallback? onDisconnect;
  final VoidCallback? onSignOut;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _storage = DocumentStorageService();
  final _authService = AuthService();
  final _deviceStorage = DeviceStorageService();

  List<SavedDevice> _devices = [];
  String? _activeDeviceId;

  int _savedDocCount = 0;
  int _storageTotalBytes = 0;
  bool _statsLoading = true;
  UserAccount? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadUser();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      final devices = await _deviceStorage.getAllDevices();
      final activeId = await _deviceStorage.getActiveDeviceId();
      if (mounted) {
        setState(() {
          _devices = devices;
          _activeDeviceId = activeId;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadUser() async {
    final user = await _authService.getCurrentUser();
    if (mounted) {
      setState(() => _currentUser = user);
    }
  }

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    try {
      final docs = await _storage.loadAllDocuments();
      int totalBytes = 0;

      for (final doc in docs) {
        final paths = [
          doc.imagePath,
          doc.originalTextPath,
          doc.originalPdfPath,
          doc.summaryTextPath,
          doc.summaryPdfPath,
          doc.originalAudioPath,
          doc.summaryAudioPath,
        ];
        for (final path in paths) {
          if (path == null) continue;
          final f = File(path);
          if (await f.exists()) {
            totalBytes += await f.length();
          }
        }
      }

      if (mounted) {
        setState(() {
          _savedDocCount = docs.length;
          _storageTotalBytes = totalBytes;
          _statsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes == 0) return '0 MB';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showThemeSelector() {
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
                  subtitle: const Text('Matches your phone display settings'),
                  trailing: current == ThemeMode.system
                      ? const Icon(Icons.check_rounded, color: AppColors.purple)
                      : null,
                  onTap: () async {
                    await ThemeController.instance.setThemeMode(
                      ThemeMode.system,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    setState(() {});
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
                    setState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.dark_mode_rounded),
                  title: const Text('Dark Theme'),
                  subtitle: const Text(
                    'Charcoal background with purple accents',
                  ),
                  trailing: current == ThemeMode.dark
                      ? const Icon(Icons.check_rounded, color: AppColors.purple)
                      : null,
                  onTap: () async {
                    await ThemeController.instance.setThemeMode(ThemeMode.dark);
                    if (ctx.mounted) Navigator.pop(ctx);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSignOutDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text(
          'Are you sure you want to sign out? You will need to log in again to access Naadh.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              widget.onSignOut?.call();
            },
            child: const Text('SIGN OUT'),
          ),
        ],
      ),
    );
  }

  // ─── Account actions ──────────────────────────────────────────────

  Future<void> _showChangePasswordDialog() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    String? error;
    var busy = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Change password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: current,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: next,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (next.text != confirm.text) {
                        setLocal(() => error = 'New passwords do not match.');
                        return;
                      }
                      setLocal(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await _authService.changePassword(
                          currentPassword: current.text,
                          newPassword: next.text,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Password updated.')),
                          );
                        }
                      } on AuthException catch (e) {
                        setLocal(() {
                          busy = false;
                          error = e.message;
                        });
                      }
                    },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountDialog() async {
    final password = TextEditingController();
    String? error;
    var busy = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Delete account?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your account is removed from this phone and you are signed '
                'out. Saved documents stay on this phone. Enter your '
                'password to confirm.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: busy
                  ? null
                  : () async {
                      setLocal(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await _authService.deleteAccount(
                          password: password.text,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        widget.onSignOut?.call();
                      } on AuthException catch (e) {
                        setLocal(() {
                          busy = false;
                          error = e.message;
                        });
                      }
                    },
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Devices ──────────────────────────────────────────────────────

  (String, Color) _deviceStatus(SavedDevice device) {
    final isActive =
        _activeDeviceId == device.deviceId ||
        (_activeDeviceId == null && _devices.length == 1);
    if (isActive) {
      switch (widget.status) {
        case ReaderConnectionStatus.connected:
        case ReaderConnectionStatus.busy:
          return ('Connected', AppColors.success);
        case ReaderConnectionStatus.connecting:
          return ('Connecting', AppColors.orange);
        case ReaderConnectionStatus.disconnected:
          break;
      }
    }
    return switch (device.setupStatus) {
      DeviceSetupStatus.identifiedNotConfigured => (
        'Needs Wi-Fi setup',
        AppColors.orange,
      ),
      DeviceSetupStatus.provisioningPending => ('Setting up', AppColors.orange),
      DeviceSetupStatus.configured => ('Not connected', AppColors.danger),
    };
  }

  Widget _buildDevicesCard(BuildContext context, bool isDark) {
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(context, isDark, Icons.memory_rounded, 'My Devices'),
          const Divider(height: 20),
          if (_devices.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'No devices yet. Scan the QR code on your Naadh reader to add one.',
                style: TextStyle(color: muted, fontSize: 13),
              ),
            )
          else
            for (final device in _devices)
              Builder(
                builder: (context) {
                  final (label, color) = _deviceStatus(device);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.graphic_eq_rounded,
                      color: isDark ? AppColors.purpleMid : AppColors.purple,
                    ),
                    title: Text(
                      device.displayName ?? device.deviceId,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: device.displayName != null
                        ? Text(device.deviceId)
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle_rounded, size: 10, color: color),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.deviceQrScanner),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: const Text('Add device'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.purple,
                side: const BorderSide(color: AppColors.purple),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context,
    bool isDark,
    IconData icon,
    String title,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: isDark ? AppColors.purpleMid : AppColors.purple,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildAccountCard(BuildContext context, bool isDark) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            context,
            isDark,
            Icons.manage_accounts_rounded,
            'Account',
          ),
          const Divider(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_rounded),
            title: const Text('Change password'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showChangePasswordDialog,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout_rounded),
            title: const Text('Log out'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showSignOutDialog,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.delete_forever_rounded,
              color: AppColors.danger,
            ),
            title: const Text(
              'Delete account',
              style: TextStyle(color: AppColors.danger),
            ),
            onTap: _showDeleteAccountDialog,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    final themeModeTitle = switch (ThemeController.instance.themeMode) {
      ThemeMode.system => 'System Default',
      ThemeMode.light => 'Light Theme',
      ThemeMode.dark => 'Dark Theme',
    };

    return RefreshIndicator(
      onRefresh: () async {
        await _loadStats();
        await _loadUser();
        await _loadDevices();
      },
      color: AppColors.purple,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Name and email ────────────────────────────────────────
          AppCard(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: isDark
                      ? AppColors.purpleDarkTint
                      : AppColors.purpleLightTint,
                  child: Icon(
                    Icons.person_rounded,
                    size: 38,
                    color: isDark ? AppColors.purpleMid : AppColors.purple,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _currentUser?.username ??
                      (widget.userName?.isNotEmpty == true
                          ? widget.userName!
                          : 'Guest'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_currentUser?.email != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _currentUser!.email!,
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          _buildDevicesCard(context, isDark),
          const SizedBox(height: AppSpacing.md),

          // ── Appearance ────────────────────────────────────────────
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader(
                  context,
                  isDark,
                  Icons.palette_rounded,
                  'Appearance',
                ),
                const Divider(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                    color: isDark ? AppColors.purpleMid : AppColors.purple,
                  ),
                  title: const Text('Theme Mode'),
                  subtitle: Text(themeModeTitle),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _showThemeSelector,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Usage ─────────────────────────────────────────────────
          AppCard(
            child: _InfoSection(
              title: 'Usage & Storage',
              icon: Icons.bar_chart_rounded,
              trailing: _statsLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.purpleMid,
                      ),
                    )
                  : null,
              rows: [
                _InfoRow(label: 'Documents Saved', value: '$_savedDocCount'),
                _InfoRow(
                  label: 'Pages in Session',
                  value: '${widget.pageCount}',
                ),
                _InfoRow(
                  label: 'Storage Used',
                  value: _statsLoading ? '…' : _formatBytes(_storageTotalBytes),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          _buildAccountCard(context, isDark),

          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Text(
              'Naadh version ${AppStrings.appVersion}',
              style: TextStyle(
                fontSize: 12,
                color: onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.title,
    required this.icon,
    required this.rows,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final List<_InfoRow> rows;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isDark ? AppColors.purpleMid : AppColors.purple,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (trailing != null) ...[const Spacer(), trailing!],
          ],
        ),
        const Divider(height: 20),
        ...rows.map(
          (row) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: Text(
                    row.label,
                    style: TextStyle(
                      color: isDark
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.value,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: isDark ? AppColors.darkText : AppColors.charcoal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;
}
