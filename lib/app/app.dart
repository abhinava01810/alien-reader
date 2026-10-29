import 'dart:async';

import 'package:flutter/material.dart';

import '../core/constants/app_strings.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_shapes.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import '../features/device/data/raspberry_pi_device.dart';
import '../features/device/domain/reader_device.dart';
import '../features/document/data/models/saved_document.dart';
import '../features/document/data/services/document_storage_service.dart';
import '../features/files/presentation/files_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/output/presentation/output_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/session/data/session_storage.dart';
import '../features/session/presentation/session_start_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../shared/models/document_output.dart';
import '../shared/widgets/alien_header.dart';
import '../shared/widgets/app_bottom_nav.dart';
import '../shared/widgets/section_header.dart';
import '../shared/widgets/splash_screen.dart';
import 'router.dart';

class AlienReaderApp extends StatefulWidget {
  const AlienReaderApp({super.key});

  @override
  State<AlienReaderApp> createState() => _AlienReaderAppState();
}

class _AlienReaderAppState extends State<AlienReaderApp> {
  @override
  void initState() {
    super.initState();
    ThemeController.instance.init();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          title: AppStrings.appName,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeController.instance.themeMode,
          onGenerateRoute: AppRouter.onGenerateRoute,
          home: const SplashGate(child: AppShell()),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final RaspberryPiDevice _device = RaspberryPiDevice();
  final SessionStorage _sessionStorage = SessionStorage();
  final DocumentStorageService _storageService = DocumentStorageService();

  late final StreamSubscription<ReaderConnectionStatus> _statusSub;

  ReaderConnectionStatus _status = ReaderConnectionStatus.disconnected;

  MainTab _tab = MainTab.home;

  int _pageCount = 0;

  bool _sessionStarted = false;
  bool _isLoadingSession = true;
  bool _isCapturing = false;
  bool _isConnecting = false;

  String? _userName;
  String? _ocrFailureMessage;

  @override
  void initState() {
    super.initState();

    _statusSub = _device.status.listen((status) {
      if (mounted) {
        setState(() {
          _status = status;
        });
      }
    });

    _loadSavedSession();
  }

  Future<void> _loadSavedSession() async {
    final userName = await _sessionStorage.getUserName();
    final pageCount = await _sessionStorage.getPageCount();

    if (!mounted) return;

    setState(() {
      _userName = userName;
      _pageCount = pageCount;

      if (userName != null && userName.isNotEmpty) {
        _sessionStarted = true;
      }

      _status = ReaderConnectionStatus.disconnected;
      _isLoadingSession = false;
    });
  }

  @override
  void dispose() {
    _statusSub.cancel();
    _device.dispose();
    super.dispose();
  }

  Future<void> _onSessionStarted(String userName, String? accessToken) async {
    setState(() {
      _userName = userName;
      _sessionStarted = true;
      _status = ReaderConnectionStatus.disconnected;
    });

    await _connect();
  }

  Future<void> _connect() async {
    if (_userName == null || _userName!.isEmpty) {
      return;
    }

    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _status = ReaderConnectionStatus.connecting;
    });

