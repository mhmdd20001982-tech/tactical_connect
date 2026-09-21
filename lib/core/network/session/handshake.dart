import 'dart:async';

import '../protocol/message_type.dart';
import '../protocol/messages/handshake_payloads.dart';
import '../protocol/messages/protocol_message.dart';
import '../transport/transport.dart';

const Duration kHandshakeTimeout = Duration(seconds: 5);

class HandshakeException implements Exception {
  HandshakeException(this.message);

  final String message;

  @override
  String toString() => 'HandshakeException: $message';
}

/// The Host's decision about a HELLO.
class HelloDecision {
  const HelloDecision.accept()
      : accepted = true,
        reason = null;

  const HelloDecision.reject(String reason)
      : accepted = false,
        reason = reason;

  final bool accepted;
  final String? reason;
}

/// Called by the Host for every valid HELLO (check the team code here).
typedef HelloAuthorizer = FutureOr<HelloDecision> Function(HelloPayload hello);

/// A connection after a successful handshake.
class PeerLink {
  const PeerLink({
    required this.connection,
    required this.remoteDeviceId,
    required this.remoteName,
    required this.messages,
  });

  final TransportConnection connection;
  final String remoteDeviceId;
  final String remoteName;

  /// Messages received after the handshake. Single-subscription and
  /// buffered until someone listens. Cancelling the subscription closes
  /// the connection.
  final Stream<ProtocolMessage> messages;
}

/// Reads the first message of a connection and forwards everything after
/// it, without cancelling the underlying subscription.
class _InboundGate {
  _InboundGate(this._connection) {
    _connection.messages.listen(
      _onMessage,
      onError: (Object _) {},
      onDone: _onDone,
    );
    // Mark the error as handled even if nobody awaits [first] in time.
    unawaited(_first.future.then<void>((_) {}, onError: (Object _) {}));
  }

  final TransportConnection _connection;
  final Completer<ProtocolMessage> _first = Completer<ProtocolMessage>();
  late final StreamController<ProtocolMessage> _rest =
      StreamController<ProtocolMessage>(onCancel: () => _connection.close());

  Future<ProtocolMessage> get first => _first.future;
  Stream<ProtocolMessage> get rest => _rest.stream;

  void _onMessage(ProtocolMessage message) {
    if (!_first.isCompleted) {
      _first.complete(message);
    } else if (!_rest.isClosed) {
      _rest.add(message);
    }
  }

  void _onDone() {
    if (!_first.isCompleted) {
      _first.completeError(
        HandshakeException('Connection closed during handshake'),
      );
    }
    if (!_rest.isClosed) unawaited(_rest.close());
  }
}

Future<void> _trySendReply(
  TransportConnection connection,
  String senderId,
  String ackedMessageId,
  HelloReply reply,
) async {
  try {
    await connection.send(_replyMessage(senderId, ackedMessageId, reply));
  } catch (_) {
    // We are rejecting anyway; nothing more to do if the send fails.
  }
}

ProtocolMessage _replyMessage(
  String senderId,
  String ackedMessageId,
  HelloReply reply,
) {
  return ProtocolMessage.create(
    type: MessageType.ack,
    senderId: senderId,
    payload: {
      'acked_message_id': ackedMessageId,
      ...reply.toPayload(),
    },
  );
}

/// Host side: waits for a HELLO, asks [authorize], and answers with an ACK.
///
/// On any failure the connection is closed and a [HandshakeException] is
/// thrown. On success the caller owns the returned [PeerLink].
Future<PeerLink> acceptPeer(
  TransportConnection connection, {
  required String localDeviceId,
  required String localName,
  required HelloAuthorizer authorize,
  Duration timeout = kHandshakeTimeout,
}) async {
  final gate = _InboundGate(connection);
  var success = false;
  try {
    final ProtocolMessage first;
    try {
      first = await gate.first.timeout(timeout);
    } on TimeoutException {
      throw HandshakeException('Timed out waiting for HELLO');
    }

    if (first.type != MessageType.hello) {
      await _trySendReply(
        connection,
        localDeviceId,
        first.id,
        const HelloReply.rejected('expected_hello'),
      );
      throw HandshakeException(
        'First message was ${first.type.wireName}, expected HELLO',
      );
    }

    final HelloPayload hello;
    try {
      hello = HelloPayload.fromPayload(first.payload);
    } on Exception catch (e) {
      await _trySendReply(
        connection,
        localDeviceId,
        first.id,
        const HelloReply.rejected('invalid_hello'),
      );
      throw HandshakeException('Invalid HELLO: $e');
    }

    final decision = await authorize(hello);
    if (!decision.accepted) {
      final reason = decision.reason ?? 'rejected';
      await _trySendReply(
        connection,
        localDeviceId,
        first.id,
        HelloReply.rejected(reason),
      );
      throw HandshakeException('Peer rejected: $reason');
    }

    await connection.send(
      _replyMessage(
        localDeviceId,
        first.id,
        HelloReply.accepted(name: localName),
      ),
    );

    success = true;
    return PeerLink(
      connection: connection,
      remoteDeviceId: hello.deviceId,
      remoteName: hello.name,
      messages: gate.rest,
    );
  } finally {
    if (!success) await connection.close();
  }
}

/// Peer side: sends HELLO and waits for the Host's ACK.
///
/// On any failure the connection is closed and a [HandshakeException] is
/// thrown. On success the caller owns the returned [PeerLink].
Future<PeerLink> connectToHost(
  TransportConnection connection, {
  required HelloPayload hello,
  Duration timeout = kHandshakeTimeout,
}) async {
  final gate = _InboundGate(connection);
  var success = false;
  try {
    final message = ProtocolMessage.create(
      type: MessageType.hello,
      senderId: hello.deviceId,
      payload: hello.toPayload(),
    );
    await connection.send(message);

    final ProtocolMessage reply;
    try {
      reply = await gate.first.timeout(timeout);
    } on TimeoutException {
      throw HandshakeException('Timed out waiting for ACK');
    }

    if (reply.type != MessageType.ack || reply.ackedMessageId != message.id) {
      throw HandshakeException(
        'Unexpected reply to HELLO: ${reply.type.wireName}',
      );
    }

    final HelloReply result;
    try {
      result = HelloReply.fromPayload(reply.payload);
    } on Exception catch (e) {
      throw HandshakeException('Invalid ACK: $e');
    }
    if (!result.accepted) {
      throw HandshakeException('Rejected by host: ${result.reason}');
    }

    success = true;
    return PeerLink(
      connection: connection,
      remoteDeviceId: reply.senderId,
      remoteName: result.name ?? 'Host',
      messages: gate.rest,
    );
  } finally {
    if (!success) await connection.close();
  }
}
