import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/connection_state.dart';
import '../models/device.dart';
import '../protocol/message_type.dart';
import '../protocol/network_message.dart';
import '../protocol/payloads.dart';
import 'lan_connection.dart';

/// Configuration options for [WebSocketLanClient].
class WebSocketClientConfig {
  final Duration connectTimeout;
  final Duration heartbeatInterval;
  final Duration heartbeatTimeout;
  final bool enableAutoReconnect;
  final Duration initialReconnectDelay;
  final Duration maxReconnectDelay;
  final double backoffMultiplier;

  const WebSocketClientConfig({
    this.connectTimeout = const Duration(seconds: 5),
    this.heartbeatInterval = const Duration(seconds: 15),
    this.heartbeatTimeout = const Duration(seconds: 6),
    this.enableAutoReconnect = true,
    this.initialReconnectDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(seconds: 16),
    this.backoffMultiplier = 2.0,
  });
}

/// Client implementation of [LanConnection] using WebSockets.
class WebSocketLanClient implements LanConnection {
  final String localDeviceId;
  final WebSocketClientConfig config;

  Device? _targetDevice;
  WebSocketChannel? _channel;
  StreamSubscription? _channelSubscription;

  ConnectionState _currentState = ConnectionState.disconnected;
  final _stateController = StreamController<ConnectionState>.broadcast();
  final _messageController = StreamController<NetworkMessage>.broadcast();

  // Pending ACKs: messageId -> Completer<AckPayload>
  final Map<String, Completer<AckPayload>> _pendingAcks = {};

  // Heartbeat timers
  Timer? _heartbeatTimer;
  Timer? _heartbeatTimeoutTimer;
  int _pingSequence = 0;

  // Reconnection tracking
  bool _manualDisconnect = false;
  Duration _currentReconnectDelay;
  Timer? _reconnectTimer;

  WebSocketLanClient({
    required this.localDeviceId,
    this.config = const WebSocketClientConfig(),
  }) : _currentReconnectDelay = config.initialReconnectDelay;

  @override
  Stream<NetworkMessage> get messages => _messageController.stream;

  @override
  Stream<ConnectionState> get state => _stateController.stream;

  @override
  ConnectionState get currentState => _currentState;

  @override
  Device? get targetDevice => _targetDevice;

  void _setState(ConnectionState newState) {
    if (_currentState != newState) {
      _currentState = newState;
      if (!_stateController.isClosed) {
        _stateController.add(newState);
      }
    }
  }

  @override
  Future<void> connect(Device device) async {
    _manualDisconnect = false;
    _targetDevice = device;
    _currentReconnectDelay = config.initialReconnectDelay;
    await _establishConnection();
  }

  Future<void> _establishConnection() async {
    if (_targetDevice == null || _manualDisconnect) return;

    _setState(ConnectionState.connecting);
    _cleanupChannel();

    final wsUri = Uri.parse('ws://${_targetDevice!.address}:${_targetDevice!.port}/ws');

    try {
      final ws = await WebSocket.connect(
        wsUri.toString(),
      ).timeout(config.connectTimeout);

      _channel = IOWebSocketChannel(ws);
      _setState(ConnectionState.connected);
      _currentReconnectDelay = config.initialReconnectDelay;

      _channelSubscription = _channel!.stream.listen(
        _onDataReceived,
        onError: _onStreamError,
        onDone: _onStreamDone,
        cancelOnError: true,
      );

      _startHeartbeat();
    } catch (e) {
      _setState(ConnectionState.error);
      _scheduleReconnect();
    }
  }

