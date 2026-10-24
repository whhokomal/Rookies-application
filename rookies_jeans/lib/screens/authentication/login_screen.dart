import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:rookies_jeans/services/shopify_api.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/models/auth_model.dart';
import 'package:rookies_jeans/screens/authentication/forgot_password.dart';
import 'package:rookies_jeans/services/auth_service.dart';
import 'package:rookies_jeans/services/otp_auth_service.dart';
import 'package:rookies_jeans/services/shopify_auth_service.dart';

/// Phone OTP is the AppColors.primary sign-in; email + password is the backup.
enum _LoginMode { phone, email }

/// Steps of the phone OTP flow.
enum _OtpStep { enterPhone, enterOtp, completeProfile }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.isCheckoutFlow = false});

  final bool isCheckoutFlow;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController    = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController phoneController    = TextEditingController();
  final TextEditingController otpController      = TextEditingController();
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController  = TextEditingController();
  final TextEditingController profileEmailController = TextEditingController();

  static const int _otpLength     = 6;
  static const int _resendSeconds = 30;

  _LoginMode mode    = _LoginMode.phone;
  _OtpStep   otpStep = _OtpStep.enterPhone;

  bool isPasswordHidden = true;
  bool isLoading        = false;

  String? _verificationToken;
  Timer?  _resendTimer;
  int     _resendIn = 0;

  double _s(double base) =>
      Responsive.of(context, baseW: 400, maxScale: 1.3).s(base);

  double _h(double base) => _s(base).clamp(48.0, 64.0);

  String get _phone => '+91${phoneController.text.trim()}';

  @override
  void dispose() {
    _resendTimer?.cancel();
    emailController.dispose();
    passwordController.dispose();
    phoneController.dispose();
    otpController.dispose();
    firstNameController.dispose();
    lastNameController.dispose();
    profileEmailController.dispose();
    super.dispose();
  }

  InputDecoration inputDecoration({
    required String hintText,
    required IconData icon,
    Widget? suffixIcon,
    String? leadingText,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: AppColors.hint,
        fontSize: _s(14.5),
        fontWeight: FontWeight.w400,
      ),
      // leadingText (e.g. "+91") sits beside the icon so it shows even when
      // the field is empty and unfocused, unlike InputDecoration.prefix.
      prefixIcon: leadingText == null
          ? Icon(icon, color: AppColors.secondaryText, size: _s(20))
          : Padding(
              padding: EdgeInsets.only(left: _s(12), right: _s(8)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: AppColors.secondaryText, size: _s(20)),
                  SizedBox(width: _s(8)),
                  Text(
                    leadingText,
                    style: TextStyle(
                      fontSize: _s(14.5),
                      color: AppColors.primary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
      suffixIcon: suffixIcon,
      counterText: '',
      filled: true,
      fillColor: AppColors.fieldFill,
      contentPadding:
          EdgeInsets.symmetric(vertical: _s(18), horizontal: _s(16)),
      border: OutlineInputBorder(
        // borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        // borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        // borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primary, width: 1.2),
      ),
      errorBorder: const OutlineInputBorder(
        // borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.redAccent),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared success handling (both login modes end here)

  void _onSignedIn(ShopifyAuthResult result) {
    AuthService.instance.signIn(result.customer);
    _showMessage(
      result.customer != null
          ? 'Welcome ${result.customer!.fullName}'
          : 'Login successful',
    );

    if (kDebugMode) debugPrint('UI LOGIN SUCCESS -> ${result.customer?.toJson()}');

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (widget.isCheckoutFlow) {
      Navigator.of(context).pop(true);
    } else {
      context.go('/home');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    FocusScope.of(context).unfocus();
    setState(() => isLoading = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      _showMessage(kFriendlyNetworkError);
      if (kDebugMode) debugPrint('UI LOGIN EXCEPTION -> $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Phone OTP

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendIn = _resendSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _handleSendOtp() async {
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phoneController.text.trim())) {
      _showMessage('Enter a valid 10-digit mobile number.');
      return;
    }

    await _run(() async {
      final error = await OtpAuthService.instance.sendOtp(_phone);
      if (!mounted) return;
      if (error != null) {
        _showMessage(error);
        return;
      }
      otpController.clear();
      setState(() => otpStep = _OtpStep.enterOtp);
      _startResendTimer();
      _showMessage('OTP sent to $_phone');
    });
  }

  Future<void> _handleResendOtp() async {
    await _run(() async {
      final error = await OtpAuthService.instance.resendOtp(_phone);
      if (!mounted) return;
      if (error != null) {
        _showMessage(error);
        return;
      }
      _startResendTimer();
      _showMessage('OTP resent to $_phone');
    });
  }

  Future<void> _handleVerifyOtp() async {
    final otp = otpController.text.trim();
    if (otp.length != _otpLength) {
      _showMessage('Enter the $_otpLength-digit OTP.');
      return;
    }

    await _run(() async {
      final result =
          await OtpAuthService.instance.verifyOtp(phone: _phone, otp: otp);
      if (!mounted) return;

      if (result.error != null) {
        _showMessage(result.error!);
        return;
      }
      if (result.needsProfile) {
        _resendTimer?.cancel();
        _verificationToken = result.verificationToken;
        firstNameController.text = result.firstName;
        lastNameController.text  = result.lastName;
        setState(() => otpStep = _OtpStep.completeProfile);
        return;
      }
      _onSignedIn(result.auth!);
    });
  }

  Future<void> _handleCompleteProfile() async {
    final firstName = firstNameController.text.trim();
    final email     = profileEmailController.text.trim();
    if (firstName.isEmpty || email.isEmpty) {
      _showMessage('Please enter your first name and email.');
      return;
    }

    await _run(() async {
      final result = await OtpAuthService.instance.completeProfile(
        verificationToken: _verificationToken ?? '',
        firstName: firstName,
        lastName: lastNameController.text.trim(),
        email: email,
      );
      if (!mounted) return;

      if (result.error != null) {
        _showMessage(result.error!);
        return;
      }
      _onSignedIn(result.auth!);
    });
  }

  void _changeNumber() {
    _resendTimer?.cancel();
    otpController.clear();
    setState(() {
      _resendIn = 0;
      _verificationToken = null;
      otpStep = _OtpStep.enterPhone;
    });
  }

  // ---------------------------------------------------------------------------
  // Email + password (backup)

  Future<void> _handleLogin() async {
    final email    = emailController.text.trim();
    final password = passwordController.text.trim();

    if (kDebugMode) debugPrint('UI LOGIN CLICK -> email: $email');

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Please enter email and password.');
      return;
    }

    await _run(() async {
      final result = await ShopifyAuthService.instance.login(
        email: email,
        password: password,
      );

      if (!mounted) return;

      if (!result.success) {
        _showMessage(result.message ?? 'Login failed');
        if (kDebugMode) debugPrint('UI LOGIN FAILED -> ${result.message}');
        return;
      }
      _onSignedIn(result);
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        content: Text(message, style: TextStyle(color: AppColors.onPrimary)),
      ),
    );
  }

  void _handleForgotPassword() {
    if (kDebugMode) debugPrint('UI FORGOT PASSWORD TAP');
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ForgotPassword()),
    );
  }

  void _switchMode(_LoginMode next) {
    FocusScope.of(context).unfocus();
    if (next == _LoginMode.email) _changeNumber();
    setState(() => mode = next);
  }

  // ---------------------------------------------------------------------------
  // UI

  Widget _label(String text) => Padding(
        padding: EdgeInsets.only(bottom: _s(8)),
        child: Text(text,
            style: TextStyle(
                fontSize: _s(14),
                fontWeight: FontWeight.w400,
                color: AppColors.primary)),
      );

  Widget _primaryButton(String text, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: _h(56),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.border,
          elevation: 0,
          // shape: RoundedRectangleBorder(
          //     borderRadius: BorderRadius.circular(14)),
        ),
        child: isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: AppColors.onPrimary),
              )
            : Text(text,
                style: TextStyle(
                    fontFamily: AppFonts.accent,
                    fontSize: _s(16),
                    fontWeight: FontWeight.w400,
                    // letterSpacing: 0.2
                    )),
      ),
    );
  }

  Widget _linkButton(String text, VoidCallback? onPressed) {
    return TextButton(
      onPressed: isLoading ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: EdgeInsets.zero,
      ),
      child: Text(text,
          style: TextStyle(fontSize: _s(13.5), fontWeight: FontWeight.w400)),
    );
  }

  Widget _divider(String text) => Row(
        children: [
          Expanded(child: Divider(color: AppColors.border)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: _s(12)),
            child: Text(text,
                style: TextStyle(color: AppColors.secondaryText, fontSize: _s(13))),
          ),
          Expanded(child: Divider(color: AppColors.border)),
        ],
      );

  List<Widget> _phoneStep() => [
        _label("Mobile Number"),
        TextFormField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(fontSize: _s(14.5)),
          onFieldSubmitted: (_) => _handleSendOtp(),
          decoration: inputDecoration(
            hintText: "Enter your mobile number",
            icon: Icons.phone_iphone_rounded,
            leadingText: "+91",
          ),
        ),
        SizedBox(height: _s(24)),
        _primaryButton("Send OTP", _handleSendOtp),
      ];

  List<Widget> _otpStep() => [
        Row(
          children: [
            Expanded(
              child: Text("OTP sent to $_phone",
                  style: TextStyle(color: AppColors.secondaryText, fontSize: _s(14))),
            ),
            _linkButton("Change", _changeNumber),
          ],
        ),
        SizedBox(height: _s(8)),
        _label("Enter OTP"),
        TextFormField(
          controller: otpController,
          keyboardType: TextInputType.number,
          maxLength: _otpLength,
          autofocus: true,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: _s(20),
              fontWeight: FontWeight.w400,
              letterSpacing: _s(10)),
          onChanged: (v) {
            if (v.length == _otpLength && !isLoading) _handleVerifyOtp();
          },
          decoration: inputDecoration(
            hintText: "• " * _otpLength,
            icon: Icons.sms_outlined,
          ),
        ),
        SizedBox(height: _s(8)),
        Align(
          alignment: Alignment.centerRight,
          child: _resendIn > 0
              ? Padding(
                  padding: EdgeInsets.symmetric(vertical: _s(12)),
                  child: Text("Resend OTP in ${_resendIn}s",
                      style: TextStyle(
                          color: AppColors.secondaryText, fontSize: _s(13.5))),
                )
              : _linkButton("Resend OTP", _handleResendOtp),
        ),
        SizedBox(height: _s(12)),
        _primaryButton("Sign In", _handleVerifyOtp),
      ];

  List<Widget> _profileStep() => [
        Text("Number verified! Tell us a bit about you to finish setting up your account.",
            style: TextStyle(
                color: AppColors.secondaryText, fontSize: _s(14), height: 1.5)),
        SizedBox(height: _s(18)),
        _label("First Name"),
        TextFormField(
          controller: firstNameController,
          textCapitalization: TextCapitalization.words,
          style: TextStyle(fontSize: _s(14.5)),
          decoration: inputDecoration(
            hintText: "Enter your first name",
            icon: Icons.person_outline_rounded,
          ),
        ),
        SizedBox(height: _s(18)),
        _label("Last Name"),
        TextFormField(
          controller: lastNameController,
          textCapitalization: TextCapitalization.words,
          style: TextStyle(fontSize: _s(14.5)),
          decoration: inputDecoration(
            hintText: "Enter your last name",
            icon: Icons.person_outline_rounded,
          ),
        ),
        SizedBox(height: _s(18)),
        _label("Email"),
        TextFormField(
          controller: profileEmailController,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(fontSize: _s(14.5)),
          decoration: inputDecoration(
            hintText: "Enter your email",
            icon: Icons.mail_outline_rounded,
          ),
        ),
        SizedBox(height: _s(24)),
        _primaryButton("Continue", _handleCompleteProfile),
        SizedBox(height: _s(8)),
        Center(child: _linkButton("Use a different number", _changeNumber)),
      ];

  List<Widget> _emailForm() => [
        _label("Email"),
        TextFormField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(fontSize: _s(14.5)),
          decoration: inputDecoration(
            hintText: "Enter your email",
            icon: Icons.mail_outline_rounded,
          ),
        ),
        SizedBox(height: _s(18)),
        _label("Password"),
        TextFormField(
          controller: passwordController,
          obscureText: isPasswordHidden,
          style: TextStyle(fontSize: _s(14.5)),
          onFieldSubmitted: (_) => _handleLogin(),
          decoration: inputDecoration(
            hintText: "Enter your password",
            icon: Icons.lock_outline_rounded,
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => isPasswordHidden = !isPasswordHidden),
              icon: Icon(
                isPasswordHidden
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: AppColors.secondaryText,
                size: _s(22),
              ),
            ),
          ),
        ),
        SizedBox(height: _s(14)),
        Align(
          alignment: Alignment.centerRight,
          child: _linkButton("Forgot Password?", _handleForgotPassword),
        ),
        SizedBox(height: _s(18)),
        _primaryButton("Sign In", _handleLogin),
      ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final outerH = width < 360 ? 16.0 : _s(24);

    final bool isPhone = mode == _LoginMode.phone;
    final List<Widget> form = !isPhone
        ? _emailForm()
        : switch (otpStep) {
            _OtpStep.enterPhone      => _phoneStep(),
            _OtpStep.enterOtp        => _otpStep(),
            _OtpStep.completeProfile => _profileStep(),
          };

    final theme = Theme.of(context);
    // Every text on this screen, incl. fields, hints and buttons, in Archivo.
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: AppFonts.body),
      ),
      child: Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: outerH, vertical: _s(24)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: EdgeInsets.all(_s(24)),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  // borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: _s(4)),
                    Center(
                      child: Column(
                        children: [
                          Text(
                            isPhone && otpStep == _OtpStep.completeProfile
                                ? "Almost There"
                                : "Welcome Back",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: AppFonts.heading,
                              fontSize: _s(30),
                              fontWeight: FontWeight.w400,
                              color: AppColors.primary,
                              // letterSpacing: -0.5,
                            ),
                          ),
                          SizedBox(height: _s(8)),
                          Text(
                            isPhone
                                ? "Sign in with your mobile number"
                                : "Sign in with your email & password",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: AppFonts.body,
                              fontSize: _s(15),
                              fontWeight: FontWeight.w400,
                              color: AppColors.secondaryText,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: _s(32)),
                    ...form,
                    if (!(isPhone && otpStep == _OtpStep.completeProfile)) ...[
                      SizedBox(height: _s(20)),
                      _divider("or"),
                      SizedBox(height: _s(8)),
                      Center(
                        child: _linkButton(
                          isPhone
                              ? "Use email & password instead"
                              : "Use mobile number (OTP) instead",
                          () => _switchMode(
                              isPhone ? _LoginMode.email : _LoginMode.phone),
                        ),
                      ),
                    ],
                    SizedBox(height: _s(14)),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text("New to ROOKIES? ",
                            style: TextStyle(
                                fontFamily: AppFonts.body,
                                fontWeight: FontWeight.w400,
                                color: AppColors.secondaryText,
                                fontSize: _s(14))),
                        GestureDetector(
                          onTap: () => context.push('/register'),
                          child: Text("Create Account",
                              style: TextStyle(
                                  fontFamily: AppFonts.body,
                                  color: AppColors.primary,
                                  fontSize: _s(14),
                                  fontWeight: FontWeight.w400)),
                        ),
                      ],
                    ),
                    SizedBox(height: _s(6)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
