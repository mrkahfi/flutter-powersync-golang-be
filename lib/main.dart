import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:uuid/uuid.dart';

import 'database/powersync.dart';
import 'models/todo.dart';
import 'models/todo_list.dart';
import 'map_screen.dart';

const _uuid = Uuid();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await openDatabase();
  runApp(const PowerSyncApp());
}

// ─── App shell ───────────────────────────────────────────────────────────────

class PowerSyncApp extends StatelessWidget {
  const PowerSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PowerSync Todos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Roboto',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white10,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
      home: const ListsScreen(),
    );
  }
}

// ─── Sync status badge ───────────────────────────────────────────────────────

class _SyncStatusBadge extends StatelessWidget {
  const _SyncStatusBadge();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: db.statusStream,
      builder: (context, snap) {
        final status = snap.data;
        final connected = status?.connected ?? false;
        final syncing = status?.downloading ?? false;

        final color = connected
            ? (syncing ? Colors.amber : Colors.greenAccent)
            : Colors.redAccent;
        final label = connected ? (syncing ? 'Syncing…' : 'Live') : 'Offline';

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withAlpha(30),
            border: Border.all(color: color, width: 1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 4, backgroundColor: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Lists screen ────────────────────────────────────────────────────────────

class ListsScreen extends StatelessWidget {
  const ListsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Lists',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MapScreen()),
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: _SyncStatusBadge(),
          ),
        ],
      ),
      body: StreamBuilder<List<TodoList>>(
        stream: TodoList.watchAll(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final lists = snap.data!;
          if (lists.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.list_alt, size: 64, color: Colors.white24),
                  const SizedBox(height: 12),
                  Text(
                    'No lists yet',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.white38),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap + to create your first list',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white24),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: lists.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final list = lists[i];
              return _ListCard(list: list);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateListDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('New List'),
      ),
    );
  }

  void _showCreateListDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New List'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'List name…'),
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _submit(ctx, controller),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _submit(ctx, controller),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(BuildContext ctx, TextEditingController c) async {
    final name = c.text.trim();
    if (name.isEmpty) return;
    await TodoList.create(id: _uuid.v4(), name: name);
    if (ctx.mounted) Navigator.pop(ctx);
  }
}

class _ListCard extends StatelessWidget {
  final TodoList list;

  const _ListCard({required this.list});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(list.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_rounded, color: colors.onErrorContainer),
      ),
      onDismissed: (_) => TodoList.delete(list.id),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => TodosScreen(list: list)),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 8,
          ),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.checklist_rounded,
              color: colors.onPrimaryContainer,
            ),
          ),
          title: Text(
            list.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      ),
    );
  }
}

// ─── Todos screen ─────────────────────────────────────────────────────────────

class TodosScreen extends StatelessWidget {
  final TodoList list;

  const TodosScreen({super.key, required this.list});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          list.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: _SyncStatusBadge(),
          ),
        ],
      ),
      body: StreamBuilder<List<Todo>>(
        stream: Todo.watchForList(list.id),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final todos = snap.data!;
          if (todos.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Colors.white24,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'All clear!',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.white38),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap + to add a task',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white24),
                  ),
                ],
              ),
            );
          }

          final pending = todos.where((t) => !t.completed).toList();
          final done = todos.where((t) => t.completed).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (pending.isNotEmpty) ...[
                _sectionHeader(context, 'Tasks (${pending.length})'),
                ...pending.map((t) => _TodoTile(todo: t)),
                const SizedBox(height: 16),
              ],
              if (done.isNotEmpty) ...[
                _sectionHeader(context, 'Completed (${done.length})'),
                ...done.map((t) => _TodoTile(todo: t)),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddTodoDialog(context),
        icon: const Icon(Icons.add_task_rounded),
        label: const Text('Add Task'),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Colors.white54,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  void _showAddTodoDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Task'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'What needs to be done?'),
          textCapitalization: TextCapitalization.sentences,
          maxLines: 2,
          onSubmitted: (_) => _submit(ctx, controller),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _submit(ctx, controller),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(BuildContext ctx, TextEditingController c) async {
    final desc = c.text.trim();
    if (desc.isEmpty) return;
    await Todo.create(id: _uuid.v4(), listId: list.id, description: desc);
    if (ctx.mounted) Navigator.pop(ctx);
  }
}

class _TodoTile extends StatelessWidget {
  final Todo todo;

  const _TodoTile({required this.todo});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey(todo.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.delete_rounded, color: colors.onErrorContainer),
      ),
      onDismissed: (_) => Todo.delete(todo.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: CheckboxListTile(
          value: todo.completed,
          onChanged: (v) => Todo.toggle(todo.id, v ?? false),
          title: Text(
            todo.description,
            style: TextStyle(
              decoration: todo.completed ? TextDecoration.lineThrough : null,
              color: todo.completed ? Colors.white38 : Colors.white,
            ),
          ),
          controlAffinity: ListTileControlAffinity.leading,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          checkboxShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }
}
