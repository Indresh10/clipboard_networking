import 'dart:io';
import 'package:clipboard_networking/clipboard_networking.dart';
import 'package:test/test.dart';

void main() {
  group('WebSocket Transport Integration', () {
    late WebSocketLanServer server;
    late WebSocketLanClient client;
    late int serverPort;

    setUp(() async {
      server = WebSocketLanServer(serverDeviceId: 'test-tv-server');
      serverPort =
          await server.start(port: 0, address: InternetAddress.loopbackIPv4);

      client = WebSocketLanClient(
        localDeviceId: 'test-client-phone',
        config: const WebSocketClientConfig(
          enableAutoReconnect: false,
          heartbeatInterval: Duration(seconds: 1),
          heartbeatTimeout: Duration(seconds: 1),
        ),
      );
    });

    tearDown(() async {
      client.dispose();
      await server.stop();
    });

    test('client connects to server and reaches connected state', () async {
      final states = <ConnectionState>[];
      final stateSub = client.state.listen(states.add);

      final targetDevice = Device(
        id: 'test-tv-server',
        name: 'Test TV',
        type: DeviceType.androidTv,
        address: '127.0.0.1',
        port: serverPort,
      );

      await client.connect(targetDevice);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(client.currentState, ConnectionState.connected);
      expect(server.connectedClients.length, 1);

      await stateSub.cancel();
    });

    test('clipboard message transfer and automatic ACK', () async {
      final targetDevice = Device(
        id: 'test-tv-server',
        name: 'Test TV',
        type: DeviceType.androidTv,
        address: '127.0.0.1',
        port: serverPort,
      );

      await client.connect(targetDevice);
      await Future.delayed(const Duration(milliseconds: 100));

      // Listen on server for incoming message
      final serverReceived = <NetworkMessage>[];
      final serverSub = server.incomingMessages.listen((msg) {
        serverReceived.add(msg.message);
      });

      final clipboardItem = ClipboardItem(
        id: 'clip-test-1',
        text: 'Antigravity rocks!',
        createdAt: DateTime.utc(2026, 10, 2, 12, 0, 0),
        sourceDeviceId: 'test-client-phone',
      );

      final msg = NetworkMessage.clipboard(
        senderId: 'test-client-phone',
        item: clipboardItem,
      );

      // Send with ACK expectation
      final ack =
          await client.sendWithAck(msg, timeout: const Duration(seconds: 2));

      expect(ack.success, isTrue);
      expect(ack.ackedMessageId, 'clip-test-1');

      // Verify server received the clipboard message
      expect(serverReceived.length, 1);
      final receivedClipboard = serverReceived.first.asClipboardPayload();
      expect(receivedClipboard.text, 'Antigravity rocks!');

      await serverSub.cancel();
    });

    test('ping and pong exchanges respond automatically', () async {
      final targetDevice = Device(
        id: 'test-tv-server',
        name: 'Test TV',
        type: DeviceType.androidTv,
        address: '127.0.0.1',
        port: serverPort,
      );

      await client.connect(targetDevice);
      await Future.delayed(const Duration(milliseconds: 100));

      // Send manual ping from client
      final ping =
          NetworkMessage.ping(senderId: 'test-client-phone', sequence: 99);
      await client.send(ping);

      // Client's internal handler handles incoming pong without error
      await Future.delayed(const Duration(milliseconds: 100));
      expect(client.currentState, ConnectionState.connected);
    });

    test('graceful disconnect cleans up client and server states', () async {
      final targetDevice = Device(
        id: 'test-tv-server',
        name: 'Test TV',
        type: DeviceType.androidTv,
        address: '127.0.0.1',
        port: serverPort,
      );

      await client.connect(targetDevice);
      await Future.delayed(const Duration(milliseconds: 100));
      expect(server.connectedClients.length, 1);

      await client.disconnect(reason: 'User disconnected');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(client.currentState, ConnectionState.disconnected);
      expect(server.connectedClients, isEmpty);
    });
  });
}
