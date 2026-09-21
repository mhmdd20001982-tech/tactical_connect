import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database.dart';
import '../../../core/database/database_provider.dart';

/// A team member together with the user row of that member.
class MemberView {
  const MemberView({required this.user, required this.member});

  final User user;
  final TeamMember member;

  bool get isOnline => member.status == 'online';
  bool get isHost => member.role == 'host';
}

class TeamRepository {
  TeamRepository(this._db);

  final AppDatabase _db;

  /// No I, O, L, 0 or 1, so a code is easy to read aloud and to type.
  static const String codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const int codeLength = 6;

  static String generateTeamCode([Random? random]) {
    final rng = random ?? Random.secure();
    final units = List<int>.generate(
      codeLength,
      (_) => codeAlphabet.codeUnitAt(rng.nextInt(codeAlphabet.length)),
    );
    return String.fromCharCodes(units);
  }

  static String normalizeCode(String code) => code.trim().toUpperCase();

  Future<User?> getSelf() {
    return (_db.select(_db.users)..where((u) => u.isSelf.equals(true)))
        .getSingleOrNull();
  }

  /// Creates a team that this device hosts, with a fresh team code.
  Future<Team> createTeam({
    required String name,
    required String hostDeviceId,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;

    var code = generateTeamCode();
    while (await _codeExists(code)) {
      code = generateTeamCode();
    }

    await _db.into(_db.teams).insert(
          TeamsCompanion.insert(
            id: id,
            teamCode: code,
            name: name,
            hostDeviceId: hostDeviceId,
            createdAt: now,
          ),
        );
    await upsertMember(
      teamId: id,
      deviceId: hostDeviceId,
      role: 'host',
      online: true,
    );

    return (_db.select(_db.teams)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<bool> _codeExists(String code) async {
    final row = await (_db.select(_db.teams)
          ..where((t) => t.teamCode.equals(code)))
        .getSingleOrNull();
    return row != null;
  }

  /// The newest active team this device hosts, if any.
  Future<Team?> latestHostedTeam(String selfDeviceId) {
    return (_db.select(_db.teams)
          ..where(
            (t) => t.hostDeviceId.equals(selfDeviceId) & t.isActive.equals(true),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Stores (or refreshes) a team this device joined as a Peer.
  Future<void> saveJoinedTeam({
    required String teamId,
    required String teamCode,
    required String teamName,
    required String hostDeviceId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.teams).insert(
          TeamsCompanion.insert(
            id: teamId,
            teamCode: teamCode,
            name: teamName,
            hostDeviceId: hostDeviceId,
            createdAt: now,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// Adds or updates a remote user (never touches the local user row).
  Future<void> upsertUser({
    required String deviceId,
    required String name,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.users).insert(
          UsersCompanion.insert(
            deviceId: deviceId,
            name: name,
            lastSeen: now,
            createdAt: now,
          ),
          onConflict: DoUpdate(
            (old) => UsersCompanion(
              name: Value(name),
              lastSeen: Value(now),
            ),
          ),
        );
  }

  Future<void> upsertMember({
    required String teamId,
    required String deviceId,
    required String role,
    required bool online,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final status = online ? 'online' : 'offline';
    await _db.into(_db.teamMembers).insert(
          TeamMembersCompanion.insert(
            teamId: teamId,
            deviceId: deviceId,
            role: role,
            joinedAt: now,
            status: Value(status),
          ),
          onConflict: DoUpdate(
            (old) => TeamMembersCompanion(
              role: Value(role),
              status: Value(status),
            ),
          ),
        );
  }

  Future<void> setMemberOnline({
    required String teamId,
    required String deviceId,
    required bool online,
  }) async {
    await (_db.update(_db.teamMembers)
          ..where((m) => m.teamId.equals(teamId) & m.deviceId.equals(deviceId)))
        .write(TeamMembersCompanion(status: Value(online ? 'online' : 'offline')));
  }

  /// Marks every member of the team (including this device) as offline.
  Future<void> setTeamOffline(String teamId) async {
    await (_db.update(_db.teamMembers)..where((m) => m.teamId.equals(teamId)))
        .write(const TeamMembersCompanion(status: Value('offline')));
  }

  /// Live list of the members of a team: host first, then by name.
  Stream<List<MemberView>> watchMembers(String teamId) {
    final query = _db.select(_db.teamMembers).join([
      innerJoin(
        _db.users,
        _db.users.deviceId.equalsExp(_db.teamMembers.deviceId),
      ),
    ])
      ..where(_db.teamMembers.teamId.equals(teamId));

    return query.watch().map((rows) {
      final members = rows
          .map(
            (row) => MemberView(
              user: row.readTable(_db.users),
              member: row.readTable(_db.teamMembers),
            ),
          )
          .toList();
      members.sort((a, b) {
        if (a.isHost != b.isHost) return a.isHost ? -1 : 1;
        return a.user.name.toLowerCase().compareTo(b.user.name.toLowerCase());
      });
      return members;
    });
  }
}

final teamRepositoryProvider = Provider<TeamRepository>((ref) {
  return TeamRepository(ref.watch(appDatabaseProvider));
});

final teamMembersProvider =
    StreamProvider.autoDispose.family<List<MemberView>, String>((ref, teamId) {
  return ref.watch(teamRepositoryProvider).watchMembers(teamId);
});
