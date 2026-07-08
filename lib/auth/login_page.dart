import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'admin_access.dart';
import 'auth_email_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  @override
  void initState() {
    super.initState();
    _checkBiometrics();
    _checkDeviceSupport();
  }

  Future<void> _checkBiometrics() async {
    try {
      final canCheck = await auth.canCheckBiometrics;
      final available = await auth.getAvailableBiometrics();
      if (!mounted) return;
      setState(() {
        _canCheckBiometrics = canCheck;
        _hasBiometrics = available.isNotEmpty;
        _biometricError = '';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _canCheckBiometrics = false;
        _hasBiometrics = false;
        _biometricError = e.message ?? 'Biometric error';
      });
    }
  }

  Future<void> _checkDeviceSupport() async {
    final isSupported = await auth.isDeviceSupported();
    if (!isSupported && mounted) {
      setState(() {
        _biometricError =
            'Biometric authentication not supported on this device';
      });
    }
  }

  // Defined at class level — NOT inside build().
  Future<void> _authenticateWithBiometrics() async {
    setState(() => errorMessage = '');
    try {
      final didAuthenticate = await auth.authenticate(
        localizedReason: 'Please authenticate to login',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );
      if (didAuthenticate) {
        try {
          final email = await secureStorage.read(key: 'email') ?? '';
          final password = await secureStorage.read(key: 'password') ?? '';
          if (email.isNotEmpty && password.isNotEmpty) {
            emailController.text = email;
            passwordController.text = password;
            await _handleAuthentication();
          } else {
            setState(() {
              errorMessage =
                  'No saved credentials found. Please login once with email and password first.';
            });
          }
        } catch (storageError) {
          setState(() {
            errorMessage =
                'Unable to retrieve saved credentials. Please login with email and password.';
          });
        }
      } else {
        setState(() => errorMessage = 'Biometric authentication failed.');
      }
    } on PlatformException catch (e) {
      setState(() => errorMessage = e.message ?? 'Biometric error');
    } catch (e) {
      setState(() => errorMessage = 'Authentication error. Please try again.');
    }
  }

  final LocalAuthentication auth = LocalAuthentication();
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  bool _canCheckBiometrics = false;
  bool _hasBiometrics = false;
  String _biometricError = '';
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool isLoading = false;
  bool isSendingResetEmail = false;
  bool isSendingVerificationEmail = false;
  String errorMessage = '';
  String successMessage = '';
  bool _obscurePassword = true;

  final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$',
  );

  final List<String> _disposableDomains = [
    'mailinator.com',
    'guerrillamail.com',
    '10minutemail.com',
    'throwawaymail.com',
    'yopmail.com',
    'trashmail.com',
  ];

  bool _isValidEmail(String email) {
    if (!_emailRegex.hasMatch(email)) return false;
    if (email.contains(' ')) return false;
    if (email.startsWith('.') || email.endsWith('.')) return false;

    final parts = email.split('@');
    if (parts.length != 2) return false;

    final domain = parts[1].toLowerCase();
    final domainParts = domain.split('.');
    if (domainParts.length < 2) return false;
    if (domainParts.any((part) => part.isEmpty)) return false;

    return !_disposableDomains.contains(domain);
  }

  Future<bool> _isEmailVerifiedStrict(User user) async {
    await user.reload();
    final refreshedUser = _auth.currentUser;
    if (refreshedUser == null) return false;

    final tokenResult = await refreshedUser.getIdTokenResult(true);
    final tokenVerified = tokenResult.claims?['email_verified'] == true;
    return refreshedUser.emailVerified && tokenVerified;
  }

  Future<bool> _verifyEmailWithAPI(String email) async {
    const bool isDebugMode = bool.fromEnvironment('dart.vm.product');
    if (isDebugMode) return true;

    const apiKey = 'YOUR_API_KEY';
    final url = Uri.parse(
        'https://emailvalidation.abstractapi.com/v1/?api_key=$apiKey&email=$email');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final isValid = data['is_valid_format']['value'] ?? true;
        final isDisposable =
            data['is_disposable_email']['value'] ?? false;
        return isValid && !isDisposable;
      }
      return _isValidEmail(email);
    } catch (e) {
      return _isValidEmail(email);
    }
  }

  Future<User> _requireVerifiedUser(User user) async {
    final refreshedUser = _auth.currentUser;

    if (refreshedUser == null) {
      throw Exception('Authentication failed. Please try again.');
    }

    final verified = await _isEmailVerifiedStrict(refreshedUser);
    if (!verified) {
      try {
        final currentEmail = refreshedUser.email;
        if (currentEmail != null && currentEmail.trim().isNotEmpty) {
          await AuthEmailService.sendVerificationEmail(
            email: currentEmail,
          );
        }
      } catch (_) {
        // Best effort only; user can still use explicit resend.
      }
      await _auth.signOut();
      throw Exception('Please verify your email before logging in. A new verification email has been sent.');
    }

    return refreshedUser;
  }

  Future<void> _handleAuthentication() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      errorMessage = '';
      successMessage = '';
    });

    // _login() manages isLoading via its own finally block.
    await _login();
  }

  Future<void> _login() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
      successMessage = '';
    });

    try {
      final email = emailController.text.trim();
      final password = passwordController.text.trim();

      UserCredential userCredential =
          await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final verifiedUser =
          await _requireVerifiedUser(userCredential.user!);

      // Double-check immediately before route navigation.
      final stillVerified = await _isEmailVerifiedStrict(verifiedUser);
      if (!stillVerified) {
        await _auth.signOut();
        throw Exception('Please verify your email before logging in.');
      }

      final userDoc = await _firestore
          .collection('users')
          .doc(verifiedUser.uid)
          .get();

      if (!userDoc.exists) {
        await _auth.signOut();
        throw Exception("User record not found");
      }

      final data = userDoc.data() as Map<String, dynamic>? ?? {};

      final isActive = data['isActive'] ?? true;
      if (!isActive) {
        await _auth.signOut();
        throw Exception("Your account has been deactivated. Please contact support.");
      }

      final role = data['role'] ?? 'client';
      final emailFromDoc = (data['email'] ?? verifiedUser.email ?? '').toString();
      final userName = emailFromDoc.split('@').first;

      await _navigateBasedOnRole(role, userName, emailFromDoc);
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      if (e is FirebaseAuthException) {
        setState(() => errorMessage = _getErrorMessage(e.code));
      } else if (msg.contains('credential') || msg.contains('malformed')) {
        setState(() => errorMessage = 'Incorrect email or password. Please check your details and try again.');
      } else if (msg.toLowerCase().contains('deactivated')) {
        setState(() => errorMessage =
            'Your account has been deactivated. Please contact support.');
      } else if (msg.toLowerCase().contains('verify your email')) {
        setState(() => errorMessage = msg);
      } else {
        setState(() => errorMessage = msg.isNotEmpty
            ? msg
            : 'Something went wrong. Please try again.');
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  /// Saves a fresh FCM token every login so push notifications never break
  /// after app reinstalls or token refreshes.
  Future<void> _refreshFcmTokenOnLogin() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      final messaging = FirebaseMessaging.instance;
      await messaging.deleteToken(); // force-generate a new token
      final token = await messaging.getToken();
      if (token != null) {
        await _firestore.collection('users').doc(user.uid).set(
          {'fcm_token': token},
          SetOptions(merge: true),
        );
      }
    } catch (_) {}
  }

  Future<void> _navigateBasedOnRole(
    String role,
    String userName,
    String email,
  ) async {
    // Credentials are saved only after full auth & role verification succeeds.
    await secureStorage.write(key: 'email', value: email);
    await secureStorage.write(
        key: 'password', value: passwordController.text.trim());

    // Refresh FCM token on every login so notifications always work.
    _refreshFcmTokenOnLogin();

    if (role == 'client') {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/client');
    } else if (role == 'admin') {
      // Admin access is enforced by Firestore Security Rules + role field.
      // No client-side email whitelist needed.
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/admin',
        arguments: userName,
      );
    } else {
      setState(() {
        errorMessage = 'Access denied.';
      });
      _auth.signOut();
    }
  }

  Future<void> _resetPassword() async {
    final email = emailController.text.trim();
    if (email.isEmpty || !_emailRegex.hasMatch(email)) {
      setState(() => errorMessage = 'Please enter a valid email');
      return;
    }

    setState(() {
      isSendingResetEmail = true;
      errorMessage = '';
      successMessage = '';
    });

    try {
      await AuthEmailService.sendPasswordResetEmail(email: email);

      setState(() {
        successMessage = 'Password reset email sent to $email';
        _showSuccessSnackbar(
          'Password reset email sent! Check your inbox or spam folder.',
        );
      });
    } on FirebaseAuthException catch (e) {
      setState(() => errorMessage = _getErrorMessage(e.code));
      _showErrorSnackbar(_getErrorMessage(e.code));
    } catch (e) {
      setState(() => errorMessage = 'Failed to send reset email');
      _showErrorSnackbar('Failed to send reset email');
    } finally {
      setState(() => isSendingResetEmail = false);
    }
  }

  Future<void> _resendVerificationEmail() async {
    final email = emailController.text.trim();
    if (email.isEmpty || !_emailRegex.hasMatch(email)) {
      setState(() => errorMessage = 'Please enter a valid email');
      return;
    }

    setState(() {
      isSendingVerificationEmail = true;
      errorMessage = '';
      successMessage = '';
    });

    try {
      await AuthEmailService.sendVerificationEmail(email: email);

      setState(() {
        successMessage = 'Verification email sent to $email';
      });
      _showSuccessSnackbar(
        'Verification email sent! Check inbox, spam, or Promotions tab.',
      );
    } catch (apiError) {
      final details = apiError.toString().replaceFirst('Exception: ', '').trim();
      setState(() => errorMessage = details.isNotEmpty
          ? details
          : 'Failed to send verification email.');
      _showErrorSnackbar(details.isNotEmpty
          ? details
          : 'Failed to send verification email.');
    } finally {
      setState(() => isSendingVerificationEmail = false);
    }
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email address. Please check and try again.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-credential':
        return 'Incorrect email or password. Please check your details and try again.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'user-disabled':
        return 'Your account has been disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please wait a few minutes and try again.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network and try again.';
      case 'operation-not-allowed':
        return 'Email/password login is not enabled. Please contact support.';
      default:
        return 'Login failed. Please check your email and password.';
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[800],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(10),
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green[800],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(10),
      ),
    );
  }

  static const Color _navy = Color(0xFF1C2D5E);
  static const Color _navyLight = Color(0xFF2E4A9E);
  static const Color _fieldFill = Color(0xFFF4F6FB);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: _navy,
      body: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────
          SizedBox(
            height: size.height * 0.36,
            child: Stack(
              children: [
                // Background gradient
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0D1B3E), Color(0xFF1C2D5E)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                // Decorative circle (top-right)
                Positioned(
                  top: -40,
                  right: -40,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.04),
                    ),
                  ),
                ),
                // Decorative circle (bottom-left)
                Positioned(
                  bottom: 20,
                  left: -30,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.04),
                    ),
                  ),
                ),
                // Logo + text
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.25),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                          image: const DecorationImage(
                            image: AssetImage('assets/images/flex_login/logo.png'),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Welcome Back',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sign in to your account',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.65),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Form card ─────────────────────────────────────────────────
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Email field
                      _inputField(
                        controller: emailController,
                        label: 'Email address',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Please enter an email';
                          final domain = value.split('@').last.toLowerCase();
                          if (!_emailRegex.hasMatch(value)) return 'Invalid email format';
                          if (_disposableDomains.contains(domain)) return 'Disposable emails not allowed';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Password field
                      _inputField(
                        controller: passwordController,
                        label: 'Password',
                        icon: Icons.lock_outline,
                        obscureText: _obscurePassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: Colors.grey[500],
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Enter your password';
                          if (value.length < 6) return 'Password too short';
                          return null;
                        },
                      ),
                      const SizedBox(height: 4),

                      // Links row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: isSendingResetEmail ? null : _resetPassword,
                            style: TextButton.styleFrom(padding: EdgeInsets.zero),
                            child: isSendingResetEmail
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Forgot Password?',
                                    style: TextStyle(color: _navy, fontSize: 13)),
                          ),
                          TextButton(
                            onPressed: isSendingVerificationEmail ? null : _resendVerificationEmail,
                            style: TextButton.styleFrom(padding: EdgeInsets.zero),
                            child: isSendingVerificationEmail
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Resend Verification',
                                    style: TextStyle(color: _navy, fontSize: 13)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Biometric button
                      if (_canCheckBiometrics && _hasBiometrics) ...[
                        Container(
                          width: double.infinity,
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _navy, width: 1.5),
                          ),
                          child: TextButton.icon(
                            icon: const Icon(Icons.fingerprint, size: 24, color: _navy),
                            label: const Text(
                              'Login with Face ID / Touch ID',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _navy,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: isLoading ? null : _authenticateWithBiometrics,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Login button — gradient
                      GestureDetector(
                        onTap: isLoading ? null : _handleAuthentication,
                        child: Container(
                          width: double.infinity,
                          height: 54,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_navy, _navyLight],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: _navy.withOpacity(0.35),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Center(
                            child: isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2.5),
                                  )
                                : const Text(
                                    'Log In',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Sign up row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("Don't have an account?",
                              style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                          TextButton(
                            onPressed: () => Navigator.pushNamed(context, '/signup'),
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                            child: const Text(
                              'Sign Up',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _navy,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Error message
                      if (errorMessage.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(errorMessage,
                                    style: TextStyle(color: Colors.red[800], fontSize: 13)),
                              ),
                            ],
                          ),
                        ),

                      // Success message
                      if (successMessage.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.green[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline, color: Colors.green[700], size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(successMessage,
                                    style: TextStyle(color: Colors.green[800], fontSize: 13)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A2E)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
        prefixIcon: Icon(icon, color: _navy, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: _fieldFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE8ECF4), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _navy, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
    );
  }
}
