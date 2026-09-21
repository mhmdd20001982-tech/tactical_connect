import 'dart:async';
import 'dart:io';

import '../discovery/udp_discovery.dart';
import '../protocol/messages/handshake_payloads.dart';
import '../protocol/messages/host_announcement.dart';
import '../protocol/messages/protocol_message.dart';
import '../protocol/protocol_constants.dart';
import '../transport/heartbeat_connection.dart';
import '../transport/tcp_transport.dart';
import '../transport/transport.dart';
import 'handshake.dart';

/// Events a [HostSession] reports to the app.
sealed class HostEvent {
  const HostEvent();
}

class PeerJoined extends HostEvent {
  const PeerJoined({required this.deviceId, required this.name});

  final String deviceId;
  final String name;
}

class PeerLeft extends HostEvent {
  const PeerLeft({required this.deviceId, this.reason});

  final String deviceId;
  final ConnectionCloseReason? reason;
}

class PeerMessage extends HostEvent {
  const PeerMessage({required this.deviceId, required this.message});

  final String deviceId;
  final ProtocolMessage message;
}

/// A connection that failed the handshake (wrong code, bad HELLO, timeout).
class PeerRejected extends HostEvent {
  const PeerRejected({required this.address, required this.reason});

  final String address;
  final String reason;
}

/// The session Host: announces itself, accepts Peers, and checks the team
/// code. One [HostSession] per team (star topology).
class HostSession {
  HostSession({
    required this.deviceId,
    required this.name,
    required this.teamName,
    required String teamCode,
    this.tcpPort = kTransportPort,
    this.announce = true,
    this.discoveryPort = kDiscoveryPort,
    this.announceTargets,
    Transport? transport,
    this.heartbeatIdle = kHeartbeatIdleInterval,
    this.heartbeatTimeout = kHeartbeatTimeout,
    this.heartbeatCheck = const Duration(seconds: 1),
  })  : _teamCode = _normalizeCode(teamCode),
        _transport = transport ?? TcpTransport();

  final String deviceId;
  final String name;
  final String teamName;
  final int tcpPort;
  final bool announce;
  final int discoveryPort;
  final List<InternetAddress>? announceTargets;
  final Duration heartbeatIdle;
  final Duration heartbeatTimeout;
  final Duration heartbeatCheck;

  final String _teamCode;
  final Transport _transport;

  final Map<String, PeerLink> _peers = {};
  final StreamController<HostEvent> _events =
      StreamController<HostEvent>.broadcast();

  TransportServer? _server;
  StreamSubscription<TransportConnection>? _serverSubscription;
  HostAnnouncer? _announcer;
  bool _stopped = false;

  /// The TCP port in use after [start] (useful when started with port 0).
  int get port => _server?.port ?? tcpPort;

  Stream<HostEvent> get events => _events.stream;

  Set<String> get peerIds => Set.unmodifiable(_peers.keys);

  Future<void> start() async {
    if (_server != null || _stopped) return;

    final server = await _transport.listen(port: tcpPort);
    _server = server;
    _serverSubscription = server.connections.listen(_onConnection);

    if (announce) {
      final announcer = HostAnnouncer(
        announcement: HostAnnouncement(
          hostDeviceId: deviceId,
          hostName: name,
          teamName: teamName,
          tcpPort: server.port,
        ),
        port: discoveryPort,
        targets: announceTargets,
      );
      _announcer = announcer;
      await announcer.start();
    }
  }

  void _onConnection(TransportConnection raw) {
    unawaited(_admit(raw));
  }

  Future<void> _admit(TransportConnection raw) async {
    final connection = HeartbeatConnection(
      raw,
      localId: deviceId,
      idleInterval: heartbeatIdle,
      timeout: heartbeatTimeout,
      checkInterval: heartbeatCheck,
    );
    try {
      final link = await acceptPeer(
        connection,
        localDeviceId: deviceId,
        localName: name,
        authorize: _authorize,
      );
      if (_stopped) {
        await link.connection.close();
        return;
      }
      _register(link);
    } on HandshakeException catch (e) {
      _emit(PeerRejected(address: raw.remoteAddress, reason: e.message));
    } catch (e) {
      _emit(PeerRejected(address: raw.remoteAddress, reason: '$e'));
    }
  }

  HelloDecision _authorize(HelloPayload hello) {
    if (hello.deviceId == deviceId) {
      return const HelloDecision.reject('same_device');
    }
    if (!_safeEquals(_normalizeCode(hello.teamCode), _teamCode)) {
      return const HelloDecision.reject('wrong_team_code');
    }
    return const HelloDecision.accept();
  }

  void _register(PeerLink link) {
    final id = link.remoteDeviceId;

    // The same device reconnected: replace its old link.
    final old = _peers[id];
    if (old != null) unawaited(old.connection.close());

    _peers[id] = link;
    _emit(PeerJoined(deviceId: id, name: link.remoteName));

    link.messages.listen(
      (message) => _emit(PeerMessage(deviceId: id, message: message)),
      onDone: () {
        // Ignore the end of a link that was already replaced.
        if (!identical(_peers[id], link)) return;
        _peers.remove(id);
        final connection = link.connection;
        _emit(
          PeerLeft(
            deviceId: id,
            reason: connection is HeartbeatConnection
                ? connection.closeReason
                : null,
          ),
        );
      },
      onError: (Object _) {},
    );
  }

  /// Sends [message] to one Peer. Throws if the Peer is not connected.
  Future<void> sendTo(String peerDeviceId, ProtocolMessage message) async {
    final link = _peers[peerDeviceId];
    if (link == null) {
      throw StateError('Peer $peerDeviceId is not connected');
    }
    await link.connection.send(message);
  }

  /// Sends [message] to every connected Peer (except [exceptDeviceId]).
  /// A failing Peer does not stop the others.
  Future<void> broadcast(
    ProtocolMessage message, {
    String? exceptDeviceId,
  }) async {
    final sends = <Future<void>>[];
    for (final entry in _peers.entries) {
      if (entry.key == exceptDeviceId) continue;
      sends.add(
        entry.value.connection.send(message).catchError((Object _) {}),
      );
    }
    await Future.wait(sends);
  }

  /// Disconnects one Peer. It may reconnect on its own.
  Future<void> kick(String peerDeviceId) async {
    final link = _peers[peerDeviceId];
    if (link != null) await link.connection.close();
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;

    await _announcer?.stop();
    await _serverSubscription?.cancel();
    await _server?.close();

    final links = _peers.values.toList();
    for (final link in links) {
      await link.connection.close();
    }
    await _events.close();
  }

  void _emit(HostEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}

/// Team codes are compared without case or surrounding spaces.
String _normalizeCode(String code) => code.trim().toUpperCase();

/// Compares two strings without stopping at the first difference.
bool _safeEquals(String a, String b) {
  var diff = a.length ^ b.length;
  final length = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
