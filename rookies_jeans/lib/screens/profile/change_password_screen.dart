import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/services/shopify_auth_service.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  static const double _kMaxContentW = 480;

  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;

  double _s(BuildContext c, double base) =>
      Responsive.of(c, baseW: 375).s(base);

  Future<void> _sendResetLink() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    final result = await ShopifyAuthService.instance.recoverPassword(
      email: _emailController.text.trim(),
    );

    if (!mounted) return;

    setState(() => _loading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: result.success ? AppColors.primary : Colors.red,
        content: Text(
          result.message ?? '',
          style: TextStyle(
            fontFamily: AppFonts.body,
            color: result.success ? AppColors.onPrimary : Colors.white,
            fontSize: 13,
          ),
        ),
      ),
    );

    if (result.success) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final toolbarHeight =
        (_s(context, 64)).clamp(56.0, 96.0) * media.textScaler.scale(1).clamp(1.0, 1.3);

    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) => Scaffold(
      backgroundColor: AppColors.bg,

      appBar: AppBar(
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        toolbarHeight: toolbarHeight,
        title: Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: _s(context, 18).clamp(16.0, 26.0),
                color: AppColors.primary,
              ),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/home');
                }
              },
            ),
            Flexible(
              child: Padding(
                padding: EdgeInsets.only(right: _s(context, 12)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'RESET PASSWORD',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: _s(context, 34).clamp(24.0, 46.0),
                      height: 1,
                      fontFamily: AppFonts.heading,
                      fontStyle: FontStyle.italic,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),

      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.all(_s(context, 20)),
              child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _kMaxContentW),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: _s(context, 10)),

                          Text(
                            "Enter your registered email address and we'll send you a password reset link.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: AppFonts.body,
                              fontSize: _s(context, 13).clamp(12.0, 17.0),
                              color: AppColors.secondaryText,
                              height: 1.5,
                            ),
                          ),

                          SizedBox(height: _s(context, 30)),

                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: TextStyle(
                              fontFamily: AppFonts.body,
                              fontSize: _s(context, 14).clamp(13.0, 18.0),
                              color: AppColors.primary,
                            ),
                            decoration: InputDecoration(
                              labelText: "Email",
                              labelStyle: TextStyle(
                                fontFamily: AppFonts.body,
                                fontSize: _s(context, 13).clamp(12.0, 17.0),
                              ),
                              border: const OutlineInputBorder(),
                              enabledBorder: const OutlineInputBorder(),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.primary,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return "Please enter your email";
                              }

                              final emailRegex = RegExp(
                                r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$',
                              );

                              if (!emailRegex.hasMatch(value.trim())) {
                                return "Enter a valid email";
                              }

                              return null;
                            },
                          ),

                          SizedBox(height: _s(context, 30)),

                          SizedBox(
                            width: double.infinity,
                            height: _s(context, 52).clamp(48.0, 64.0),
                            child: ElevatedButton(
                              onPressed: _loading ? null : _sendResetLink,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.onPrimary,
                                elevation: 0,
                              ),
                              child: _loading
                                  ? SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.onPrimary,
                                      ),
                                    )
                                  : Text(
                                      "SEND RESET LINK",
                                      style: TextStyle(
                                        fontFamily: AppFonts.bold,
                                        fontSize: _s(context, 13).clamp(12.0, 17.0),
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.onPrimary,
                                      ),
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
          },
        ),
      ),
      ),
    );
  }
}