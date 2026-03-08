import 'package:powersync/powersync.dart';
import 'package:sqlite3/sqlite3.dart';
import '../database/powersync.dart';
import '../app_config.dart';

/// A to-do item synced via PowerSync.
class Todo {
  final String id;
  final String listId;
  final String createdBy;
  final String description;
  final bool completed;

  const Todo({
    required this.id,
    required this.listId,
    required this.createdBy,
    required this.description,
    required this.completed,
  });

  factory Todo.fromRow(ResultSet row, int index) {
    return Todo(
      id: row.rows[index][row.columnNames.indexOf('id')] as String,
      listId:
          row.rows[index][row.columnNames.indexOf('list_id')] as String? ?? '',
      createdBy:
          row.rows[index][row.columnNames.indexOf('created_by')] as String? ??
          '',
      description:
          row.rows[index][row.columnNames.indexOf('description')] as String? ??
          '',
      completed:
          (row.rows[index][row.columnNames.indexOf('completed')] as int? ??
              0) ==
          1,
    );
  }

  /// All todos for the given [listId], reactive stream.
  static Stream<List<Todo>> watchForList(String listId) {
    return db
        .watch(
          'SELECT * FROM todos WHERE list_id = ? ORDER BY created_at ASC',
          parameters: [listId],
        )
        .map((rs) => List.generate(rs.rows.length, (i) => Todo.fromRow(rs, i)));
  }

  /// Insert a new todo into local SQLite (gets synced automatically).
  static Future<void> create({
    required String id,
    required String listId,
    required String description,
  }) async {
    await db.execute(
      'INSERT INTO todos (id, list_id, created_by, description, completed) VALUES (?, ?, ?, ?, 0)',
      [id, listId, devUserId, description],
    );
  }

  /// Toggle the completed flag.
  static Future<void> toggle(String id, bool completed) async {
    await db.execute('UPDATE todos SET completed = ? WHERE id = ?', [
      completed ? 1 : 0,
      id,
    ]);
  }

  /// Delete a todo.
  static Future<void> delete(String id) async {
    await db.execute('DELETE FROM todos WHERE id = ?', [id]);
  }
}
