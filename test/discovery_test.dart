import 'package:clipboard_networking/clipboard_networking.dart';
import 'package:test/test.dart';

void main() {
  group('Discovery & Advertising', () {
    late MockDeviceAdvertiser advertiser;
    late MockDeviceDiscovery discovery;

    setUp(() {
      MockDiscoveryHub.instance.reset();
      advertiser = MockDeviceAdvertiser();
      discovery = MockDeviceDiscovery();
    });

    tearDown(() async {
      await advertiser.stopAdvertising();
      await discovery.stop();
      MockDiscoveryHub.instance.reset();
    });

    test('discovery detects advertised TV device', () async {
      final discoveredList = <Device>[];
      final sub = discovery.discover().listen(discoveredList.add);

      await discovery.start();
      expect(discovery.isScanning, isTrue);

      await advertiser.startAdvertising(
        serviceName: 'Living Room TV',
        port: 43824,
        txtRecords: {
          'id': 'tv-001',
          'name': 'Living Room TV',
          'type': 'android_tv',
          'version': '1',
        },
      );
      expect(advertiser.isAdvertising, isTrue);

      // Allow microtasks to propagate
      await Future.delayed(const Duration(milliseconds: 50));

      expect(discoveredList.length, 1);
      final dev = discoveredList.first;
      expect(dev.id, 'tv-001');
      expect(dev.name, 'Living Room TV');
      expect(dev.type, DeviceType.androidTv);
      expect(dev.status, DeviceStatus.online);

      // Now stop advertising -> should notify offline
      await advertiser.stopAdvertising();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(discoveredList.length, 2);
      expect(discoveredList.last.status, DeviceStatus.offline);

      await sub.cancel();
    });

    test('discovery attaches to already-advertising devices when starting', () async {
      await advertiser.startAdvertising(
        serviceName: 'Bedroom TV',
        port: 43824,
        txtRecords: {
          'id': 'tv-bedroom',
          'name': 'Bedroom TV',
          'type': 'android_tv',
        },
      );

      final discoveredList = <Device>[];
      final sub = discovery.discover().listen(discoveredList.add);

      await discovery.start();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(discoveredList.isNotEmpty, isTrue);
      expect(discoveredList.first.id, 'tv-bedroom');

      await sub.cancel();
    });
  });
}
