import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_connect/core/network/protocol/message_codec.dart';
import 'package:tactical_connect/core/network/protocol/message_type.dart';
import 'package:tactical_connect/core/network/protocol/messages/protocol_message.dart';
import 'package:tactical_connect/core/network/protocol/protocol_exception.dart';

ProtocolMessage _sample({Map<String, dynamic> payload = const {}}) {
  return ProtocolMessage.create(
    type: MessageType.hello,
    senderId: 'device-1',
    payload: payload,
  );
}

void main() {
  group('encode / decode', () {
    test('round trip keeps every field', () {
      final original = _sample(payload: {'name': 'أحمد', 'team_code': 'AB12'});
      final decoded = decodeMessage(encodeMessage(original));

      expect(decoded.type, MessageType.hello);
      expect(decoded.id, original.id);
      expect(decoded.senderId, 'device-1');
      expect(decoded.timestamp, original.timestamp);
      expect(decoded.payload, {'name': 'أحمد', 'team_code': 'AB12'});
    });

    test('newlines inside strings do not break framing', () {
      final message = _sample(payload: {'text': 'line1\nline2\r\nline3'});
      final encoded = encodeMessage(message);

      expect('\n'.allMatches(encoded).length, 1);
      expect(encoded.endsWith('\n'), isTrue);

      final decoded = MessageFrameDecoder().add(encoded);
      expect(decoded.single.payload['text'], 'line1\nline2\r\nline3');
    });

    test('ACK carries acked_message_id', () {
      final ack = ProtocolMessage.ack(
        senderId: 'device-2',
        ackedMessageId: 'abc',
      );
      final decoded = decodeMessage(encodeMessage(ack));
      expect(decoded.type, MessageType.ack);
      expect(decoded.ackedMessageId, 'abc');
    });

    test('ACK without acked_message_id is rejected', () {
      final line = jsonEncode({
        'v': 1,
        'type': 'ACK',
        'id': 'x',
        'sender_id': 'd',
        'ts': 1,
        'payload': {},
      });
      expect(() => decodeMessage(line), throwsA(isA<ProtocolException>()));
    });

    test('unsupported version is rejected', () {
      final line = jsonEncode({
        'v': 99,
        'type': 'PING',
        'id': 'x',
        'sender_id': 'd',
        'ts': 1,
      });
      expect(() => decodeMessage(line), throwsA(isA<ProtocolException>()));
    });

    test('unknown type is rejected', () {
      final line = jsonEncode({
        'v': 1,
        'type': 'NOPE',
        'id': 'x',
        'sender_id': 'd',
        'ts': 1,
      });
      expect(() => decodeMessage(line), throwsA(isA<ProtocolException>()));
    });

    test('missing payload becomes empty map', () {
      final line = jsonEncode({
        'v': 1,
        'type': 'PING',
        'id': 'x',
        'sender_id': 'd',
        'ts': 1,
      });
      expect(decodeMessage(line).payload, isEmpty);
    });
  });

  group('MessageFrameDecoder', () {
    test('handles a message split across chunks', () {
      final encoded = encodeMessage(_sample());
      final decoder = MessageFrameDecoder();

      expect(decoder.add(encoded.substring(0, 10)), isEmpty);
      expect(decoder.add(encoded.substring(10)), hasLength(1));
    });

    test('handles several messages in one chunk', () {
      final decoder = MessageFrameDecoder();
      final chunk = encodeMessage(_sample()) + encodeMessage(_sample());
      expect(decoder.add(chunk), hasLength(2));
    });

    test('skips malformed frames and reports them', () {
      var malformedCount = 0;
      final decoder = MessageFrameDecoder(
        onMalformed: (line, error) => malformedCount++,
      );

      final result = decoder.add('not json\n${encodeMessage(_sample())}');
      expect(result, hasLength(1));
      expect(malformedCount, 1);
    });

    test('throws when a frame is too large without a newline', () {
      final decoder = MessageFrameDecoder(maxFrameChars: 50);
      expect(
        () => decoder.add('x' * 100),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('throws when a complete line is too large', () {
      final decoder = MessageFrameDecoder(maxFrameChars: 50);
      expect(
        () => decoder.add('${'x' * 100}\n'),
        throwsA(isA<ProtocolException>()),
      );
    });
  });

  group('decodeMessageStream', () {
    test('handles multi-byte characters split across byte chunks', () async {
      final message = _sample(payload: {'name': 'محمد الأحمد'});
      final bytes = utf8.encode(encodeMessage(message));

      final chunks = <List<int>>[];
      for (var i = 0; i < bytes.length; i += 3) {
        final end = (i + 3 < bytes.length) ? i + 3 : bytes.length;
        chunks.add(bytes.sublist(i, end));
      }

      final result =
          await decodeMessageStream(Stream.fromIterable(chunks)).toList();

      expect(result, hasLength(1));
      expect(result.single.payload['name'], 'محمد الأحمد');
    });
  });
}
