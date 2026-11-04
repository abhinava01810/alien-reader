import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shapes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_dialogs.dart';
import '../../../../shared/widgets/section_header.dart';
import '../../data/models/provisioning_models.dart';
import '../../data/models/saved_device.dart';
import '../../data/services/device_storage_service.dart';
import '../../data/services/network_binding.dart';
import '../../data/services/setup_pairing_service.dart';

enum _Step { joinHotspot, waiting, networks, password, sending, done, failed }

/// Pairs a reader that was identified from its QR code.
///
/// 1. Tell the person to join the reader's setup hotspot by hand.
/// 2. Ask the reader for a setup session (no secret) and wait for its
///    physical button to be pressed.
/// 3. List the Wi-Fi networks the reader can see.
/// 4. Send the chosen network and password to the reader.
///
/// The scanned [deviceId] only labels the setup. Holding the device and
/// pressing its button is what authorises it.
class DevicePairingScreen extends StatefulWidget {
  const DevicePairingScreen({
    super.key,
    required this.deviceId,
    this.service,
    this.binding = const PlatformNetworkBinding(),
    this.storage,
    this.pollInterval = const Duration(seconds: 2),
    this.pollTimeout = const Duration(minutes: 3),
  });

  final String deviceId;

  /// Overrides the service (tests). Otherwise one is built for the address
  /// entered on the first step.
  final SetupPairingService? service;
  final NetworkBinding binding;
  final DeviceStorageService? storage;
  final Duration pollInterval;

  /// Used when the reader does not say how long the pairing window lasts.
  final Duration pollTimeout;

  @override
  State<DevicePairingScreen> createState() => _DevicePairingScreenState();
}

class _DevicePairingScreenState extends State<DevicePairingScreen> {
  static const _minWifiPassword = 8;
  static const _maxWifiPassword = 63;

  final _address = TextEditingController(text: PairingConfig.defaultBaseUrl);
  final _ssid = TextEditingController();
  final _password = TextEditingController();

  SetupPairingService? _ownedService;
  SetupPairingService? _service;

  _Step _step = _Step.joinHotspot;
  bool _busy = false;
  String? _error;
  String _failureTitle = '';
  String _failureMessage = '';

  // Polling
  Timer? _pollTimer;
  bool _pollInFlight = false;
  int _pollAttempts = 0;
  int _pollErrors = 0;
  Duration _pollLimit = Duration.zero;

  // Setup session
  String? _token;
  List<WifiNetworkInfo> _networks = const [];
  WifiNetworkInfo? _selected;
  bool _hidden = false;
  bool _showPassword = false;

  // Result
  String _sentSsid = '';
  String? _deviceMessage;
  bool _contactLost = false;

  bool get _canLeaveFreely =>
      _step == _Step.joinHotspot ||
      _step == _Step.done ||
      _step == _Step.failed;

