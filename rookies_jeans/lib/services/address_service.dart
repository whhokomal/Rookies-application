import 'package:flutter/foundation.dart';
import 'package:rookies_jeans/services/shopify_api.dart';
import 'package:rookies_jeans/models/address_model.dart';
import 'package:rookies_jeans/services/shopify_auth_service.dart';

class AddressService extends ChangeNotifier {
  AddressService._();
  static final AddressService instance = AddressService._();

  List<ShopifyAddress> _addresses = [];
  bool _isLoading = false;
  String? _error;

  List<ShopifyAddress> get addresses => List.unmodifiable(_addresses);
  bool get isLoading => _isLoading;
  String? get error => _error;

  void _log(String msg) {
    if (kDebugMode) debugPrint('[AddressService] $msg');
  }

  String _normalizeId(String id) => id.contains('?') ? id.split('?').first : id;

  List<ShopifyAddress> _sortAddresses(List<ShopifyAddress> list) {
    final sorted = List<ShopifyAddress>.from(list);
    sorted.sort((a, b) {
      if (a.isDefault && !b.isDefault) return -1;
      if (!a.isDefault && b.isDefault) return 1;
      return 0;
    });
    return sorted;
  }

  Future<void> fetchAddresses() async {
    final token = await ShopifyAuthService.instance.getSavedCustomerToken();
    if (token == null || token.isEmpty) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    const query = r'''
      query customerAddresses($token: String!) {
        customer(customerAccessToken: $token) {
          defaultAddress { id }
          addresses(first: 100) {
            edges {
              node {
                id
                firstName
                lastName
                address1
                address2
                city
                province
                country
                zip
                phone
              }
            }
          }
        }
      }
    ''';

    try {
      final res = await ShopifyGraphQL.post(
        query,
        variables: {'token': token},
        tag: 'AddressService',
      );

      _log('fetchAddresses status: ${res.statusCode}');
      final customer = res.data?['customer'] as Map<String, dynamic>?;

      if (customer == null) {
        _error = 'Could not load addresses.';
        return;
      }

      final rawDefaultId =
          (customer['defaultAddress'] as Map<String, dynamic>?)?['id']
              as String?;

      final defaultId =
          rawDefaultId != null ? _normalizeId(rawDefaultId) : null;

      _log('fetchAddresses defaultId (normalized): $defaultId');

      final edges = customer['addresses']?['edges'] as List<dynamic>? ?? [];

      final parsed = edges.map((e) {
        final node = e['node'] as Map<String, dynamic>;
        final nodeId = _normalizeId(node['id'] as String);
        return ShopifyAddress.fromJson(
          node,
          isDefault: nodeId == defaultId,
        );
      }).toList();

      _addresses = _sortAddresses(parsed);
    } catch (e, stack) {
      _log('fetchAddresses error: $e\n$stack');
      _error = 'Failed to load addresses.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> addAddress(
    Map<String, dynamic> addressInput, {
    bool setAsDefault = false,
  }) async {
    final token = await ShopifyAuthService.instance.getSavedCustomerToken();
    if (token == null) return 'Not logged in.';

    const mutation = r'''
      mutation customerAddressCreate(
        $token: String!
        $address: MailingAddressInput!
      ) {
        customerAddressCreate(
          customerAccessToken: $token
          address: $address
        ) {
          customerAddress { id }
          customerUserErrors { message }
        }
      }
    ''';

    try {
      final res = await ShopifyGraphQL.post(
        mutation,
        variables: {'token': token, 'address': addressInput},
      );

      final result = res.data?['customerAddressCreate'];
      final errors = result?['customerUserErrors'] as List? ?? [];

      if (errors.isNotEmpty) {
        final msg = errors.first['message'] as String? ?? 'Could not add address.';
        _log('addAddress errors: $errors');
        return msg;
      }

      final newId = result?['customerAddress']?['id'] as String?;

      if (setAsDefault && newId != null) {
        await setDefaultAddress(newId);
      } else {
        await fetchAddresses();
      }

      return null;
    } catch (e) {
      _log('addAddress exception: $e');
      return 'Something went wrong.';
    }
  }

  Future<String?> updateAddress(
    String addressId,
    Map<String, dynamic> addressInput, {
    bool setAsDefault = false,
  }) async {
    final token = await ShopifyAuthService.instance.getSavedCustomerToken();
    if (token == null) return 'Not logged in.';

    const mutation = r'''
      mutation customerAddressUpdate(
        $token: String!
        $id: ID!
        $address: MailingAddressInput!
      ) {
        customerAddressUpdate(
          customerAccessToken: $token
          id: $id
          address: $address
        ) {
          customerAddress { id }
          customerUserErrors { message }
        }
      }
    ''';

    try {
      final res = await ShopifyGraphQL.post(
        mutation,
        variables: {
          'token': token,
          'id': addressId,
          'address': addressInput,
        },
      );

      final result = res.data?['customerAddressUpdate'];
      final errors = result?['customerUserErrors'] as List? ?? [];

      if (errors.isNotEmpty) {
        final msg = errors.first['message'] as String? ?? 'Could not update address.';
        _log('updateAddress errors: $errors');
        return msg;
      }

      if (setAsDefault) {
        await setDefaultAddress(addressId);
      } else {
        await fetchAddresses();
      }

      return null;
    } catch (e) {
      _log('updateAddress exception: $e');
      return 'Something went wrong.';
    }
  }

  Future<String?> deleteAddress(String addressId) async {
    final token = await ShopifyAuthService.instance.getSavedCustomerToken();
    if (token == null) return 'Not logged in.';

    const mutation = r'''
      mutation customerAddressDelete($token: String!, $id: ID!) {
        customerAddressDelete(
          customerAccessToken: $token
          id: $id
        ) {
          deletedCustomerAddressId
          customerUserErrors { message }
        }
      }
    ''';

    try {
      final res = await ShopifyGraphQL.post(
        mutation,
        variables: {'token': token, 'id': addressId},
      );

      final result = res.data?['customerAddressDelete'];
      final errors = result?['customerUserErrors'] as List? ?? [];

      if (errors.isNotEmpty) {
        final msg = errors.first['message'] as String? ?? 'Could not delete address.';
        _log('deleteAddress errors: $errors');
        return msg;
      }

      _addresses = _sortAddresses(
        _addresses.where((a) => a.id != addressId).toList(),
      );
      notifyListeners();
      return null;
    } catch (e) {
      _log('deleteAddress exception: $e');
      return 'Something went wrong.';
    }
  }

  Future<bool> setDefaultAddress(String addressId) async {
    final token = await ShopifyAuthService.instance.getSavedCustomerToken();
    if (token == null) return false;

    const mutation = r'''
      mutation customerDefaultAddressUpdate(
        $token: String!
        $addressId: ID!
      ) {
        customerDefaultAddressUpdate(
          customerAccessToken: $token
          addressId: $addressId
        ) {
          customer { defaultAddress { id } }
          customerUserErrors { message }
        }
      }
    ''';

    try {
      final res = await ShopifyGraphQL.post(
        mutation,
        variables: {'token': token, 'addressId': addressId},
      );

      _log('setDefaultAddress raw response: ${res.body}');

      final result = res.data?['customerDefaultAddressUpdate'];
      final errors = result?['customerUserErrors'] as List? ?? [];

      if (errors.isNotEmpty) {
        _log('setDefaultAddress errors: $errors');
        return false;
      }

      final rawConfirmedId =
          result?['customer']?['defaultAddress']?['id'] as String?;

      final effectiveDefaultId = rawConfirmedId != null
          ? _normalizeId(rawConfirmedId)
          : _normalizeId(addressId);

      _log('setDefaultAddress effectiveDefaultId (normalized): $effectiveDefaultId');

      _addresses = _sortAddresses(
        _addresses
            .map((a) => ShopifyAddress(
                  id: a.id,
                  firstName: a.firstName,
                  lastName: a.lastName,
                  address1: a.address1,
                  address2: a.address2,
                  city: a.city,
                  province: a.province,
                  country: a.country,
                  zip: a.zip,
                  phone: a.phone,
                  isDefault: _normalizeId(a.id) == effectiveDefaultId,
                ))
            .toList(),
      );

      notifyListeners();

      await fetchAddresses();

      return true;
    } catch (e) {
      _log('setDefaultAddress exception: $e');
      return false;
    }
  }

  void clearAddresses() {
    _addresses = [];
    _error = null;
    notifyListeners();
  }
}
