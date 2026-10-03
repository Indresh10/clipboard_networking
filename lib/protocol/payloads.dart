import 'package:meta/meta.dart';
import '../models/clipboard_item.dart';
import '../models/device_type.dart';

/// Base class for protocol message payloads.
abstract class MessagePayload {
  const MessagePayload();
  Map<String, dynamic> toJson();
}

/// Payload for HELLO handshake message.
@immutable
class HelloPayload extends MessagePayload {
  final String clientName;
  final DeviceType deviceType;
  final int protocolVersion;
  final String? authToken;

  const HelloPayload({
    required this.clientName,
    required this.deviceType,
    this.protocolVersion = 1,
    this.authToken,
  });

  @override
  Map<String, dynamic> toJson() => {
        'clientName': clientName,
        'deviceType': deviceType.toJson(),
        'protocolVersion': protocolVersion,
        if (authToken != null) 'authToken': authToken,
      };

  factory HelloPayload.fromJson(Map<String, dynamic> json) => HelloPayload(
        clientName: json['clientName'] as String,
        deviceType: DeviceType.fromJson(json['deviceType'] as String? ?? 'android'),
        protocolVersion: (json['protocolVersion'] as num?)?.toInt() ?? 1,
        authToken: json['authToken'] as String?,
      );
}

/// Payload for DEVICE_INFO message.
@immutable
class DeviceInfoPayload extends MessagePayload {
  final String deviceId;
  final String deviceName;
  final DeviceType deviceType;
  final List<String> capabilities;
  final Map<String, dynamic> platformDetails;

  const DeviceInfoPayload({
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    this.capabilities = const ['clipboard', 'pairing'],
    this.platformDetails = const {},
  });

  @override
  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'deviceType': deviceType.toJson(),
        'capabilities': capabilities,
        'platformDetails': platformDetails,
      };

  factory DeviceInfoPayload.fromJson(Map<String, dynamic> json) => DeviceInfoPayload(
        deviceId: json['deviceId'] as String,
        deviceName: json['deviceName'] as String,
        deviceType: DeviceType.fromJson(json['deviceType'] as String? ?? 'android'),
        capabilities: (json['capabilities'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
            const ['clipboard'],
        platformDetails: (json['platformDetails'] as Map<String, dynamic>?) ?? const {},
      );
}

/// Payload for PAIR_REQUEST message.
@immutable
class PairRequestPayload extends MessagePayload {
  final String clientDeviceId;
  final String clientDeviceName;
  final DeviceType clientDeviceType;
  final String? pinCode;
  final String? sessionToken;

  const PairRequestPayload({
    required this.clientDeviceId,
    required this.clientDeviceName,
    required this.clientDeviceType,
    this.pinCode,
    this.sessionToken,
  });

  @override
  Map<String, dynamic> toJson() => {
        'clientDeviceId': clientDeviceId,
        'clientDeviceName': clientDeviceName,
        'clientDeviceType': clientDeviceType.toJson(),
        if (pinCode != null) 'pinCode': pinCode,
        if (sessionToken != null) 'sessionToken': sessionToken,
      };

  factory PairRequestPayload.fromJson(Map<String, dynamic> json) => PairRequestPayload(
        clientDeviceId: json['clientDeviceId'] as String,
        clientDeviceName: json['clientDeviceName'] as String,
        clientDeviceType: DeviceType.fromJson(json['clientDeviceType'] as String? ?? 'android'),
        pinCode: json['pinCode'] as String?,
        sessionToken: json['sessionToken'] as String?,
      );
}

/// Payload for PAIR_RESPONSE message.
@immutable
class PairResponsePayload extends MessagePayload {
  final bool success;
  final String status;
  final String? pairedAuthToken;
  final String? tvDeviceId;
  final String? tvDeviceName;
  final String? errorMessage;

  const PairResponsePayload({
    required this.success,
    required this.status,
    this.pairedAuthToken,
    this.tvDeviceId,
    this.tvDeviceName,
    this.errorMessage,
  });

  @override
  Map<String, dynamic> toJson() => {
        'success': success,
        'status': status,
        if (pairedAuthToken != null) 'pairedAuthToken': pairedAuthToken,
        if (tvDeviceId != null) 'tvDeviceId': tvDeviceId,
        if (tvDeviceName != null) 'tvDeviceName': tvDeviceName,
        if (errorMessage != null) 'errorMessage': errorMessage,
      };

  factory PairResponsePayload.fromJson(Map<String, dynamic> json) => PairResponsePayload(
        success: json['success'] as bool,
        status: json['status'] as String? ?? (json['success'] == true ? 'paired' : 'failed'),
        pairedAuthToken: json['pairedAuthToken'] as String?,
        tvDeviceId: json['tvDeviceId'] as String?,
        tvDeviceName: json['tvDeviceName'] as String?,
        errorMessage: json['errorMessage'] as String?,
      );
}

/// Payload for PAIR_COMPLETE message.
@immutable
class PairCompletePayload extends MessagePayload {
  final bool confirmed;
  final String clientDeviceId;

  const PairCompletePayload({
    required this.confirmed,
    required this.clientDeviceId,
  });

  @override
  Map<String, dynamic> toJson() => {
        'confirmed': confirmed,
        'clientDeviceId': clientDeviceId,
      };

  factory PairCompletePayload.fromJson(Map<String, dynamic> json) => PairCompletePayload(
        confirmed: json['confirmed'] as bool? ?? true,
        clientDeviceId: json['clientDeviceId'] as String,
      );
}

/// Payload for CLIPBOARD message.
@immutable
class ClipboardPayload extends MessagePayload {
  final String itemId;
  final String text;
  final bool sensitive;
  final String sourceDeviceId;
  final int timestamp;

  const ClipboardPayload({
    required this.itemId,
    required this.text,
    this.sensitive = false,
    required this.sourceDeviceId,
    required this.timestamp,
  });

  @override
  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'text': text,
        'sensitive': sensitive,
        'sourceDeviceId': sourceDeviceId,
        'timestamp': timestamp,
      };

  factory ClipboardPayload.fromJson(Map<String, dynamic> json) => ClipboardPayload(
        itemId: json['itemId'] as String,
        text: json['text'] as String,
        sensitive: json['sensitive'] as bool? ?? false,
        sourceDeviceId: json['sourceDeviceId'] as String,
        timestamp: (json['timestamp'] as num).toInt(),
      );

  ClipboardItem toClipboardItem() => ClipboardItem(
        id: itemId,
        text: text,
        createdAt: DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
        sourceDeviceId: sourceDeviceId,
        sensitive: sensitive,
      );

  factory ClipboardPayload.fromClipboardItem(ClipboardItem item) => ClipboardPayload(
        itemId: item.id,
        text: item.text,
        sensitive: item.sensitive,
        sourceDeviceId: item.sourceDeviceId,
        timestamp: item.createdAt.millisecondsSinceEpoch,
      );
}

