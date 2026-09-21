import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_connect/core/network/discovery/udp_discovery.dart';
import 'package:tactical_connect/core/network/protocol/message_codec.dart';
import 'package:tactical_connect/core/network/protocol/message_type.dart';
import 'package:tactical_connect/core/network/protocol/messages/host_announcement.dart';
import 'package:tactical_connect/core/network/protocol/messages/protocol_message.dart';

Future<void> _waitFor(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 5)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

const _announcement = HostAnnouncement(
  hostDeviceId: 'host-1',
  hostName: 'Commander',
  teamName: 'Alpha',
  tcpPort: 7891,
);

HostAnnouncer _announcer(int port, {HostAnnouncement? announcement}) {
  return HostAnnouncer(
    announcement: announcement ?? _announcement,
    port: port,
    interval: const Duration(milliseconds: 50),
    targets: [InternetAddress.loopbackIPv4],
  );
}

HostDiscovery _discovery({String? ownDeviceId}) {
  return HostDiscovery(
    port: 0,
    ownDeviceId: ownDeviceId,
    ttl: const Duration(milliseconds: 400),
    expiryCheckInterval: const Duration(milliseconds: 50),
  );
}

void main() {
  test('finds an announced host, then forgets it after the TTL', () async {
    final discovery = _discovery();
    await discovery.start();
    final announcer = _announcer(discovery.port);
    await announcer.start();

    await _waitFor(() => discovery.hosts.isNotEmpty);

    final host = discovery.hosts.single;
    expect(host.announcement, _announcement);
    expect(host.address.address, '127.0.0.1');

    await announcer.stop();
    await _waitFor(() => discovery.hosts.isEmpty);

    await discovery.stop();
  });

  test('changes stream emits when a host appears', () async {
    final discovery = _discovery();
    await discovery.start();
    final emissions = <List<DiscoveredHost>>[];
    discovery.changes.listen(emissions.add);

    final announcer = _announcer(discovery.port);
    await announcer.start();

    await _waitFor(() => emissions.isNotEmpty);
    expect(emissions.first.single.announcement.teamName, 'Alpha');

    await announcer.stop();
    await discovery.stop();
  });

  test('ignores announcements from its own device id', () async {
    final discovery = _discovery(ownDeviceId: 'host-1');
    await discovery.start();
    final announcer = _announcer(discovery.port);
    await announcer.start();

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(discovery.hosts, isEmpty);

    await announcer.stop();
    await discovery.stop();
  });

  test('ignores junk and announcements with a mismatched sender', () async {
    final discovery = _discovery();
    await discovery.start();

    final raw = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final target = InternetAddress.loopbackIPv4;

    raw.send(utf8.encode('junk'), target, discovery.port);

    // sender_id says "spoof" but the payload claims to be host-1.
    final spoofed = ProtocolMessage.create(
      type: MessageType.hostAnnounce,
      senderId: 'spoof',
      payload: _announcement.toPayload(),
    );
    raw.send(utf8.encode(encodeMessage(spoofed)), target, discovery.port);

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(discovery.hosts, isEmpty);

    // A valid announcement still works afterwards.
    final valid = ProtocolMessage.create(
      type: MessageType.hostAnnounce,
      senderId: 'host-1',
      payload: _announcement.toPayload(),
    );
    raw.send(utf8.encode(encodeMessage(valid)), target, discovery.port);
    await _waitFor(() => discovery.hosts.isNotEmpty);
    expect(discovery.hosts.single.announcement.hostDeviceId, 'host-1');

    raw.close();
    await discovery.stop();
  });
}