    try {
      await _device.startSession(_userName!);

      await _sessionStorage.saveSession(
        userName: _userName!,
        connected: true,
        pageCount: _pageCount,
      );

      if (!mounted) return;

      setState(() {
        _status = ReaderConnectionStatus.connected;
        _sessionStarted = true;
        _ocrFailureMessage = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to Naadh Reader as $_userName')),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _status = ReaderConnectionStatus.disconnected;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection failed: $e. You can retry anytime.'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  Future<void> _capture() async {
    if (_isCapturing) return;

    if (_status != ReaderConnectionStatus.connected &&
        _status != ReaderConnectionStatus.busy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please connect to the Raspberry Pi first'),
        ),
      );
      return;
    }

    setState(() {
      _isCapturing = true;
      _status = ReaderConnectionStatus.busy;
      _ocrFailureMessage = null;
    });

    final targetPageNumber = _pageCount + 1;
    final navigator = Navigator.of(context);

    // StreamController that feeds live Pi status strings into ProcessingScreen.
    final statusCtrl = StreamController<String>.broadcast();

    // Step 1: Trigger the Pi capture immediately (returns page info + image_url).
    // If this fails, abort before navigating.
    Map<String, dynamic> triggerResult;
    try {
      triggerResult = await _device.triggerCaptureAsync();
    } catch (e) {
      setState(() {
        _isCapturing = false;
        _status = ReaderConnectionStatus.connected;
      });
      await statusCtrl.close();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Capture failed: $e')));
      }
      return;
    }

    final pageNumber =
        (triggerResult['page_number'] as int?) ?? targetPageNumber;
    final imageRelUrl = triggerResult['image_url'] as String?;
    final fullImageUrl = (imageRelUrl != null && imageRelUrl.isNotEmpty)
        ? _device.getFullUrl(imageRelUrl)
        : null;

    // Step 2: Navigate immediately to ProcessingScreen with image + status stream.
    await navigator.pushNamed(
      AppRoutes.processing,
      arguments: ProcessingArgs(
        pageNumber: pageNumber,
        imageUrl: fullImageUrl,
        statusStream: statusCtrl.stream,
        onProcess: () async {
          try {
            // Step 3: Poll Pi until READY (OCR + summary + audio done).
            final captureData = await _device.pollPageUntilReady(
              pageNumber,
              onStatusUpdate: (status) {
                if (!statusCtrl.isClosed) {
                  statusCtrl.add(status);
                }
              },
            );

            if (!mounted) return;

            // Update page count and persist.
            setState(() {
              _pageCount = pageNumber;
              _status = ReaderConnectionStatus.connected;
            });
            await _sessionStorage.savePageCount(pageNumber);

            // Step 4: Build full URLs and navigate to Output.
            await _saveAndNavigateToResults(captureData, pageNumber);
          } on OcrFailureException catch (e) {
            if (mounted) {
              setState(() {
                _ocrFailureMessage = e.message;
                _status = ReaderConnectionStatus.connected;
              });
            }
            rethrow;
          } catch (e) {
            if (mounted) {
              setState(() {
                _status = ReaderConnectionStatus.connected;
              });
            }
            rethrow;
          } finally {
            if (mounted) {
              setState(() {
                _isCapturing = false;
              });
            }
            await statusCtrl.close();
          }
        },
      ),
    );

    // Ensure cleanup if user backed out of the processing screen.
    if (!statusCtrl.isClosed) {
      await statusCtrl.close();
    }
    if (mounted) {
      setState(() {
        _isCapturing = false;
        if (_status == ReaderConnectionStatus.busy) {
          _status = ReaderConnectionStatus.connected;
        }
      });
    }
  }

  Future<void> _saveAndNavigateToResults(
    Map<String, dynamic> capture,
    int pageNumber,
  ) async {
    final imageRawUrl = capture['image_url'] as String?;
    final originalText = ((capture['text'] as String?) ?? '').trim();
    final summaryText = ((capture['summary'] as String?) ?? '').trim();
    final originalAudioRaw = capture['original_audio_url'] as String?;
    final summaryAudioRaw = capture['summary_audio_url'] as String?;

    final fullImageUrl = (imageRawUrl != null && imageRawUrl.isNotEmpty)
        ? _device.getFullUrl(imageRawUrl)
        : null;
    final fullOriginalAudioUrl =
        (originalAudioRaw != null && originalAudioRaw.isNotEmpty)
        ? _device.getFullUrl(originalAudioRaw)
        : null;
    final fullSummaryAudioUrl =
        (summaryAudioRaw != null && summaryAudioRaw.isNotEmpty)
        ? _device.getFullUrl(summaryAudioRaw)
        : null;

    final output = DocumentOutput(
      originalText: originalText.isNotEmpty
          ? originalText
          : 'No readable text was detected in this document.',
      summaryText: summaryText.isNotEmpty
          ? summaryText
          : 'No AI summary could be generated.',
      imageUrl: fullImageUrl,
      originalAudioUrl: fullOriginalAudioUrl,
      summaryAudioUrl: fullSummaryAudioUrl,
    );

    // Auto-save captured document locally to persistent phone storage
    SavedDocument? savedDoc;
    try {
      savedDoc = await _storageService.saveCompleteDocument(
        originalText: output.originalText,
        summaryText: output.summaryText,
        pageNumber: pageNumber,
        imageUrl: output.imageUrl,
        originalAudioUrl: output.originalAudioUrl,
        summaryAudioUrl: output.summaryAudioUrl,
      );
    } catch (e) {
      debugPrint('[AppShell] Auto-save document failed: $e');
    }

    if (!mounted) return;

    // Replace Processing screen with DocumentResults (Output page)
    await Navigator.of(context).pushReplacementNamed(
      AppRoutes.documentResults,
      arguments: DocumentResultsArgs(output: output, savedDocument: savedDoc),
    );
  }

