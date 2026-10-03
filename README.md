# clipboard_networking

Core networking, LAN discovery, protocol, and pairing package for the **Clipboard Sharer** cross-platform ecosystem.

## Features

- **Domain Models**:
  - `Device`: Identity, status, IP, port, device type, authentication credentials.
  - `ClipboardItem`: ID, content text, creation timestamp, source device ID, sensitive flag.
  - `DeviceType`: `windows`, `android`, `ios`, `androidTv`, `macos`.
  - `ConnectionState`: `disconnected`, `discovering`, `connecting`, `connected`, `error`.
  - `DeviceStatus`: `online`, `offline`, `paired`, `unpaired`.
  - `PairingPayload`: QR code representation and 6-digit numeric PIN payload.
- **Protocol**:
  - JSON network envelope (`version`, `type`, `messageId`, `timestamp`, `senderId`, `payload`).
  - 10 standardized message types: `HELLO`, `DEVICE_INFO`, `PAIR_REQUEST`, `PAIR_RESPONSE`, `PAIR_COMPLETE`, `CLIPBOARD`, `ACK`, `PING`, `PONG`, `DISCONNECT`.
  - Strongly-typed payload parsers and builders for every message type.
- **LAN Discovery**:
  - DNS-SD / mDNS using `nsd` (`_clipboard._tcp`).
  - Pluggable `DeviceDiscovery` and `DeviceAdvertiser` interfaces with in-memory `MockDiscoveryHub` for testing and simulated environments.
- **Transport**:
  - `WebSocketLanServer` (for Android TV): Upgrades HTTP requests, manages connected clients, automatic message acknowledgments (ACKs), heartbeat monitoring.
  - `WebSocketLanClient` (for Mobile / Windows): Connects to TV over WebSocket, auto-reconnect with exponential backoff, periodic heartbeats, ACK awaiting (`sendWithAck`).
- **Pairing & Authentication**:
  - Android TV generates temporary 6-digit numeric PINs and cryptographically secure QR session tokens (valid for 5 minutes).
  - Single-use validation: code is invalidated immediately upon successful pairing.
  - Persistent auth tokens generated for authenticated sessions.
- **High-Level Facades**:
  - `ClipboardSharerReceiver`: Turnkey Android TV controller.
  - `ClipboardSharerClient`: Turnkey Mobile & Windows controller.

---

## Usage

### 1. Android TV (Receiver)

```dart
import 'package:clipboard_networking/clipboard_networking.dart';

final receiver = ClipboardSharerReceiver(
  deviceId: 'tv-livingroom-01',
  deviceName: 'Living Room Android TV',
);

// Start server and begin mDNS advertisement
await receiver.start();

// Listen to incoming clipboard items to insert into TV UI / IME
receiver.incomingClipboardStream.listen((item) {
  print('Received text: ${item.text} from ${item.sourceDeviceId}');
});

// Generate pairing QR & 6-digit PIN code
final pairingPayload = await receiver.startPairing();
print('Pairing PIN: ${pairingPayload.pinCode}');
print('Pairing QR Data: ${pairingPayload.toQrString()}');
```

### 2. Mobile (Android / iOS)

```dart
import 'package:clipboard_networking/clipboard_networking.dart';

final client = ClipboardSharerClient(
  deviceId: 'phone-uuid',
  deviceName: 'Pixel 8',
  deviceType: DeviceType.android,
);

// Scan QR code using mobile_scanner or camera
final qrPayload = PairingPayload.tryFromQrString(scannedQrString);
if (qrPayload != null) {
  final result = await client.pairWithQr(qrPayload);
  if (result.success) {
    print('Paired! Device: ${result.pairedDevice}');
  }
}

// Send clipboard content to TV
await client.sendText('https://youtu.be/example');
```

### 3. Windows Desktop

```dart
import 'package:clipboard_networking/clipboard_networking.dart';

final client = ClipboardSharerClient(
  deviceId: 'pc-uuid',
  deviceName: 'Workstation PC',
  deviceType: DeviceType.windows,
);

// Discover TVs on the LAN
client.discoveredDevicesStream.listen((devices) {
  print('Discovered TVs: $devices');
});
await client.startDiscovery();

// Pair using 6-digit code
final tvDevice = client.discoveredDevices.first;
final result = await client.pairWithPin(tvDevice, '123456');

// Send clipboard text
await client.sendText('Copied password', sensitive: true);
```

---

## Testing

Run tests with FVM:

```bash
fvm flutter test
fvm dart analyze
```
