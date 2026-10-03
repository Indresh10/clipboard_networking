import '../models/connection_state.dart';
import '../models/device.dart';
import '../protocol/network_message.dart';

/// Abstract contract for LAN client connections.
abstract class LanConnection {
  /// Stream of incoming protocol messages from the remote peer.
  Stream<NetworkMessage> get messages;

  /// Stream of connection state transitions.
  Stream<ConnectionState> get state;

  /// Current state of the connection.
  ConnectionState get currentState;

  /// Remote device this connection is bound to.
  Device? get targetDevice;

  /// Connects to the given [device].
  Future<void> connect(Device device);

  /// Sends a protocol message to the connected device.
  Future<void> send(NetworkMessage message);

  /// Disconnects gracefully.
  Future<void> disconnect({String reason = 'Normal closure'});

  /// Disposes resources and closes streams.
  void dispose();
}
