/// Control message types. Data types (chat, location, point, SOS)
/// are added together with their features.
enum MessageType {
  hello('HELLO'),
  ack('ACK'),
  ping('PING'),
  hostAnnounce('HOST_ANNOUNCE');

  const MessageType(this.wireName);

  final String wireName;

  static MessageType? fromWireName(String name) {
    for (final type in MessageType.values) {
      if (type.wireName == name) return type;
    }
    return null;
  }
}
