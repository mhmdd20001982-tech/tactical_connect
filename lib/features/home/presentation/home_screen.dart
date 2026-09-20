import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/database/database_provider.dart';

final selfUserStreamProvider = StreamProvider<User?>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.users)..where((tbl) => tbl.isSelf.equals(true)))
      .watchSingleOrNull();
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final selfUserAsync = ref.watch(selfUserStreamProvider);

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
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
              ),
              loading: () => const Text(
                'Connecting...',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Network Status',
            icon: const Icon(Icons.wifi_tethering),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Local mesh discovery active'),
                  duration: Duration(seconds: 2),
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
          _PeersTab(),
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
            icon: Icon(Icons.radar_outlined),
            selectedIcon: Icon(Icons.radar),
            label: 'Peers',
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
            'No active sessions',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          const Text(
            'Connect to a peer to begin encrypted transmission.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _PeersTab extends StatelessWidget {
  const _PeersTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.green,
              child: Icon(Icons.wifi, color: Colors.white),
            ),
            title: Text('Local Subnet Broadcast'),
            subtitle: Text('Listening on port 4242...'),
            trailing: Text(
              'ONLINE',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            'DISCOVERED PEERS (0)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Column(
              children: [
                Icon(Icons.sensors, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                const Text('Scanning for nearby tactical units...'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsTab extends ConsumerWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        ListTile(
          leading: Icon(Icons.perm_identity),
          title: Text('Device Protocol ID'),
          subtitle: Text('Generated via local hardware entropy'),
        ),
        Divider(),
        ListTile(
          leading: Icon(Icons.security),
          title: Text('End-to-End Encryption'),
          subtitle: Text('Curve25519 + ChaCha20-Poly1305'),
          trailing: Icon(Icons.check_circle, color: Colors.green),
        ),
      ],
    );
  }
}