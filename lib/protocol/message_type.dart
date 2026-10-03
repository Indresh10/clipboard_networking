/// Standard message types supported by the Clipboard Sharer protocol.
enum MessageType {
  hello('HELLO'),
  deviceInfo('DEVICE_INFO'),
  pairRequest('PAIR_REQUEST'),
  pairResponse('PAIR_RESPONSE'),
  pairComplete('PAIR_COMPLETE'),
  clipboard('CLIPBOARD'),
  ack('ACK'),
  ping('PING'),
  pong('PONG'),
  disconnect('DISCONNECT');

  final String value;
  const MessageType(this.value);

  String toJson() => value;

  static MessageType fromJson(String value) {
    final normalized = value.trim().toUpperCase();
    return MessageType.values.firstWhere(
      (type) => type.value == normalized,
      orElse: () {
        // Fallback for case-insensitive matching
        for (final item in MessageType.values) {
          if (item.name.toUpperCase() == normalized ||
              item.value.replaceAll('_', '') == normalized.replaceAll('_', '')) {
            return item;
          }
        }
        throw ArgumentError('Unknown MessageType: $value');
      },
    );
  }
}
