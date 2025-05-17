// import 'dart:convert';
// import 'package:shelf/shelf.dart';
// import 'package:http/http.dart' as http;
// import 'package:firebase_admin/firebase_admin.dart';
// import 'package:googleapis_auth/auth_io.dart' show ServiceAccountCredentials, clientViaServiceAccount;

// class ReceiptValidator {
//   Future<Response> handleRequest(Request request) async {
//     if (request.method != 'POST') {
//       return Response(405, body: jsonEncode({'error': 'Method not allowed'}));
//     }

//     try {
//       final body = await request.readAsString();
//       final data = jsonDecode(body) as Map<String, dynamic>;
//       final platform = data['platform'] as String?;
//       final receipt = data['receipt'] as String?;
//       final productId = data['productId'] as String?;
//       final type = data['type'] as String?;
//       final userId = data['userId'] as String?;

//       if (platform == null || receipt == null || productId == null || type == null || userId == null) {
//         return Response(400, body: jsonEncode({'error': 'Missing required fields'}));
//       }

//       // Initialize Firebase Admin SDK for Auth verification
//       final serviceAccountJson = const String.fromEnvironment('FIREBASE_SERVICE_ACCOUNT');
//       if (serviceAccountJson.isEmpty) {
//         throw Exception('FIREBASE_SERVICE_ACCOUNT environment variable is not set');
//       }

//       Map<String, dynamic> serviceAccount;
//       try {
//         serviceAccount = jsonDecode(serviceAccountJson) as Map<String, dynamic>;
//       } catch (e) {
//         print('Failed to parse FIREBASE_SERVICE_ACCOUNT: $e');
//         throw Exception('Invalid FIREBASE_SERVICE_ACCOUNT JSON');
//       }

//       FirebaseAdminApp app;
//       try {
//         app = await FirebaseAdmin.instance.initializeApp(
//           AppOptions(
//             credential: Credential(serviceAccount),
//             projectId: serviceAccount['project_id'] as String?,
//           ),
//         );
//       } catch (e) {
//         print('Firebase Admin initialization failed: $e');
//         // Fallback to googleapis_auth for token verification
//         final credentials = ServiceAccountCredentials.fromJson(serviceAccount);
//         final client = await clientViaServiceAccount(
//           credentials,
//           ['https://www.googleapis.com/auth/firebase'],
//         );
//         final token = await client.credentials.accessToken;
//         // Verify token manually
//         final response = await http.get(
//           Uri.parse('https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=${token.data}'),
//         );
//         if (response.statusCode != 200) {
//           throw Exception('Failed to verify fallback token: ${response.body}');
//         }
//         // Proceed with token verification
//         app = await FirebaseAdmin.instance.initializeApp(
//           AppOptions(projectId: serviceAccount['project_id'] as String?),
//         );
//       }

//       // Verify Firebase Auth token
//       final authToken = request.headers['Authorization']?.replaceFirst('Bearer ', '') ?? '';
//       if (authToken.isEmpty) {
//         return Response(401, body: jsonEncode({'error': 'Missing Authorization header'}));
//       }

//       dynamic decodedToken;
//       try {
//         decodedToken = await app.auth().verifyIdToken(authToken);
//       } catch (e) {
//         print('Token verification failed: $e');
//         return Response(401, body: jsonEncode({'error': 'Invalid Firebase Auth token'}));
//       }

//       if (decodedToken.uid != userId) {
//         return Response(401, body: jsonEncode({'error': 'Unauthorized: User ID mismatch'}));
//       }

//       bool isValid = false;
//       int? expiresDate;

//       if (platform == 'ios') {
//         final response = await http.get(
//           Uri.parse('https://api.storekit.itunes.apple.com/inApps/v1/transactions/$receipt'),
//           headers: {
//             'Authorization': 'Bearer ${const String.fromEnvironment('APPLE_API_TOKEN')}',
//           },
//         );

//         if (response.statusCode != 200) {
//           throw Exception('Apple API error: ${response.statusCode} ${response.body}');
//         }

//         final transaction = jsonDecode(response.body) as Map<String, dynamic>;
//         isValid = transaction['signedDate'] != null &&
//                   transaction['productId'] == productId &&
//                   (type == 'consumable' ? transaction['type'] == 'Consumable' : transaction['type'] == 'Auto-Renewable Subscription');
//         expiresDate = transaction['expiresDate'] as int?;
//       } else if (platform == 'android') {
//         final accessToken = await _getGoogleAccessToken();
//         final endpoint = type == 'consumable'
//             ? 'purchases/products/$productId/tokens/$receipt'
//             : 'purchases/subscriptions/$productId/tokens/$receipt';
//         final response = await http.get(
//           Uri.parse('https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${const String.fromEnvironment('ANDROID_PACKAGE_NAME')}/$endpoint'),
//           headers: {
//             'Authorization': 'Bearer $accessToken',
//           },
//         );

//         if (response.statusCode != 200) {
//           throw Exception('Google API error: ${response.statusCode} ${response.body}');
//         }

//         final purchase = jsonDecode(response.body) as Map<String, dynamic>;
//         isValid = type == 'consumable'
//             ? purchase['paymentState'] == 1
//             : purchase['paymentState'] == 1 && purchase['autoRenewing'] == true;
//         expiresDate = int.tryParse(purchase['expiryTimeMillis']?.toString() ?? '');
//       } else {
//         throw Exception('Invalid platform');
//       }

//       return Response.ok(
//         jsonEncode({
//           'isValid': isValid,
//           'expiresDate': expiresDate,
//           'productId': productId,
//           'type': type,
//         }),
//         headers: {'Content-Type': 'application/json'},
//       );
//     } catch (e) {
//       print('Validation error: $e');
//       return Response(500, body: jsonEncode({
//         'isValid': false,
//         'error': e.toString(),
//         'productId': data['productId'] ?? 'unknown',
//         'type': data['type'] ?? 'unknown',
//       }));
//     }
//   }

//   Future<String> _getGoogleAccessToken() async {
//     final response = await http.post(
//       Uri.parse('https://accounts.google.com/o/oauth2/token'),
//       headers: {'Content-Type': 'application/json'},
//       body: jsonEncode({
//         'grant_type': 'refresh_token',
//         'client_id': const String.fromEnvironment('GOOGLE_CLIENT_ID'),
//         'client_secret': const String.fromEnvironment('GOOGLE_CLIENT_SECRET'),
//         'refresh_token': const String.fromEnvironment('GOOGLE_REFRESH_TOKEN'),
//       }),
//     );

//     if (response.statusCode != 200) {
//       throw Exception('Failed to get Google access token: ${response.body}');
//     }

//     final data = jsonDecode(response.body) as Map<String, dynamic>;
//     return data['access_token'] as String;
//   }
// }