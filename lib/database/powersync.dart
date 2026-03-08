import 'package:powersync/powersync.dart';

import 'schema.dart';
import 'connector.dart';

import 'package:path_provider/path_provider.dart';

/// Global PowerSync database singleton.
late final PowerSyncDatabase db;

/// Call once from [main] before [runApp].
Future<void> openDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final path = '${dir.path}/powersync.db';

  db = PowerSyncDatabase(schema: schema, path: path);
  await db.initialize();

  // Connect to the backend — starts background sync immediately.
  await db.connect(connector: AppConnector());
}
