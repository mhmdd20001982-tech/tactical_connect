import 'payload_fields.dart';

/// Payload of a HOST_ANNOUNCE message (sent by the session Host over UDP).
///
/// It does not contain an IP address: the receiver uses the address the
/// datagram came from. It does not contain the team code either.
class HostAnnouncement {
  const HostAnnouncement({
    required this.hostDeviceId,
    required this.hostName,
    required this.teamName,
    required this.tcpPort,
  });

  factory HostAnnouncement.fromPayload(Map<String, dynamic> payload) {
    return HostAnnouncement(
      hostDeviceId: requiredString(payload, 'host_device_id'),
      hostName: requiredString(payload, 'host_name', maxLength: 64),
      teamName: requiredString(payload, 'team_name', maxLength: 64),
      tcpPort: requiredPort(payload, 'tcp_port'),
    );
  }

  final String hostDeviceId;
  final String hostName;
  final String teamName;
  final int tcpPort;

  Map<String, dynamic> toPayload() => {
        'host_device_id': hostDeviceId,
        'host_name': hostName,
        'team_name': teamName,
        'tcp_port': tcpPort,
      };

  @override
  bool operator ==(Object other) {
    return other is HostAnnouncement &&
        other.hostDeviceId == hostDeviceId &&
        other.hostName == hostName &&
        other.teamName == teamName &&
        other.tcpPort == tcpPort;
  }

  @override
  int get hashCode => Object.hash(hostDeviceId, hostName, teamName, tcpPort);
}
