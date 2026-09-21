import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_connect/core/network/protocol/message_type.dart';
import 'package:tactical_connect/core/network/protocol/messages/protocol_message.dart';
import 'package:tactical_connect/core/network/transport/heartbeat_connection.dart';
import 'package:tactical_connect/core/network/transport/transport.dart';

/// In-memory connection so timing can be tested without sockets.
class _FakeConnection implements TransportConnection {
  final StreamController<ProtocolMessage> _incoming =
      StreamController<ProtocolMessage>();
  final Completer<void> _done = Completer<void>();
  final List<ProtocolMessage> sent = [];
  bool _closed = false;

  @override
  String get remoteAddress => '127.0.0.1';

  @override
  int get remotePort => 1;

  @override
  Stream<ProtocolMessage> get messages => _incoming.stream;

  @override
  Future<void> get done => _done.future;

  @override
  bool get isClosed => _closed;

  @override
  Future<void> send(ProtocolMessage message) async {
    if (_closed) throw StateError('closed');
    sent.add(message);
  }

  @override
  Future<void> close() async => _shutdown();

  void _shutdown() {
    if (_closed) return;
    _closed = true;
    _done.complete();
    unawaited(_incoming.close());
  }

  /// Simulates the peer closing the connection.
  void remoteClose() => _shutdown();

  /// Simulates a message arriving from the peer.
  void receive(ProtocolMessage message) => _incoming.add(message);
}

Future<void> _waitFor(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 5)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

ProtocolMessage _hello() {
  return ProtocolMessage.create(type: MessageType.hello, senderId: 'peer');
}

ProtocolMessage _ping() => ProtocolMessage.ping(senderId: 'peer');

HeartbeatConnection _make(_FakeConnection fake) {
  return HeartbeatConnection(
    fake,
    localId: 'me',
    idleInterval: const Duration(milliseconds: 100),
    timeout: const Duration(milliseconds: 400),
    checkInterval: const Duration(milliseconds: 10),
  );
}

void main() {
  test('sends a PING after being idle', () async {
    final fake = _FakeConnection();
    final conn = _make(fake);
    conn.messages.listen((_) {});

    await _waitFor(() => fake.sent.any((m) => m.type == MessageType.ping));

    final ping = fake.sent.firstWhere((m) => m.type == MessageType.ping);
    expect(ping.senderId, 'me');

    await conn.close();
  });

  test('does not send PING while traffic flows', () async {
    final fake = _FakeConnection();
    final conn = _make(fake);
    conn.messages.listen((_) {});

    for (var i = 0; i < 12; i++) {
      fake.receive(_hello());
      await conn.send(_hello());
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }

    expect(fake.sent.where((m) => m.type == MessageType.ping), isEmpty);
    expect(conn.isClosed, isFalse);

    await conn.close();
  });

  test('forwards normal messages and hides PING messages', () async {
    final fake = _FakeConnection();
    final conn = _make(fake);
    final inbox = <ProtocolMessage>[];
    conn.messages.listen(inbox.add);

    final hello = _hello();
    fake.receive(hello);
    fake.receive(_ping());

    await _waitFor(() => inbox.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(inbox, hasLength(1));
    expect(inbox.single.id, hello.id);

    await conn.close();
  });

  test('incoming PINGs keep the connection alive', () async {
    final fake = _FakeConnection();
    final conn = _make(fake);
    conn.messages.listen((_) {});

    // 800 ms of PINGs is twice the timeout.
    for (var i = 0; i < 16; i++) {
      fake.receive(_ping());
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(conn.isClosed, isFalse);
    expect(conn.closeReason, isNull);

    // Once the PINGs stop, the timeout must close it.
    await conn.done.timeout(const Duration(seconds: 3));
    expect(conn.closeReason, ConnectionCloseReason.heartbeatTimeout);
  });

  test('closes with heartbeatTimeout when nothing is received', () async {
    final fake = _FakeConnection();
    final conn = _make(fake);
    conn.messages.listen((_) {});

    await conn.done.timeout(const Duration(seconds: 3));

    expect(conn.closeReason, ConnectionCloseReason.heartbeatTimeout);
    expect(conn.isClosed, isTrue);
    expect(fake.isClosed, isTrue);
  });

  test('remote close ends the connection with reason remote', () async {
    final fake = _FakeConnection();
    final conn = _make(fake);
    var ended = false;
    conn.messages.listen((_) {}, onDone: () => ended = true);

    fake.remoteClose();

    await conn.done.timeout(const Duration(seconds: 3));
    await _waitFor(() => ended);
    expect(conn.closeReason, ConnectionCloseReason.remote);
  });

  test('local close ends the connection with reason local', () async {
    final fake = _FakeConnection();
    final conn = _make(fake);
    conn.messages.listen((_) {});

    await conn.close();

    expect(conn.closeReason, ConnectionCloseReason.local);
    expect(fake.isClosed, isTrue);
    expect(() => conn.send(_hello()), throwsA(isA<StateError>()));
  });
}
