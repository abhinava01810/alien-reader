import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shapes.dart';
import '../../auth/data/services/auth_service.dart';

class SessionStartScreen extends StatefulWidget {
  const SessionStartScreen({
    super.key,
    required this.onSessionStarted,
    this.authService,
  });

  final void Function(String userName, String? accessToken) onSessionStarted;
  final AuthService? authService;

  @override
  State<SessionStartScreen> createState() => _SessionStartScreenState();
}

class _SessionStartScreenState extends State<SessionStartScreen> {
  late final AuthService _authService;

  bool _isRegistering = false;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  // Controllers - Login
  final _loginUserCtrl = TextEditingController();
  final _loginPassCtrl = TextEditingController();
  bool _obscureLoginPass = true;

  // Controllers - Registration
  final _regUserCtrl = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPhoneCtrl = TextEditingController();
  final _regPassCtrl = TextEditingController();
  final _regConfirmPassCtrl = TextEditingController();
  bool _obscureRegPass = true;
  bool _obscureRegConfirmPass = true;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
  }

  @override
  void dispose() {
    _loginUserCtrl.dispose();
    _loginPassCtrl.dispose();
    _regUserCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPhoneCtrl.dispose();
    _regPassCtrl.dispose();
    _regConfirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final username = _loginUserCtrl.text.trim();
    final password = _loginPassCtrl.text;

    if (username.isEmpty) {
      setState(() => _errorMessage = 'Please enter your username.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final user = await _authService.login(
        username: username,
        password: password,
      );
      if (!mounted) return;
      widget.onSessionStarted(user.username, null);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Login failed: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleRegister() async {
    final username = _regUserCtrl.text.trim();
    final email = _regEmailCtrl.text.trim();
    final phone = _regPhoneCtrl.text.trim();
    final password = _regPassCtrl.text;
    final confirmPassword = _regConfirmPassCtrl.text;

    if (username.isEmpty) {
      setState(() => _errorMessage = 'Username is required.');
      return;
    }
    if (email.isEmpty && phone.isEmpty) {
      setState(
        () => _errorMessage =
            'Please provide at least one contact method (email or phone) for account recovery.',
      );
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Password is required.');
      return;
    }
    if (password.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters.');
      return;
    }
    if (password != confirmPassword) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final user = await _authService.register(
        username: username,
        password: password,
        email: email.isNotEmpty ? email : null,
        phone: phone.isNotEmpty ? phone : null,
      );
      if (!mounted) return;
      widget.onSessionStarted(user.username, null);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Registration failed: $e';
        _isLoading = false;
      });
    }
  }

  void _showForgotPasswordDialog() {
    final userCtrl = TextEditingController(text: _loginUserCtrl.text.trim());
    final contactCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    String? dialogError;
    bool isResetting = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.lock_reset_rounded, color: AppColors.purple),
                SizedBox(width: 8),
                Text('Account Recovery', style: TextStyle(fontSize: 18)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Enter your username and registered email or phone number to set a new password.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: userCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contactCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Registered Email or Phone',
                      prefixIcon: Icon(Icons.contact_mail_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPassCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New Password',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPassCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm New Password',
                      prefixIcon: Icon(Icons.check_circle_outline_rounded),
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      dialogError!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('CANCEL'),
              ),
              FilledButton(
                onPressed: isResetting
                    ? null
                    : () async {
                        final u = userCtrl.text.trim();
                        final c = contactCtrl.text.trim();
                        final p = newPassCtrl.text;
                        final cp = confirmPassCtrl.text;

                        if (u.isEmpty || c.isEmpty || p.isEmpty) {
                          setDialogState(() {
                            dialogError = 'Please fill in all recovery fields.';
                          });
                          return;
                        }
                        if (p.length < 6) {
                          setDialogState(() {
                            dialogError =
                                'New password must be at least 6 characters.';
                          });
                          return;
                        }
                        if (p != cp) {
                          setDialogState(() {
                            dialogError = 'Passwords do not match.';
                          });
                          return;
                        }

                        setDialogState(() {
                          isResetting = true;
                          dialogError = null;
                        });

                        try {
                          await _authService.recoverPassword(
                            username: u,
                            contactMethod: c,
                            newPassword: p,
                          );
                          if (!mounted) return;
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                          }
                          setState(() {
                            _successMessage =
                                'Password updated successfully! You can now sign in.';
                            _loginUserCtrl.text = u;
                            _loginPassCtrl.text = p;
                            _isRegistering = false;
                          });
                        } catch (e) {
                          setDialogState(() {
                            isResetting = false;
                            dialogError = e.toString();
                          });
                        }
                      },
                child: isResetting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('RESET PASSWORD'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Alien Innovations Brand Header ─────────────────────
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurfaceElevated
                            : AppColors.purpleLightTint,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.purple.withValues(alpha: 0.12),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/images/alien_innovations_logo.png',
                        width: 72,
                        height: 72,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Welcome to Naadh',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: isDark ? AppColors.darkText : AppColors.purple,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Alien Innovations • Smart Document Reader',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Tab Switcher: Sign In vs Create Account ─────────────
                  Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurfaceElevated
                          : AppColors.lightSurfaceElevated,
                      borderRadius: BorderRadius.circular(
                        AppShapes.buttonRadius,
                      ),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (_isRegistering) {
                                setState(() {
                                  _isRegistering = false;
                                  _errorMessage = null;
                                  _successMessage = null;
                                });
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: !_isRegistering
                                    ? (isDark
                                          ? AppColors.darkSurface
                                          : AppColors.lightSurface)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  AppShapes.buttonRadius - 3,
                                ),
                                boxShadow: !_isRegistering
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.06,
                                          ),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Text(
                                'Sign In',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: !_isRegistering
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: !_isRegistering
                                      ? (isDark
                                            ? AppColors.purpleMid
                                            : AppColors.purple)
                                      : (isDark
                                            ? AppColors.darkTextMuted
                                            : AppColors.lightTextMuted),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (!_isRegistering) {
                                setState(() {
                                  _isRegistering = true;
                                  _errorMessage = null;
                                  _successMessage = null;
                                });
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _isRegistering
                                    ? (isDark
                                          ? AppColors.darkSurface
                                          : AppColors.lightSurface)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  AppShapes.buttonRadius - 3,
                                ),
                                boxShadow: _isRegistering
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.06,
                                          ),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Text(
                                'Create Account',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: _isRegistering
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: _isRegistering
                                      ? (isDark
                                            ? AppColors.purpleMid
                                            : AppColors.purple)
                                      : (isDark
                                            ? AppColors.darkTextMuted
                                            : AppColors.lightTextMuted),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Messages (Error / Success) ─────────────────────────
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.danger.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppColors.danger,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: AppColors.danger,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_successMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_outline_rounded,
                            color: AppColors.success,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _successMessage!,
                              style: const TextStyle(
                                color: AppColors.success,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Form Content ───────────────────────────────────────
                  if (!_isRegistering) ...[
                    // LOGIN FORM
                    TextField(
                      controller: _loginUserCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        hintText: 'Enter your registered username',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _loginPassCtrl,
                      obscureText: _obscureLoginPass,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _handleLogin(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: 'Enter your password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureLoginPass
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureLoginPass = !_obscureLoginPass;
                            });
                          },
                          tooltip: _obscureLoginPass
                              ? 'Show password'
                              : 'Hide password',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _showForgotPasswordDialog,
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('SIGN IN'),
                    ),
                  ] else ...[
                    // REGISTRATION FORM
                    TextField(
                      controller: _regUserCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Username *',
                        hintText: 'e.g. johndoe',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _regEmailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email Address (optional)',
                        hintText: 'name@example.com',
                        prefixIcon: Icon(Icons.email_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _regPhoneCtrl,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number (optional)',
                        hintText: '+1 234 567 890',
                        prefixIcon: Icon(Icons.phone_rounded),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '* At least one recovery contact (email or phone) is required.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark
                              ? AppColors.darkTextMuted
                              : AppColors.lightTextMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _regPassCtrl,
                      obscureText: _obscureRegPass,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Password *',
                        hintText: 'Minimum 6 characters',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureRegPass
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureRegPass = !_obscureRegPass;
                            });
                          },
                          tooltip: _obscureRegPass
                              ? 'Show password'
                              : 'Hide password',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _regConfirmPassCtrl,
                      obscureText: _obscureRegConfirmPass,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _handleRegister(),
                      decoration: InputDecoration(
                        labelText: 'Confirm Password *',
                        hintText: 'Re-enter your password',
                        prefixIcon: const Icon(
                          Icons.check_circle_outline_rounded,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureRegConfirmPass
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureRegConfirmPass = !_obscureRegConfirmPass;
                            });
                          },
                          tooltip: _obscureRegConfirmPass
                              ? 'Show password'
                              : 'Hide password',
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _isLoading ? null : _handleRegister,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('CREATE ACCOUNT'),
                    ),
                  ],

                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'Alien Innovations © 2026 • Secure & Private',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.darkTextMuted.withValues(alpha: 0.6)
                            : AppColors.lightTextMuted.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
