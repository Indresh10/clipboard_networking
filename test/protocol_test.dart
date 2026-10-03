import 'package:clipboard_networking/clipboard_networking.dart';
import 'package:test/test.dart';

void main() {
  group('MessageType', () {
    test('all 10 message types serialize and deserialize', () {
      final types = [
        MessageType.hello,
        MessageType.deviceInfo,
        MessageType.pairRequest,
        MessageType.pairResponse,
        MessageType.pairComplete,
        MessageType.clipboard,
        MessageType.ack,
        MessageType.ping,
        MessageType.pong,
        MessageType.disconnect,
      ];

      for (final type in types) {
        final jsonStr = type.toJson();
        final parsed = MessageType.fromJson(jsonStr);
        expect(parsed, equals(type));
      }
    });

    test('case-insensitivity and loose parsing', () {
      expect(MessageType.fromJson('hello'), MessageType.hello);
      expect(MessageType.fromJson('pair_request'), MessageType.pairRequest);
      expect(MessageType.fromJson('PAIR_REQUEST'), MessageType.pairRequest);
      expect(MessageType.fromJson('device_info'), MessageType.deviceInfo);
      expect(() => MessageType.fromJson('INVALID_TYPE'), throwsArgumentError);
    });
  });

  group('NetworkMessage Envelope & Payloads', () {
    test('HELLO message serialization', () {
      final msg = NetworkMessage.hello(
        senderId: 'client-1',
        clientName: 'Indresh iPhone',
        deviceType: DeviceType.ios,
        authToken: 'existing-auth-token',
      );

      expect(msg.type, MessageType.hello);
      expect(msg.version, 1);
      expect(msg.senderId, 'client-1');

      final encoded = msg.encode();
      final decoded = NetworkMessage.decode(encoded);

      expect(decoded.type, MessageType.hello);
      expect(decoded.senderId, 'client-1');

      final payload = decoded.asHelloPayload();
      expect(payload.clientName, 'Indresh iPhone');
      expect(payload.deviceType, DeviceType.ios);
      expect(payload.authToken, 'existing-auth-token');
      expect(payload.protocolVersion, 1);
    });

    test('DEVICE_INFO message serialization', () {
      final msg = NetworkMessage.deviceInfo(
        senderId: 'tv-1',
        deviceName: 'Android TV Living Room',
        deviceType: DeviceType.androidTv,
        capabilities: ['clipboard', 'ime_commit', 'pairing'],
        platformDetails: {'android_version': 13},
      );

      final decoded = NetworkMessage.decode(msg.encode());
      final payload = decoded.asDeviceInfoPayload();

      expect(payload.deviceId, 'tv-1');
      expect(payload.deviceName, 'Android TV Living Room');
      expect(payload.deviceType, DeviceType.androidTv);
      expect(payload.capabilities, contains('ime_commit'));
      expect(payload.platformDetails['android_version'], 13);
    });

    test('PAIR_REQUEST message serialization (QR & PIN variants)', () {
      // PIN variant
      final pinMsg = NetworkMessage.pairRequest(
        senderId: 'win-1',
        clientDeviceName: 'Indresh PC',
        clientDeviceType: DeviceType.windows,
        pinCode: '123456',
      );

      final decodedPin = NetworkMessage.decode(pinMsg.encode()).asPairRequestPayload();
      expect(decodedPin.clientDeviceId, 'win-1');
      expect(decodedPin.pinCode, '123456');
      expect(decodedPin.sessionToken, isNull);

      // QR variant
      final qrMsg = NetworkMessage.pairRequest(
        senderId: 'phone-1',
        clientDeviceName: 'Pixel 8',
        clientDeviceType: DeviceType.android,
        sessionToken: 'qr-token-321',
      );

      final decodedQr = NetworkMessage.decode(qrMsg.encode()).asPairRequestPayload();
      expect(decodedQr.clientDeviceId, 'phone-1');
      expect(decodedQr.sessionToken, 'qr-token-321');
      expect(decodedQr.pinCode, isNull);
    });

    test('PAIR_RESPONSE message serialization', () {
      final msg = NetworkMessage.pairResponse(
        senderId: 'tv-1',
        success: true,
        status: 'paired',
        pairedAuthToken: 'secure-device-token-xyz',
        tvDeviceId: 'tv-1',
        tvDeviceName: 'Sony TV',
      );

      final decoded = NetworkMessage.decode(msg.encode()).asPairResponsePayload();
      expect(decoded.success, isTrue);
      expect(decoded.status, 'paired');
      expect(decoded.pairedAuthToken, 'secure-device-token-xyz');
      expect(decoded.tvDeviceId, 'tv-1');
      expect(decoded.tvDeviceName, 'Sony TV');
    });

    test('PAIR_COMPLETE message serialization', () {
      final msg = NetworkMessage.pairComplete(
        senderId: 'client-1',
        clientDeviceId: 'client-1',
        confirmed: true,
      );

      final decoded = NetworkMessage.decode(msg.encode()).asPairCompletePayload();
      expect(decoded.clientDeviceId, 'client-1');
      expect(decoded.confirmed, isTrue);
    });

    test('CLIPBOARD message serialization', () {
      final item = ClipboardItem(
        id: 'msg-item-1',
        text: 'Copied link https://antigravity.dev',
        createdAt: DateTime.utc(2026, 10, 2, 12, 0, 0),
        sourceDeviceId: 'laptop-1',
        sensitive: false,
      );

      final msg = NetworkMessage.clipboard(senderId: 'laptop-1', item: item);
      final decoded = NetworkMessage.decode(msg.encode());

      expect(decoded.type, MessageType.clipboard);
      final payload = decoded.asClipboardPayload();
      expect(payload.text, 'Copied link https://antigravity.dev');
      expect(payload.itemId, 'msg-item-1');
      expect(payload.sensitive, isFalse);

      final extractedItem = payload.toClipboardItem();
      expect(extractedItem, equals(item));
    });

    test('ACK message serialization', () {
      final msg = NetworkMessage.ack(
        senderId: 'tv-1',
        ackedMessageId: 'msg-item-1',
        success: true,
      );

      final decoded = NetworkMessage.decode(msg.encode()).asAckPayload();
      expect(decoded.ackedMessageId, 'msg-item-1');
      expect(decoded.success, isTrue);
    });

    test('PING and PONG message serialization', () {
      final pingMsg = NetworkMessage.ping(senderId: 'client-1', sequence: 42);
      final pingDecoded = NetworkMessage.decode(pingMsg.encode()).asPingPayload();
      expect(pingDecoded.sequence, 42);

      final pongMsg = NetworkMessage.pong(senderId: 'tv-1', sequence: 42);
      final pongDecoded = NetworkMessage.decode(pongMsg.encode()).asPongPayload();
      expect(pongDecoded.sequence, 42);
    });

    test('DISCONNECT message serialization', () {
      final msg = NetworkMessage.disconnect(
        senderId: 'client-1',
        reason: 'User logged off',
        code: 1001,
      );

      final decoded = NetworkMessage.decode(msg.encode()).asDisconnectPayload();
      expect(decoded.reason, 'User logged off');
      expect(decoded.code, 1001);
    });

    test('throws FormatException on malformed message envelope', () {
      expect(() => NetworkMessage.decode('{}'), throwsFormatException);
      expect(() => NetworkMessage.decode('{"version": 1}'), throwsFormatException);
      expect(() => NetworkMessage.decode('not-json'), throwsFormatException);
    });
  });
}
