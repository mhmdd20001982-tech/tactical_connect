import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_connect/core/network/protocol/message_type.dart';
import 'package:tactical_connect/core/network/protocol/messages/protocol_message.dart';
import 'package:tactical_connect/core/network/session/host_session.dart';
import 'package:tactical_connect/core/network/session/peer_session.dart';

Future<void> _waitFor(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 5)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

HostSession _host({int port = 0, String code = 'AB12CD'}) {
  return HostSession(
    deviceId: 'host-1',
    name: 'Commander',
    teamName: 'Alpha',
    teamCode: code,
    tcpPort: port,
    announce: false,
    heartbeatIdle: const Duration(milliseconds: 100),
    heartbeatTimeout: const Duration(milliseconds: 400),
    heartbeatCheck: const Duration(milliseconds: 10),
  );
}

PeerSession _peer(int port, {String code = 'AB12CD', String id = 'peer-1'}) {
  return PeerSession(
    deviceId: id,
    name: 'Ahmad',
    teamCode: code,
    hostAddress: '127.0.0.1',
    hostPort: port,
    backoff: const [Duration(milliseconds: 50), Duration(milliseconds: 100)],
    connectTimeout: const Duration(seconds: 1),
    handshakeTimeout: const Duration(seconds: 1),
    heartbeatIdle: const Duration(milliseconds: 100),
    heartbeatTimeout: const Duration(milliseconds: 400),
    heartbeatCheck: const Duration(milliseconds: 10),
  );
}

/// The message type does not matter after the handshake; HELLO is used here
/// only as a carrier for a test payload.
ProtocolMessage _data(String senderId, String text) {
  return ProtocolMessage.create(
    type: MessageType.hello,
    senderId: senderId,
    payload: {'text': text},
  );
}

void main() {
  test('peer joins the host and both sides know each other', () async {
    final host = _host();
    await host.start();
    final events = <HostEvent>[];
    host.events.listen(events.add);

    final peer = _peer(host.port);
    await peer.start();

    await _waitFor(() => peer.state == PeerState.connected);
    await _waitFor(() => events.whereType<PeerJoined>().isNotEmpty);

    final joined = events.whereType<PeerJoined>().single;
    expect(joined.deviceId, 'peer-1');
    expect(joined.name, 'Ahmad');
    expect(peer.hostDeviceId, 'host-1');
    expect(peer.hostName, 'Commander');
    expect(host.peerIds, {'peer-1'});

    await peer.stop();
    await host.stop();
    expect(peer.state, PeerState.closed);
  });

  test('team code is compared without case and spaces', () async {
    final host = _host(code: 'AB12CD');
    await host.start();

    final peer = _peer(host.port, code: '  ab12cd ');
    await peer.start();

    await _waitFor(() => peer.state == PeerState.connected);

    await peer.stop();
    await host.stop();
  });

  test('messages flow peer to host, host to peer, and broadcast', () async {
    final host = _host();
    await host.start();
    final events = <HostEvent>[];
    host.events.listen(events.add);

    final peer = _peer(host.port);
    final peerInbox = <ProtocolMessage>[];
    peer.messages.listen(peerInbox.add);
    await peer.start();
    await _waitFor(() => peer.state == PeerState.connected);
    await _waitFor(() => host.peerIds.contains('peer-1'));

    await peer.send(_data('peer-1', 'from peer'));
    await _waitFor(() => events.whereType<PeerMessage>().isNotEmpty);
    final received = events.whereType<PeerMessage>().single;
    expect(received.deviceId, 'peer-1');
    expect(received.message.payload['text'], 'from peer');

    await host.sendTo('peer-1', _data('host-1', 'direct'));
    await host.broadcast(_data('host-1', 'everyone'));
    await _waitFor(() => peerInbox.length == 2);
    expect(peerInbox.map((m) => m.payload['text']), ['direct', 'everyone']);

    await peer.stop();
    await host.stop();
  });

  test('wrong team code is rejected and the peer does not retry', () async {
    final host = _host();
    await host.start();
    final events = <HostEvent>[];
    host.events.listen(events.add);

    final peer = _peer(host.port, code: 'WRONG1');
    await peer.start();

    await _waitFor(() => peer.state == PeerState.rejected);
    expect(peer.rejectionReason, contains('wrong_team_code'));

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(events.whereType<PeerRejected>(), hasLength(1));
    expect(events.whereType<PeerJoined>(), isEmpty);
    expect(host.peerIds, isEmpty);

    await peer.stop();
    await host.stop();
  });

  test('peer reconnects after the host drops it', () async {
    final host = _host();
    await host.start();
    final events = <HostEvent>[];
    host.events.listen(events.add);

    final peer = _peer(host.port);
    final states = <PeerState>[];
    peer.states.listen(states.add);
    await peer.start();

    await _waitFor(() => events.whereType<PeerJoined>().length == 1);
    await host.kick('peer-1');

    await _waitFor(() => events.whereType<PeerJoined>().length == 2);
    await _waitFor(() => peer.state == PeerState.connected);

    expect(states, contains(PeerState.reconnecting));
    expect(events.whereType<PeerLeft>(), isNotEmpty);
    expect(host.peerIds, {'peer-1'});

    await peer.stop();
    await host.stop();
  });

  test('peer keeps retrying until the host comes back', () async {
    final first = _host();
    await first.start();
    final port = first.port;
    await first.stop();

    final peer = _peer(port);
    await peer.start();
    await _waitFor(() => peer.state == PeerState.reconnecting);

    final second = _host(port: port);
    await second.start();
    await _waitFor(() => peer.state == PeerState.connected);

    await peer.stop();
    await second.stop();
  });

  test('host stop makes connected peers go to reconnecting', () async {
    final host = _host();
    await host.start();

    final peer = _peer(host.port);
    await peer.start();
    await _waitFor(() => peer.state == PeerState.connected);

    await host.stop();
    await _waitFor(() => peer.state == PeerState.reconnecting);

    await peer.stop();
  });

  test('send fails while the peer is not connected', () async {
    final peer = _peer(1);
    expect(
      () => peer.send(_data('peer-1', 'nobody home')),
      throwsA(isA<StateError>()),
    );
    await peer.stop();
  });
}
