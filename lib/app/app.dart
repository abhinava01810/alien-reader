import 'dart:async';

import 'package:flutter/material.dart';

import '../core/constants/app_strings.dart';
import '../core/services/auth_service_cloud.dart';
import '../core/services/cloud_api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_shapes.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/verify_email_banner.dart';
import '../features/auth/presentation/verify_email_screen.dart';
import '../features/device/data/device_events.dart';
import '../features/device/data/raspberry_pi_device.dart';
import '../features/device/data/services/device_storage_service.dart';
import '../features/device/data/services/pi_api_service.dart';
import '../features/device/domain/reader_device.dart';
import '../features/document/data/models/saved_document.dart';
import '../features/document/data/services/document_storage_service.dart';
import '../features/files/presentation/files_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/output/presentation/output_screen.dart';
import '../features/phone_processing/data/phone_document_processor.dart';
import '../features/phone_processing/data/phone_processing_settings.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/session/data/session_storage.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../shared/models/document_output.dart';
import '../shared/widgets/alien_header.dart';
import '../shared/widgets/app_bottom_nav.dart';
import '../shared/widgets/section_header.dart';
import '../shared/widgets/splash_screen.dart';
import 'router.dart';

class AlienReaderApp extends StatefulWidget {
  const AlienReaderApp({super.key, this.cloudAuth});

  /// Overrides the cloud auth service (tests).
  final CloudAuthService? cloudAuth;

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
          home: SplashGate(child: AppShell(cloudAuth: widget.cloudAuth)),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.cloudAuth});

  final CloudAuthService? cloudAuth;

  @override
  State<AppShell> createState() => _AppShellState();
}

