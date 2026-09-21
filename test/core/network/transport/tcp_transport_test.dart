import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_connect/core/network/protocol/message_codec.dart';
import 'package:tactical_connect/core/network/protocol/message_type.dart';
import 'package:tactical_connect/core/network/protocol/messages/protocol_message.dart';
import 'package:tactical_connect/core/network/protocol/protocol_constants.dart';
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

/// Wraps a connection and collects everything it receives.
class _Endpoint {
  _Endpoint(this.connection) {
    connection.messages.listen(inbox.add);
  }

  final TransportConnection connection;
  final List<ProtocolMessage> inbox = [];
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

  /// Returns [client side, server side] of a fresh connection.
  Future<List<_Endpoint>> connectPair() async {
    final acceptedFuture = server.connections.first;
    final client = await transport.connect('127.0.0.1', server.port);
    final accepted = await acceptedFuture.timeout(const Duration(seconds: 5));
    return [_Endpoint(client), _Endpoint(accepted)];
  }

  test('client and server exchange messages in both directions', () async {
    final pair = await connectPair();
    final client = pair[0];
    final accepted = pair[1];

    final hello = ProtocolMessage.create(
      type: MessageType.hello,
      senderId: 'client',
      payload: {'name': 'محمد'},
    );
    await client.connection.send(hello);
    await _waitFor(() => accepted.inbox.isNotEmpty);
    expect(accepted.inbox.single.id, hello.id);
    expect(accepted.inbox.single.payload['name'], 'محمد');

    final ack = ProtocolMessage.ack(
      senderId: 'server',
      ackedMessageId: hello.id,
    );
    await accepted.connection.send(ack);
    await _waitFor(() => client.inbox.isNotEmpty);
    expect(client.inbox.single.ackedMessageId, hello.id);

    await client.connection.close();
    await accepted.connection.close();
  });

  test('messages sent back to back arrive in order', () async {
    final pair = await connectPair();
    final client = pair[0];
    final accepted = pair[1];

    final sent = List.generate(
      50,
      (i) => ProtocolMessage.create(
        type: MessageType.ping,
        senderId: 'client',
        payload: {'n': i},
      ),
    );
    for (final message in sent) {
      unawaited(client.connection.send(message));
    }

    await _waitFor(() => accepted.inbox.length == sent.length);
    expect(
      accepted.inbox.map((m) => m.payload['n']).toList(),
      List.generate(50, (i) => i),
    );

    await client.connection.close();
    await accepted.connection.close();
  });

  test('closing one side completes done on the other side', () async {
    final pair = await connectPair();
    final client = pair[0];
    final accepted = pair[1];

    await client.connection.close();
    await accepted.connection.done.timeout(const Duration(seconds: 5));
    await _waitFor(() => accepted.connection.isClosed);
    expect(client.connection.isClosed, isTrue);
  });

  test('send on a closed connection fails', () async {
    final pair = await connectPair();
    final client = pair[0];

    await client.connection.close();
    expect(
      () => client.connection.send(
        ProtocolMessage.ping(senderId: 'client'),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('malformed line from a raw peer is skipped', () async {
    final acceptedFuture = server.connections.first;
    final raw = await Socket.connect('127.0.0.1', server.port);
    raw.listen((_) {}, onError: (Object _) {});
    final accepted = _Endpoint(
      await acceptedFuture.timeout(const Duration(seconds: 5)),
    );

    final good = ProtocolMessage.ping(senderId: 'raw');
    raw.write('this is not json\n');
    raw.write(encodeMessage(good));
    await raw.flush();

    await _waitFor(() => accepted.inbox.isNotEmpty);
    expect(accepted.inbox, hasLength(1));
    expect(accepted.inbox.single.id, good.id);

    raw.destroy();
    await accepted.connection.close();
  });

  test('oversized frame makes the server drop the connection', () async {
    final acceptedFuture = server.connections.first;
    final raw = await Socket.connect('127.0.0.1', server.port);
    raw.listen((_) {}, onError: (Object _) {});
    raw.done.catchError((Object _) {});
    final accepted = _Endpoint(
      await acceptedFuture.timeout(const Duration(seconds: 5)),
    );

    raw.write('x' * (kMaxFrameChars + 10));

    await accepted.connection.done.timeout(const Duration(seconds: 10));
    expect(accepted.connection.isClosed, isTrue);

    raw.destroy();
  });

  test('connect fails when nobody is listening', () async {
    final port = server.port;
    await server.close();

    expect(
      () => transport.connect(
        '127.0.0.1',
        port,
        timeout: const Duration(seconds: 2),
      ),
      throwsA(isA<SocketException>()),
    );
  });
}