/// Payload for ACK message.
@immutable
class AckPayload extends MessagePayload {
  final String ackedMessageId;
  final bool success;
  final String? reason;

  const AckPayload({
    required this.ackedMessageId,
    this.success = true,
    this.reason,
  });

  @override
  Map<String, dynamic> toJson() => {
        'ackedMessageId': ackedMessageId,
        'success': success,
        if (reason != null) 'reason': reason,
      };

  factory AckPayload.fromJson(Map<String, dynamic> json) => AckPayload(
        ackedMessageId: json['ackedMessageId'] as String,
        success: json['success'] as bool? ?? true,
        reason: json['reason'] as String?,
      );
}

/// Payload for PING message.
@immutable
class PingPayload extends MessagePayload {
  final int sequence;

  const PingPayload({required this.sequence});

  @override
  Map<String, dynamic> toJson() => {'sequence': sequence};

  factory PingPayload.fromJson(Map<String, dynamic> json) =>
      PingPayload(sequence: (json['sequence'] as num?)?.toInt() ?? 0);
}

/// Payload for PONG message.
@immutable
class PongPayload extends MessagePayload {
  final int sequence;

  const PongPayload({required this.sequence});

  @override
  Map<String, dynamic> toJson() => {'sequence': sequence};

  factory PongPayload.fromJson(Map<String, dynamic> json) =>
      PongPayload(sequence: (json['sequence'] as num?)?.toInt() ?? 0);
}

/// Payload for DISCONNECT message.
@immutable
class DisconnectPayload extends MessagePayload {
  final String reason;
  final int code;

  const DisconnectPayload({
    this.reason = 'Normal closure',
    this.code = 1000,
  });

  @override
  Map<String, dynamic> toJson() => {
        'reason': reason,
        'code': code,
      };

  factory DisconnectPayload.fromJson(Map<String, dynamic> json) => DisconnectPayload(
        reason: json['reason'] as String? ?? 'Normal closure',
        code: (json['code'] as num?)?.toInt() ?? 1000,
      );
}
