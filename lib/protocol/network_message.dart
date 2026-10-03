import 'dart:convert';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../models/clipboard_item.dart';
import '../models/device_type.dart';
import 'message_type.dart';
import 'payloads.dart';

/// The standard network message envelope used for all LAN communication.
@immutable
class NetworkMessage {
  static const int currentProtocolVersion = 1;
  static const _uuid = Uuid();

  final int version;
  final MessageType type;
  final String messageId;
  final int timestamp;
  final String senderId;
  final Map<String, dynamic> payload;

  const NetworkMessage({
    this.version = currentProtocolVersion,
    required this.type,
    required this.messageId,
    required this.timestamp,
    required this.senderId,
    this.payload = const {},
  });

  /// Serializes the envelope into a standard Map.
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'type': type.toJson(),
      'messageId': messageId,
      'timestamp': timestamp,
      'senderId': senderId,
      'payload': payload,
    };
  }

  /// Deserializes a [NetworkMessage] from a JSON map.
  factory NetworkMessage.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('type') || !json.containsKey('messageId')) {
      throw const FormatException('Invalid NetworkMessage format: missing type or messageId');
    }

    return NetworkMessage(
      version: (json['version'] as num?)?.toInt() ?? currentProtocolVersion,
      type: MessageType.fromJson(json['type'] as String),
      messageId: json['messageId'] as String,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      senderId: (json['senderId'] as String?) ?? '',
      payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
    );
  }

  /// Encodes this message to a JSON string.
  String encode() => jsonEncode(toJson());

  /// Decodes a JSON string into a [NetworkMessage].
  static NetworkMessage decode(String jsonString) {
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Decoded JSON is not an object');
    }
    return NetworkMessage.fromJson(decoded);
  }

  // --- Factory constructors for each message type ---

  static NetworkMessage hello({
    required String senderId,
    required String clientName,
    required DeviceType deviceType,
    String? authToken,
  }) {
    final payload = HelloPayload(
      clientName: clientName,
      deviceType: deviceType,
      protocolVersion: currentProtocolVersion,
      authToken: authToken,
    );
    return NetworkMessage(
      type: MessageType.hello,
      messageId: _uuid.v4(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      senderId: senderId,
      payload: payload.toJson(),
    );
  }

  static NetworkMessage deviceInfo({
    required String senderId,
    required String deviceName,
    required DeviceType deviceType,
    List<String> capabilities = const ['clipboard', 'pairing'],
    Map<String, dynamic> platformDetails = const {},
  }) {
    final payload = DeviceInfoPayload(
      deviceId: senderId,
      deviceName: deviceName,
      deviceType: deviceType,
      capabilities: capabilities,
      platformDetails: platformDetails,
    );
    return NetworkMessage(
      type: MessageType.deviceInfo,
      messageId: _uuid.v4(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      senderId: senderId,
      payload: payload.toJson(),
    );
  }

  static NetworkMessage pairRequest({
    required String senderId,
    required String clientDeviceName,
    required DeviceType clientDeviceType,
    String? pinCode,
    String? sessionToken,
  }) {
    final payload = PairRequestPayload(
      clientDeviceId: senderId,
      clientDeviceName: clientDeviceName,
      clientDeviceType: clientDeviceType,
      pinCode: pinCode,
      sessionToken: sessionToken,
    );
    return NetworkMessage(
      type: MessageType.pairRequest,
      messageId: _uuid.v4(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      senderId: senderId,
      payload: payload.toJson(),
    );
  }

  static NetworkMessage pairResponse({
    required String senderId,
    required bool success,
    required String status,
    String? pairedAuthToken,
    String? tvDeviceId,
    String? tvDeviceName,
    String? errorMessage,
  }) {
    final payload = PairResponsePayload(
      success: success,
      status: status,
      pairedAuthToken: pairedAuthToken,
      tvDeviceId: tvDeviceId,
      tvDeviceName: tvDeviceName,
      errorMessage: errorMessage,
    );
    return NetworkMessage(
      type: MessageType.pairResponse,
      messageId: _uuid.v4(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      senderId: senderId,
      payload: payload.toJson(),
    );
  }

  static NetworkMessage pairComplete({
    required String senderId,
    required String clientDeviceId,
    bool confirmed = true,
  }) {
    final payload = PairCompletePayload(
      confirmed: confirmed,
      clientDeviceId: clientDeviceId,
    );
    return NetworkMessage(
      type: MessageType.pairComplete,
      messageId: _uuid.v4(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      senderId: senderId,
      payload: payload.toJson(),
    );
  }

  static NetworkMessage clipboard({
    required String senderId,
    required ClipboardItem item,
  }) {
    final payload = ClipboardPayload.fromClipboardItem(item);
    return NetworkMessage(
      type: MessageType.clipboard,
      messageId: item.id,
      timestamp: item.createdAt.millisecondsSinceEpoch,
      senderId: senderId,
      payload: payload.toJson(),
    );
  }

  static NetworkMessage ack({
    required String senderId,
    required String ackedMessageId,
    bool success = true,
    String? reason,
  }) {
    final payload = AckPayload(
      ackedMessageId: ackedMessageId,
      success: success,
      reason: reason,
    );
    return NetworkMessage(
      type: MessageType.ack,
      messageId: _uuid.v4(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      senderId: senderId,
      payload: payload.toJson(),
    );
  }

  static NetworkMessage ping({
    required String senderId,
    int sequence = 0,
  }) {
    final payload = PingPayload(sequence: sequence);
    return NetworkMessage(
      type: MessageType.ping,
      messageId: _uuid.v4(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      senderId: senderId,
      payload: payload.toJson(),
    );
  }

  static NetworkMessage pong({
    required String senderId,
    int sequence = 0,
  }) {
    final payload = PongPayload(sequence: sequence);
    return NetworkMessage(
      type: MessageType.pong,
      messageId: _uuid.v4(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      senderId: senderId,
      payload: payload.toJson(),
    );
  }

  static NetworkMessage disconnect({
    required String senderId,
    String reason = 'Normal closure',
    int code = 1000,
  }) {
    final payload = DisconnectPayload(reason: reason, code: code);
    return NetworkMessage(
      type: MessageType.disconnect,
      messageId: _uuid.v4(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      senderId: senderId,
      payload: payload.toJson(),
    );
  }

  // --- Strongly-typed payload extractors ---

  HelloPayload asHelloPayload() => HelloPayload.fromJson(payload);
  DeviceInfoPayload asDeviceInfoPayload() => DeviceInfoPayload.fromJson(payload);
  PairRequestPayload asPairRequestPayload() => PairRequestPayload.fromJson(payload);
  PairResponsePayload asPairResponsePayload() => PairResponsePayload.fromJson(payload);
  PairCompletePayload asPairCompletePayload() => PairCompletePayload.fromJson(payload);
  ClipboardPayload asClipboardPayload() => ClipboardPayload.fromJson(payload);
  AckPayload asAckPayload() => AckPayload.fromJson(payload);
  PingPayload asPingPayload() => PingPayload.fromJson(payload);
  PongPayload asPongPayload() => PongPayload.fromJson(payload);
  DisconnectPayload asDisconnectPayload() => DisconnectPayload.fromJson(payload);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkMessage &&
          runtimeType == other.runtimeType &&
          version == other.version &&
          type == other.type &&
          messageId == other.messageId &&
          timestamp == other.timestamp &&
          senderId == other.senderId;

  @override
  int get hashCode => Object.hash(version, type, messageId, timestamp, senderId);

  @override
  String toString() {
    return 'NetworkMessage(type: ${type.value}, id: $messageId, from: $senderId, v: $version)';
  }
}
