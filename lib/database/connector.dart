import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:powersync/powersync.dart';

import '../app_config.dart';

/// Connects the PowerSync client to your Go backend.
///
/// Responsibilities:
///   1. [fetchCredentials] – obtain a JWT from the Go server and return it
///      to the PowerSync SDK so it can authenticate with the sync service.
///   2. [uploadData] – relay local mutations (created/updated/deleted rows)
///      to the Go backend via the /api/data endpoints.
class AppConnector extends PowerSyncBackendConnector {
  /// Cached token, refreshed automatically by PowerSync when it expires.
  PowerSyncCredentials? _cachedCredentials;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    // In production, replace devUserId with your real logged-in user's ID.
    final uri = Uri.parse('$backendUrl/api/auth/token?user_id=$devUserId');
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('fetchCredentials failed: ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['token'] as String;
    final expiresIn = (body['expires_in'] as num).toInt(); // seconds

    _cachedCredentials = PowerSyncCredentials(
      endpoint: powerSyncUrl,
      token: token,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
    return _cachedCredentials;
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) return;

    try {
      for (final op in transaction.crud) {
        await _uploadOp(op);
      }
      await transaction.complete();
    } catch (e) {
      // Leave the transaction in the queue so it retries on next upload.
      rethrow;
    }
  }

  Future<void> _uploadOp(CrudEntry op) async {
    final url = Uri.parse('$backendUrl/api/data');
    late http.Response response;

    switch (op.op) {
      case UpdateType.put:
        response = await http.put(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'id': op.id,
            'table': op.table,
            'op': 'PUT',
            'data': {'id': op.id, ...?op.opData},
          }),
        );
      case UpdateType.patch:
        response = await http.patch(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'id': op.id,
            'table': op.table,
            'op': 'PATCH',
            'data': {'id': op.id, ...?op.opData},
          }),
        );
      case UpdateType.delete:
        response = await http.delete(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'id': op.id, 'table': op.table, 'op': 'DELETE'}),
        );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Upload failed (${response.statusCode}): ${response.body}',
      );
    }
  }
}
