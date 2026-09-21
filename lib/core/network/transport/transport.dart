import 'dart:async';

import '../protocol/messages/protocol_message.dart';

/// One live connection to another device.
///
/// Everything above this layer (sessions, heartbeat, sync) depends only on
/// these interfaces, so TCP can later be replaced by TLS-over-TCP without
/// touching the layers above.
abstract class TransportConnection {
  String get remoteAddress;
  int get remotePort;

  /// Incoming messages. Single-subscription.
  /// The stream ends when the connection closes. Cancelling the
  /// subscription closes the connection.
  Stream<ProtocolMessage> get messages;

  /// Completes when the connection is closed (by either side).
  Future<void> get done;

  bool get isClosed;

  /// Sends one message. Calls are serialized in call order.
  Future<void> send(ProtocolMessage message);

  Future<void> close();
}

/// Listens for incoming connections (used by the session Host).
abstract class TransportServer {
  int get port;

  /// Accepted connections. Single-subscription.
  Stream<TransportConnection> get connections;

  Future<void> close();
}

abstract class Transport {
  Future<TransportServer> listen({required int port});

  Future<TransportConnection> connect(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 5),
  });
}
