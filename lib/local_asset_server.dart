import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

class LocalAssetServer {
  static const int port = 8080;
  static Object? _server; // store the server instance

  static Future<void> start() async {
    if (_server != null) return;
    
    final handler = const Pipeline().addHandler(_handleRequest);
    try {
      _server = await io.serve(handler, '127.0.0.1', port, shared: true);
      print('LocalAssetServer running on http://127.0.0.1:$port');
    } catch (e) {
      print('LocalAssetServer failed to start: $e');
    }
  }

  static Future<Response> _handleRequest(Request request) async {
    final path = Uri.decodeComponent(request.url.path);
    try {
      final ByteData data = await rootBundle.load(path);
      final List<int> bytes = data.buffer.asUint8List();
      
      String contentType = 'application/octet-stream';
      if (path.endsWith('.json')) contentType = 'application/json';
      else if (path.endsWith('.png')) contentType = 'image/png';
      else if (path.endsWith('.pbf')) contentType = 'application/x-protobuf';
      
      // Need permissive CORS for Web GL fetch (even though we're in app context)
      final headers = {
        'Content-Type': contentType,
        'Access-Control-Allow-Origin': '*',
      };
      return Response.ok(bytes, headers: headers);
    } catch (e) {
      print('LocalAssetServer: Asset not found: $path');
      return Response.notFound('Not found');
    }
  }
}
