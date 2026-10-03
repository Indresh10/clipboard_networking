import 'package:clipboard_networking/clipboard_networking.dart';
import 'package:test/test.dart';

void main() {
  group('ClipboardSharer High-Level Service Integration', () {
    late ClipboardSharerReceiver receiver;
    late ClipboardSharerClient client;
    late MockDeviceAdvertiser mockAdvertiser;
    late MockDeviceDiscovery mockDiscovery;

    setUp(() {
      MockDiscoveryHub.instance.reset();
      mockAdvertiser = MockDeviceAdvertiser();
      mockDiscovery = MockDeviceDiscovery();
    });

    tearDown(() async {
      client.dispose();
      await receiver.stop();
      MockDiscoveryHub.instance.reset();
    });

    test('Mobile QR flow: pairing and clipboard sharing end-to-end', () async {
      receiver = ClipboardSharerReceiver(
        deviceId: 'tv-sony-livingroom',
        deviceName: 'Living Room TV',
        advertiser: mockAdvertiser,
        config: const ReceiverConfig(
          port: 0, // dynamic port for testing
          autoAdvertise: true,
        ),
      );

      await receiver.start();
      expect(receiver.isRunning, isTrue);

      client = ClipboardSharerClient(
        deviceId: 'phone-pixel-8',
        deviceName: 'Indresh Pixel 8',
        deviceType: DeviceType.android,
        discovery: mockDiscovery,
        connection: WebSocketLanClient(
          localDeviceId: 'phone-pixel-8',
          config: const WebSocketClientConfig(
            enableAutoReconnect: false,
          ),
        ),
      );

      // 1. TV generates pairing session (simulates user navigating to TV Pairing Screen)
      final pairingPayload = await receiver.startPairing(
        localIpOverride: '127.0.0.1',
      );
      expect(pairingPayload.pinCode.length, 6);
      expect(pairingPayload.sessionToken.isNotEmpty, isTrue);

      // 2. Client pairs using the scanned QR payload
      final pairResult = await client.pairWithQr(pairingPayload);

      expect(pairResult.success, isTrue);
      expect(pairResult.status, 'paired');
      expect(pairResult.authToken, isNotNull);
      expect(pairResult.pairedDevice, isNotNull);
      expect(pairResult.pairedDevice!.status, DeviceStatus.paired);

      // Verify TV registered the paired device
      expect(receiver.pairedDevices.length, 1);
      expect(receiver.pairedDevices.first.id, 'phone-pixel-8');
      expect(receiver.currentPairingSession, isNull); // single use!

      // 3. Client sends a clipboard item to the TV
      final receivedItems = <ClipboardItem>[];
      final clipSub = receiver.incomingClipboardStream.listen(receivedItems.add);

      final sentOk = await client.sendText('https://youtube.com/watch?v=123456');
      expect(sentOk, isTrue);

      // Wait briefly for delivery
      await Future.delayed(const Duration(milliseconds: 100));

      expect(receivedItems.length, 1);
      final received = receivedItems.first;
      expect(received.text, 'https://youtube.com/watch?v=123456');
      expect(received.sourceDeviceId, 'phone-pixel-8');

      await clipSub.cancel();
    });

    test('Windows Desktop PIN flow: pairing with 6-digit code and sending text', () async {
      receiver = ClipboardSharerReceiver(
        deviceId: 'tv-tcl-bedroom',
        deviceName: 'Bedroom TV',
        advertiser: mockAdvertiser,
        config: const ReceiverConfig(
          port: 0,
          autoAdvertise: true,
        ),
      );

      final tvPort = await receiver.start();

      client = ClipboardSharerClient(
        deviceId: 'win-indresh-pc',
        deviceName: 'Indresh Workstation',
        deviceType: DeviceType.windows,
        discovery: mockDiscovery,
        connection: WebSocketLanClient(
          localDeviceId: 'win-indresh-pc',
          config: const WebSocketClientConfig(
            enableAutoReconnect: false,
          ),
        ),
      );

      // TV generates pairing session
      final sessionPayload = await receiver.startPairing(
        localIpOverride: '127.0.0.1',
      );

      final tvDevice = Device(
        id: 'tv-tcl-bedroom',
        name: 'Bedroom TV',
        type: DeviceType.androidTv,
        address: '127.0.0.1',
        port: tvPort,
      );

      // Windows user enters 6-digit code
      final pairResult = await client.pairWithPin(tvDevice, sessionPayload.pinCode);

      expect(pairResult.success, isTrue);
      expect(pairResult.status, 'paired');
      expect(receiver.pairedDevices.length, 1);
      expect(receiver.pairedDevices.first.id, 'win-indresh-pc');

      // Windows sends copied password
      final receivedItems = <ClipboardItem>[];
      final clipSub = receiver.incomingClipboardStream.listen(receivedItems.add);

      final item = ClipboardItem(
        id: 'pwd-01',
        text: 'SuperSecretWiFiKey987!',
        createdAt: DateTime.now().toUtc(),
        sourceDeviceId: 'win-indresh-pc',
        sensitive: true,
      );

      final sendOk = await client.sendClipboard(item);
      expect(sendOk, isTrue);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(receivedItems.length, 1);
      expect(receivedItems.first.text, 'SuperSecretWiFiKey987!');
      expect(receivedItems.first.sensitive, isTrue);

      await clipSub.cancel();
    });
  });
}
