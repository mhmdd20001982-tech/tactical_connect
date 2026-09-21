/// Wire-protocol constants for Tactical Connect V1.
const int kProtocolVersion = 1;

/// UDP port used for HOST_ANNOUNCE discovery broadcasts.
const int kDiscoveryPort = 7890;

/// Default TCP port used by the session Host.
const int kTransportPort = 7891;

const Duration kHostAnnounceInterval = Duration(seconds: 2);

/// Send a PING if nothing was sent for this long.
const Duration kHeartbeatIdleInterval = Duration(seconds: 10);

/// Drop the connection if nothing was received for this long.
const Duration kHeartbeatTimeout = Duration(seconds: 25);

/// Peer reconnect backoff in seconds (last value repeats).
const List<int> kReconnectBackoffSeconds = [2, 4, 8, 16];

/// Maximum characters allowed in one frame (one JSON line).
const int kMaxFrameChars = 1024 * 1024;
