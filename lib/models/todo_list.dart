import 'package:powersync/powersync.dart';
import 'package:sqlite3/sqlite3.dart';
import '../database/powersync.dart';
import '../app_config.dart';

/// A list that groups [Todo] items, synced via PowerSync.
class TodoList {
  final String id;
  final String createdBy;
  final String name;

  const TodoList({
    required this.id,
    required this.createdBy,
    required this.name,
  });

  factory TodoList.fromRow(ResultSet rs, int index) {
    return TodoList(
      id: rs.rows[index][rs.columnNames.indexOf('id')] as String,
      createdBy:
          rs.rows[index][rs.columnNames.indexOf('created_by')] as String? ?? '',
      name: rs.rows[index][rs.columnNames.indexOf('name')] as String? ?? '',
    );
  }

  /// All lists for the current user — reactive stream.
  static Stream<List<TodoList>> watchAll() {
    return db
        .watch(
          'SELECT * FROM lists WHERE created_by = ? ORDER BY created_at ASC',
          parameters: [devUserId],
        )
        .map(
          (rs) => List.generate(rs.rows.length, (i) => TodoList.fromRow(rs, i)),
        );
  }

  /// Create a new list.
  static Future<void> create({required String id, required String name}) async {
    await db.execute(
      'INSERT INTO lists (id, created_by, name) VALUES (?, ?, ?)',
      [id, devUserId, name],
    );
  }

  /// Delete a list and its todos.
  static Future<void> delete(String id) async {
    await db.execute('DELETE FROM todos WHERE list_id = ?', [id]);
    await db.execute('DELETE FROM lists WHERE id = ?', [id]);
  }
}
