import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../models/device.dart';
import '../models/device_status.dart';
import '../models/pairing_payload.dart';
import '../protocol/payloads.dart';

/// Active temporary pairing session on the TV / receiver.
class ActivePairingSession {
  final String sessionId;
  final String pinCode;
  final String sessionToken;
  final DateTime expiresAt;

  ActivePairingSession({
    required this.sessionId,
    required this.pinCode,
    required this.sessionToken,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);
}

/// Result of pairing attempt.
@immutable
class PairingResult {
  final bool success;
  final String status;
  final String? authToken;
  final Device? pairedDevice;
  final String? errorMessage;

  const PairingResult({
    required this.success,
    required this.status,
    this.authToken,
    this.pairedDevice,
    this.errorMessage,
  });
}

/// Server-side manager for pairing sessions and paired device verification on Android TV.
class PairingManager {
  static const _uuid = Uuid();
  static final _random = Random.secure();

  final String serverDeviceId;
  final String serverDeviceName;
  final String serverAddress;
  final int serverPort;

  ActivePairingSession? _activeSession;
  final Map<String, Device> _pairedDevices = {};
  void Function(List<Device> devices)? onPairedDevicesChanged;

  PairingManager({
    required this.serverDeviceId,
    required this.serverDeviceName,
    required this.serverAddress,
    required this.serverPort,
    List<Device> initialPairedDevices = const [],
    this.onPairedDevicesChanged,
  }) {
    for (final dev in initialPairedDevices) {
      _pairedDevices[dev.id] = dev;
    }
  }

  ActivePairingSession? get activeSession =>
      (_activeSession != null && !_activeSession!.isExpired) ? _activeSession : null;

  List<Device> get pairedDevices => _pairedDevices.values.toList();

  /// Creates a new single-use pairing session with a 6-digit numeric PIN
  /// and a secure QR session token, valid for [validity] (default 5 minutes).
  PairingPayload createPairingSession({
    Duration validity = const Duration(minutes: 5),
  }) {
    final sessionId = _uuid.v4();
    // Cryptographically secure 6-digit PIN (100000 - 999999)
    final pinCode = (100000 + _random.nextInt(900000)).toString();
    // Cryptographically secure 32-character token for QR scan
    final tokenBytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final sessionToken = sha256.convert(tokenBytes).toString().substring(0, 32);
    final expiresAt = DateTime.now().toUtc().add(validity);

    _activeSession = ActivePairingSession(
      sessionId: sessionId,
      pinCode: pinCode,
      sessionToken: sessionToken,
      expiresAt: expiresAt,
    );

    return PairingPayload(
      sessionId: sessionId,
      deviceId: serverDeviceId,
      deviceName: serverDeviceName,
      address: serverAddress,
      port: serverPort,
      pinCode: pinCode,
      sessionToken: sessionToken,
      expiresAt: expiresAt,
    );
  }

  /// Cancels any active pairing session.
  void cancelPairingSession() {
    _activeSession = null;
  }

  /// Evaluates an incoming [PairRequestPayload] from a client over LAN.
  PairResponsePayload processPairRequest(
    PairRequestPayload request, {
    required String clientIp,
  }) {
    final session = _activeSession;

    // Check if session exists
    if (session == null) {
      return const PairResponsePayload(
        success: false,
        status: 'no_session',
        errorMessage: 'No active pairing session on this TV. Please open the pairing screen.',
      );
    }

    // Check expiration
    if (session.isExpired) {
      _activeSession = null;
      return const PairResponsePayload(
        success: false,
        status: 'expired',
        errorMessage: 'Pairing session has expired. Please refresh the pairing screen.',
      );
    }

    // Validate either QR session token or 6-digit numeric PIN
    final matchesToken = request.sessionToken != null &&
        request.sessionToken!.trim() == session.sessionToken;
    final matchesPin = request.pinCode != null &&
        request.pinCode!.trim() == session.pinCode;

    if (!matchesToken && !matchesPin) {
      return const PairResponsePayload(
        success: false,
        status: 'invalid_code',
        errorMessage: 'Invalid pairing PIN code or QR token.',
      );
    }

    // Invalidate session immediately (single-use requirement)
    _activeSession = null;

    // Generate persistent auth token for this client
    final authBytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final authToken = sha256.convert(authBytes).toString();

    // Register paired device
    final pairedDevice = Device(
      id: request.clientDeviceId,
      name: request.clientDeviceName,
      type: request.clientDeviceType,
      address: clientIp,
      port: 0,
      status: DeviceStatus.paired,
      lastSeen: DateTime.now().toUtc(),
      pairedAt: DateTime.now().toUtc(),
      authToken: authToken,
    );

    _pairedDevices[pairedDevice.id] = pairedDevice;
    onPairedDevicesChanged?.call(pairedDevices);

    return PairResponsePayload(
      success: true,
      status: 'paired',
      pairedAuthToken: authToken,
      tvDeviceId: serverDeviceId,
      tvDeviceName: serverDeviceName,
    );
  }

  /// Verifies if a client is already paired and their [authToken] matches.
  bool verifyClientAuth(String clientId, String? authToken) {
    if (authToken == null || authToken.isEmpty) return false;
    final device = _pairedDevices[clientId];
    if (device == null || device.authToken == null) return false;
    return device.authToken == authToken;
  }

  /// Removes a previously paired device.
  bool removePairedDevice(String deviceId) {
    final removed = _pairedDevices.remove(deviceId) != null;
    if (removed) {
      onPairedDevicesChanged?.call(pairedDevices);
    }
    return removed;
  }

  /// Clears all paired devices.
  void clearPairedDevices() {
    _pairedDevices.clear();
    onPairedDevicesChanged?.call(pairedDevices);
  }
}
