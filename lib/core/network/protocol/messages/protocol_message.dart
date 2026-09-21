import 'package:uuid/uuid.dart';

import '../message_type.dart';
import '../protocol_constants.dart';
import '../protocol_exception.dart';

/// One protocol message (the envelope).
///
/// Wire format (one JSON object per line):
/// {"v":1,"type":"HELLO","id":"...","sender_id":"...","ts":123,"payload":{}}
class ProtocolMessage {
  const ProtocolMessage({
    required this.type,
    required this.id,
    required this.senderId,
    required this.timestamp,
    this.payload = const <String, dynamic>{},
    this.version = kProtocolVersion,
  });

  factory ProtocolMessage.create({
    required MessageType type,
    required String senderId,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) {
    return ProtocolMessage(
      type: type,
      id: const Uuid().v4(),
      senderId: senderId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: payload,
    );
  }

  factory ProtocolMessage.ack({
    required String senderId,
    required String ackedMessageId,
  }) {
    return ProtocolMessage.create(
      type: MessageType.ack,
      senderId: senderId,
      payload: {'acked_message_id': ackedMessageId},
    );
  }

  factory ProtocolMessage.ping({required String senderId}) {
    return ProtocolMessage.create(type: MessageType.ping, senderId: senderId);
  }

  factory ProtocolMessage.fromJson(Map<String, dynamic> json) {
    final version = json['v'];
    if (version is! int) {
      throw ProtocolException('Missing or invalid "v"');
    }
    if (version != kProtocolVersion) {
      throw ProtocolException('Unsupported protocol version: $version');
    }

    final typeName = json['type'];
    if (typeName is! String) {
      throw ProtocolException('Missing or invalid "type"');
    }
    final type = MessageType.fromWireName(typeName);
    if (type == null) {
      throw ProtocolException('Unknown message type: $typeName');
    }

    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw ProtocolException('Missing or invalid "id"');
    }

    final senderId = json['sender_id'];
    if (senderId is! String || senderId.isEmpty) {
      throw ProtocolException('Missing or invalid "sender_id"');
    }

    final timestamp = json['ts'];
    if (timestamp is! int) {
      throw ProtocolException('Missing or invalid "ts"');
    }

    final rawPayload = json['payload'];
    final Map<String, dynamic> payload;
    if (rawPayload == null) {
      payload = const <String, dynamic>{};
    } else if (rawPayload is Map) {
      payload = Map<String, dynamic>.from(rawPayload);
    } else {
      throw ProtocolException('"payload" must be an object');
    }

    final message = ProtocolMessage(
      type: type,
      id: id,
      senderId: senderId,
      timestamp: timestamp,
      payload: payload,
      version: version,
    );

    if (type == MessageType.ack && message.ackedMessageId == null) {
      throw ProtocolException('ACK without "acked_message_id"');
    }
    return message;
  }

  final int version;
  final MessageType type;
  final String id;
  final String senderId;
  final int timestamp;
  final Map<String, dynamic> payload;

  /// For ACK messages: the id of the message being acknowledged.
  String? get ackedMessageId {
    final value = payload['acked_message_id'];
    return value is String ? value : null;
  }

  Map<String, dynamic> toJson() => {
        'v': version,
        'type': type.wireName,
        'id': id,
        'sender_id': senderId,
        'ts': timestamp,
        'payload': payload,
      };
}
