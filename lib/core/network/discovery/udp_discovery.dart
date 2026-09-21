import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../protocol/message_codec.dart';
import '../protocol/message_type.dart';
import '../protocol/messages/host_announcement.dart';
import '../protocol/messages/protocol_message.dart';
import '../protocol/protocol_constants.dart';
import '../protocol/protocol_exception.dart';

/// Sends HOST_ANNOUNCE datagrams while this device is the session Host.
///
/// V1 limitation: by default it sends to 255.255.255.255 only. On a device
/// with several network adapters the OS picks one. The manual IP fallback
/// covers the cases where broadcast does not reach the peers.
class HostAnnouncer {
  HostAnnouncer({
    required this.announcement,
    this.port = kDiscoveryPort,
    this.interval = kHostAnnounceInterval,
    List<InternetAddress>? targets,
  }) : targets = targets ?? [InternetAddress('255.255.255.255')];

  final HostAnnouncement announcement;
  final int port;
  final Duration interval;
  final List<InternetAddress> targets;

  RawDatagramSocket? _socket;
  Timer? _timer;

  bool get isRunning => _socket != null;

  Future<void> start() async {
    if (_socket != null) return;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    _socket = socket;
    _sendOnce();
    _timer = Timer.periodic(interval, (_) => _sendOnce());
  }

  void _sendOnce() {
    final socket = _socket;
    if (socket == null) return;

    final message = ProtocolMessage.create(
      type: MessageType.hostAnnounce,
      senderId: announcement.hostDeviceId,
      payload: announcement.toPayload(),
    );
    final bytes = utf8.encode(encodeMessage(message));

    for (final target in targets) {
      try {
        socket.send(bytes, target, port);
      } on SocketException {
        // Network is down or the address is not reachable.
        // Try again on the next tick.
      }
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}

/// A Host that was seen on the network.
class DiscoveredHost {
  const DiscoveredHost({required this.announcement, required this.address});

  final HostAnnouncement announcement;

  /// The address the datagram came from (not taken from the payload).
  final InternetAddress address;

  bool sameAs(DiscoveredHost other) {
    return announcement == other.announcement &&
        address.address == other.address.address;
  }
}

class _Entry {
  _Entry(this.host, this.lastSeen);

  final DiscoveredHost host;
  Duration lastSeen;
}

/// Listens for HOST_ANNOUNCE datagrams and keeps a list of live Hosts.
///
/// A Host disappears from the list when nothing was heard from it for [ttl].
/// After [stop] this object cannot be started again; create a new one.
class HostDiscovery {
  HostDiscovery({
    int port = kDiscoveryPort,
    this.ownDeviceId,
    Duration? ttl,
    this.expiryCheckInterval = const Duration(seconds: 1),
  })  : _requestedPort = port,
        ttl = ttl ?? kHostAnnounceInterval * 3;

  final int _requestedPort;

  /// Announcements from this device id are ignored.
  final String? ownDeviceId;
  final Duration ttl;
  final Duration expiryCheckInterval;

  final Stopwatch _clock = Stopwatch();
  final Map<String, _Entry> _entries = {};
  final StreamController<List<DiscoveredHost>> _changes =
      StreamController<List<DiscoveredHost>>.broadcast();
  RawDatagramSocket? _socket;
  Timer? _expiryTimer;

  /// The bound port after [start] (useful when started with port 0).
  int get port => _socket?.port ?? _requestedPort;

  /// Emits the full list every time a Host appears, changes, or expires.
  Stream<List<DiscoveredHost>> get changes => _changes.stream;

  List<DiscoveredHost> get hosts =>
      List.unmodifiable(_entries.values.map((entry) => entry.host));

  Future<void> start() async {
    if (_socket != null) return;
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _requestedPort,
      reuseAddress: true,
    );
    _socket = socket;
    _clock.start();
    socket.listen(_onEvent, onError: (Object _) {});
    _expiryTimer = Timer.periodic(expiryCheckInterval, (_) => _expire());
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;

    Datagram? datagram = socket.receive();
    while (datagram != null) {
      _handle(datagram);
      datagram = socket.receive();
    }
  }

  void _handle(Datagram datagram) {
    final ProtocolMessage message;
    try {
      message = decodeMessage(utf8.decode(datagram.data, allowMalformed: true));
    } on ProtocolException {
      return; // Not one of our messages.
    }
    if (message.type != MessageType.hostAnnounce) return;

    final HostAnnouncement announcement;
    try {
      announcement = HostAnnouncement.fromPayload(message.payload);
    } on ProtocolException {
      return;
    }

    // The envelope must agree with the payload about who the Host is.
    if (message.senderId != announcement.hostDeviceId) return;
    if (announcement.hostDeviceId == ownDeviceId) return;

    final host = DiscoveredHost(
      announcement: announcement,
      address: datagram.address,
    );
    final previous = _entries[announcement.hostDeviceId];
    _entries[announcement.hostDeviceId] = _Entry(host, _clock.elapsed);

    if (previous == null || !previous.host.sameAs(host)) _emit();
  }

  void _expire() {
    final now = _clock.elapsed;
    final before = _entries.length;
    _entries.removeWhere((_, entry) => now - entry.lastSeen > ttl);
    if (_entries.length != before) _emit();
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(hosts);
  }

  Future<void> stop() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _socket?.close();
    _socket = null;
    _entries.clear();
    if (!_changes.isClosed) await _changes.close();
  }
}
