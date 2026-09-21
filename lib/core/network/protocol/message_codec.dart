import 'dart:async';
import 'dart:convert';

import 'messages/protocol_message.dart';
import 'protocol_constants.dart';
import 'protocol_exception.dart';

/// Encodes one message as a single line ending with '\n'.
/// jsonEncode escapes newlines inside strings, so framing stays safe.
String encodeMessage(ProtocolMessage message) {
  return '${jsonEncode(message.toJson())}\n';
}

/// Decodes one line (without framing) into a message.
/// Throws [ProtocolException] if the line is not a valid message.
ProtocolMessage decodeMessage(String line) {
  Object? decoded;
  try {
    decoded = jsonDecode(line);
  } on FormatException catch (e) {
    throw ProtocolException('Invalid JSON: ${e.message}');
  }
  if (decoded is! Map) {
    throw ProtocolException('Frame is not a JSON object');
  }
  return ProtocolMessage.fromJson(Map<String, dynamic>.from(decoded));
}

/// Splits incoming text into newline-delimited frames and decodes them.
///
/// - Malformed frames are skipped and reported through [onMalformed].
/// - A frame larger than [maxFrameChars] throws [ProtocolException];
///   the caller should close the connection.
class MessageFrameDecoder {
  MessageFrameDecoder({
    this.maxFrameChars = kMaxFrameChars,
    this.onMalformed,
  });

  final int maxFrameChars;
  final void Function(String line, Object error)? onMalformed;

  String _pending = '';

  List<ProtocolMessage> add(String chunk) {
    final messages = <ProtocolMessage>[];
    _pending += chunk;

    var start = 0;
    while (true) {
      final newline = _pending.indexOf('\n', start);
      if (newline == -1) break;

      final line = _pending.substring(start, newline).trim();
      start = newline + 1;

      if (line.length > maxFrameChars) {
        throw ProtocolException('Frame too large');
      }
      if (line.isEmpty) continue;

      try {
        messages.add(decodeMessage(line));
      } on ProtocolException catch (e) {
        onMalformed?.call(line, e);
      }
    }

    _pending = _pending.substring(start);
    if (_pending.length > maxFrameChars) {
      throw ProtocolException('Frame too large');
    }
    return messages;
  }
}

/// Turns a raw byte stream (for example a Socket) into protocol messages.
Stream<ProtocolMessage> decodeMessageStream(
  Stream<List<int>> bytes, {
  int maxFrameChars = kMaxFrameChars,
  void Function(String line, Object error)? onMalformed,
}) async* {
  final decoder = MessageFrameDecoder(
    maxFrameChars: maxFrameChars,
    onMalformed: onMalformed,
  );
  final text = const Utf8Decoder(allowMalformed: true).bind(bytes);
  await for (final chunk in text) {
    for (final message in decoder.add(chunk)) {
      yield message;
    }
  }
}