  @override
  void dispose() {
    _pollTimer?.cancel();
    widget.binding.release();
    _ownedService?.dispose();
    _address.dispose();
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  // ─── Flow ─────────────────────────────────────────────────────────

  String? _normalizedAddress() {
    var text = _address.text.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'http://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    return text;
  }

  Future<void> _beginSession() async {
    final base = _normalizedAddress();
    if (base == null) {
      setState(() {
        _step = _Step.joinHotspot;
        _error = 'Enter a valid device address.';
      });
      return;
    }

    _stopPolling();
    setState(() {
      _step = _Step.joinHotspot;
      _busy = true;
      _error = null;
    });

    await widget.binding.bindToWifi();
    _ownedService?.dispose();
    _ownedService = null;
    _service =
        widget.service ?? (_ownedService = SetupPairingService(baseUrl: base));

    try {
      final session = await _service!.startSession();
      if (!mounted) return;
      if (session.token != null) {
        _token = session.token;
        await _loadNetworks();
        return;
      }
      setState(() {
        _step = _Step.waiting;
        _busy = false;
      });
      _startPolling(session);
    } on SetupRateLimitException catch (e) {
      _showJoinError(e.toString());
    } on SetupAuthException catch (e) {
      _showJoinError(e.toString());
    } on SetupNetworkException catch (e) {
      _showJoinError(
        '$e\nIf Android says the network has no internet, choose to stay '
        'connected.',
      );
    }
  }

  void _showJoinError(String message) {
    if (!mounted) return;
    setState(() {
      _step = _Step.joinHotspot;
      _busy = false;
      _error = message;
    });
  }

  void _startPolling(PairingSession session) {
    _pollAttempts = 0;
    _pollErrors = 0;
    _pollLimit = session.expiresInSeconds != null
        ? Duration(seconds: session.expiresInSeconds! + 15)
        : widget.pollTimeout;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      widget.pollInterval,
      (_) => _pollOnce(session.pendingId),
    );
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollOnce(String pendingId) async {
    // A slow reply must not stack up further requests.
    if (_pollInFlight || _step != _Step.waiting) return;
    _pollInFlight = true;
    try {
      _pollAttempts++;
      if (widget.pollInterval * _pollAttempts > _pollLimit) {
        _stopPolling();
        _fail(
          'Setup timed out',
          'The button was not pressed in time. Start again and press it as '
              'soon as you see the prompt.',
        );
        return;
      }

      final result = await _service!.pollSession(pendingId);
      if (!mounted || _step != _Step.waiting) return;
      _pollErrors = 0;

      switch (result) {
        case PollApproved(:final token):
          _stopPolling();
          _token = token;
          await _loadNetworks();
        case PollExpired():
          _stopPolling();
          _fail(
            'Setup timed out',
            'The confirmation window closed before the button was pressed. '
                'Start again and press it as soon as you see the prompt.',
          );
        case PollDenied():
          _stopPolling();
          _fail(
            'Setup was refused',
            'The device did not accept this setup request. Start again, '
                'and make sure you are pressing the button on the right reader.',
          );
        case PollPending():
          setState(() {});
      }
    } on SetupRateLimitException {
      // Keep waiting; the next tick tries again.
    } on SetupNetworkException catch (e) {
      if (++_pollErrors >= 5 && mounted) {
        _stopPolling();
        _fail('Lost contact with the device', e.toString());
      }
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> _loadNetworks() async {
    if (!mounted) return;
    setState(() {
      _step = _Step.networks;
      _busy = true;
      _error = null;
    });
    try {
      final networks = await _service!.getNetworks(_token!);
      if (!mounted) return;
      setState(() {
        _networks = networks;
        _busy = false;
      });
    } on SetupAuthException {
      _fail(
        'Setup session ended',
        'The device closed the setup session. Start again.',
      );
    } on SetupRateLimitException catch (e) {
      _showNetworkError(e.toString());
    } on SetupNetworkException catch (e) {
      _showNetworkError(e.toString());
    }
  }

  void _showNetworkError(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  void _chooseNetwork(WifiNetworkInfo network) {
    _password.clear();
    setState(() {
      _selected = network;
      _hidden = false;
      _error = null;
      _step = _Step.password;
    });
  }

  void _chooseHiddenNetwork() {
    _password.clear();
    _ssid.clear();
    setState(() {
      _selected = null;
      _hidden = true;
      _error = null;
      _step = _Step.password;
    });
  }

  bool get _isOpenNetwork => !_hidden && (_selected?.isOpen ?? false);

  Future<void> _submitWifi() async {
    final ssid = _hidden ? _ssid.text.trim() : (_selected?.ssid ?? '');
    final password = _isOpenNetwork ? '' : _password.text;

    if (ssid.isEmpty) {
      setState(() => _error = 'Enter the network name.');
      return;
    }
    if (!_isOpenNetwork &&
        (password.length < _minWifiPassword ||
            password.length > _maxWifiPassword)) {
      setState(
        () => _error =
            'Wi-Fi password must be $_minWifiPassword-$_maxWifiPassword '
            'characters.',
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _step = _Step.sending;
      _error = null;
    });

    try {
      final result = await _service!.submitWifi(
        _token!,
        ssid: ssid,
        password: password,
        hidden: _hidden,
      );
      await _finish(ssid, message: result.message, contactLost: false);
    } on DeviceUnreachableException {
      // Expected when the reader drops its hotspot to join the network.
      await _finish(ssid, contactLost: true);
    } on SetupAuthException {
      _fail(
        'Setup session ended',
        'The device closed the setup session before the Wi-Fi details were '
            'accepted. Start again.',
      );
    } on SetupRateLimitException catch (e) {
      _backToPassword(e.toString());
    } on SetupNetworkException catch (e) {
      _backToPassword(e.toString());
    } finally {
      // The password must not outlive the request.
      _password.clear();
    }
  }

  void _backToPassword(String message) {
    if (!mounted) return;
    setState(() {
      _step = _Step.password;
      _error = message;
    });
  }

  Future<void> _finish(
    String ssid, {
    String? message,
    required bool contactLost,
  }) async {
    try {
      // The reader has the details but has not confirmed it joined the
      // network, so the device is recorded as still being set up.
      await (widget.storage ?? DeviceStorageService()).updateDeviceSetupStatus(
        widget.deviceId,
        DeviceSetupStatus.provisioningPending,
      );
    } catch (_) {}
    await widget.binding.release();
    if (!mounted) return;
    setState(() {
      _sentSsid = ssid;
      _deviceMessage = message;
      _contactLost = contactLost;
      _step = _Step.done;
    });
  }

  void _fail(String title, String message) {
    _stopPolling();
    widget.binding.release();
    if (!mounted) return;
    setState(() {
      _failureTitle = title;
      _failureMessage = message;
      _busy = false;
      _step = _Step.failed;
    });
  }

  Future<void> _confirmExit() async {
    final leave = await showConfirmDialog(
      context: context,
      title: 'Stop setup?',
      message:
          'Your reader will stay in setup mode. You can start again from '
          'the beginning at any time.',
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  // ─── UI ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canLeaveFreely,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pair your reader'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close',
            onPressed: _canLeaveFreely
                ? () => Navigator.of(context).pop()
                : _confirmExit,
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Stepper(index: _stepIndex, failed: _step == _Step.failed),
                const SizedBox(height: AppSpacing.lg),
                if (_error != null && _step != _Step.failed) ...[
                  _Banner(_error!),
                  const SizedBox(height: AppSpacing.md),
                ],
                _content(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int get _stepIndex => switch (_step) {
    _Step.joinHotspot => 0,
    _Step.waiting => 1,
    _Step.networks || _Step.password || _Step.sending => 2,
    _Step.done => 4,
    // A failure can only happen while waiting for the button or after it.
    _Step.failed => _token == null ? 1 : 2,
  };

  Widget _content() => switch (_step) {
    _Step.joinHotspot => _joinView(),
    _Step.waiting => _waitingView(),
    _Step.networks => _networksView(),
    _Step.password => _passwordView(),
    _Step.sending => _sendingView(),
    _Step.done => _doneView(),
    _Step.failed => _failedView(),
  };

  Widget _primaryButton({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    bool loading = false,
  }) {
    final child = loading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.onBrand,
            ),
          )
        : Text(label);
    return FilledButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading || icon == null ? const SizedBox.shrink() : Icon(icon),
      label: child,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.purple,
        foregroundColor: AppColors.onBrand,
        minimumSize: const Size.fromHeight(AppSpacing.buttonHeight),
      ),
    );
  }

  Widget _secondaryButton(String label, VoidCallback? onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(AppSpacing.buttonHeight),
      ),
      child: Text(label),
    );
  }

  Widget _heroIcon(IconData icon, Color color) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 48, color: color),
      ),
    );
  }

  Widget _title(String text) => Text(
    text,
    textAlign: TextAlign.center,
    style: Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
  );

  Widget _body(String text) => Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(color: context.mutedText, height: 1.4),
  );

  // Step 1 -----------------------------------------------------------

  Widget _joinView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Row(
            children: [
              Icon(Icons.router_rounded, color: context.accent),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Setting up',
                      style: TextStyle(color: context.mutedText, fontSize: 12),
                    ),
                    Text(
                      widget.deviceId,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Instructions(
          title: 'Join the reader\'s Wi-Fi',
          steps: const [
            'Open your phone\'s Wi-Fi settings.',
            'Join the network named ${PairingConfig.hotspotName}.',
            'If Android says it has no internet, choose to stay connected.',
            'Come back to Naadh and tap Continue.',
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Advanced: device address',
              style: TextStyle(color: context.mutedText, fontSize: 13),
            ),
            children: [
              TextField(
                controller: _address,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Device address',
                  prefixIcon: Icon(Icons.lan_rounded),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _primaryButton(
          label: 'Continue',
          icon: Icons.arrow_forward_rounded,
          loading: _busy,
          onPressed: _beginSession,
        ),
      ],
    );
  }

  // Step 2 -----------------------------------------------------------

  Widget _waitingView() {
    final seconds = (widget.pollInterval * _pollAttempts).inSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heroIcon(Icons.touch_app_rounded, context.accent),
        const SizedBox(height: AppSpacing.lg),
        _title('Press the button on your device to confirm setup'),
        const SizedBox(height: AppSpacing.sm),
        _body(
          'This proves the reader is in your hands. Setup continues '
          'automatically once you press it.',
        ),
        const SizedBox(height: AppSpacing.xl),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppShapes.chipRadius),
          child: LinearProgressIndicator(
            minHeight: 6,
            color: context.accent,
            backgroundColor: context.surfaceElevated,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          seconds > 0 ? 'Waiting… ${seconds}s' : 'Waiting…',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.mutedText, fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.xl),
        _secondaryButton('Cancel', _confirmExit),
      ],
    );
  }

  // Step 3 -----------------------------------------------------------

  Widget _networksView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Choose your Wi-Fi',
          icon: Icons.wifi_rounded,
          trailing: IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Scan again',
            onPressed: _busy ? null : _loadNetworks,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'These are the networks your reader can see.',
          style: TextStyle(color: context.mutedText, fontSize: 13),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xxl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_networks.isEmpty)
          AppCard(
            child: Column(
              children: [
                Icon(
                  Icons.wifi_off_rounded,
                  size: 36,
                  color: context.mutedText,
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text('No networks found'),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: _loadNetworks,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Scan again'),
                ),
              ],
            ),
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < _networks.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      _networks[i].isOpen
                          ? Icons.wifi_rounded
                          : Icons.wifi_lock_rounded,
                      color: context.accent,
                    ),
                    title: Text(
                      _networks[i].ssid,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${_networks[i].security} · '
                      '${_networks[i].signalStrength}% signal',
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: context.mutedText,
                    ),
                    onTap: () => _chooseNetwork(_networks[i]),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        _secondaryButton(
          'Other network (hidden)',
          _busy ? null : _chooseHiddenNetwork,
        ),
      ],
    );
  }

  Widget _passwordView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_hidden)
          TextField(
            controller: _ssid,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Network name',
              prefixIcon: Icon(Icons.wifi_rounded),
            ),
          )
        else
          AppCard(
            child: Row(
              children: [
                Icon(
                  _isOpenNetwork ? Icons.wifi_rounded : Icons.wifi_lock_rounded,
                  color: context.accent,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    _selected?.ssid ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _error = null;
                    _step = _Step.networks;
                  }),
                  child: const Text('Change'),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        if (_isOpenNetwork)
          Text(
            'This network is open, so no password is needed.',
            style: TextStyle(color: context.mutedText),
          )
        else
          TextField(
            controller: _password,
            obscureText: !_showPassword,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _submitWifi(),
            decoration: InputDecoration(
              labelText: 'Wi-Fi password',
              prefixIcon: const Icon(Icons.lock_rounded),
              suffixIcon: IconButton(
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'The password goes straight to your reader. Naadh does not save it.',
          style: TextStyle(color: context.mutedText, fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.xl),
        _primaryButton(
          label: 'Connect',
          icon: Icons.wifi_tethering_rounded,
          onPressed: _submitWifi,
        ),
      ],
    );
  }

  Widget _sendingView() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        children: [
          const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(strokeWidth: 4),
          ),
          const SizedBox(height: AppSpacing.lg),
          _title('Sending Wi-Fi details…'),
          const SizedBox(height: AppSpacing.sm),
          _body('Keep your phone near the reader.'),
        ],
      ),
    );
  }

  // Result -----------------------------------------------------------

  Widget _doneView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heroIcon(
          _contactLost
              ? Icons.signal_wifi_statusbar_connected_no_internet_4_rounded
              : Icons.check_circle_rounded,
          _contactLost ? AppColors.orange : AppColors.success,
        ),
        const SizedBox(height: AppSpacing.lg),
        _title(
          _contactLost ? 'Lost contact with the reader' : 'Wi-Fi details sent',
        ),
        const SizedBox(height: AppSpacing.sm),
        _body(
          _contactLost
              ? 'That is expected if the reader has already left its setup '
                    'hotspot to join "$_sentSsid". Naadh has not confirmed it.'
              : (_deviceMessage?.isNotEmpty == true
                    ? _deviceMessage!
                    : 'The reader is now joining "$_sentSsid". Naadh has not '
                          'confirmed the connection yet.'),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Instructions(
          title: 'What happens next',
          steps: [
            'The reader leaves ${PairingConfig.hotspotName} and joins '
                '"$_sentSsid". Your phone may disconnect from it.',
            'Reconnect your phone to your normal Wi-Fi.',
            'Open Naadh and connect to the reader from Home.',
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        _primaryButton(
          label: 'Done',
          icon: Icons.check_rounded,
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
        ),
      ],
    );
  }

  Widget _failedView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heroIcon(Icons.error_outline_rounded, AppColors.danger),
        const SizedBox(height: AppSpacing.lg),
        _title(_failureTitle),
        const SizedBox(height: AppSpacing.sm),
        _body(_failureMessage),
        const SizedBox(height: AppSpacing.xl),
        _primaryButton(
          label: 'Start again',
          icon: Icons.refresh_rounded,
          onPressed: _beginSession,
        ),
        const SizedBox(height: AppSpacing.sm),
        _secondaryButton('Close', () => Navigator.of(context).pop()),
      ],
    );
  }
}

