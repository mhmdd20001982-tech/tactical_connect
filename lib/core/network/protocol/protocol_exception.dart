/// Thrown when a frame or message violates the wire protocol.
class ProtocolException implements Exception {
  ProtocolException(this.message);

  final String message;

  @override
  String toString() => 'ProtocolException: $message';
}