  void _onDataReceived(dynamic rawData) {
    try {
      final rawString = rawData is List<int> ? utf8.decode(rawData) : rawData.toString();
      final message = NetworkMessage.decode(rawString);

      // Handle internal protocol messages
      if (message.type == MessageType.ping) {
        // Automatically respond with PONG
        final ping = message.asPingPayload();
        send(NetworkMessage.pong(senderId: localDeviceId, sequence: ping.sequence));
        return;
      }

      if (message.type == MessageType.pong) {
        // Heartbeat received
        _heartbeatTimeoutTimer?.cancel();
        _heartbeatTimeoutTimer = null;
        return;
      }

      if (message.type == MessageType.ack) {
        final ack = message.asAckPayload();
        final completer = _pendingAcks.remove(ack.ackedMessageId);
        if (completer != null && !completer.isCompleted) {
          completer.complete(ack);
        }
      }

      if (message.type == MessageType.disconnect) {
        _onStreamDone();
        return;
      }

      // Forward application messages to listeners
      if (!_messageController.isClosed) {
        _messageController.add(message);
      }
    } catch (_) {
      // Discard invalid / malformed messages
    }
  }

  void _onStreamError(dynamic error) {
    _cleanupChannel();
    _setState(ConnectionState.error);
    _scheduleReconnect();
  }

  void _onStreamDone() {
    _cleanupChannel();
    if (!_manualDisconnect) {
      _setState(ConnectionState.disconnected);
      _scheduleReconnect();
    } else {
      _setState(ConnectionState.disconnected);
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(config.heartbeatInterval, (_) {
      if (_currentState == ConnectionState.connected) {
        _pingSequence++;
        send(NetworkMessage.ping(senderId: localDeviceId, sequence: _pingSequence));

        _heartbeatTimeoutTimer?.cancel();
        _heartbeatTimeoutTimer = Timer(config.heartbeatTimeout, () {
          // Heartbeat timed out! Reconnect
          _cleanupChannel();
          _setState(ConnectionState.error);
          _scheduleReconnect();
        });
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatTimeoutTimer?.cancel();
    _heartbeatTimeoutTimer = null;
  }

  void _scheduleReconnect() {
    if (!config.enableAutoReconnect || _manualDisconnect || _targetDevice == null) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_currentReconnectDelay, () {
      if (!_manualDisconnect && _targetDevice != null) {
        // Calculate next backoff
        final nextDelayMs = (_currentReconnectDelay.inMilliseconds * config.backoffMultiplier).toInt();
        _currentReconnectDelay = Duration(
          milliseconds: nextDelayMs.clamp(
            config.initialReconnectDelay.inMilliseconds,
            config.maxReconnectDelay.inMilliseconds,
          ),
        );
        _establishConnection();
      }
    });
  }

  @override
  Future<void> send(NetworkMessage message) async {
    if (_channel == null || _currentState != ConnectionState.connected) {
      throw StateError('Cannot send message: WebSocket is not connected (state: $_currentState)');
    }
    _channel!.sink.add(message.encode());
  }

  /// Sends a message and awaits an ACK from the receiver.
  Future<AckPayload> sendWithAck(
    NetworkMessage message, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final completer = Completer<AckPayload>();
    _pendingAcks[message.messageId] = completer;

    try {
      await send(message);
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          _pendingAcks.remove(message.messageId);
          throw TimeoutException('Timed out waiting for ACK for message: ${message.messageId}');
        },
      );
    } catch (_) {
      _pendingAcks.remove(message.messageId);
      rethrow;
    }
  }

  void _cleanupChannel() {
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    for (final completer in _pendingAcks.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Connection lost while awaiting ACK'));
      }
    }
    _pendingAcks.clear();

    _channelSubscription?.cancel();
    _channelSubscription = null;

    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  @override
  Future<void> disconnect({String reason = 'Normal closure'}) async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    if (_channel != null && _currentState == ConnectionState.connected) {
      try {
        await send(NetworkMessage.disconnect(senderId: localDeviceId, reason: reason));
      } catch (_) {}
    }

    _cleanupChannel();
    _setState(ConnectionState.disconnected);
  }

  @override
  void dispose() {
    disconnect();
    _stateController.close();
    _messageController.close();
  }
}