// ─── Small shared pieces ─────────────────────────────────────────────

class _Stepper extends StatelessWidget {
  const _Stepper({required this.index, required this.failed});

  final int index;
  final bool failed;

  static const _labels = ['Join', 'Confirm', 'Wi-Fi', 'Done'];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${index.clamp(0, 3) + 1} of ${_labels.length}',
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  color: i <= index ? AppColors.success : context.borderColor,
                ),
              ),
            _dot(context, i),
          ],
        ],
      ),
    );
  }

  Widget _dot(BuildContext context, int i) {
    final done = i < index;
    final current = i == index;
    final color = done
        ? AppColors.success
        : current
        ? (failed ? AppColors.danger : context.accent)
        : context.borderColor;
    return Column(
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: color,
          child: done
              ? const Icon(
                  Icons.check_rounded,
                  size: 15,
                  color: AppColors.onBrand,
                )
              : Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: current ? AppColors.onBrand : context.mutedText,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          _labels[i],
          style: TextStyle(
            fontSize: 11,
            fontWeight: current ? FontWeight.w700 : FontWeight.w500,
            color: current ? context.strongText : context.mutedText,
          ),
        ),
      ],
    );
  }
}

class _Instructions extends StatelessWidget {
  const _Instructions({required this.title, required this.steps});

  final String title;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: context.surfaceElevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == steps.length - 1 ? 0 : AppSpacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: context.accent,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onBrand,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        color: context.strongText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
