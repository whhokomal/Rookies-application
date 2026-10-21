import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rookies_jeans/constants/app_ui.dart';
import 'package:rookies_jeans/models/address_model.dart';
import 'package:rookies_jeans/services/address_service.dart';

class AddEditAddressScreen extends StatefulWidget {
  const AddEditAddressScreen({super.key, this.address});

  final ShopifyAddress? address;

  @override
  State<AddEditAddressScreen> createState() => _AddEditAddressScreenState();
}

class _AddEditAddressScreenState extends State<AddEditAddressScreen> {
  static const _fHead = AppFonts.heading;
  static const _fBody = AppFonts.body;
  static const _fBold = AppFonts.bold;

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _address1;
  late final TextEditingController _address2;
  late final TextEditingController _city;
  late final TextEditingController _province;
  late final TextEditingController _country;
  late final TextEditingController _zip;
  late final TextEditingController _phone;

  bool _setAsDefault = false;
  bool _isSaving     = false;

  bool get _isEditing => widget.address != null;

  @override
  void initState() {
    super.initState();
    final a = widget.address;
    _firstName = TextEditingController(text: a?.firstName ?? '');
    _lastName  = TextEditingController(text: a?.lastName  ?? '');
    _address1  = TextEditingController(text: a?.address1  ?? '');
    _address2  = TextEditingController(text: a?.address2  ?? '');
    _city      = TextEditingController(text: a?.city      ?? '');
    _province  = TextEditingController(text: a?.province  ?? '');
    _country   = TextEditingController(text: a?.country   ?? 'India');
    _zip       = TextEditingController(text: a?.zip       ?? '');
    _phone     = TextEditingController(text: a?.phone     ?? '');
    _setAsDefault = a?.isDefault ?? false;
  }

  @override
  void dispose() {
    for (final c in [
      _firstName, _lastName, _address1, _address2,
      _city, _province, _country, _zip, _phone,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final input = {
      'firstName': _firstName.text.trim(),
      'lastName' : _lastName.text.trim(),
      'address1' : _address1.text.trim(),
      'address2' : _address2.text.trim(),
      'city'     : _city.text.trim(),
      'province' : _province.text.trim(),
      'country'  : _country.text.trim(),
      'zip'      : _zip.text.trim(),
      'phone'    : _phone.text.trim(),
    };

    String? error;
    if (_isEditing) {
      error = await AddressService.instance.updateAddress(
        widget.address!.id,
        input,
        setAsDefault: _setAsDefault,
      );
    } else {
      error = await AddressService.instance.addAddress(
        input,
        setAsDefault: _setAsDefault,
      );
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error,
            style: const TextStyle(fontFamily: _fBody, color: Colors.white),
          ),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) => Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        toolbarHeight: 84,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(left: 12, right: 16),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(false),
                child: Icon(
                  Icons.arrow_back_ios_new,
                  size: 22,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _isEditing ? 'EDIT ADDRESS' : 'ADD ADDRESS',
                style: TextStyle(
                  fontSize: 34,
                  height: 1,
                  fontFamily: _fHead,
                  fontStyle: FontStyle.italic,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
          children: [
            _sectionLabel('Full Name'),
            Row(
              children: [
                Expanded(
                  child: _field(
                    controller: _firstName,
                    hint: 'First name',
                    textCapitalization: TextCapitalization.words,
                    validator: _required,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(
                    controller: _lastName,
                    hint: 'Last name',
                    textCapitalization: TextCapitalization.words,
                    validator: _required,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _sectionLabel('Address'),
            _field(
              controller: _address1,
              hint: 'Flat / House no., Building, Street',
              textCapitalization: TextCapitalization.sentences,
              validator: _required,
            ),
            const SizedBox(height: 10),
            _field(
              controller: _address2,
              hint: 'Area, Colony, Landmark (optional)',
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 18),
            _sectionLabel('City & State'),
            Row(
              children: [
                Expanded(
                  child: _field(
                    controller: _city,
                    hint: 'City',
                    textCapitalization: TextCapitalization.words,
                    validator: _required,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(
                    controller: _province,
                    hint: 'State',
                    textCapitalization: TextCapitalization.words,
                    validator: _required,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _sectionLabel('Pincode & Country'),
            Row(
              children: [
                Expanded(
                  child: _field(
                    controller: _zip,
                    hint: 'Pincode',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (v.trim().length < 4) return 'Invalid pincode';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(
                    controller: _country,
                    hint: 'Country',
                    textCapitalization: TextCapitalization.words,
                    validator: _required,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _sectionLabel('Phone Number'),
            _field(
              controller: _phone,
              hint: '+91 98765 43210',
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]'))],
            ),
            const SizedBox(height: 24),
            Container(
              color: AppColors.card,
              child: InkWell(
                onTap: () => setState(() => _setAsDefault = !_setAsDefault),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Set as default address',
                              style: TextStyle(
                                fontFamily: _fBold,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'This address will be pre-selected at checkout',
                              style: TextStyle(
                                fontFamily: _fBody,
                                fontSize: 11,
                                color: AppColors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _setAsDefault,
                        onChanged: (v) => setState(() => _setAsDefault = v),
                        activeThumbColor: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
                shape: AppShapes.button,
              ),
              child: _isSaving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.onPrimary),
                    )
                  : Text(
                      _isEditing ? 'Save Changes' : 'Add Address',
                      style: const TextStyle(
                        fontFamily: _fBold,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: _fBold,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.secondaryText,
            letterSpacing: 0.8,
          ),
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        validator: validator,
        style: TextStyle(
          fontFamily: _fBody,
          fontSize: 14,
          color: AppColors.primary,
        ),
        decoration: InputDecoration(
          filled: true,
          fillColor: AppColors.fieldFill,
          hintText: hint,
          hintStyle: TextStyle(
            fontFamily: _fBody,
            fontSize: 14,
            color: AppColors.hint,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: AppColors.primary, width: 1.5),
          ),
          errorBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: Color(0xFFD32F2F)),
          ),
          focusedErrorBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: Color(0xFFD32F2F), width: 1.5),
          ),
          errorStyle: const TextStyle(
            fontFamily: _fBody,
            fontSize: 11,
            color: Color(0xFFD32F2F),
          ),
        ),
      );

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return null;
  }
}