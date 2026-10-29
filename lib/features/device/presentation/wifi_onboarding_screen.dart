import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/pi_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shapes.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/models/provisioning_models.dart';
import '../data/models/saved_device.dart';
import '../data/services/device_storage_service.dart';
import '../data/services/pi_api_service.dart';

enum WifiOnboardingStep {
  enterSecret,
  selectNetwork,
  enterPassword,
  connecting,
  success,
  failed,
}

/// Screen handling the multi-step Wi-Fi onboarding workflow with the Raspberry Pi.
///
/// Flow:
/// 1. Enter device-specific setup PIN or secret (`POST /api/setup/session`).
/// 2. Inspect setup status (`GET /api/setup/status`) and scan networks (`GET /api/setup/networks`).
/// 3. Detect and honestly present mock/simulated mode vs live mode.
/// 4. Select SSID & enter password (`POST /api/setup/wifi`).
/// 5. Bounded polling of connection status (`GET /api/setup/connection-status`) with cancellation.
/// 6. Display clear success/failure/rollback states and store device state.
class WifiOnboardingScreen extends StatefulWidget {
  const WifiOnboardingScreen({
    super.key,
    required this.deviceId,
    this.apiService,
    this.storageService,
    this.customBaseUrl,
  });

  final String deviceId;
  final PiApiService? apiService;
  final DeviceStorageService? storageService;
  final String? customBaseUrl;

  @override
  State<WifiOnboardingScreen> createState() => _WifiOnboardingScreenState();
}

