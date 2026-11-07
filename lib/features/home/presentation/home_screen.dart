import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shapes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/responsive.dart';
import '../../../features/device/data/device_events.dart';
import '../../../features/device/data/services/device_storage_service.dart';
import '../../../features/device/domain/reader_device.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_dialogs.dart';
import '../../../shared/widgets/section_header.dart';
import '../widgets/home_camera_placeholder.dart';
import 'full_screen_camera_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.status,
    required this.onConnect,
    required this.onCapture,
    required this.onFinish,
    required this.pageCount,
    this.onDisconnect,
    this.onDeletePage,
    this.ocrFailureMessage,
    this.userName,
    this.onOpenFiles,
    this.onOpenSettings,
    this.onOpenProfile,
    this.onOpenConnection,
    this.deviceStorage,
  });

  final ReaderConnectionStatus status;
  final VoidCallback onConnect;
  final VoidCallback? onDisconnect;
  final VoidCallback onCapture;
  final VoidCallback onFinish;
  final int pageCount;
  final VoidCallback? onDeletePage;
  final String? ocrFailureMessage;
  final String? userName;
  final VoidCallback? onOpenFiles;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenProfile;

  /// Opens the Raspberry Pi connection sheet (status bar tap).
  final VoidCallback? onOpenConnection;
  final DeviceStorageService? deviceStorage;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedPageIndex = 0;
  bool? _hasDevice;
  StreamSubscription<DeviceChange>? _deviceChanges;

  @override
  void initState() {
    super.initState();
    _loadHasDevice();
    // Home stays alive in the tab stack, so reload when pairing saves a reader.
    _deviceChanges = DeviceEvents.changes.listen((_) => _loadHasDevice());
  }

  @override
  void dispose() {
    _deviceChanges?.cancel();
    super.dispose();
  }

  Future<void> _loadHasDevice() async {
    final known = await (widget.deviceStorage ?? DeviceStorageService())
        .hasKnownReader();
    if (!mounted) return;
    // A live connection that arrived while this was loading wins.
    setState(() => _hasDevice = known || _isLive(widget.status));
  }

  static bool _isLive(ReaderConnectionStatus s) =>
      s != ReaderConnectionStatus.disconnected;

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // The live connection decides: once the app is connecting to or
    // connected to a reader, Home shows that reader, saved or not.
    if (_isLive(widget.status) && _hasDevice != true) {
      _hasDevice = true;
    }

    if (widget.pageCount <= _selectedPageIndex) {
      _selectedPageIndex = widget.pageCount > 0 ? widget.pageCount - 1 : 0;
    }
  }

  void _openFullScreenCamera() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullScreenCameraScreen(
          status: widget.status,
          onCapture: widget.onCapture,
          onProcess: widget.onFinish,
          pageCount: widget.pageCount,
        ),
      ),
    );
  }

  void _showPagePreview(int pageIndex) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: isDark
              ? AppColors.darkSurfaceElevated
              : AppColors.lightSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppShapes.cardRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Page ${pageIndex + 1} Preview',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.of(ctx).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  height: 220,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkBackground : AppColors.cloud,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.article_rounded,
                          size: 56,
                          color: isDark
                              ? AppColors.purpleMid
                              : AppColors.purple,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Page ${pageIndex + 1} Captured',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ready for OCR processing',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkTextMuted
                                : AppColors.lightTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (widget.onDeletePage != null)
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          widget.onDeletePage!();
                        },
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: AppColors.danger,
                        ),
                        label: const Text(
                          'Delete Page',
                          style: TextStyle(color: AppColors.danger),
                        ),
                      ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.purple,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppShapes.buttonRadius,
                          ),
                        ),
                      ),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pad = Responsive.adaptivePadding(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final cameraHeight = (screenHeight * 0.42).clamp(230.0, 360.0);

    final isDeviceReady =
        widget.status == ReaderConnectionStatus.connected ||
        widget.status == ReaderConnectionStatus.busy;

    // Nothing to render until the saved-device lookup resolves, unless the
    // live connection already says there is a reader.
    if (_hasDevice == null && !_isLive(widget.status)) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: 12),
      children: [
        if (_hasDevice == false && !_isLive(widget.status)) ...[
          _buildFirstRunSetupCard(context, isDark),
        ] else ...[
          _buildDeviceStatusBar(context, isDark),
          const SizedBox(height: AppSpacing.md),
          _buildCameraCard(cameraHeight),
          const SizedBox(height: AppSpacing.md),
          _buildCaptureAndReadControls(isDark, isDeviceReady),
          if (widget.ocrFailureMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            _buildOcrFailureBanner(),
          ],
          const SizedBox(height: AppSpacing.md),
          _buildCapturedPagesSection(context, isDark),
        ],
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  Widget _buildFirstRunSetupCard(BuildContext context, bool isDark) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      color: isDark
          ? AppColors.darkSurfaceElevated
          : AppColors.lightSurfaceElevated,
      borderColor: isDark ? AppColors.darkBorder : AppColors.lightBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.purpleDarkTint
                  : AppColors.purpleLightTint,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.qr_code_scanner_rounded,
              color: isDark ? AppColors.purpleMid : AppColors.purple,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Set up your Naadh reader',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Scan the QR code on your device to get started.',
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: isDark
                  ? AppColors.darkTextMuted
                  : AppColors.lightTextMuted,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.deviceQrScanner),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
              label: const Text(
                'Scan QR code',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.purple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppShapes.buttonRadius),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDisconnect() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Disconnect reader?',
      message: 'You can reconnect at any time.',
    );
    if (confirmed == true) widget.onDisconnect?.call();
  }

  Widget _buildDeviceStatusBar(BuildContext context, bool isDark) {
    final (label, color, icon) = switch (widget.status) {
      ReaderConnectionStatus.connected => (
        'Connected',
        AppColors.success,
        Icons.check_circle_rounded,
      ),
      ReaderConnectionStatus.busy => (
        'Busy',
        AppColors.purpleMid,
        Icons.sync_rounded,
      ),
      ReaderConnectionStatus.connecting => (
        'Connecting...',
        AppColors.orange,
        Icons.autorenew_rounded,
      ),
      ReaderConnectionStatus.disconnected => (
        'Disconnected',
        AppColors.danger,
        Icons.cloud_off_rounded,
      ),
    };
    final isDeviceReady =
        widget.status == ReaderConnectionStatus.connected ||
        widget.status == ReaderConnectionStatus.busy;
    final isConnecting = widget.status == ReaderConnectionStatus.connecting;

    Widget? action;
    if (isDeviceReady) {
      if (widget.onDisconnect != null) {
        action = TextButton.icon(
          onPressed: _confirmDisconnect,
          icon: const Icon(Icons.link_off_rounded, size: 16),
          label: const Text('Disconnect'),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
        );
      }
    } else {
      action = TextButton.icon(
        onPressed: isConnecting ? null : widget.onConnect,
        icon: const Icon(Icons.refresh_rounded, size: 16),
        label: const Text('Reconnect'),
        style: TextButton.styleFrom(
          foregroundColor: isDark ? AppColors.purpleMid : AppColors.purple,
        ),
      );
    }

    return Material(
      color: context.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.buttonRadius),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpenConnection,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ?action,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraCard(double cameraHeight) {
    return SizedBox(
      height: cameraHeight,
      width: double.infinity,
      child: HomeCameraPlaceholder(
        status: widget.status,
        onToggleFullScreen: _openFullScreenCamera,
        onConnect: widget.onConnect,
      ),
    );
  }

  Widget _buildCaptureAndReadControls(bool isDark, bool isDeviceReady) {
    final n = widget.pageCount;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: isDeviceReady ? widget.onCapture : null,
              icon: const Icon(Icons.photo_camera_rounded, size: 20),
              label: const Text(
                'Capture page',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.purple,
                disabledForegroundColor: isDark
                    ? AppColors.darkBorder
                    : AppColors.gray,
                side: BorderSide(
                  color: isDeviceReady
                      ? AppColors.purple
                      : (isDark ? AppColors.darkBorder : AppColors.gray),
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppShapes.buttonRadius),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: n > 0 ? widget.onFinish : null,
              icon: const Icon(Icons.graphic_eq_rounded, size: 20),
              label: Text(
                'Read $n ${n == 1 ? 'page' : 'pages'}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.orange,
                disabledBackgroundColor: isDark
                    ? AppColors.darkBorder
                    : AppColors.gray.withValues(alpha: 0.4),
                foregroundColor: Colors.white,
                disabledForegroundColor: AppColors.darkTextMuted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppShapes.buttonRadius),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OCR FAILURE BANNER
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildOcrFailureBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.danger,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.ocrFailureMessage!,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 6. COMPACT CAPTURED PAGES THUMBNAIL STRIP (Adobe Scan Inspired)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildCapturedPagesSection(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Captured Pages',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: widget.pageCount > 0
                  ? AppColors.purple.withValues(alpha: 0.12)
                  : (isDark ? AppColors.darkBorder : AppColors.cloud),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${widget.pageCount} ${widget.pageCount == 1 ? 'Page' : 'Pages'}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
                color: widget.pageCount > 0
                    ? AppColors.purple
                    : (isDark
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        widget.pageCount == 0
            ? _buildEmptyPagesState(isDark)
            : _buildHorizontalThumbnailsStrip(isDark),
      ],
    );
  }

  Widget _buildEmptyPagesState(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceElevated.withValues(alpha: 0.5)
            : AppColors.cloud.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.document_scanner_rounded,
            size: 18,
            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
          ),
          const SizedBox(width: 8),
          Text(
            'No pages captured yet',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppColors.darkTextMuted
                  : AppColors.lightTextMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalThumbnailsStrip(bool isDark) {
    return SizedBox(
      height: 94,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: widget.pageCount,
        itemBuilder: (context, index) {
          final isSelected = index == _selectedPageIndex;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedPageIndex = index;
              });
              _showPagePreview(index);
            },
            child: Container(
              width: 76,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurfaceElevated
                    : AppColors.lightSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? AppColors.orange
                      : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  width: isSelected ? 2.0 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.article_rounded,
                          size: 18,
                          color: isSelected
                              ? AppColors.orange
                              : (isDark
                                    ? AppColors.purpleMid
                                    : AppColors.purple),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 3,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkBorder
                                : AppColors.gray.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          height: 3,
                          width: 38,
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkBorder
                                : AppColors.gray.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const Spacer(),
                        Center(
                          child: Text(
                            'Page ${index + 1}',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? AppColors.orange
                                  : (isDark
                                        ? AppColors.darkText
                                        : AppColors.charcoal),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Delete Page Button
                  if (widget.onDeletePage != null)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () {
                          widget.onDeletePage!();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 9,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
