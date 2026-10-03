/// Represents the lifecycle state of a connection to a remote TV / device.
enum ConnectionState {
  disconnected,
  discovering,
  connecting,
  connected,
  error;

  String toJson() => name;

  static ConnectionState fromJson(String value) {
    return ConnectionState.values.firstWhere(
      (e) => e.name.toLowerCase() == value.toLowerCase(),
      orElse: () => ConnectionState.disconnected,
    );
  }

  bool get isConnected => this == ConnectionState.connected;
  bool get isConnecting => this == ConnectionState.connecting;
  bool get isDisconnected => this == ConnectionState.disconnected;
}
