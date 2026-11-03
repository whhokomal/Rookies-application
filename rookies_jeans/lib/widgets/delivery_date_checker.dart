import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Check delivery date" on the product page, like the website's: the
/// customer enters a pincode and sees the expected delivery date and
/// whether COD is available there. The last pincode checked is remembered
/// and checked again automatically on the next product.
class DeliveryDateChecker extends StatefulWidget {
  const DeliveryDateChecker({super.key});

  @override
  State<DeliveryDateChecker> createState() => _DeliveryDateCheckerState();
}

class _DeliveryDateCheckerState extends State<DeliveryDateChecker> {
  /// The website's delivery-date worker. It answers
  /// `{ok, serviceable, cod, days, date}` for a pincode and weight in kg.
  static const _api = 'https://rookies-edd.skzaid264.workers.dev';

  /// Same default parcel weight the website sends.
  static const _weightKg = 0.5;
  static const _savedPinKey = 'rj_pin';

  final _controller = TextEditingController();
  bool _checking = false;
  String? _date;
  bool? _cod;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedPin();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadSavedPin() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_savedPinKey);
    if (saved == null || !mounted) return;
    _controller.text = saved;
    _check();
  }

  Future<void> _check() async {
    FocusScope.of(context).unfocus();
    final pin = _controller.text.trim();
    if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(pin)) {
      setState(() {
        _date = null;
        _error = 'Enter a valid 6-digit pincode';
      });
      return;
    }
    setState(() {
      _checking = true;
      _date = null;
      _error = null;
    });
    try {
      final res = await http
          .get(Uri.parse('$_api?pincode=$pin&weight=$_weightKg'))
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw const FormatException();
      if (!mounted) return;
      if (data['serviceable'] != true) {
        setState(() => _error = "We don't deliver to $pin yet");
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_savedPinKey, pin);
      if (!mounted) return;
      setState(() {
        _date = '${data['date']}';
        _cod = data['cod'] == true;
      });
    } catch (e) {
      // On a web build this is usually the worker's CORS rule, which only
      // allows https://rookiesjeans.com.
      debugPrint('DeliveryDateChecker: $pin failed: $e');
      if (mounted) {
        setState(() => _error = "Couldn't check right now. Try again.");
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final border = BorderSide(color: AppColors.primary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CHECK DELIVERY DATE',
          style: TextStyle(
            fontFamily: AppFonts.accent,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 10),
        // One outline around the field and button, so both are exactly the
        // same height.
        Container(
          height: 44,
          decoration: BoxDecoration(border: Border.fromBorderSide(border)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.postalCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onSubmitted: (_) => _check(),
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: 14,
                    color: AppColors.primary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter pincode',
                    hintStyle: TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: 14,
                      color: AppColors.hint,
                    ),
                    isDense: true,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  expands: true,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.center,
                ),
              ),
              Material(
                color: AppColors.primary,
                child: InkWell(
                  onTap: _checking ? null : _check,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Center(
                      child: _checking
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onPrimary,
                              ),
                            )
                          : Text(
                              'CHECK',
                              style: TextStyle(
                                fontFamily: AppFonts.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: AppColors.onPrimary,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_error != null || _date != null) ...[
          const SizedBox(height: 8),
          _message(),
        ],
      ],
    );
  }

  Widget _message() {
    final style = TextStyle(
      fontFamily: AppFonts.body,
      fontSize: 13,
      height: 1.4,
      color: _error != null ? AppColors.danger : AppColors.primary,
    );
    if (_error != null) return Text(_error!, style: style);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          const TextSpan(text: 'Get it by '),
          TextSpan(
            text: _date,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: ' · ${_cod == true ? 'COD available' : 'Prepaid only'}',
          ),
        ],
      ),
    );
  }
}
