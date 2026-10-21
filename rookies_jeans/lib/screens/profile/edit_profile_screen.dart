import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/services/auth_service.dart';

/// Lets the signed-in customer change the first name, last name and phone
/// number on their Shopify account.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const double _kMaxContentW = 480;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _phone;
  late final String _originalPhone;

  bool _saving = false;

  double _s(BuildContext c, double base) =>
      Responsive.of(c, baseW: 375).s(base);

  @override
  void initState() {
    super.initState();
    final auth = AuthService.instance;
    _firstName = TextEditingController(text: auth.firstName);
    _lastName = TextEditingController(text: auth.lastName);
    _originalPhone = _localPhone(auth.phone);
    _phone = TextEditingController(text: _originalPhone);
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// "+919876543210" -> "9876543210"; other countries keep their "+code".
  static String _localPhone(String phone) {
    if (phone.startsWith('+91') && phone.length == 13) return phone.substring(3);
    return phone;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final phoneChanged = _phone.text.trim() != _originalPhone;
    if (phoneChanged && !await _confirmPhoneChange()) return;
    if (!mounted) return;

    setState(() => _saving = true);
    final error = await AuthService.instance.updateProfile(
      firstName: _firstName.text,
      lastName: _lastName.text,
      phone: _phone.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    AppToast.show(context, error ?? 'Profile updated', isError: error != null);
    if (error == null) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/profile');
      }
    }
  }

  /// Phone OTP login finds the account by this number, so make sure the
  /// customer knows the new one is what they'll sign in with.
  Future<bool> _confirmPhoneChange() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          'Change phone number?',
          style: TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w800, color: AppColors.primary),
        ),
        content: Text(
          'If you sign in with a phone OTP, you will need to use the new number from now on.',
          style: TextStyle(fontFamily: AppFonts.body, color: AppColors.secondaryText, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(fontFamily: AppFonts.body, color: AppColors.secondaryText)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Change', style: TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w800, color: AppColors.primary)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  InputDecoration _decoration(BuildContext context, String label, {String? hint, String? prefix}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefix,
      labelStyle: TextStyle(
        fontFamily: AppFonts.body,
        fontSize: _s(context, 13).clamp(12.0, 17.0),
      ),
      border: const OutlineInputBorder(),
      enabledBorder: const OutlineInputBorder(),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final toolbarHeight =
        (_s(context, 64)).clamp(56.0, 96.0) * media.textScaler.scale(1).clamp(1.0, 1.3);
    final fieldStyle = TextStyle(
      fontFamily: AppFonts.body,
      fontSize: _s(context, 14).clamp(13.0, 18.0),
      color: AppColors.primary,
    );
    final email = AuthService.instance.email;

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
                    context.go('/profile');
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
                      'EDIT PROFILE',
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
          child: SingleChildScrollView(
            padding: EdgeInsets.all(_s(context, 20)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kMaxContentW),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: _s(context, 10)),
                      TextFormField(
                        controller: _firstName,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        style: fieldStyle,
                        decoration: _decoration(context, 'First name'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Please enter your first name'
                            : null,
                      ),
                      SizedBox(height: _s(context, 16)),
                      TextFormField(
                        controller: _lastName,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        style: fieldStyle,
                        decoration: _decoration(context, 'Last name'),
                      ),
                      SizedBox(height: _s(context, 16)),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                        ],
                        style: fieldStyle,
                        decoration: _decoration(
                          context,
                          'Phone number',
                          hint: '10-digit mobile number',
                        ),
                        validator: (v) {
                          final value = (v ?? '').trim();
                          if (value.isEmpty) return null;
                          final indian = RegExp(r'^[6-9]\d{9}$');
                          final international = RegExp(r'^\+[1-9]\d{7,14}$');
                          if (!indian.hasMatch(value) && !international.hasMatch(value)) {
                            return 'Enter a valid 10-digit mobile number';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => _saving ? null : _save(),
                      ),
                      if (email.isNotEmpty) ...[
                        SizedBox(height: _s(context, 16)),
                        TextFormField(
                          initialValue: email,
                          enabled: false,
                          style: fieldStyle.copyWith(color: AppColors.secondaryText),
                          decoration: _decoration(context, 'Email (can\'t be changed here)'),
                        ),
                      ],
                      SizedBox(height: _s(context, 30)),
                      SizedBox(
                        width: double.infinity,
                        height: _s(context, 52).clamp(48.0, 64.0),
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.onPrimary,
                            elevation: 0,
                            shape: AppShapes.button,
                          ),
                          child: _saving
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.onPrimary,
                                  ),
                                )
                              : Text(
                                  'SAVE CHANGES',
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
        ),
      ),
    );
  }
}
