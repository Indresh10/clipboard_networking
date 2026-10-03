import 'package:meta/meta.dart';

/// Represents a unit of clipboard content transferred over the local network.
@immutable
class ClipboardItem {
  final String id;
  final String text;
  final DateTime createdAt;
  final String sourceDeviceId;
  final bool sensitive;

  const ClipboardItem({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.sourceDeviceId,
    this.sensitive = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'sourceDeviceId': sourceDeviceId,
      'sensitive': sensitive,
    };
  }

  factory ClipboardItem.fromJson(Map<String, dynamic> json) {
    return ClipboardItem(
      id: json['id'] as String,
      text: json['text'] as String,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now().toUtc(),
      sourceDeviceId: json['sourceDeviceId'] as String,
      sensitive: json['sensitive'] as bool? ?? false,
    );
  }

  ClipboardItem copyWith({
    String? id,
    String? text,
    DateTime? createdAt,
    String? sourceDeviceId,
    bool? sensitive,
  }) {
    return ClipboardItem(
      id: id ?? this.id,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      sourceDeviceId: sourceDeviceId ?? this.sourceDeviceId,
      sensitive: sensitive ?? this.sensitive,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClipboardItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          text == other.text &&
          createdAt == other.createdAt &&
          sourceDeviceId == other.sourceDeviceId &&
          sensitive == other.sensitive;

  @override
  int get hashCode => Object.hash(id, text, createdAt, sourceDeviceId, sensitive);

  @override
  String toString() {
    return 'ClipboardItem(id: $id, sourceDeviceId: $sourceDeviceId, sensitive: $sensitive, textLength: ${text.length}, createdAt: $createdAt)';
  }
}
