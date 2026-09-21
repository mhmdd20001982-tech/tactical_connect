import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_connect/core/network/protocol/message_codec.dart';
import 'package:tactical_connect/core/network/protocol/message_type.dart';
import 'package:tactical_connect/core/network/protocol/messages/handshake_payloads.dart';
import 'package:tactical_connect/core/network/protocol/messages/protocol_message.dart';
import 'package:tactical_connect/core/network/session/handshake.dart';
import 'package:tactical_connect/core/network/transport/tcp_transport.dart';
import 'package:tactical_connect/core/network/transport/transport.dart';

Future<void> _waitFor(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 5)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

const _hello = HelloPayload(
  deviceId: 'peer-1',
  name: 'Ahmad',
  teamCode: 'AB12CD',
  appVersion: '1.0.0',
);

HelloDecision _checkCode(HelloPayload hello) {
  return hello.teamCode == 'AB12CD'
      ? const HelloDecision.accept()
      : const HelloDecision.reject('wrong_team_code');
}

void main() {
  late TcpTransport transport;
  late TransportServer server;

  setUp(() async {
    transport = TcpTransport();
    server = await transport.listen(port: 0);
  });

  tearDown(() async {
    await server.close();
  });

  test('successful handshake, then messages flow both ways', () async {
    final acceptedFuture = server.connections.first;
    final client = await transport.connect('127.0.0.1', server.port);
    final accepted = await acceptedFuture.timeout(const Duration(seconds: 5));

    final hostFuture = acceptPeer(
      accepted,
      localDeviceId: 'host-1',
      localName: 'Commander',
      authorize: _checkCode,
    );
    final peerLink = await connectToHost(client, hello: _hello);
    final hostLink = await hostFuture;

    expect(hostLink.remoteDeviceId, 'peer-1');
    expect(hostLink.remoteName, 'Ahmad');
    expect(peerLink.remoteDeviceId, 'host-1');
    expect(peerLink.remoteName, 'Commander');

    final hostInbox = <ProtocolMessage>[];
    final peerInbox = <ProtocolMessage>[];
    hostLink.messages.listen(hostInbox.add);
    peerLink.messages.listen(peerInbox.add);

    await peerLink.connection.send(
      ProtocolMessage.create(
        type: MessageType.ping,
        senderId: 'peer-1',
        payload: {'n': 1},
      ),
    );
    await hostLink.connection.send(
      ProtocolMessage.create(
        type: MessageType.ping,
        senderId: 'host-1',
        payload: {'n': 2},
      ),
    );

    await _waitFor(() => hostInbox.isNotEmpty && peerInbox.isNotEmpty);
    expect(hostInbox.single.payload['n'], 1);
    expect(peerInbox.single.payload['n'], 2);

    await client.close();
    await accepted.close();
  });

  test('wrong team code is rejected on both sides', () async {
    final acceptedFuture = server.connections.first;
    final client = await transport.connect('127.0.0.1', server.port);
    final accepted = await acceptedFuture.timeout(const Duration(seconds: 5));

    final hostFuture = acceptPeer(
      accepted,
      localDeviceId: 'host-1',
      localName: 'Commander',
      authorize: _checkCode,
    );
    final peerFuture = connectToHost(
      client,
      hello: const HelloPayload(
        deviceId: 'peer-2',
        name: 'Intruder',
        teamCode: 'WRONG1',
        appVersion: '1.0.0',
      ),
    );

    await Future.wait([
      expectLater(hostFuture, throwsA(isA<HandshakeException>())),
      expectLater(
        peerFuture,
        throwsA(
          predicate<Object>(
            (e) => e is HandshakeException && e.message.contains('wrong_team_code'),
          ),
        ),
      ),
    ]);

    expect(accepted.isClosed, isTrue);
    expect(client.isClosed, isTrue);
  });

  test('host times out when no HELLO arrives', () async {
    final acceptedFuture = server.connections.first;
    final raw = await Socket.connect('127.0.0.1', server.port);
    raw.listen((_) {}, onError: (Object _) {});
    final accepted = await acceptedFuture.timeout(const Duration(seconds: 5));

    await expectLater(
      acceptPeer(
        accepted,
        localDeviceId: 'host-1',
        localName: 'Commander',
        authorize: _checkCode,
        timeout: const Duration(milliseconds: 200),
      ),
      throwsA(isA<HandshakeException>()),
    );
    expect(accepted.isClosed, isTrue);

    raw.destroy();
  });

  test('host rejects a first message that is not HELLO', () async {
    final acceptedFuture = server.connections.first;
    final raw = await Socket.connect('127.0.0.1', server.port);
    raw.listen((_) {}, onError: (Object _) {});
    final accepted = await acceptedFuture.timeout(const Duration(seconds: 5));

    raw.write(encodeMessage(ProtocolMessage.ping(senderId: 'raw')));

    await expectLater(
      acceptPeer(
        accepted,
        localDeviceId: 'host-1',
        localName: 'Commander',
        authorize: _checkCode,
      ),
      throwsA(isA<HandshakeException>()),
    );
    expect(accepted.isClosed, isTrue);

    raw.destroy();
  });

  test('host rejects a HELLO with missing fields', () async {
    final acceptedFuture = server.connections.first;
    final raw = await Socket.connect('127.0.0.1', server.port);
    raw.listen((_) {}, onError: (Object _) {});
    final accepted = await acceptedFuture.timeout(const Duration(seconds: 5));

    raw.write(
      encodeMessage(
        ProtocolMessage.create(type: MessageType.hello, senderId: 'raw'),
      ),
    );

    await expectLater(
      acceptPeer(
        accepted,
        localDeviceId: 'host-1',
        localName: 'Commander',
        authorize: _checkCode,
      ),
      throwsA(
        predicate<Object>(
          (e) => e is HandshakeException && e.message.contains('Invalid HELLO'),
        ),
      ),
    );

    raw.destroy();
  });

  test('peer times out when the host never answers', () async {
    final acceptedFuture = server.connections.first;
    final client = await transport.connect('127.0.0.1', server.port);
    final accepted = await acceptedFuture.timeout(const Duration(seconds: 5));

    await expectLater(
      connectToHost(
        client,
        hello: _hello,
        timeout: const Duration(milliseconds: 200),
      ),
      throwsA(isA<HandshakeException>()),
    );
    expect(client.isClosed, isTrue);

    await accepted.close();
  });
}
