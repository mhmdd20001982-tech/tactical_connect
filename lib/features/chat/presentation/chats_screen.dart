import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/identity/device_id_provider.dart';

// مزوّد يجلب رسائل الفريق الحالي
final teamMessagesProvider = StreamProvider.autoDispose.family<List<Message>, String>((ref, teamId) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.messages)
        ..where((m) => m.teamId.equals(teamId))
        ..orderBy([(m) => drift.OrderingTerm(expression: m.createdAt, mode: drift.OrderingMode.asc)]))
      .watch();
});

// مزوّد يجلب الفريق النشط الأخير دون الوقوع بخطأ التكرار
final activeTeamProvider = FutureProvider.autoDispose<Team?>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final teams = await (db.select(db.teams)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => drift.OrderingTerm(expression: t.createdAt, mode: drift.OrderingMode.desc)])
        ..limit(1))
      .get();
  return teams.isEmpty ? null : teams.first;
});

class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String teamId) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    final db = ref.read(appDatabaseProvider);
    final selfDeviceId = await DeviceIdProvider.getDeviceId();
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.into(db.messages).insert(
      MessagesCompanion.insert(
        id: const Uuid().v4(),
        teamId: teamId,
        senderDeviceId: selfDeviceId,
        type: 'text',
        content: drift.Value(text),
        createdAt: now,
        syncState: const drift.Value('LOCAL'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeTeamAsync = ref.watch(activeTeamProvider);

    return activeTeamAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) => Scaffold(body: Center(child: Text('خطأ: $err'))),
      data: (team) {
        if (team == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('المحادثة الميدانية')),
            body: const Center(
              child: Text(
                'لا يوجد فريق متصل حالياً\nيرجى الانضمام لفريق من تبويب Team',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final messagesAsync = ref.watch(teamMessagesProvider(team.id));

        return Scaffold(
          appBar: AppBar(
            title: Text('غرفة: ${team.name}'),
            actions: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text('كود: ${team.teamCode}', style: const TextStyle(color: Colors.tealAccent)),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: messagesAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, _) => Center(child: Text('خطأ في جلب الرسائل: $err')),
                  data: (messages) {
                    if (messages.isEmpty) {
                      return const Center(child: Text('لا توجد رسائل بعد. ابدأ المحادثة الميدانية!'));
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        return FutureBuilder<String>(
                          future: DeviceIdProvider.getDeviceId(),
                          builder: (context, snapshot) {
                            final isMe = snapshot.data == msg.senderDeviceId;
                            return Align(
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isMe ? Colors.teal.shade800 : Colors.grey.shade800,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      msg.content ?? '',
                                      style: const TextStyle(fontSize: 16, color: Colors.white),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      DateTime.fromMillisecondsSinceEpoch(msg.createdAt)
                                          .toLocal()
                                          .toString()
                                          .substring(11, 16),
                                      style: const TextStyle(fontSize: 10, color: Colors.white60),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  border: Border(top: BorderSide(color: Colors.grey.shade800)),
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: 'اكتب رسالة ميدانية...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _sendMessage(team.id),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        icon: const Icon(Icons.send),
                        onPressed: () => _sendMessage(team.id),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}