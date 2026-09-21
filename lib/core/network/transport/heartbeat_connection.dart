import 'dart:async';

import '../protocol/message_type.dart';
import '../protocol/messages/protocol_message.dart';
import '../protocol/protocol_constants.dart';
import 'transport.dart';

/// Why a connection ended.
enum ConnectionCloseReason {
  /// We closed it (close() or the consumer cancelled [messages]).
  local,

  /// The peer or the network closed it.
  remote,

  /// Nothing was received for longer than the heartbeat timeout.
  heartbeatTimeout,
}

/// Wraps any [TransportConnection] and adds a bidirectional heartbeat.
///
/// - If nothing was sent for [idleInterval], it sends a PING.
/// - If nothing was received for [timeout], it closes the connection.
/// - Any received message counts as life; PING messages are not forwarded.
///
/// Both sides run the same logic, so no PONG is needed.
class HeartbeatConnection implements TransportConnection {
  HeartbeatConnection(
    this._inner, {
    required this.localId,
    this.idleInterval = kHeartbeatIdleInterval,
    this.timeout = kHeartbeatTimeout,
    this.checkInterval = const Duration(seconds: 1),
  }) : assert(timeout > idleInterval, 'timeout must be > idleInterval') {
    _clock.start();
    _subscription = _inner.messages.listen(
      _onMessage,
      onError: (Object _) {},
      onDone: _finish,
    );
    _timer = Timer.periodic(checkInterval, (_) => _tick());
    _inner.done.then<void>(
      (_) => _finish(),
      onError: (Object _) => _finish(),
    );
  }

  final TransportConnection _inner;

  /// Our device id, used as sender_id of PING messages.
  final String localId;
  final Duration idleInterval;
  final Duration timeout;
  final Duration checkInterval;

  final Stopwatch _clock = Stopwatch();
  Duration _lastSent = Duration.zero;
  Duration _lastReceived = Duration.zero;

  late final StreamSubscription<ProtocolMessage> _subscription;
  late final Timer _timer;
  late final StreamController<ProtocolMessage> _controller =
      StreamController<ProtocolMessage>(
    onCancel: () => _abort(ConnectionCloseReason.local),
  );
  final Completer<void> _doneCompleter = Completer<void>();
  ConnectionCloseReason? _reason;

  /// Null while the connection is open.
  ConnectionCloseReason? get closeReason => _reason;

  @override
  String get remoteAddress => _inner.remoteAddress;

  @override
  int get remotePort => _inner.remotePort;

  @override
  Stream<ProtocolMessage> get messages => _controller.stream;

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  bool get isClosed => _doneCompleter.isCompleted || _inner.isClosed;

  void _onMessage(ProtocolMessage message) {
    _lastReceived = _clock.elapsed;
    if (message.type == MessageType.ping) return;
    if (!_controller.isClosed) _controller.add(message);
  }

  void _tick() {
    if (_doneCompleter.isCompleted) return;
    final now = _clock.elapsed;

    if (now - _lastReceived >= timeout) {
      _abort(ConnectionCloseReason.heartbeatTimeout);
      return;
    }
    if (now - _lastSent >= idleInterval) {
      unawaited(
        send(ProtocolMessage.ping(senderId: localId)).catchError((Object _) {}),
      );
    }
  }

  /// Ends the connection right away.
  void _abort(ConnectionCloseReason reason) {
    if (_doneCompleter.isCompleted) return;
    _reason ??= reason;
    unawaited(_inner.close());
    _finish();
  }

  void _finish() {
    if (_doneCompleter.isCompleted) return;
    _reason ??= ConnectionCloseReason.remote;
    _timer.cancel();
    _doneCompleter.complete();
    unawaited(_subscription.cancel());
    if (!_controller.isClosed) unawaited(_controller.close());
  }

  @override
  Future<void> send(ProtocolMessage message) {
    if (isClosed) {
      return Future<void>.error(StateError('Connection is closed'));
    }
    _lastSent = _clock.elapsed;
    return _inner.send(message);
  }

  @override
  Future<void> close() async {
    if (_doneCompleter.isCompleted) return;
    _reason ??= ConnectionCloseReason.local;
    _timer.cancel();
    await _inner.close();
    _finish();
  }
}
