import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rookies_jeans/services/shopify_api.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/services/shopify_auth_service.dart';

class ForgotPassword extends StatefulWidget {
  const ForgotPassword({super.key});

  @override
  State<ForgotPassword> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<ForgotPassword> {
  final TextEditingController emailController = TextEditingController();

  bool isLoading = false;
  bool emailSent = false;

  double _s(double base) =>
      Responsive.of(context, baseW: 400, maxScale: 1.3).s(base);

  double _h(double base) => _s(base).clamp(48.0, 64.0);

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  InputDecoration inputDecoration({
    required String hintText,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: AppColors.hint,
        fontSize: _s(14.5),
        fontWeight: FontWeight.w400,
      ),
      prefixIcon: Icon(
        icon,
        color: AppColors.secondaryText,
        size: _s(20),
      ),
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

  bool _isValidEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  Future<void> _handleSendResetLink() async {
    FocusScope.of(context).unfocus();

    final email = emailController.text.trim();

    if (kDebugMode) {
      debugPrint('UI FORGOT PASSWORD CLICK -> email: $email');
    }

    if (email.isEmpty || !_isValidEmail(email)) {
      _showMessage('Please enter a valid email address.');
      return;
    }

    setState(() => isLoading = true);

    try {
      final result = await ShopifyAuthService.instance.recoverPassword(
        email: email,
      );

      if (!mounted) return;

      if (kDebugMode) {
        debugPrint(
            'UI FORGOT PASSWORD RESULT -> success: ${result.success}, message: ${result.message}');
      }

      if (result.success) {
        setState(() => emailSent = true);
      } else {
        _showMessage(
            result.message ?? 'Something went wrong. Please try again.');
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage(kFriendlyNetworkError);
      if (kDebugMode) {
        debugPrint('UI FORGOT PASSWORD EXCEPTION -> $e');
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        content: Text(
          message,
          style: TextStyle(color: AppColors.onPrimary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final outerH = width < 360 ? 16.0 : _s(24);

    return Scaffold(
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
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            color: AppColors.primary,
                            size: _s(24),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: _s(12)),
                    Center(
                      child: Column(
                        children: [
                          Container(
                            padding: EdgeInsets.all(_s(16)),
                            decoration: BoxDecoration(
                              color: AppColors.fieldFill,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Icon(
                              emailSent
                                  ? Icons.mark_email_read_outlined
                                  : Icons.lock_reset_rounded,
                              color: AppColors.primary,
                              size: _s(28),
                            ),
                          ),
                          SizedBox(height: _s(18)),
                          Text(
                            emailSent ? "Check Your Email" : "Forgot Password?",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: _s(26),
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                              // letterSpacing: -0.5,
                            ),
                          ),
                          SizedBox(height: _s(8)),
                          Text(
                            emailSent
                                ? "If an account exists for ${emailController.text.trim()}, we've sent a link to reset your password."
                                : "Enter the email linked to your account and we'll send you a link to reset your password.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: _s(14.5),
                              color: AppColors.secondaryText,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: _s(28)),
                    if (!emailSent) ...[
                      Text(
                        "Email",
                        style: TextStyle(
                          fontSize: _s(14),
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(height: _s(8)),
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        style: TextStyle(fontSize: _s(14.5)),
                        onFieldSubmitted: (_) => _handleSendResetLink(),
                        decoration: inputDecoration(
                          hintText: "Enter your email",
                          icon: Icons.mail_outline_rounded,
                        ),
                      ),
                      SizedBox(height: _s(22)),
                      SizedBox(
                        width: double.infinity,
                        height: _h(56),
                        child: ElevatedButton(
                          onPressed: isLoading ? null : _handleSendResetLink,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.onPrimary,
                            disabledBackgroundColor: AppColors.border,
                            elevation: 0,
                            shape: const RoundedRectangleBorder(
                                // borderRadius: BorderRadius.circular(14),
                                ),
                          ),
                          child: isLoading
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: AppColors.onPrimary,
                                  ),
                                )
                              : Text(
                                  "Send Reset Link",
                                  style: TextStyle(
                                    fontSize: _s(16),
                                    fontWeight: FontWeight.w700,
                                    // letterSpacing: 0.2,
                                  ),
                                ),
                        ),
                      ),
                    ] else ...[
                      SizedBox(
                        width: double.infinity,
                        height: _h(56),
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() => emailSent = false);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: BorderSide(color: AppColors.border),
                            shape: const RoundedRectangleBorder(
                                // borderRadius: BorderRadius.circular(14),
                                ),
                          ),
                          child: Text(
                            "Use a Different Email",
                            style: TextStyle(
                              fontSize: _s(15),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: _s(12)),
                      SizedBox(
                        width: double.infinity,
                        height: _h(56),
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.onPrimary,
                            elevation: 0,
                            shape: const RoundedRectangleBorder(
                                // borderRadius: BorderRadius.circular(14),
                                ),
                          ),
                          child: Text(
                            "Back to Sign In",
                            style: TextStyle(
                              fontSize: _s(16),
                              fontWeight: FontWeight.w700,
                              // letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: _s(6)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}