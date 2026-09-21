import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/session/peer_session.dart';
import '../application/session_controller.dart';
import '../data/team_repository.dart';
import 'join_team_screen.dart';

/// The "Team" tab: create or join a team, or show the active one.
class TeamTab extends ConsumerWidget {
  const TeamTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (session.error != null) _ErrorCard(message: session.error!),
        if (session.role == SessionRole.none)
          const _StartCards()
        else
          _ActiveTeam(session: session),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: Icon(Icons.error_outline, color: scheme.onErrorContainer),
        title: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
      ),
    );
  }
}

class _StartCards extends ConsumerWidget {
  const _StartCards();

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateTeamDialog(),
    );
    if (name == null || name.trim().isEmpty) return;
    await ref.read(sessionControllerProvider.notifier).createTeam(name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(latestHostedTeamProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Icon(Icons.groups_outlined, size: 64, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'You are not in a team',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(height: 24),
        if (latest != null) ...[
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: ListTile(
              leading: const Icon(Icons.history),
              title: Text('Resume "${latest.name}"'),
              subtitle: Text('Team code: ${latest.teamCode}'),
              trailing: FilledButton.tonal(
                onPressed: () => ref
                    .read(sessionControllerProvider.notifier)
                    .resumeHosting(latest),
                child: const Text('Resume'),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        FilledButton.icon(
          onPressed: () => _create(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Create a team'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const JoinTeamScreen()),
          ),
          icon: const Icon(Icons.login),
          label: const Text('Join a team'),
        ),
      ],
    );
  }
}

class _CreateTeamDialog extends StatefulWidget {
  const _CreateTeamDialog();

  @override
  State<_CreateTeamDialog> createState() => _CreateTeamDialogState();
}

class _CreateTeamDialogState extends State<_CreateTeamDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create a team'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(
          labelText: 'Team name',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}

class _ActiveTeam extends ConsumerWidget {
  const _ActiveTeam({required this.session});

  final SessionState session;

  String get _statusLabel {
    if (session.role == SessionRole.host) return 'HOSTING';
    switch (session.peerState) {
      case PeerState.connected:
        return 'CONNECTED';
      case PeerState.reconnecting:
        return 'RECONNECTING';
      default:
        return 'CONNECTING';
    }
  }

  Color get _statusColor {
    if (session.role == SessionRole.host) return Colors.green;
    return session.peerState == PeerState.connected
        ? Colors.green
        : Colors.orange;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHost = session.role == SessionRole.host;
    final teamId = session.teamId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        session.teamName ?? 'Joining team...',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      _statusLabel,
                      style: TextStyle(
                        color: _statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                if (isHost && session.teamCode != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'TEAM CODE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  Row(
                    children: [
                      SelectableText(
                        session.teamCode!,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy code',
                        icon: const Icon(Icons.copy),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: session.teamCode!),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Team code copied'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  Text(
                    'Peers on the same network can find this team and join '
                    'with the code. Port ${session.hostPort}.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            'MEMBERS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        if (teamId != null)
          _Members(teamId: teamId)
        else
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Waiting for the host...'),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => ref.read(sessionControllerProvider.notifier).leave(),
          icon: const Icon(Icons.logout),
          label: Text(isHost ? 'Stop hosting' : 'Leave team'),
        ),
      ],
    );
  }
}

class _Members extends ConsumerWidget {
  const _Members({required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(teamMembersProvider(teamId));

    return members.when(
      data: (list) => Column(
        children: [
          for (final member in list)
            ListTile(
              leading: CircleAvatar(
                child: Icon(member.isHost ? Icons.shield : Icons.person),
              ),
              title: Text(
                member.user.isSelf
                    ? '${member.user.name} (you)'
                    : member.user.name,
              ),
              subtitle: Text(member.isHost ? 'Host' : 'Peer'),
              trailing: Text(
                member.isOnline ? 'ONLINE' : 'OFFLINE',
                style: TextStyle(
                  color: member.isOnline ? Colors.green : Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Could not load members: $e'),
      ),
    );
  }
}
