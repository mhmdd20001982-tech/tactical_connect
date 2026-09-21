import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/discovery/udp_discovery.dart';
import '../../../core/network/protocol/protocol_constants.dart';
import '../application/session_controller.dart';

/// Pick a team found on the network (or type the host IP) and enter the
/// team code.
class JoinTeamScreen extends ConsumerStatefulWidget {
  const JoinTeamScreen({super.key});

  @override
  ConsumerState<JoinTeamScreen> createState() => _JoinTeamScreenState();
}

class _JoinTeamScreenState extends ConsumerState<JoinTeamScreen> {
  final _codeController = TextEditingController();
  final _ipController = TextEditingController();
  DiscoveredHost? _selected;

  @override
  void dispose() {
    _codeController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  bool get _canJoin {
    final hasCode = _codeController.text.trim().isNotEmpty;
    final hasTarget =
        _ipController.text.trim().isNotEmpty || _selected != null;
    return hasCode && hasTarget;
  }

  Future<void> _join() async {
    final manualIp = _ipController.text.trim();
    final selected = _selected;

    // A typed IP wins over a selected team.
    final address = manualIp.isNotEmpty ? manualIp : selected!.address.address;
    final port = manualIp.isNotEmpty
        ? kTransportPort
        : selected!.announcement.tcpPort;

    await ref.read(sessionControllerProvider.notifier).joinTeam(
          address: address,
          port: port,
          teamCode: _codeController.text,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hosts = ref.watch(discoveredHostsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Join a team')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            maxLength: 12,
            decoration: const InputDecoration(
              labelText: 'Team code',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              'NEARBY TEAMS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          hosts.when(
            data: (list) {
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.sensors, size: 40, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('Scanning for teams on this network...'),
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  for (final host in list)
                    ListTile(
                      selected: _selected?.announcement.hostDeviceId ==
                          host.announcement.hostDeviceId,
                      leading: const Icon(Icons.groups),
                      title: Text(host.announcement.teamName),
                      subtitle: Text(
                        'Host: ${host.announcement.hostName}  '
                        '(${host.address.address}:${host.announcement.tcpPort})',
                      ),
                      trailing: _selected?.announcement.hostDeviceId ==
                              host.announcement.hostDeviceId
                          ? const Icon(Icons.check_circle)
                          : null,
                      onTap: () => setState(() => _selected = host),
                    ),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Discovery is not available: $e'),
            ),
          ),
          ExpansionTile(
            title: const Text('Enter the host IP manually'),
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  controller: _ipController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Host IP address',
                    hintText: '192.168.1.10',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _canJoin ? _join : null,
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }
}
