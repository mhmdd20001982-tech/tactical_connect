import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../protocol/message_codec.dart';
import '../protocol/messages/protocol_message.dart';
import '../protocol/protocol_exception.dart';
import 'transport.dart';

/// Plain TCP transport (V1, unencrypted).
class TcpTransport implements Transport {
  @override
  Future<TransportServer> listen({required int port}) async {
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    return _TcpServer(server);
  }

  @override
  Future<TransportConnection> connect(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    return TcpConnection(socket);
  }
}

class _TcpServer implements TransportServer {
  _TcpServer(this._server) {
    _server.listen(
      (socket) => _controller.add(TcpConnection(socket)),
      onError: _controller.addError,
      onDone: _controller.close,
    );
  }

  final ServerSocket _server;
  final StreamController<TransportConnection> _controller =
      StreamController<TransportConnection>();

  @override
  int get port => _server.port;

  @override
  Stream<TransportConnection> get connections => _controller.stream;

  @override
  Future<void> close() async {
    await _server.close();
  }
}

/// A TCP connection.
///
/// The socket is read right away (from the constructor). Decoded messages
/// are buffered in [messages] until someone listens. The connection state
/// ([done], [isClosed]) is tracked here and does not depend on
/// `Socket.done`.
class TcpConnection implements TransportConnection {
  TcpConnection(
    Socket socket, {
    void Function(String line, Object error)? onMalformed,
  })  : _socket = socket,
        _decoder = MessageFrameDecoder(onMalformed: onMalformed),
        remoteAddress = socket.remoteAddress.address,
        remotePort = socket.remotePort {
    _socket.setOption(SocketOption.tcpNoDelay, true);

    _subscription = const Utf8Decoder(allowMalformed: true)
        .bind(_socket)
        .listen(
          _onText,
          onError: (Object _) => _shutdown(),
          onDone: () => _shutdown(),
          cancelOnError: true,
        );

    // Extra safety net: also react when the socket reports it is done.
    _socket.done.then<void>(
      (_) => _shutdown(),
      onError: (Object _) => _shutdown(),
    );
  }

  final Socket _socket;
  final MessageFrameDecoder _decoder;
  late final StreamSubscription<String> _subscription;
  late final StreamController<ProtocolMessage> _controller =
      StreamController<ProtocolMessage>(
    onCancel: () => _shutdown(fromCancel: true),
  );
  final Completer<void> _doneCompleter = Completer<void>();
  Future<void> _sendChain = Future<void>.value();
  bool _closed = false;

  @override
  final String remoteAddress;

  @override
  final int remotePort;

  @override
  Stream<ProtocolMessage> get messages => _controller.stream;

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  bool get isClosed => _closed;

  void _onText(String chunk) {
    if (_doneCompleter.isCompleted) return;
    try {
      for (final message in _decoder.add(chunk)) {
        if (_controller.isClosed) return;
        _controller.add(message);
      }
    } on ProtocolException {
      // The peer broke the protocol (for example an oversized frame).
      // Drop the connection.
      _shutdown();
    }
  }

  void _shutdown({bool fromCancel = false}) {
    _closed = true;
    if (_doneCompleter.isCompleted) return;
    _doneCompleter.complete();
    _socket.destroy();
    unawaited(_subscription.cancel());
    if (!fromCancel && !_controller.isClosed) {
      unawaited(_controller.close());
    }
  }

  @override
  Future<void> send(ProtocolMessage message) {
    if (_closed) {
      return Future<void>.error(StateError('Connection is closed'));
    }
    final bytes = utf8.encode(encodeMessage(message));
    final next = _sendChain.then((_) async {
      _socket.add(bytes);
      await _socket.flush();
    });
    // Keep the chain alive even if one send fails.
    _sendChain = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  @override
  Future<void> close() async {
    if (_doneCompleter.isCompleted) return;
    _closed = true;
    try {
      // Let messages that are already queued go out first.
      await _sendChain.timeout(const Duration(seconds: 2));
    } catch (_) {
      // Ignore: we are closing anyway.
    }
    _shutdown();
  }
}
