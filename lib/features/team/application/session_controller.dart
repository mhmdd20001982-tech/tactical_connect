import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/identity/self_user_provider.dart';
import '../../../core/network/discovery/udp_discovery.dart';
import '../../../core/network/protocol/protocol_constants.dart';
import '../../../core/network/session/host_session.dart';
import '../../../core/network/session/peer_session.dart';
import '../data/team_repository.dart';

enum SessionRole { none, host, peer }

/// What the UI needs to know about the current session.
class SessionState {
  const SessionState({
    this.role = SessionRole.none,
    this.teamId,
    this.teamName,
    this.teamCode,
    this.peerState,
    this.hostPort,
    this.error,
  });

  final SessionRole role;
  final String? teamId;
  final String? teamName;
  final String? teamCode;

  /// Connection state (Peer role only).
  final PeerState? peerState;

  /// TCP port we listen on (Host role only).
  final int? hostPort;

  /// Last error, shown to the user. Cleared by the next action.
  final String? error;

  bool get isActive => role != SessionRole.none;
}

/// Owns the one active [HostSession] or [PeerSession] and keeps the
/// database in step with it.
class SessionController extends Notifier<SessionState> {
  HostSession? _host;
  PeerSession? _peer;
  StreamSubscription<HostEvent>? _hostEvents;
  StreamSubscription<PeerState>? _peerStates;

  /// Database writes run one after another, in event order.
  Future<void> _queue = Future<void>.value();
  bool _disposed = false;

  TeamRepository get _repo => ref.read(teamRepositoryProvider);

  @override
  SessionState build() {
    ref.onDispose(() {
      _disposed = true;
      unawaited(_stopSessions());
    });
    return const SessionState();
  }

  void _set(SessionState next) {
    if (!_disposed) state = next;
  }

  void _enqueue(Future<void> Function() job) {
    _queue = _queue.then((_) => job()).catchError((Object _) {});
  }

  Future<User> _self() async {
    final self = await _repo.getSelf();
    if (self == null) throw StateError('No local identity');
    return self;
  }

  // ---------------------------------------------------------------- Host

  Future<void> createTeam(String teamName) async {
    final name = teamName.trim();
    if (name.isEmpty) return;
    try {
      final self = await _self();
      final team = await _repo.createTeam(
        name: name,
        hostDeviceId: self.deviceId,
      );
      await _startHosting(team, self);
    } catch (e) {
      _set(SessionState(error: 'Could not create the team: $e'));
    }
  }

  Future<void> resumeHosting(Team team) async {
    try {
      final self = await _self();
      await _startHosting(team, self);
    } catch (e) {
      _set(SessionState(error: 'Could not resume hosting: $e'));
    }
  }

  Future<void> _startHosting(Team team, User self) async {
    await _stopSessions();

    final host = HostSession(
      deviceId: self.deviceId,
      name: self.name,
      teamName: team.name,
      teamId: team.id,
      teamCode: team.teamCode,
    );
    try {
      await host.start();
    } catch (_) {
      await host.stop();
      rethrow;
    }
    _host = host;

    await _repo.setTeamOffline(team.id);
    await _repo.upsertMember(
      teamId: team.id,
      deviceId: self.deviceId,
      role: 'host',
      online: true,
    );

    _hostEvents = host.events.listen(
      (event) => _enqueue(() => _onHostEvent(team.id, event)),
    );

    _set(
      SessionState(
        role: SessionRole.host,
        teamId: team.id,
        teamName: team.name,
        teamCode: team.teamCode,
        hostPort: host.port,
      ),
    );
  }

  Future<void> _onHostEvent(String teamId, HostEvent event) async {
    switch (event) {
      case PeerJoined(:final deviceId, :final name):
        await _repo.upsertUser(deviceId: deviceId, name: name);
        await _repo.upsertMember(
          teamId: teamId,
          deviceId: deviceId,
          role: 'peer',
          online: true,
        );
      case PeerLeft(:final deviceId):
        await _repo.setMemberOnline(
          teamId: teamId,
          deviceId: deviceId,
          online: false,
        );
      case PeerMessage():
      case PeerRejected():
        // Messages belong to later features; rejected attempts are ignored.
        break;
    }
  }

  // ---------------------------------------------------------------- Peer