  /// Disconnects from Raspberry Pi hardware and releases controls.
  /// The user stays logged into the application.
  Future<void> _disconnectFromPi() async {
    try {
      await _device.endSession();
    } catch (_) {
      // Clear status locally even if disconnect request errors.
    }

    if (!mounted) return;

    setState(() {
      _status = ReaderConnectionStatus.disconnected;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Disconnected from Raspberry Pi. Hardware controls released.',
        ),
      ),
    );
  }

  /// Signs out of the application and clears session storage.
  Future<void> _signOut() async {
    try {
      await _device.endSession();
    } catch (_) {}

    await _sessionStorage.clearSession();

    if (!mounted) return;

    setState(() {
      _sessionStarted = false;
      _userName = null;
      _pageCount = 0;
      _status = ReaderConnectionStatus.disconnected;
      _tab = MainTab.home;
      _ocrFailureMessage = null;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Signed out successfully.')));
  }

  Future<void> _process() async {
    if (!mounted) return;

    final capture = _device.lastCapture;

    if (capture == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pages captured yet. '
            'Capture a document first.',
          ),
        ),
      );
      return;
    }

    await _saveAndNavigateToResults(capture, _pageCount);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingSession) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_sessionStarted) {
      return SessionStartScreen(onSessionStarted: _onSessionStarted);
    }

    return Scaffold(
      appBar: AlienHeader(onOpenSettings: _openSettings),
      body: IndexedStack(
        index: MainTab.values.indexOf(_tab),
        children: [
          HomeScreen(
            status: _status,
            onConnect: _connect,
            onDisconnect: _disconnectFromPi,
            onCapture: _capture,
            onFinish: _process,
            pageCount: _pageCount,
            ocrFailureMessage: _ocrFailureMessage,
            userName: _userName,
            onOpenFiles: () => setState(() => _tab = MainTab.files),
            onOpenSettings: _openSettings,
            onOpenConnection: _showConnectionDialog,
            onOpenProfile: () => setState(() => _tab = MainTab.profile),
            onDeletePage: () async {
              if (_pageCount <= 0) return;

              final newPageCount = _pageCount - 1;

              setState(() {
                _pageCount = newPageCount;
              });

              await _sessionStorage.savePageCount(newPageCount);
            },
          ),
          OutputScreen(isProcessing: _status == ReaderConnectionStatus.busy),
          FilesScreen(device: _device),
          ProfileScreen(
            userName: _userName,
            status: _status,
            pageCount: _pageCount,
            sessionActive:
                _status == ReaderConnectionStatus.connected ||
                _status == ReaderConnectionStatus.busy,
            onDisconnect: _disconnectFromPi,
            onSignOut: _signOut,
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentTab: _tab,
        onChanged: (tab) {
          setState(() {
            _tab = tab;
          });
        },
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          status: _status,
          statusStream: _device.status,
          onOpenConnection: () => _showConnectionDialog(fromSettings: true),
        ),
      ),
    );
  }

  /// Raspberry Pi connection sheet. Opened from the Home status bar or the
  /// Settings screen; [fromSettings] hides the link back to Settings.
  void _showConnectionDialog({bool fromSettings = false}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final isConnected =
            _status == ReaderConnectionStatus.connected ||
            _status == ReaderConnectionStatus.busy;
        final statusColor = isConnected ? AppColors.success : AppColors.danger;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(
                  title: 'Raspberry Pi Connection',
                  icon: Icons.memory_rounded,
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: context.surface,
                    borderRadius: BorderRadius.circular(AppShapes.cardRadius),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isConnected
                            ? Icons.check_circle_rounded
                            : Icons.cloud_off_rounded,
                        color: statusColor,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isConnected
                                  ? 'Hardware Connected'
                                  : 'Disconnected',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Active User: ${_userName ?? 'Unknown'}',
                              style: TextStyle(
                                fontSize: 13,
                                color: context.mutedText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  height: AppSpacing.buttonHeight,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(
                        context,
                      ).pushNamed(AppRoutes.deviceQrScanner);
                    },
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('SCAN WI-FI / SET UP DEVICE'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.purple,
                      foregroundColor: AppColors.onBrand,
                    ),
                  ),
                ),
                if (isConnected) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: AppSpacing.buttonHeight,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _disconnectFromPi();
                      },
                      icon: const Icon(Icons.link_off_rounded),
                      label: const Text('RELEASE PI / DISCONNECT'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                      ),
                    ),
                  ),
                ],
                if (!fromSettings) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _openSettings();
                    },
                    icon: const Icon(Icons.settings_rounded),
                    label: const Text('All Settings & Preferences'),
                    style: TextButton.styleFrom(
                      foregroundColor: context.accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
