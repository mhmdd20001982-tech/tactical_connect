import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/identity/self_user_provider.dart';
import '../../../core/network/session/peer_session.dart';
import '../../team/application/session_controller.dart';
import '../../team/presentation/team_tab.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  String _statusText(SessionState s) {
    switch (s.role) {
      case SessionRole.none:
        return 'Not in a team';
      case SessionRole.host:
        return 'Hosting "${s.teamName}" on port ${s.hostPort}';
      case SessionRole.peer:
        switch (s.peerState) {
          case PeerState.connected:
            return 'Connected to "${s.teamName}"';
          case PeerState.reconnecting:
            return 'Connection lost, reconnecting...';
          default:
            return 'Connecting...';
        }
    }
  }

  Color? _statusColor(SessionState s) {
    switch (s.role) {
      case SessionRole.none:
        return null;
      case SessionRole.host:
        return Colors.green;
      case SessionRole.peer:
        return s.peerState == PeerState.connected
            ? Colors.green
            : Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selfUserAsync = ref.watch(selfUserStreamProvider);
    final session = ref.watch(sessionControllerProvider);
    final subtitleColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tactical Connect',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            selfUserAsync.when(
              data: (user) => Text(
                user != null ? 'Operator: ${user.name}' : 'Operator: Unknown',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: subtitleColor),
              ),
              loading: () => Text(
                'Loading...',
                style: TextStyle(fontSize: 12, color: subtitleColor),
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Network status',
            icon: Icon(Icons.wifi_tethering, color: _statusColor(session)),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_statusText(session)),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          _ChatsTab(),
          TeamTab(),
          _SettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Team',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _ChatsTab extends StatelessWidget {
  const _ChatsTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.forum_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'No conversations yet',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create or join a team from the Team tab.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _SettingsTab extends ConsumerWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final self = ref.watch(selfUserStreamProvider).value;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.perm_identity),
          title: const Text('Device ID'),
          subtitle: SelectableText(self?.deviceId ?? 'Not available'),
        ),
        const Divider(),
        const ListTile(
          leading: Icon(Icons.lock_open),
          title: Text('Encryption'),
          subtitle: Text(
            'Not enabled yet. Traffic on the local network is not encrypted '
            'in this version.',
          ),
          trailing: Icon(Icons.warning_amber, color: Colors.orange),
        ),
      ],
    );
  }
}
