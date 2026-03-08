import 'package:powersync/powersync.dart';

/// PowerSync schema — must match the tables in your Go backend / Postgres.
///
/// PowerSync syncs these columns into the on-device SQLite database.
/// Order of columns matters: keep it in sync with your Go `db/db.go`.
final schema = Schema([
  Table('todos', [
    Column.text('list_id'),
    Column.text('created_by'),
    Column.text('description'),
    Column.integer('completed'), // SQLite has no boolean; 0/1
    Column.text('created_at'),
  ]),
  Table('lists', [
    Column.text('created_by'),
    Column.text('name'),
    Column.text('created_at'),
  ]),
]);
