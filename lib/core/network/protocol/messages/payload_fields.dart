import '../protocol_exception.dart';

/// Reads a required, non-empty string field from a message payload.
String requiredString(
  Map<String, dynamic> payload,
  String key, {
  int maxLength = 128,
}) {
  final value = payload[key];
  if (value is! String || value.trim().isEmpty) {
    throw ProtocolException('Missing or invalid "$key"');
  }
  if (value.length > maxLength) {
    throw ProtocolException('"$key" is too long');
  }
  return value;
}

/// Reads a required TCP/UDP port (1..65535) from a message payload.
int requiredPort(Map<String, dynamic> payload, String key) {
  final value = payload[key];
  if (value is! int || value < 1 || value > 65535) {
    throw ProtocolException('Missing or invalid "$key"');
  }
  return value;
}