  Future<void> joinTeam({
    required String address,
    int port = kTransportPort,
    required String teamCode,
  }) async {
    final code = TeamRepository.normalizeCode(teamCode);
    try {
      final self = await _self();
      await _stopSessions();

      final peer = PeerSession(
        deviceId: self.deviceId,
        name: self.name,
        teamCode: code,
        hostAddress: address.trim(),
        hostPort: port,
      );
      _peer = peer;
      _peerStates = peer.states.listen(
        (peerState) => _onPeerState(peer, self, code, peerState),
      );
      _set(
        SessionState(
          role: SessionRole.peer,
          teamCode: code,
          peerState: PeerState.connecting,
        ),
      );
      await peer.start();
    } catch (e) {
      _set(SessionState(error: 'Could not join the team: $e'));
    }
  }

  void _onPeerState(
    PeerSession peer,
    User self,
    String code,
    PeerState peerState,
  ) {
    if (_disposed || !identical(_peer, peer)) return;

    switch (peerState) {
      case PeerState.connected:
        _enqueue(() async {
          final hostId = peer.hostDeviceId;
          if (hostId == null) return;
          final teamId = peer.teamId ?? 'team-$hostId';
          final teamName = peer.teamName ?? peer.hostName ?? 'Team';

          await _repo.saveJoinedTeam(
            teamId: teamId,
            teamCode: code,
            teamName: teamName,
            hostDeviceId: hostId,
          );
          await _repo.upsertUser(
            deviceId: hostId,
            name: peer.hostName ?? 'Host',
          );
          await _repo.upsertMember(
            teamId: teamId,
            deviceId: hostId,
            role: 'host',
            online: true,
          );
          await _repo.upsertMember(
            teamId: teamId,
            deviceId: self.deviceId,
            role: 'peer',
            online: true,
          );

          if (identical(_peer, peer)) {
            _set(
              SessionState(
                role: SessionRole.peer,
                teamId: teamId,
                teamName: teamName,
                teamCode: code,
                peerState: PeerState.connected,
              ),
            );
          }
        });
      case PeerState.connecting:
      case PeerState.reconnecting:
        final teamId = state.teamId;
        final hostId = peer.hostDeviceId;
        _set(
          SessionState(
            role: SessionRole.peer,
            teamId: teamId,
            teamName: state.teamName,
            teamCode: code,
            peerState: peerState,
          ),
        );
        if (peerState == PeerState.reconnecting &&
            teamId != null &&
            hostId != null) {
          _enqueue(
            () => _repo.setMemberOnline(
              teamId: teamId,
              deviceId: hostId,
              online: false,
            ),
          );
        }
      case PeerState.rejected:
        final message = _rejectionMessage(peer.rejectionReason);
        unawaited(_stopSessions());
        _set(SessionState(error: message));
      case PeerState.idle:
      case PeerState.closed:
        break;
    }
  }

  String _rejectionMessage(String? reason) {
    final text = reason ?? '';
    if (text.contains('wrong_team_code')) return 'Wrong team code.';
    if (text.contains('same_device')) return 'You cannot join your own team.';
    return 'The host refused the connection ($text).';
  }

  // -------------------------------------------------------------- Common

  /// Leaves the current team (Peer) or stops hosting (Host).
  Future<void> leave() async {
    final teamId = state.teamId;
    await _stopSessions();
    await _queue;
    if (teamId != null) await _repo.setTeamOffline(teamId);
    _set(const SessionState());
  }

  Future<void> _stopSessions() async {
    final hostEvents = _hostEvents;
    final peerStates = _peerStates;
    final host = _host;
    final peer = _peer;
    _hostEvents = null;
    _peerStates = null;
    _host = null;
    _peer = null;

    await hostEvents?.cancel();
    await peerStates?.cancel();
    await host?.stop();
    await peer?.stop();
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

/// Hosts seen on the network. Discovery runs only while something watches
/// this provider (the join screen).
final discoveredHostsProvider =
    StreamProvider.autoDispose<List<DiscoveredHost>>((ref) async* {
  final self = await ref.watch(selfUserStreamProvider.future);
  final discovery = HostDiscovery(ownDeviceId: self?.deviceId);
  ref.onDispose(() => unawaited(discovery.stop()));

  await discovery.start();
  yield discovery.hosts;
  yield* discovery.changes;
});

/// The newest team this device hosts, used for the "resume" card.
final latestHostedTeamProvider = FutureProvider.autoDispose<Team?>((ref) async {
  final self = await ref.watch(selfUserStreamProvider.future);
  ref.watch(sessionControllerProvider.select((s) => s.role));
  if (self == null) return null;
  return ref.watch(teamRepositoryProvider).latestHostedTeam(self.deviceId);
});