/// Whether the cloud session is still being checked, valid, or absent.
enum _CloudAuthState { checking, signedIn, signedOut }

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late final CloudAuthService _cloudAuth =
      widget.cloudAuth ?? CloudAuthService();
  StreamSubscription<void>? _sessionExpiredSub;
  StreamSubscription<DeviceChange>? _deviceChangeSub;
  _CloudAuthState _authState = _CloudAuthState.checking;
  CloudUser? _cloudUser;

  final RaspberryPiDevice _device = RaspberryPiDevice();
  final SessionStorage _sessionStorage = SessionStorage();
  final DocumentStorageService _storageService = DocumentStorageService();
  final PhoneProcessingSettings _phoneSettings = PhoneProcessingSettings();
  PhoneDocumentProcessor? _phoneProcessor;

  late final StreamSubscription<ReaderConnectionStatus> _statusSub;

  ReaderConnectionStatus _status = ReaderConnectionStatus.disconnected;

  MainTab _tab = MainTab.home;

  /// The most recent processed capture, handed to the Output tab.
  SavedDocument? _latestOutput;

  int _pageCount = 0;

  /// The last page this app captured on the reader, until the reader reports
  /// it READY or FAILED. The next capture waits for that.
  int? _readerPageInFlight;

  bool _isLoadingSession = true;
  bool _isCapturing = false;
  bool _isConnecting = false;

  String? _userName;
  String? _ocrFailureMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _statusSub = _device.status.listen((status) {
      if (mounted) {
        setState(() {
          _status = status;
        });
      }
    });

    _sessionExpiredSub = _cloudAuth.api.onSessionExpired.listen(
      (_) => _signOut(expired: true),
    );

    _loadSavedSession();
    _checkCloudSession();

    // Pairing confirmed the reader on the home network: show Home and
    // connect, so it is ready to capture.
    _deviceChangeSub = DeviceEvents.changes.listen((change) {
      if (!change.readyToConnect || !mounted) return;
      setState(() => _tab = MainTab.home);
      _connect();
    });
  }

  /// Routes on stored tokens right away, then confirms them with
  /// `GET /auth/me` in the background so a slow backend never blocks launch.
  Future<void> _checkCloudSession() async {
    final hasTokens = await _cloudAuth.isLoggedIn;
    if (!mounted) return;
    setState(() {
      _authState = hasTokens
          ? _CloudAuthState.signedIn
          : _CloudAuthState.signedOut;
    });
    if (!hasTokens) return;

    try {
      final user = await _cloudAuth.getCurrentUser();
      if (!mounted) return;
      setState(() {
        _cloudUser = user;
        _userName = user.name;
      });
    } on SessionExpiredException {
      // onSessionExpired already routes back to login.
    } catch (_) {
      // Offline or cold start: keep the stored session.
    }
  }

  Future<void> _onCloudLoggedIn(CloudUser user) async {
    setState(() {
      _cloudUser = user;
      _authState = _CloudAuthState.signedIn;
    });
    await _sessionStorage.saveSession(
      userName: user.name,
      connected: false,
      pageCount: _pageCount,
    );
    await _onSessionStarted(user.name, null);
  }

  Future<void> _loadSavedSession() async {
    final userName = await _sessionStorage.getUserName();
    final pageCount = await _sessionStorage.getPageCount();

    if (!mounted) return;

    setState(() {
      _userName = userName;
      _pageCount = pageCount;

      _status = ReaderConnectionStatus.disconnected;
      _isLoadingSession = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusSub.cancel();
    _phoneProcessor?.close();
    _sessionExpiredSub?.cancel();
    _deviceChangeSub?.cancel();
    _device.dispose();
    super.dispose();
  }

  Future<void> _onSessionStarted(String userName, String? accessToken) async {
    setState(() {
      _userName = userName;
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
      // A new reader session restarts page numbers and drops older jobs, so
      // pages counted in an earlier session are no longer on the reader.
      _readerPageInFlight = null;
      _pageCount = 0;
      if (mounted) setState(() {});

      await _sessionStorage.saveSession(
        userName: _userName!,
        connected: true,
        pageCount: _pageCount,
      );

      // Home keeps showing this reader (with Reconnect) from now on, even
      // if it was never paired by QR on this phone.
      await DeviceStorageService().markReaderConnected();

      if (!mounted) return;

      setState(() {
        _status = ReaderConnectionStatus.connected;
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkReaderAfterResume();
  }

  /// After the app comes back to the foreground, asks the reader whether
  /// this app's session is still the active one. If the reader restarted,
  /// ended the session or cannot be reached, Home shows Disconnected with
  /// Reconnect instead of a stale "Connected".
  Future<void> _checkReaderAfterResume() async {
    if (_status != ReaderConnectionStatus.connected ||
        _isCapturing ||
        _isConnecting) {
      return;
    }
    final ourSession = _device.sessionId;
    String? lost;
    try {
      final data = await PiApiService().getStatus();
      if (data['status'] != 'APP_ACTIVE') {
        lost = 'The reader ended this session.';
      } else if (ourSession != null && data['session_id'] != ourSession) {
        lost = 'The reader is in another session.';
      }
    } catch (_) {
      lost = "Couldn't reach the reader.";
    }
    if (lost == null || !mounted) return;
    // Only if nothing changed while the reader was being asked.
    if (_status != ReaderConnectionStatus.connected || _isCapturing) return;
    setState(() => _status = ReaderConnectionStatus.disconnected);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$lost Tap Reconnect to continue.')));
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

    // One page at a time on the reader: never trigger the next capture until
    // the reader reports the previous page fully processed.
    if (!await _waitForReaderToFinishPreviousPage()) {
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _status = ReaderConnectionStatus.connected;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'The reader is still working on page $_readerPageInFlight. '
            'Try again in a moment.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;

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
    _readerPageInFlight = pageNumber;
    final imageRelUrl = triggerResult['image_url'] as String?;
    final fullImageUrl = (imageRelUrl != null && imageRelUrl.isNotEmpty)
        ? _device.getFullUrl(imageRelUrl)
        : null;

    // Settings → "Process on phone": OCR, summary and audio for this
    // app-triggered capture run on the phone. Off by default.
    final phoneKey = fullImageUrl == null
        ? null
        : await _phoneSettings.readyKey();
    if (phoneKey != null) {
      await _processOnPhone(
        navigator: navigator,
        statusCtrl: statusCtrl,
        imageUrl: fullImageUrl!,
        pageNumber: pageNumber,
        geminiKey: phoneKey,
      );
      return;
    }

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

  /// Waits until the reader reports the last page this app captured as
  /// READY or FAILED, i.e. its OCR, summary and audio are finished.
  ///
  /// The reader processes every app capture itself, including when the phone
  /// does its own processing ("Process on phone"), and it cannot take a new
  /// capture while busy. Returns false if the page is still not finished
  /// after [limit]; the caller must not capture then.
  Future<bool> _waitForReaderToFinishPreviousPage({
    Duration interval = const Duration(seconds: 2),
    Duration limit = const Duration(minutes: 6),
  }) async {
    final page = _readerPageInFlight;
    if (page == null) return true;

    final watch = Stopwatch()..start();
    var missing = 0;
    var told = false;
    while (watch.elapsed < limit) {
      final data = await _device.getCaptureDetails(page);
      final status = (data?['status'] as String? ?? '').toUpperCase();
      if (status == 'READY' || status == 'FAILED') {
        _readerPageInFlight = null;
        return true;
      }
      if (data == null) {
        // Gone from the reader (new session or restart). A short network
        // blip also lands here, so require several misses in a row.
        if (++missing >= 5) {
          _readerPageInFlight = null;
          return true;
        }
      } else {
        missing = 0;
      }
      if (!told && mounted) {
        told = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Waiting for the reader to finish page $page before the next '
              'capture…',
            ),
          ),
        );
      }
      await Future<void>.delayed(interval);
    }
    return false;
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
    await _saveOutputAndShowResults(output, pageNumber);
  }

  /// App-mode capture processed on the phone: fetch the photo, OCR, Gemini
  /// summary and TTS audio all happen here; the Pi only took the picture.
  Future<void> _processOnPhone({
    required NavigatorState navigator,
    required StreamController<String> statusCtrl,
    required String imageUrl,
    required int pageNumber,
    required String geminiKey,
  }) async {
    await navigator.pushNamed(
      AppRoutes.processing,
      arguments: ProcessingArgs(
        pageNumber: pageNumber,
        imageUrl: imageUrl,
        statusStream: statusCtrl.stream,
        onPhone: true,
        onProcess: () async {
          try {
            final result = await (_phoneProcessor ??= PhoneDocumentProcessor())
                .process(
                  imageUrl: imageUrl,
                  pageNumber: pageNumber,
                  geminiKey: geminiKey,
                  onStatus: (status) {
                    if (!statusCtrl.isClosed) statusCtrl.add(status);
                  },
                );
            if (!mounted) return;
            setState(() {
              _pageCount = pageNumber;
              _status = ReaderConnectionStatus.connected;
            });
            await _sessionStorage.savePageCount(pageNumber);
            await _saveOutputAndShowResults(
              DocumentOutput(
                originalText: result.text,
                summaryText: result.summary,
                imageUrl: Uri.file(result.imagePath).toString(),
                originalAudioUrl: Uri.file(result.originalAudioPath).toString(),
                summaryAudioUrl: result.summaryAudioPath == null
                    ? null
                    : Uri.file(result.summaryAudioPath!).toString(),
              ),
              pageNumber,
            );
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
              setState(() => _status = ReaderConnectionStatus.connected);
            }
            rethrow;
          } finally {
            if (mounted) setState(() => _isCapturing = false);
            await statusCtrl.close();
          }
        },
      ),
    );

    if (!statusCtrl.isClosed) await statusCtrl.close();
    if (mounted) {
      setState(() {
        _isCapturing = false;
        if (_status == ReaderConnectionStatus.busy) {
          _status = ReaderConnectionStatus.connected;
        }
      });
    }
  }

  Future<void> _saveOutputAndShowResults(
    DocumentOutput output,
    int pageNumber,
  ) async {
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

    if (savedDoc == null) {
      // Not saved, so the Output tab cannot load it: show this result on
      // its own page instead.
      await Navigator.of(context).pushReplacementNamed(
        AppRoutes.documentResults,
        arguments: DocumentResultsArgs(output: output, savedDocument: savedDoc),
      );
      return;
    }

    // Close the Processing screen and land on the Output tab with this result.
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      _latestOutput = savedDoc;
      _tab = MainTab.output;
    });
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
  /// Ends the Pi session and the cloud session, then shows login.
  /// [expired] means the tokens were already rejected and cleared.
  Future<void> _signOut({bool expired = false}) async {
    if (_authState == _CloudAuthState.signedOut) return;

    try {
      await _device.endSession();
    } catch (_) {}

    if (!expired) await _cloudAuth.logout();

    await _sessionStorage.clearSession();

    if (!mounted) return;

    setState(() {
      _authState = _CloudAuthState.signedOut;
      _cloudUser = null;
      _userName = null;
      _pageCount = 0;
      _status = ReaderConnectionStatus.disconnected;
      _tab = MainTab.home;
      _ocrFailureMessage = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          expired
              ? 'Your session expired. Please log in again.'
              : 'Signed out successfully.',
        ),
      ),
    );
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
    if (_isLoadingSession || _authState == _CloudAuthState.checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_authState == _CloudAuthState.signedOut) {
      return LoginScreen(auth: _cloudAuth, onLoggedIn: _onCloudLoggedIn);
    }

    final user = _cloudUser;
    final needsVerify = user != null && !user.emailVerified;
    return Scaffold(
      appBar: AlienHeader(onOpenSettings: _openSettings),
      body: Column(
        children: [
          if (needsVerify)
            VerifyEmailBanner(
              email: user.email,
              onVerifyNow: () => _openVerifyEmail(user.email),
            ),
          Expanded(child: _tabs()),
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

  /// Back to the 6-digit code screen for an account that has not verified
  /// its email yet (it has Resend code for an expired or lost code).
  Future<void> _openVerifyEmail(String email) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => VerifyEmailScreen(
          email: email,
          auth: _cloudAuth,
          onVerified: (user) async {
            if (mounted) setState(() => _cloudUser = user);
            navigator.pop();
            messenger.showSnackBar(
              const SnackBar(content: Text('Email verified.')),
            );
          },
        ),
      ),
    );
  }

  Widget _tabs() {
    return IndexedStack(
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
        OutputScreen(
          isProcessing: _status == ReaderConnectionStatus.busy,
          latestDocument: _latestOutput,
        ),
        FilesScreen(device: _device),
        ProfileScreen(
          userName: _userName,
          cloudUser: _cloudUser,
          cloudAuth: _cloudAuth,
          status: _status,
          pageCount: _pageCount,
          sessionActive:
              _status == ReaderConnectionStatus.connected ||
              _status == ReaderConnectionStatus.busy,
          onDisconnect: _disconnectFromPi,
          onSignOut: _signOut,
        ),
      ],
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
