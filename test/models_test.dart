import 'package:clipboard_networking/clipboard_networking.dart';
import 'package:test/test.dart';

void main() {
  group('DeviceType', () {
    test('serializes and deserializes correctly', () {
      expect(DeviceType.windows.toJson(), 'windows');
      expect(DeviceType.android.toJson(), 'android');
      expect(DeviceType.ios.toJson(), 'ios');
      expect(DeviceType.androidTv.toJson(), 'android_tv');
      expect(DeviceType.macos.toJson(), 'macos');

      expect(DeviceType.fromJson('windows'), DeviceType.windows);
      expect(DeviceType.fromJson('android'), DeviceType.android);
      expect(DeviceType.fromJson('ios'), DeviceType.ios);
      expect(DeviceType.fromJson('android_tv'), DeviceType.androidTv);
      expect(DeviceType.fromJson('tv'), DeviceType.androidTv);
      expect(DeviceType.fromJson('macos'), DeviceType.macos);
      expect(DeviceType.fromJson('unknown_device'), DeviceType.android);
    });

    test('helper getters work', () {
      expect(DeviceType.androidTv.isTv, isTrue);
      expect(DeviceType.windows.isTv, isFalse);
      expect(DeviceType.android.isMobile, isTrue);
      expect(DeviceType.ios.isMobile, isTrue);
      expect(DeviceType.windows.isDesktop, isTrue);
      expect(DeviceType.macos.isDesktop, isTrue);
    });
  });

  group('ConnectionState', () {
    test('toJson and fromJson match', () {
      for (final state in ConnectionState.values) {
        expect(ConnectionState.fromJson(state.toJson()), state);
      }
      expect(ConnectionState.fromJson('invalid_state'), ConnectionState.disconnected);
    });

    test('helper getters work', () {
      expect(ConnectionState.connected.isConnected, isTrue);
      expect(ConnectionState.connecting.isConnecting, isTrue);
      expect(ConnectionState.disconnected.isDisconnected, isTrue);
    });
  });

  group('DeviceStatus', () {
    test('toJson and fromJson match', () {
      for (final status in DeviceStatus.values) {
        expect(DeviceStatus.fromJson(status.toJson()), status);
      }
      expect(DeviceStatus.fromJson('invalid_status'), DeviceStatus.unpaired);
      expect(DeviceStatus.paired.isPaired, isTrue);
      expect(DeviceStatus.online.isOnline, isTrue);
    });
  });

  group('ClipboardItem', () {
    test('serializes to and from JSON', () {
      final now = DateTime.utc(2026, 10, 2, 12, 0, 0);
      final item = ClipboardItem(
        id: 'clip-123',
        text: 'Secret WiFi Password',
        createdAt: now,
        sourceDeviceId: 'phone-001',
        sensitive: true,
      );

      final json = item.toJson();
      expect(json['id'], 'clip-123');
      expect(json['text'], 'Secret WiFi Password');
      expect(json['sensitive'], isTrue);
      expect(json['sourceDeviceId'], 'phone-001');

      final reconstructed = ClipboardItem.fromJson(json);
      expect(reconstructed, equals(item));
      expect(reconstructed.hashCode, equals(item.hashCode));
    });

    test('copyWith works', () {
      final item = ClipboardItem(
        id: 'clip-1',
        text: 'hello',
        createdAt: DateTime.now().toUtc(),
        sourceDeviceId: 'dev-1',
      );

      final updated = item.copyWith(text: 'world', sensitive: true);
      expect(updated.id, 'clip-1');
      expect(updated.text, 'world');
      expect(updated.sensitive, isTrue);
    });
  });

  group('Device', () {
    test('serializes to and from JSON', () {
      final now = DateTime.utc(2026, 10, 2, 12, 0, 0);
      final device = Device(
        id: 'tv-001',
        name: 'Living Room TV',
        type: DeviceType.androidTv,
        address: '192.168.1.100',
        port: 43824,
        status: DeviceStatus.paired,
        lastSeen: now,
        pairedAt: now,
        authToken: 'token-abc-123',
        metadata: {'version': '1.0'},
      );

      final json = device.toJson();
      expect(json['id'], 'tv-001');
      expect(json['type'], 'android_tv');
      expect(json['port'], 43824);
      expect(json['authToken'], 'token-abc-123');

      final reconstructed = Device.fromJson(json);
      expect(reconstructed, equals(device));
      expect(reconstructed.hashCode, equals(device.hashCode));
    });

    test('copyWith updates properties', () {
      final device = Device(
        id: 'dev-1',
        name: 'Old Name',
        type: DeviceType.windows,
        address: '127.0.0.1',
        port: 8080,
      );

      final updated = device.copyWith(
        name: 'New Name',
        status: DeviceStatus.paired,
        authToken: 'auth-token',
      );

      expect(updated.name, 'New Name');
      expect(updated.status, DeviceStatus.paired);
      expect(updated.authToken, 'auth-token');
      expect(updated.id, 'dev-1');
    });
  });

  group('PairingPayload', () {
    test('JSON serialization, QR string conversion and parsing', () {
      final expires = DateTime.utc(2026, 10, 2, 12, 5, 0);
      final payload = PairingPayload(
        sessionId: 'sess-999',
        deviceId: 'tv-living-room',
        deviceName: 'Sony Bravia TV',
        address: '192.168.1.50',
        port: 43824,
        pinCode: '654321',
        sessionToken: 'secure-token-abcdef',
        expiresAt: expires,
      );

      final qrString = payload.toQrString();
      expect(qrString, contains('sess-999'));
      expect(qrString, contains('654321'));

      final parsed = PairingPayload.tryFromQrString(qrString);
      expect(parsed, isNotNull);
      expect(parsed, equals(payload));
      expect(parsed!.pinCode, '654321');
      expect(parsed.sessionToken, 'secure-token-abcdef');
    });

    test('tryFromQrString returns null on malformed QR string', () {
      expect(PairingPayload.tryFromQrString(''), isNull);
      expect(PairingPayload.tryFromQrString('invalid-not-json'), isNull);
      expect(PairingPayload.tryFromQrString('{"partial": 123}'), isNull);
    });

    test('isExpired check works', () {
      final expiredPayload = PairingPayload(
        sessionId: 'sess-1',
        deviceId: 'tv',
        deviceName: 'TV',
        address: '1.2.3.4',
        port: 80,
        pinCode: '111111',
        sessionToken: 'token',
        expiresAt: DateTime.now().toUtc().subtract(const Duration(seconds: 10)),
      );
      expect(expiredPayload.isExpired, isTrue);

      final validPayload = PairingPayload(
        sessionId: 'sess-2',
        deviceId: 'tv',
        deviceName: 'TV',
        address: '1.2.3.4',
        port: 80,
        pinCode: '111111',
        sessionToken: 'token',
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      );
      expect(validPayload.isExpired, isFalse);
    });
  });
}
