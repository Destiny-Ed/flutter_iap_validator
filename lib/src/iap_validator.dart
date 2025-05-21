import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Type of in-app purchase product.
enum ProductType { subscription, consumable }

/// Backend type for validation.
enum BackendType { firebase, dart }

/// Result of a receipt validation.
class ValidationResult {
  final bool isValid;
  final int? expiresDate; // Milliseconds since epoch
  final String productId;
  final ProductType type;

  ValidationResult({
    required this.isValid,
    required this.expiresDate,
    required this.productId,
    required this.type,
  });

  factory ValidationResult.fromJson(Map<String, dynamic> json) {
    return ValidationResult(
      isValid: json['isValid'] == true,
      expiresDate: json['expiresDate'] as int?,
      productId: json['productId'] as String,
      type: json['type'] == 'consumable' ? ProductType.consumable : ProductType.subscription,
    );
  }
}

/// Validates in-app purchases and receipts for iOS and Android Flutter apps.
class IAPValidator {
  final InAppPurchase _iap = InAppPurchase.instance;
  final String _backendUrl;
  final BackendType _backendType;
  final Map<String, ProductType> _products;
  final FirebaseAuth? _auth;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  final Map<String, bool> _subscriptionStatus = {};
  final Function(String productId, int quantity, ValidationResult result)? _onConsumableDelivered;

  /// Constructs an [IAPValidator] with backend details, product configurations,
  /// and optional consumable delivery callback.
  IAPValidator({
    required String backendUrl,
    required BackendType backendType,
    required Map<String, ProductType> products,
    FirebaseAuth? auth,
    Function(String productId, int quantity, ValidationResult result)? onConsumableDelivered,
  })  : _backendUrl = backendUrl,
        _backendType = backendType,
        _products = products,
        _auth = backendType == BackendType.dart ? (auth ?? FirebaseAuth.instance) : null,
        _onConsumableDelivered = onConsumableDelivered;

  /// Initializes the validator and listens for purchase updates.
  Future<void> initialize() async {
    final bool isAvailable = await _iap.isAvailable();
    if (!isAvailable) {
      throw Exception('In-app purchase not available');
    }

    _subscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (e) => print('Purchase stream error: $e'),
    );

    await _iap.restorePurchases();
  }

  /// Fetches available products.
  Future<List<ProductDetails>> fetchProducts() async {
    final response = await _iap.queryProductDetails(_products.keys.toSet());
    if (response.productDetails.isEmpty) {
      throw Exception('No products found');
    }
    return response.productDetails;
  }

  /// Initiates a purchase for the specified product ID.
  Future<void> buyProduct(String productId) async {
    if (!_products.containsKey(productId)) {
      throw Exception('Unknown product: $productId');
    }

    final products = await fetchProducts();
    final product = products.firstWhere(
      (p) => p.id == productId,
      orElse: () => throw Exception('Product $productId not found'),
    );

    final purchaseParam = PurchaseParam(productDetails: product);
    final isConsumable = _products[productId] == ProductType.consumable;
    await _iap.buyConsumable(
      purchaseParam: purchaseParam,
      autoConsume: !isConsumable,
    );
  }

  /// Checks if any subscription is active.
  bool isSubscribed() => _subscriptionStatus.values.any((active) => active);

  /// Checks if a specific product is purchased.
  bool isPurchased(String productId) => _subscriptionStatus[productId] ?? false;

  /// Handles purchase updates and validates receipts.
  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (!_products.containsKey(purchase.productID)) continue;

      final isConsumable = _products[purchase.productID] == ProductType.consumable;

      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final result = await _validateReceipt(purchase);
          if (result.isValid) {
            if (isConsumable) {
              _onConsumableDelivered?.call(purchase.productID, 1, result);
              await _iap.completePurchase(purchase);
            } else {
              _subscriptionStatus[purchase.productID] = true;
              await _iap.completePurchase(purchase);
            }
            print('Purchase validated: ${purchase.productID}');
          } else {
            print('Invalid purchase: ${purchase.error}');
          }
          break;
        case PurchaseStatus.error:
          print('Purchase error: ${purchase.error}');
          _subscriptionStatus[purchase.productID] = false;
          break;
        case PurchaseStatus.canceled:
          print('Purchase canceled: ${purchase.productID}');
          _subscriptionStatus[purchase.productID] = false;
          break;
        default:
          break;
      }
    }
  }

  /// Validates a receipt with the chosen backend.
  Future<ValidationResult> _validateReceipt(PurchaseDetails purchase) async {
    try {
      final headers = {'Content-Type': 'application/json'};
      final body = {
        'platform': purchase.productID.contains('android') ? 'android' : 'ios',
        'receipt': purchase.verificationData.serverVerificationData,
        'productId': purchase.productID,
        'type': _products[purchase.productID] == ProductType.consumable ? 'consumable' : 'subscription',
      };

      if (_backendType == BackendType.dart) {
        final idToken = await _auth?.currentUser?.getIdToken();
        if (idToken == null) {
          throw Exception('User not authenticated for Dart backend');
        }
        headers['Authorization'] = 'Bearer $idToken';
        body['userId'] = _auth?.currentUser?.uid ?? "";
      }

      final response = await http.post(
        Uri.parse(_backendUrl),
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        throw Exception('Backend validation failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ValidationResult.fromJson(data);
    } catch (e) {
      print('Receipt validation failed: $e');
      return ValidationResult(
        isValid: false,
        expiresDate: null,
        productId: purchase.productID,
        type: _products[purchase.productID]!,
      );
    }
  }

  /// Disposes the purchase stream.
  void dispose() {
    _subscription?.cancel();
  }
}