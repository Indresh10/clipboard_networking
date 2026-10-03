import 'dart:convert';
import 'package:meta/meta.dart';

/// Data payload exchanged for pairing.
/// Can be encoded into a QR code for mobile scanners,
/// or used to verify a 6-digit PIN on desktop.
@immutable
class PairingPayload {
  final String sessionId;
  final String deviceId;
  final String deviceName;
  final String address;
  final int port;
  final String pinCode;
  final String sessionToken;
  final DateTime expiresAt;

  const PairingPayload({
    required this.sessionId,
    required this.deviceId,
    required this.deviceName,
    required this.address,
    required this.port,
    required this.pinCode,
    required this.sessionToken,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'address': address,
      'port': port,
      'pinCode': pinCode,
      'sessionToken': sessionToken,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
    };
  }

  factory PairingPayload.fromJson(Map<String, dynamic> json) {
    return PairingPayload(
      sessionId: json['sessionId'] as String,
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      address: json['address'] as String,
      port: (json['port'] as num).toInt(),
      pinCode: json['pinCode'] as String,
      sessionToken: json['sessionToken'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
    );
  }

  /// Encodes this payload into a JSON string suitable for a QR code.
  String toQrString() => jsonEncode(toJson());

  /// Attempts to parse a QR string into a [PairingPayload].
  static PairingPayload? tryFromQrString(String qrString) {
    try {
      final decoded = jsonDecode(qrString);
      if (decoded is Map<String, dynamic>) {
        return PairingPayload.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PairingPayload &&
          runtimeType == other.runtimeType &&
          sessionId == other.sessionId &&
          deviceId == other.deviceId &&
          pinCode == other.pinCode &&
          sessionToken == other.sessionToken &&
          expiresAt == other.expiresAt;

  @override
  int get hashCode => Object.hash(sessionId, deviceId, pinCode, sessionToken, expiresAt);

  @override
  String toString() {
    return 'PairingPayload(sessionId: $sessionId, device: $deviceName ($deviceId), pin: $pinCode, expiresAt: $expiresAt)';
  }
}
