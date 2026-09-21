import '../protocol_exception.dart';
import 'payload_fields.dart';

/// Payload of the HELLO message a Peer sends right after connecting.
class HelloPayload {
  const HelloPayload({
    required this.deviceId,
    required this.name,
    required this.teamCode,
    required this.appVersion,
  });

  factory HelloPayload.fromPayload(Map<String, dynamic> payload) {
    return HelloPayload(
      deviceId: requiredString(payload, 'device_id'),
      name: requiredString(payload, 'name', maxLength: 64),
      teamCode: requiredString(payload, 'team_code', maxLength: 32),
      appVersion: requiredString(payload, 'app_version', maxLength: 32),
    );
  }

  final String deviceId;
  final String name;
  final String teamCode;
  final String appVersion;

  Map<String, dynamic> toPayload() => {
        'device_id': deviceId,
        'name': name,
        'team_code': teamCode,
        'app_version': appVersion,
      };
}

/// Answer of the Host to a HELLO. It travels inside an ACK message,
/// next to "acked_message_id".
class HelloReply {
  const HelloReply.accepted({this.name, this.teamId, this.teamName})
      : accepted = true,
        reason = null;

  const HelloReply.rejected(String reason)
      : accepted = false,
        reason = reason,
        name = null,
        teamId = null,
        teamName = null;

  factory HelloReply.fromPayload(Map<String, dynamic> payload) {
    final accepted = payload['accepted'];
    if (accepted is! bool) {
      throw ProtocolException('Missing or invalid "accepted"');
    }
    if (accepted) {
      String? optional(String key) {
        final value = payload[key];
        return value is String && value.isNotEmpty ? value : null;
      }

      return HelloReply.accepted(
        name: optional('name'),
        teamId: optional('team_id'),
        teamName: optional('team_name'),
      );
    }
    final reason = payload['reason'];
    return HelloReply.rejected(reason is String ? reason : 'unknown');
  }

  final bool accepted;

  /// Why the Host refused. Only set when [accepted] is false.
  final String? reason;

  /// Display name of the Host. Only set when [accepted] is true.
  final String? name;

  /// Identity of the team the Host runs. Only set when [accepted] is true.
  final String? teamId;
  final String? teamName;

  Map<String, dynamic> toPayload() => {
        'accepted': accepted,
        if (reason != null) 'reason': reason,
        if (name != null) 'name': name,
        if (teamId != null) 'team_id': teamId,
        if (teamName != null) 'team_name': teamName,
      };
}