class _WifiOnboardingScreenState extends State<WifiOnboardingScreen>
    with WidgetsBindingObserver {
  late final PiApiService _apiService;
  late final DeviceStorageService _storageService;

  WifiOnboardingStep _currentStep = WifiOnboardingStep.enterSecret;

  // Controllers
  final _secretController = TextEditingController();
  final _passwordController = TextEditingController();
  final _customSsidController = TextEditingController();

  bool _obscureSecret = true;
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  // Session state
  String? _sessionToken;
  SetupStatusModel? _setupStatus;
  List<WifiNetworkInfo> _networks = [];
  WifiNetworkInfo? _selectedNetwork;
  bool _isManualSsid = false;

  // Polling state
  Timer? _pollingTimer;
  int _pollAttempts = 0;
  static const int _maxPollAttempts = 30; // 30 * 2s = 60s max
  ConnectionStatusModel? _lastConnectionStatus;

  String get _baseUrl => widget.customBaseUrl ?? PiConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiService = widget.apiService ?? PiApiService();
    _storageService = widget.storageService ?? DeviceStorageService();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Cancel active polling if user leaves the app
      _stopPolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    _secretController.dispose();
    _passwordController.dispose();
    _customSsidController.dispose();
    if (widget.apiService == null) {
      _apiService.dispose();
    }
    super.dispose();
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  // ------------------------------------------------------------
  // STEP 1: Authenticate Setup Session
  // ------------------------------------------------------------
  Future<void> _authenticate() async {
    final secret = _secretController.text.trim();
    if (secret.isEmpty) {
      setState(
        () => _errorMessage = 'Please enter the device setup PIN or secret.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final session = await _apiService.createSetupSession(
        secret,
        baseUrl: _baseUrl,
      );

      _sessionToken = session.token;

      // Immediately fetch setup status to detect mock vs live backend
      final status = await _apiService.getSetupStatus(baseUrl: _baseUrl);
      _setupStatus = status;

      // Scan available networks
      await _loadNetworks();

      if (!mounted) return;
      setState(() {
        _currentStep = WifiOnboardingStep.selectNetwork;
        _isLoading = false;
      });
    } on SetupAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } on SetupRateLimitException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } on SetupNetworkException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            '${e.message}\nMake sure your phone is connected to the Naadh device hotspot.';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Authentication error: $e';
        _isLoading = false;
      });
    }
  }

  // ------------------------------------------------------------
  // STEP 2: Load Available Networks
  // ------------------------------------------------------------
  Future<void> _loadNetworks() async {
    if (_sessionToken == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final networks = await _apiService.getAvailableNetworks(
        _sessionToken!,
        baseUrl: _baseUrl,
      );

      if (!mounted) return;
      setState(() {
        _networks = networks;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to scan networks: $e';
        _isLoading = false;
      });
    }
  }

  // ------------------------------------------------------------
  // STEP 3: Submit Wi-Fi Credentials
  // ------------------------------------------------------------
  Future<void> _submitWifi() async {
    final ssid = _isManualSsid
        ? _customSsidController.text.trim()
        : (_selectedNetwork?.ssid ?? '');

    if (ssid.isEmpty) {
      setState(() => _errorMessage = 'Please enter or select a Wi-Fi network.');
      return;
    }

    final password = _passwordController.text;
    final isOpen = _selectedNetwork?.isOpen == true;

    if (!isOpen && password.length < 8) {
      setState(
        () => _errorMessage = 'Wi-Fi password must be at least 8 characters.',
      );
      return;
    }

    setState(() {
      _currentStep = WifiOnboardingStep.connecting;
      _isLoading = true;
      _errorMessage = null;
      _pollAttempts = 0;
    });

    try {
      await _apiService.provisionWifi(
        _sessionToken!,
        ssid: ssid,
        password: password,
        hidden: _isManualSsid,
        timeoutSeconds: 30,
        baseUrl: _baseUrl,
      );

      // SECURITY: Clear password immediately after submission. Never store it.
      _passwordController.clear();

      // Begin polling connection status
      _startPolling();
    } on SetupAuthException {
      if (!mounted) return;
      setState(() {
        _currentStep = WifiOnboardingStep.enterSecret;
        _errorMessage =
            'Your setup session expired. Please re-enter your setup PIN.';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _currentStep = WifiOnboardingStep.failed;
        _errorMessage = 'Failed to submit Wi-Fi configuration: $e';
        _isLoading = false;
      });
    }
  }

  // ------------------------------------------------------------
  // STEP 4: Poll Connection Status
  // ------------------------------------------------------------
  void _startPolling() {
    _stopPolling();
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      _pollAttempts++;

      if (_pollAttempts > _maxPollAttempts) {
        _stopPolling();
        if (!mounted) return;
        setState(() {
          _currentStep = WifiOnboardingStep.failed;
          _errorMessage =
              'Connection attempt timed out after 60 seconds. The device did not confirm a successful connection.';
        });
        return;
      }

      try {
        final status = await _apiService.getConnectionStatus(
          _sessionToken!,
          baseUrl: _baseUrl,
        );

        if (!mounted) return;
        setState(() {
          _lastConnectionStatus = status;
        });

        if (status.isConnected) {
          _stopPolling();
          await _onProvisioningSuccess(status);
        } else if (status.isFailed) {
          _stopPolling();
          setState(() {
            _currentStep = WifiOnboardingStep.failed;
            _errorMessage =
                status.errorReason ??
                (status.isRollback
                    ? 'Connection failed. The device safely restored its previous hotspot mode.'
                    : 'The device failed to connect to the selected Wi-Fi network.');
          });
        }
      } catch (e) {
        // Network hiccups during hotspot-to-STA transition are expected.
        // Keep polling until max attempts.
      }
    });
  }

  Future<void> _onProvisioningSuccess(ConnectionStatusModel status) async {
    final isMock = status.isMockMode || (_setupStatus?.isMockMode == true);

    // Save device configuration state locally
    await _storageService.updateDeviceSetupStatus(
      widget.deviceId,
      isMock
          ? DeviceSetupStatus.identifiedNotConfigured
          : DeviceSetupStatus.configured,
      lastKnownAddress: status.ipAddress,
    );
    await _storageService.setActiveDeviceId(widget.deviceId);

    if (!mounted) return;
    setState(() {
      _currentStep = WifiOnboardingStep.success;
      _isLoading = false;
    });
  }

  // ------------------------------------------------------------
  // Cancel Setup Session
  // ------------------------------------------------------------
  Future<void> _cancelSetup() async {
    _stopPolling();
    if (_sessionToken != null) {
      await _apiService.cancelSetupSession(_sessionToken!, baseUrl: _baseUrl);
      _sessionToken = null;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // ------------------------------------------------------------
  // UI Builders
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _showExitConfirmationDialog();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Wi-Fi Setup'),
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancel Setup',
            onPressed: _showExitConfirmationDialog,
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildProgressStepper(),
                const SizedBox(height: AppSpacing.md),
                if (_setupStatus?.isMockMode == true ||
                    _lastConnectionStatus?.isMockMode == true)
                  _buildMockModeNotice(),
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _buildErrorBanner(),
                ],
                const SizedBox(height: AppSpacing.md),
                _buildCurrentStepContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMockModeNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        border: Border.all(color: AppColors.orange, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.science_rounded, color: AppColors.orange, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Simulated / Demo Mode Active',
                  style: TextStyle(
                    color: AppColors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'The Raspberry Pi backend has live network mutations disabled (development environment). Displayed Wi-Fi networks and connection states are simulated and will not reconfigure actual physical networking.',
                  style: TextStyle(
                    color: AppColors.charcoal.withValues(alpha: 0.85),
                    fontSize: 11.5,
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

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.danger,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage ?? '',
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

  Widget _buildProgressStepper() {
    final stepIndex = switch (_currentStep) {
      WifiOnboardingStep.enterSecret => 0,
      WifiOnboardingStep.selectNetwork => 1,
      WifiOnboardingStep.enterPassword => 1,
      WifiOnboardingStep.connecting => 2,
      WifiOnboardingStep.success => 3,
      WifiOnboardingStep.failed => 2,
    };

    final steps = ['PIN Auth', 'Select Network', 'Connecting', 'Complete'];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.cloud.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: steps.asMap().entries.map((entry) {
          final idx = entry.key;
          final title = entry.value;
          final isDone = idx < stepIndex;
          final isCurrent = idx == stepIndex;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: isDone
                            ? AppColors.success
                            : (isCurrent ? AppColors.purple : AppColors.gray),
                        child: Icon(
                          isDone ? Icons.check_rounded : Icons.circle_rounded,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: isCurrent
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isCurrent
                              ? AppColors.purple
                              : AppColors.charcoal,
                        ),
                      ),
                    ],
                  ),
                ),
                if (idx < steps.length - 1)
                  Container(
                    width: 12,
                    height: 2,
                    color: isDone ? AppColors.success : AppColors.gray,
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCurrentStepContent() {
    return switch (_currentStep) {
      WifiOnboardingStep.enterSecret => _buildEnterSecretView(),
      WifiOnboardingStep.selectNetwork => _buildSelectNetworkView(),
      WifiOnboardingStep.enterPassword => _buildEnterPasswordView(),
      WifiOnboardingStep.connecting => _buildConnectingView(),
      WifiOnboardingStep.success => _buildSuccessView(),
      WifiOnboardingStep.failed => _buildFailedView(),
    };
  }

  // View: Enter PIN / Secret
  Widget _buildEnterSecretView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.purple.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(AppShapes.cardRadius),
            border: Border.all(color: AppColors.purple.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.fingerprint_rounded,
                    color: AppColors.purple,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Device Authentication',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.purple,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Device ID: ${widget.deviceId}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Enter the physical setup PIN or secret printed on the device label to authenticate local provisioning.',
                style: TextStyle(
                  fontSize: 12,
                  color: context.mutedText,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _secretController,
          obscureText: _obscureSecret,
          decoration: InputDecoration(
            labelText: 'Device Setup PIN or Secret',
            hintText: 'e.g. 123456 or device secret',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureSecret
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
              tooltip: _obscureSecret ? 'Show PIN' : 'Hide PIN',
              onPressed: () => setState(() => _obscureSecret = !_obscureSecret),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Note: Credentials are sent directly to the local Raspberry Pi over plain HTTP setup transport without intermediate cloud storage.',
          style: TextStyle(fontSize: 11, color: context.mutedText),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: _isLoading ? null : _authenticate,
          icon: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.login_rounded),
          label: Text(_isLoading ? 'AUTHENTICATING…' : 'AUTHENTICATE DEVICE'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.purple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppShapes.buttonRadius),
            ),
          ),
        ),
      ],
    );
  }

  // View: Select Network
  Widget _buildSelectNetworkView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Available Wi-Fi Networks',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.charcoal,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              tooltip: 'Rescan Wi-Fi Networks',
              onPressed: _isLoading ? null : _loadNetworks,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text(
                    'Scanning for nearby networks…',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          )
        else if (_networks.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.cloud.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.wifi_off_rounded,
                  size: 36,
                  color: context.mutedText,
                ),
                const SizedBox(height: 8),
                const Text(
                  'No networks found nearby.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loadNetworks,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Scan Again'),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _networks.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final net = _networks[index];
              return ListTile(
                leading: Icon(
                  net.isOpen ? Icons.wifi_rounded : Icons.wifi_lock_rounded,
                  color: AppColors.purple,
                ),
                title: Text(
                  net.ssid,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  '${net.security} • ${net.signalStrength}% signal',
                  style: const TextStyle(fontSize: 11.5),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  setState(() {
                    _selectedNetwork = net;
                    _isManualSsid = false;
                    _errorMessage = null;
                    if (net.isOpen) {
                      _submitWifi();
                    } else {
                      _currentStep = WifiOnboardingStep.enterPassword;
                    }
                  });
                },
              );
            },
          ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _isManualSsid = true;
              _selectedNetwork = null;
              _currentStep = WifiOnboardingStep.enterPassword;
            });
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add Hidden / Custom Network'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppShapes.buttonRadius),
            ),
          ),
        ),
      ],
    );
  }

  // View: Enter Password
  Widget _buildEnterPasswordView() {
    final ssid = _isManualSsid
        ? 'Custom Network'
        : (_selectedNetwork?.ssid ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isManualSsid) ...[
          TextField(
            controller: _customSsidController,
            decoration: InputDecoration(
              labelText: 'Network Name (SSID)',
              hintText: 'Enter Wi-Fi network name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              prefixIcon: const Icon(Icons.wifi_rounded),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cloud.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.wifi_rounded, color: AppColors.purple),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    ssid,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(
                    () => _currentStep = WifiOnboardingStep.selectNetwork,
                  ),
                  child: const Text('Change'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'Wi-Fi Password',
            hintText: 'Enter network passphrase',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
              tooltip: _obscurePassword ? 'Show Password' : 'Hide Password',
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Security Note: Wi-Fi passwords are transmitted to the reader and immediately wiped from app memory. Passwords are never saved in storage or telemetry.',
          style: TextStyle(fontSize: 11, color: context.mutedText),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: _isLoading ? null : _submitWifi,
          icon: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.wifi_rounded),
          label: const Text('CONNECT DEVICE TO WI-FI'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.purple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppShapes.buttonRadius),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          onPressed: () =>
              setState(() => _currentStep = WifiOnboardingStep.selectNetwork),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppShapes.buttonRadius),
            ),
          ),
          child: const Text('Back to Network List'),
        ),
      ],
    );
  }

  // View: Connecting & Polling
  Widget _buildConnectingView() {
    final ssid = _isManualSsid
        ? _customSsidController.text.trim()
        : (_selectedNetwork?.ssid ?? '');

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
        child: Column(
          children: [
            const SizedBox(
              width: 56,
              height: AppSpacing.buttonHeight,
              child: CircularProgressIndicator(
                strokeWidth: 3.5,
                color: AppColors.purple,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Connecting to $ssid',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Attempt $_pollAttempts of $_maxPollAttempts…\nThe Raspberry Pi is applying the network configuration and verifying connection.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: context.mutedText,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton.icon(
              onPressed: _cancelSetup,
              icon: const Icon(Icons.cancel_rounded),
              label: const Text('Cancel Connection Attempt'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // View: Success
  Widget _buildSuccessView() {
    final isMock =
        _lastConnectionStatus?.isMockMode == true ||
        (_setupStatus?.isMockMode == true);
    final assignedIp = _lastConnectionStatus?.ipAddress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_outline_rounded,
            color: AppColors.success,
            size: 56,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          isMock
              ? 'Simulated Wi-Fi Setup Complete'
              : 'Wi-Fi Configuration Succeeded!',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isMock
              ? 'The device successfully executed the simulated connection handshake with the test backend.'
              : 'Your Naadh reader is now configured to connect to your local Wi-Fi.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: context.mutedText),
        ),
        if (assignedIp != null && assignedIp.isNotEmpty && !isMock) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cloud,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lan_rounded,
                  size: 18,
                  color: AppColors.purple,
                ),
                const SizedBox(width: 8),
                Text(
                  'Assigned IP: $assignedIp',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cloud.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppShapes.cardRadius),
            border: Border.all(color: AppColors.gray),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Next Steps:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                '1. Ensure your phone reconnects to your home Wi-Fi network.\n'
                '2. The reader is saved in your device list.\n'
                '3. Open Naadh and tap Connect to begin scanning.',
                style: TextStyle(
                  fontSize: 12,
                  color: context.strongText,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          icon: const Icon(Icons.home_rounded),
          label: const Text('RETURN TO APPLICATION'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.purple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppShapes.buttonRadius),
            ),
          ),
        ),
      ],
    );
  }

  // View: Failed
  Widget _buildFailedView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.error_outline_rounded,
            color: AppColors.danger,
            size: 56,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Wi-Fi Connection Failed',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage ?? 'The device was unable to establish a connection.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: context.mutedText),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: () {
            setState(() {
              _errorMessage = null;
              _currentStep = WifiOnboardingStep.selectNetwork;
            });
          },
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('TRY AGAIN'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.purple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppShapes.buttonRadius),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          onPressed: _cancelSetup,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppShapes.buttonRadius),
            ),
          ),
          child: const Text('Cancel Setup'),
        ),
      ],
    );
  }

  void _showExitConfirmationDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Setup?'),
        content: const Text(
          'If you exit now, any active provisioning session will be cancelled and Wi-Fi configuration will not be applied.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Continue Setup'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _cancelSetup();
            },
            child: const Text(
              'Exit',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
