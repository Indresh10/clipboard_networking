import 'package:clipboard_networking/clipboard_networking.dart';
import 'package:test/test.dart';

void main() {
  group('PairingManager', () {
    late PairingManager manager;
    List<Device>? lastEmittedDevices;

    setUp(() {
      lastEmittedDevices = null;
      manager = PairingManager(
        serverDeviceId: 'tv-living-room',
        serverDeviceName: 'Sony Google TV',
        serverAddress: '192.168.1.100',
        serverPort: 43824,
        onPairedDevicesChanged: (devices) {
          lastEmittedDevices = devices;
        },
      );
    });

    test('createPairingSession generates valid 6-digit PIN and token', () {
      final payload = manager.createPairingSession(validity: const Duration(minutes: 5));

      expect(payload.deviceId, 'tv-living-room');
      expect(payload.deviceName, 'Sony Google TV');
      expect(payload.address, '192.168.1.100');
      expect(payload.port, 43824);
      expect(payload.pinCode.length, 6);
      expect(int.tryParse(payload.pinCode), isNotNull);
      expect(payload.sessionToken.length, 32);
      expect(payload.isExpired, isFalse);

      expect(manager.activeSession, isNotNull);
      expect(manager.activeSession!.pinCode, payload.pinCode);
    });

    test('processPairRequest succeeds with matching 6-digit PIN (Desktop flow)', () {
      final session = manager.createPairingSession();

      final request = PairRequestPayload(
        clientDeviceId: 'pc-001',
        clientDeviceName: 'Windows Desktop',
        clientDeviceType: DeviceType.windows,
        pinCode: session.pinCode,
      );

      final response = manager.processPairRequest(request, clientIp: '192.168.1.55');

      expect(response.success, isTrue);
      expect(response.status, 'paired');
      expect(response.pairedAuthToken, isNotNull);
      expect(response.tvDeviceId, 'tv-living-room');

      // Verify device was saved to paired devices
      expect(manager.pairedDevices.length, 1);
      final pairedDevice = manager.pairedDevices.first;
      expect(pairedDevice.id, 'pc-001');
      expect(pairedDevice.name, 'Windows Desktop');
      expect(pairedDevice.type, DeviceType.windows);
      expect(pairedDevice.authToken, response.pairedAuthToken);

      // Verify callback was notified
      expect(lastEmittedDevices, isNotNull);
      expect(lastEmittedDevices!.first.id, 'pc-001');

      // CRITICAL: Session must be invalidated immediately (single-use)
      expect(manager.activeSession, isNull);

      // A second attempt with the same PIN must fail
      final secondAttempt = manager.processPairRequest(request, clientIp: '192.168.1.55');
      expect(secondAttempt.success, isFalse);
      expect(secondAttempt.status, 'no_session');
    });

    test('processPairRequest succeeds with matching QR token (Mobile flow)', () {
      final session = manager.createPairingSession();

      final request = PairRequestPayload(
        clientDeviceId: 'phone-001',
        clientDeviceName: 'Pixel 8 Pro',
        clientDeviceType: DeviceType.android,
        sessionToken: session.sessionToken,
      );

      final response = manager.processPairRequest(request, clientIp: '192.168.1.66');

      expect(response.success, isTrue);
      expect(response.status, 'paired');
      expect(response.pairedAuthToken, isNotNull);

      expect(manager.pairedDevices.length, 1);
      expect(manager.pairedDevices.first.id, 'phone-001');
      expect(manager.activeSession, isNull); // single-use
    });

    test('processPairRequest fails with invalid PIN or token', () {
      manager.createPairingSession();

      final badRequest = PairRequestPayload(
        clientDeviceId: 'hacker-001',
        clientDeviceName: 'Unknown',
        clientDeviceType: DeviceType.windows,
        pinCode: '000000',
      );

      final response = manager.processPairRequest(badRequest, clientIp: '192.168.1.99');
      expect(response.success, isFalse);
      expect(response.status, 'invalid_code');

      // Session should still be active for a valid retry
      expect(manager.activeSession, isNotNull);
    });

    test('processPairRequest fails when session has expired', () {
      manager.createPairingSession(validity: const Duration(milliseconds: -10)); // expired

      final request = PairRequestPayload(
        clientDeviceId: 'pc-001',
        clientDeviceName: 'PC',
        clientDeviceType: DeviceType.windows,
        pinCode: '123456',
      );

      final response = manager.processPairRequest(request, clientIp: '192.168.1.55');
      expect(response.success, isFalse);
      expect(response.status, 'expired');
    });

    test('verifyClientAuth works for registered auth token', () {
      final session = manager.createPairingSession();
      final response = manager.processPairRequest(
        PairRequestPayload(
          clientDeviceId: 'phone-1',
          clientDeviceName: 'iPhone',
          clientDeviceType: DeviceType.ios,
          sessionToken: session.sessionToken,
        ),
        clientIp: '192.168.1.77',
      );

      final token = response.pairedAuthToken!;
      expect(manager.verifyClientAuth('phone-1', token), isTrue);
      expect(manager.verifyClientAuth('phone-1', 'wrong-token'), isFalse);
      expect(manager.verifyClientAuth('phone-1', null), isFalse);
      expect(manager.verifyClientAuth('unregistered-id', token), isFalse);
    });

    test('removePairedDevice and clearPairedDevices', () {
      final session = manager.createPairingSession();
      manager.processPairRequest(
        PairRequestPayload(
          clientDeviceId: 'dev-1',
          clientDeviceName: 'Device 1',
          clientDeviceType: DeviceType.android,
          sessionToken: session.sessionToken,
        ),
        clientIp: '192.168.1.1',
      );

      expect(manager.pairedDevices.length, 1);

      final removed = manager.removePairedDevice('dev-1');
      expect(removed, isTrue);
      expect(manager.pairedDevices, isEmpty);

      // Verify clear
      manager.clearPairedDevices();
      expect(manager.pairedDevices, isEmpty);
    });
  });
}
