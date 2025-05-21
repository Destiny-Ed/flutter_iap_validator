# flutter_iap_validator

A Flutter package for secure in-app purchase and receipt validation on iOS and Android. Offers two backend options: Firebase Functions (JavaScript) or a custom Dart server. Used in NotteChat for flexible monetization.

## Features

- **Cross-Platform**: Validates iOS (StoreKit 2) and Android (Google Play Billing).
- **Subscriptions & Consumables**: Handles multiple subscription tiers and consumable IAPs.
- **Dual Backends**: Choose Firebase Functions or a custom Dart server for validation.
- **Validation-Only**: Returns purchase status, giving apps full data control.
- **Dynamic Configuration**: Supports any product IDs and types.

## Installation

Add to `pubspec.yaml`:

```yaml
dependencies:
  flutter_iap_validator: ^1.0.0
  in_app_purchase: ^3.2.0
  http: ^1.2.2
  firebase_auth: ^4.12.0 # Required for Dart backend
```

Run:

```bash
flutter pub get
```

## Usage

### Initialize the validator

```dart
final validator = IAPValidator(
  backendUrl: 'https://your-backend.com/validate', // Firebase or Dart server URL
  backendType: BackendType.dart, // or BackendType.firebase
  products: {
    'pro_weekly': ProductType.subscription,
    'pro_monthly': ProductType.subscription,
    'pro_yearly': ProductType.subscription,
    'query_credits_10': ProductType.consumable,
    'ad_free_session': ProductType.consumable,
  },
  auth: FirebaseAuth.instance, // Required for Dart backend
  onConsumableDelivered: (productId, quantity, result) {
    if (result.isValid && productId == 'query_credits_10') {
      print('Add $quantity credits for user');
    }
  },
);
await validator.initialize();
```

### Fetch products

```dart
final products = await validator.fetchProducts();
print('Available products: ${products.map((p) => p.id)}');
```

### Initiate a purchase

```dart
await validator.buyProduct('pro_monthly'); // Subscription
await validator.buyProduct('query_credits_10'); // Consumable
```

### Check purchase status

```dart
if (validator.isSubscribed()) {
  print('Pro subscription active!');
} else if (validator.isPurchased('query_credits_10')) {
  print('Query credits purchased!');
}
```

### Dispose when done

```dart
validator.dispose();
```

## Backend Setup

### Option 1: Firebase Functions (JavaScript)

#### Deploy `functions/index.js`

Install dependencies:

```bash
cd functions
npm install firebase-functions axios
```

Set environment variables:

```bash
firebase functions:config:set apple_api_token="your_apple_api_token" google_client_id="your_client_id" google_client_secret="your_client_secret" google_refresh_token="your_refresh_token" android_package_name="your.package.name"
```

Deploy:

```bash
firebase deploy --only functions
```

Use the function URL (e.g., `https://us-central1-your-project.cloudfunctions.net/validateReceipt`).

### Option 2: Custom Dart Backend

Run `server/bin/server.dart`

Install dependencies:

```bash
cd server
dart pub get
```

Set environment variables:

```bash
export FIREBASE_SERVICE_ACCOUNT='{"type":"service_account",...}'
export APPLE_API_TOKEN="your_apple_api_token"
export GOOGLE_CLIENT_ID="your_client_id"
export GOOGLE_CLIENT_SECRET="your_client_secret"
export GOOGLE_REFRESH_TOKEN="your_refresh_token"
export ANDROID_PACKAGE_NAME="your.package.name"
```

Run locally:

```bash
dart run bin/server.dart
```

Deploy to Cloud Run:

```dockerfile
FROM dart:stable
WORKDIR /app
COPY server/ .
RUN dart pub get
CMD ["dart", "run", "bin/server.dart"]
```

```bash
gcloud run deploy iap-validator   --source .   --region us-central1   --allow-unauthenticated   --set-env-vars "FIREBASE_SERVICE_ACCOUNT=$FIREBASE_SERVICE_ACCOUNT,APPLE_API_TOKEN=$APPLE_API_TOKEN,..."
```

## Obtaining Tokens and Secrets

### Apple (App Store Connect)

#### App-Specific Shared Secret

1. Sign in to App Store Connect.
2. Go to Apps > Select your app > In-App Purchases > Manage.
3. Generate/View the App-Specific Shared Secret.

#### App Store Server API Token

1. Go to Users and Access > Integrations > App Store Server API.
2. Generate API Key and download `.p8` file.
3. Use Issuer ID and Key ID to generate a JWT:

```json
{
  "iss": "your_issuer_id",
  "iat": Math.floor(Date.now() / 1000),
  "exp": Math.floor(Date.now() / 1000) + 3600,
  "aud": "appstoreconnect-v1",
  "bid": "com.example.nottechat"
}
```

Use a JWT library and sign with the private key.

### Google (Google Play Console)

#### Service Account for Google Play Developer API

1. Go to API access > Service Accounts in Play Console.
2. Create service account in Google Cloud Console and download the key.
3. Assign Android Publisher role.
4. Grant access to app in Play Console.

#### Refresh Token

Use OAuth Playground to get a refresh token if needed.

#### Android Package Name

Find in Play Console app details.

### Firebase Service Account (Dart Only)

Generate from Firebase Console > Service Accounts and set:

```bash
export FIREBASE_SERVICE_ACCOUNT='{"type":"service_account","project_id":"your-project",...}'
```

## NotteChat Example

```dart
Future<void> handlePurchase(ValidationResult result) async {
  final userId = FirebaseAuth.instance.currentUser?.uid;
  if (result.isValid) {
    if (result.type == ProductType.subscription) {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'subscriptionStatus': {
          'productId': result.productId,
          'isActive': true,
          'expiresDate': result.expiresDate,
        },
      });
    } else if (result.productId == 'query_credits_10') {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'queryCredits': FieldValue.increment(10),
      });
    } else if (result.productId == 'ad_free_session') {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'adFreeUntil': DateTime.now().add(Duration(hours: 24)).millisecondsSinceEpoch,
      });
    }
  }
}
```

## License

MIT License

## Contributing

Fork, create pull requests, or open issues at https://github.com/Destiny-Ed/flutter_iap_validator.
