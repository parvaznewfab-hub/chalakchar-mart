import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/referral_service.dart';
import '../../utils/web_recaptcha_helper.dart';
import '../main_navigation_page.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../user/settings_details_pages.dart';

class LoginPage extends StatefulWidget {
  final bool isFromLogout;
  final bool isPopup;

  /// If true, the same OTP flow is presented as account creation.
  /// Existing login calls still work because the default is false.
  final bool createAccountMode;

  const LoginPage({
    super.key,
    this.isFromLogout = false,
    this.isPopup = false,
    this.createAccountMode = false,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController referralCodeController = TextEditingController();

  final AuthService _authService = AuthService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final Color primaryColor = const Color(0xFF32A8C7);

  String? verificationId;
  bool loading = false;

  String get _pageTitle =>
      widget.createAccountMode ? 'Create Account' : 'Secure Login';

  String get _pageSubtitle => widget.createAccountMode
      ? 'Enter mobile number. Referral code is optional.'
      : 'Login safely with mobile OTP';

  String get _primaryButtonText => widget.createAccountMode
      ? 'SEND OTP & CREATE ACCOUNT'
      : 'LOGIN WITH OTP';

  @override
  void dispose() {
    phoneController.dispose();
    referralCodeController.dispose();
    if (kIsWeb) {
      setRecaptchaVisible(false);
    }
    super.dispose();
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('88') && digits.length == 13) return '+$digits';
    if (digits.startsWith('0') && digits.length == 11) return '+88$digits';
    return '+88$digits';
  }


  String _normalizeReferralCode(String value) {
    return value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }

  Future<void> _applyReferralCodeIfNeeded(User user) async {
    if (!widget.createAccountMode) return;

    final enteredCode = _normalizeReferralCode(referralCodeController.text);
    if (enteredCode.isEmpty) return;

    try {
      final result = await ReferralService.applyReferral(enteredCode);
      _showMessage(result);
    } catch (e) {
      debugPrint('Referral apply failed: $e');
      _showMessage('Referral code could not be applied now.');
    }
  }

  Future<void> _afterLogin() async {
    if (kIsWeb) {
      setRecaptchaVisible(false);
    }

    final user = _auth.currentUser;
    if (user == null) {
      _showMessage('Login failed. Please try again.');
      return;
    }

    String role = 'user';

    // 1) Profile/role save must be critical
    try {
      role = await _authService.createOrGetUser();

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        throw Exception('User document was not created in Firestore.');
      }

      final data = userDoc.data() ?? {};
      role = (data['role'] ?? role).toString();

      if (role == 'superAdmin' ||
          role == AuthService.roleSuperAdmin) {
        role = AuthService.roleSuperAdmin;
      } else if (role == 'admin' ||
          role == AuthService.roleAdmin) {
        role = AuthService.roleAdmin;
      } else if (role == 'staff' ||
          role == AuthService.roleStaff) {
        role = AuthService.roleStaff;
      } else if (role == 'vendor') {
        role = 'vendor';
      } else {
        role = 'user';
      }

      await _applyReferralCodeIfNeeded(user);
    } catch (e) {
      debugPrint('After login profile error: $e');

      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      _showMessage('Login failed: $e');
      return;
    }

    // 2) Notification permission is NOT critical for login
    try {
      await NotificationService.init();
      await NotificationService.saveToken(user.uid);
    } catch (e) {
      debugPrint('Notification skipped after login: $e');
    }

    if (!mounted) return;

    if (widget.isPopup && Navigator.canPop(context)) {
      Navigator.pop(context, true);
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => MainNavigation(
          role: role,
          initialIndex: 0,
        ),
      ),
          (route) => false,
    );
  }

  Future<void> sendOTP() async {
    final rawPhone = phoneController.text.trim();
    final digits = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.length != 11 || !digits.startsWith('01')) {
      _showMessage('Please enter valid 11 digit Bangladeshi mobile number');
      return;
    }

    final phone = _normalizePhone(rawPhone);

    if (kIsWeb) {
      setRecaptchaVisible(true);
    }

    setState(() => loading = true);

    try {
      if (kIsWeb) {
        final verifier = RecaptchaVerifier(
          auth: FirebaseAuthPlatform.instance,
          container: 'recaptcha-container',
          size: RecaptchaVerifierSize.compact,
        );

        final confirmationResult = await _auth
            .signInWithPhoneNumber(phone, verifier)
            .timeout(const Duration(seconds: 40));

        if (!mounted) return;
        setState(() => loading = false);

        await Future.delayed(const Duration(milliseconds: 350));
        await _showWebOTPDialog(confirmationResult);
      } else {
        await _auth.verifyPhoneNumber(
          phoneNumber: phone,
          timeout: const Duration(seconds: 60),
          verificationCompleted: (PhoneAuthCredential credential) async {
            try {
              await _auth.signInWithCredential(credential);
              await _afterLogin();
            } catch (e) {
              _showMessage('Auto verification failed: $e');
            }
          },
          verificationFailed: (FirebaseAuthException e) {
            if (!mounted) return;
            setState(() => loading = false);
            _showMessage(e.message ?? 'Verification failed');
          },
          codeSent: (String verId, int? resendToken) {
            if (!mounted) return;
            setState(() {
              loading = false;
              verificationId = verId;
            });
            _showOTPDialog();
          },
          codeAutoRetrievalTimeout: (String verId) {
            verificationId = verId;
          },
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);

      if (kIsWeb) {
        setRecaptchaVisible(false);
      }

      _showMessage('OTP failed: $e');
    }
  }

  Future<void> _showWebOTPDialog(ConfirmationResult confirmationResult) async {
    final otpController = TextEditingController();
    bool verifying = false;

    await showDialog(
      context: context,
      barrierDismissible: !verifying,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> verify() async {
              final otp = otpController.text.trim();

              if (otp.length != 6) {
                _showMessage('Enter valid 6 digit OTP');
                return;
              }

              setDialogState(() => verifying = true);

              try {
                await confirmationResult.confirm(otp);

                if (ctx.mounted) Navigator.pop(ctx);
                await _afterLogin();
              } catch (e) {
                _showMessage('Invalid OTP');
              } finally {
                if (ctx.mounted) setDialogState(() => verifying = false);
              }
            }

            return AlertDialog(
              title: const Text('Enter OTP'),
              content: TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  hintText: '6-digit code',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                onSubmitted: (_) => verify(),
              ),
              actions: [
                TextButton(
                  onPressed: verifying ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: verifying ? null : verify,
                  child: verifying
                      ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Text('Verify'),
                ),
              ],
            );
          },
        );
      },
    );

    otpController.dispose();
  }

  Future<void> _showOTPDialog() async {
    final otpController = TextEditingController();
    bool verifying = false;

    await showDialog(
      context: context,
      barrierDismissible: !verifying,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> verify() async {
              final otp = otpController.text.trim();

              if (otp.length != 6 || verificationId == null) {
                _showMessage('Enter valid 6 digit OTP');
                return;
              }

              setDialogState(() => verifying = true);

              try {
                final credential = PhoneAuthProvider.credential(
                  verificationId: verificationId!,
                  smsCode: otp,
                );

                await _auth.signInWithCredential(credential);

                if (ctx.mounted) Navigator.pop(ctx);
                await _afterLogin();
              } catch (e) {
                _showMessage('Invalid OTP');
              } finally {
                if (ctx.mounted) setDialogState(() => verifying = false);
              }
            }

            return AlertDialog(
              title: const Text('Enter OTP'),
              content: TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  hintText: '6-digit code',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                onSubmitted: (_) => verify(),
              ),
              actions: [
                TextButton(
                  onPressed: verifying ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: verifying ? null : verify,
                  child: verifying
                      ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Text('Verify'),
                ),
              ],
            );
          },
        );
      },
    );

    otpController.dispose();
  }

  Future<void> _facebookLogin() async {
    if (loading) return;

    setState(() => loading = true);

    try {
      await _authService.signInWithFacebook();

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        await _afterLogin();
        return;
      }

      _showMessage('Facebook login cancelled or failed');
    } catch (e) {
      _showMessage('Facebook login failed: $e');
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _googleLogin() async {
    if (loading) return;

    setState(() => loading = true);

    try {
      await _authService.signInWithGoogle();

      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser != null) {
        await _afterLogin();
        return;
      }

      _showMessage('Google login failed');
    } catch (e) {
      _showMessage('Google login failed: $e');
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  void _closeLogin() {
    if (widget.isFromLogout) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const MainNavigation(
            role: 'user',
            initialIndex: 0,
          ),
        ),
            (route) => false,
      );
      return;
    }

    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  TextSpan _policyTextSpan(String text, Widget page) {
    return TextSpan(
      text: text,
      style: const TextStyle(
        decoration: TextDecoration.none,
        fontWeight: FontWeight.bold,
      ),
      recognizer: TapGestureRecognizer()
        ..onTap = () {
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(builder: (_) => page),
          );
        },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = kIsWeb;
    final panelWidth = isWeb ? 500.0 : double.infinity;

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                Container(
                  width: panelWidth,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF32A8C7), Color(0xFF1592B3)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 85,
                        height: 85,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          image: const DecorationImage(
                            image: AssetImage('assets/images/chalakchar_mart_logo.png'),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'ChalakChar Mart',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _pageTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _pageSubtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 22),

                      if (widget.createAccountMode) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.verified_user_outlined, color: Colors.white, size: 21),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Create account by OTP or Google. Referral code will be saved if you enter it.',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.75)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(14),
                                  bottomLeft: Radius.circular(14),
                                ),
                                border: Border(
                                  right: BorderSide(color: Colors.grey.shade300),
                                ),
                              ),
                              child: const Text(
                                '+88',
                                style: TextStyle(
                                  color: Color(0xFF1F2937),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: phoneController,
                                enabled: !loading,
                                cursorColor: primaryColor,
                                style: const TextStyle(
                                  color: Color(0xFF111827),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                                decoration: const InputDecoration(
                                  filled: true,
                                  fillColor: Colors.white,
                                  hintText: '01XXXXXXXXX',
                                  hintStyle: TextStyle(
                                    color: Color(0xFF9CA3AF),
                                    fontWeight: FontWeight.w600,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                                ),
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) {
                                  if (!loading) sendOTP();
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (widget.createAccountMode) ...[
                        const SizedBox(height: 14),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.75)),
                          ),
                          child: TextField(
                            controller: referralCodeController,
                            enabled: !loading,
                            cursorColor: primaryColor,
                            textCapitalization: TextCapitalization.characters,
                            style: const TextStyle(
                              color: Color(0xFF111827),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              fontSize: 15,
                            ),
                            decoration: const InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              prefixIcon: Icon(Icons.card_giftcard, color: Color(0xFF32A8C7)),
                              hintText: 'Referral Code (Optional)',
                              hintStyle: TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontWeight: FontWeight.w600,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Optional: enter a friend referral code before OTP or Google signup.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 22),

                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: const TextStyle(color: Colors.white70, fontSize: 10.5),
                          children: [
                            const TextSpan(text: 'By continuing you agree to our '),
                            _policyTextSpan('Terms of Service', const TermsConditionsPage()),
                            const TextSpan(text: ', '),
                            _policyTextSpan('Privacy Policy', const PrivacyPolicyPage()),
                            const TextSpan(text: ' & '),
                            _policyTextSpan('Refund-Return Policy', const ReturnPolicyPage()),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: loading ? null : sendOTP,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: primaryColor,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: loading
                              ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: primaryColor,
                            ),
                          )
                              : Text(
                            _primaryButtonText,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: primaryColor,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      InkWell(
                        onTap: loading
                            ? null
                            : () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => LoginPage(
                                isFromLogout: widget.isFromLogout,
                                isPopup: widget.isPopup,
                                createAccountMode: !widget.createAccountMode,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(30),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Text(
                            widget.createAccountMode
                                ? 'Already registered? Sign in to your account'
                                : 'New here? Create your account and use a referral code',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              height: 1.4,
                              decoration: TextDecoration.none,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        widget.createAccountMode ? 'or create account with' : 'or continue with',
                        style: const TextStyle(color: Colors.white70),
                      ),

                      const SizedBox(height: 15),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _socialButton(
                            icon: Icons.facebook,
                            color: const Color(0xFF1877F2),
                            onTap: loading ? null : _facebookLogin,
                          ),
                          const SizedBox(width: 20),
                          _socialButton(
                            icon: Icons.g_mobiledata_rounded,
                            color: Colors.blue,
                            iconSize: 36,
                            onTap: loading ? null : _googleLogin,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                Positioned(
                  right: 10,
                  top: 10,
                  child: GestureDetector(
                    onTap: loading ? null : _closeLogin,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.close, color: primaryColor, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _socialButton({
    required IconData icon,
    required Color color,
    double iconSize = 25,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: CircleAvatar(
        radius: 24,
        backgroundColor: Colors.white,
        child: Icon(icon, color: color, size: iconSize),
      ),
    );
  }
}
