// import 'package:shelf/shelf.dart';
// import 'package:shelf/shelf_io.dart' as io;
// import '../lib/validator.dart';

// void main() async {
//   final validator = ReceiptValidator();
//   final handler = const Pipeline()
//       .addMiddleware(logRequests())
//       .addHandler(validator.handleRequest);

//   final server = await io.serve(handler, '0.0.0.0', 8080);
//   print('Server running on ${server.address}:${server.port}');
// }