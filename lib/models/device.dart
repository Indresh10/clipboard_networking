import 'package:meta/meta.dart';
import 'device_status.dart';
import 'device_type.dart';

/// Represents a remote or local device participating in the Clipboard Sharer LAN.
@immutable
class Device {
  final String id;
  final String name;
  final DeviceType type;
  final String address;
  final int port;
  final DeviceStatus status;
  final DateTime? lastSeen;
  final DateTime? pairedAt;
  final String? authToken;
  final Map<String, dynamic> metadata;

  const Device({
    required this.id,
    required this.name,
    required this.type,
    required this.address,
    required this.port,
    this.status = DeviceStatus.unpaired,
    this.lastSeen,
    this.pairedAt,
    this.authToken,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.toJson(),
      'address': address,
      'port': port,
      'status': status.toJson(),
      'lastSeen': lastSeen?.toUtc().toIso8601String(),
      'pairedAt': pairedAt?.toUtc().toIso8601String(),
      if (authToken != null) 'authToken': authToken,
      'metadata': metadata,
    };
  }

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] as String,
      name: json['name'] as String,
      type: DeviceType.fromJson(json['type'] as String? ?? 'android'),
      address: json['address'] as String,
      port: (json['port'] as num?)?.toInt() ?? 43824,
      status: DeviceStatus.fromJson(json['status'] as String? ?? 'unpaired'),
      lastSeen: json['lastSeen'] != null ? DateTime.parse(json['lastSeen'] as String) : null,
      pairedAt: json['pairedAt'] != null ? DateTime.parse(json['pairedAt'] as String) : null,
      authToken: json['authToken'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
    );
  }

  Device copyWith({
    String? id,
    String? name,
    DeviceType? type,
    String? address,
    int? port,
    DeviceStatus? status,
    DateTime? lastSeen,
    DateTime? pairedAt,
    String? authToken,
    Map<String, dynamic>? metadata,
  }) {
    return Device(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      address: address ?? this.address,
      port: port ?? this.port,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      pairedAt: pairedAt ?? this.pairedAt,
      authToken: authToken ?? this.authToken,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Device &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          type == other.type &&
          address == other.address &&
          port == other.port &&
          status == other.status &&
          authToken == other.authToken;

  @override
  int get hashCode => Object.hash(id, name, type, address, port, status, authToken);

  @override
  String toString() {
    return 'Device(id: $id, name: $name, type: ${type.name}, address: $address:$port, status: ${status.name})';
  }
}
