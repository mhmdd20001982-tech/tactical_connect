import 'dart:async';

import '../protocol/messages/handshake_payloads.dart';
import '../protocol/messages/protocol_message.dart';
import '../protocol/protocol_constants.dart';
import '../transport/heartbeat_connection.dart';
import '../transport/tcp_transport.dart';
import '../transport/transport.dart';
import 'handshake.dart';

enum PeerState {
  /// Created, [PeerSession.start] not called yet.
  idle,

  /// First connection attempt.
  connecting,

  /// Handshake done, messages can flow.
  connected,

  /// Lost the connection (or the first attempt failed); waiting to retry.
  reconnecting,

  /// The Host refused us (for example a wrong team code). Final state.
  rejected,

  /// [PeerSession.stop] was called.
  closed,
}

/// A Peer's side of the session: connects to the Host, does the handshake,
/// and reconnects with backoff when the connection drops.
class PeerSession {
  PeerSession({
    required this.deviceId,
    required this.name,
    required this.teamCode,
    required this.hostAddress,
    this.hostPort = kTransportPort,
    this.appVersion = '1.0.0',
    Transport? transport,
    List<Duration>? backoff,
    this.connectTimeout = const Duration(seconds: 5),
    this.handshakeTimeout = kHandshakeTimeout,
    this.heartbeatIdle = kHeartbeatIdleInterval,
    this.heartbeatTimeout = kHeartbeatTimeout,
    this.heartbeatCheck = const Duration(seconds: 1),
  })  : _transport = transport ?? TcpTransport(),
        _backoff = backoff ??
            kReconnectBackoffSeconds.map((s) => Duration(seconds: s)).toList(),
        assert(
          backoff == null || backoff.length > 0,
          'backoff must not be empty',
        );

  final String deviceId;
  final String name;
  final String teamCode;
  final String hostAddress;
  final int hostPort;
  final String appVersion;
  final Duration connectTimeout;
  final Duration handshakeTimeout;
  final Duration heartbeatIdle;
  final Duration heartbeatTimeout;
  final Duration heartbeatCheck;

  final Transport _transport;
  final List<Duration> _backoff;

  final StreamController<PeerState> _states =
      StreamController<PeerState>.broadcast();
  final StreamController<ProtocolMessage> _messages =
      StreamController<ProtocolMessage>.broadcast();

  PeerState _state = PeerState.idle;
  PeerLink? _link;
  Future<void>? _loop;
  bool _stopped = false;
  Timer? _sleepTimer;
  Completer<void>? _sleepCompleter;

  /// Set after the first successful handshake.
  String? hostDeviceId;
  String? hostName;

  /// Team identity announced by the Host in its ACK.
  String? teamId;
  String? teamName;

  /// Why the Host refused us. Set together with [PeerState.rejected].
  String? rejectionReason;

  PeerState get state => _state;

  /// Emits every state change.
  Stream<PeerState> get states => _states.stream;

  /// Messages from the Host, across reconnects. Broadcast: messages that
  /// arrive while nobody listens are dropped.
  Stream<ProtocolMessage> get messages => _messages.stream;

  HelloPayload get _hello => HelloPayload(
        deviceId: deviceId,
        name: name,
        teamCode: teamCode,
        appVersion: appVersion,
      );

  /// Starts connecting in the background. Returns right away.
  Future<void> start() async {
    if (_stopped) return;
    _loop ??= _run();
  }

  /// Sends to the Host. Throws [StateError] when not connected.
  Future<void> send(ProtocolMessage message) {
    final link = _link;
    if (link == null || _state != PeerState.connected) {
      return Future<void>.error(StateError('Not connected to the host'));
    }
    return link.connection.send(message);
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _wakeSleep();
    await _link?.connection.close();

    final loop = _loop;
    if (loop != null) {
      await loop;
    } else {
      _setState(PeerState.closed);
      await _states.close();
      await _messages.close();
    }
  }

  Future<void> _run() async {
    var attempt = 0;
    try {
      while (!_stopped) {
        _setState(
          attempt == 0 ? PeerState.connecting : PeerState.reconnecting,
        );

        PeerLink? link;
        try {
          final raw = await _transport.connect(
            hostAddress,
            hostPort,
            timeout: connectTimeout,
          );
          final connection = HeartbeatConnection(
            raw,
            localId: deviceId,
            idleInterval: heartbeatIdle,
            timeout: heartbeatTimeout,
            checkInterval: heartbeatCheck,
          );
          link = await connectToHost(
            connection,
            hello: _hello,
            timeout: handshakeTimeout,
          );
        } on HandshakeException catch (e) {
          if (e.rejected) {
            rejectionReason = e.message;
            _setState(PeerState.rejected);
            return;
          }
        } catch (_) {
          // Could not connect (host down, network unreachable). Retry below.
        }

        if (link != null) {
          if (_stopped) {
            await link.connection.close();
            break;
          }
          attempt = 0;
          await _runConnected(link);
          if (_stopped) break;
        }

        final index = attempt < _backoff.length ? attempt : _backoff.length - 1;
        final delay = _backoff[index];
        attempt++;
        _setState(PeerState.reconnecting);
        await _sleep(delay);
      }
    } finally {
      _link = null;
      if (_stopped) _setState(PeerState.closed);
      await _states.close();
      await _messages.close();
    }
  }

  /// Runs until the connection ends.
  Future<void> _runConnected(PeerLink link) async {
    _link = link;
    hostDeviceId = link.remoteDeviceId;
    hostName = link.remoteName;
    teamId = link.remoteTeamId;
    teamName = link.remoteTeamName;

    final ended = Completer<void>();
    link.messages.listen(
      (message) {
        if (!_messages.isClosed) _messages.add(message);
      },
      onDone: () {
        if (!ended.isCompleted) ended.complete();
      },
      onError: (Object _) {},
    );

    _setState(PeerState.connected);
    await ended.future;
    _link = null;
  }

  Future<void> _sleep(Duration duration) {
    final completer = Completer<void>();
    _sleepCompleter = completer;
    _sleepTimer = Timer(duration, () {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  void _wakeSleep() {
    _sleepTimer?.cancel();
    final completer = _sleepCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void _setState(PeerState next) {
    if (_state == next) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }
}
