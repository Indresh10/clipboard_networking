import 'dart:async';
import '../models/device.dart';
import '../models/device_status.dart';
import '../models/device_type.dart';
import '../models/pairing_payload.dart';
import '../protocol/message_type.dart';
import '../protocol/network_message.dart';
import '../protocol/payloads.dart';
import '../transport/lan_connection.dart';
import 'pairing_manager.dart';

/// Client-side pairing orchestrator for Mobile (QR) and Windows Desktop (6-digit PIN).
class PairingClientService {
  final String localDeviceId;
  final String localDeviceName;
  final DeviceType localDeviceType;

  PairingClientService({
    required this.localDeviceId,
    required this.localDeviceName,
    required this.localDeviceType,
  });

  /// Executes pairing using a scanned [PairingPayload] (from a QR code).
  Future<PairingResult> pairWithQrPayload({
    required PairingPayload payload,
    required LanConnection connection,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final targetDevice = Device(
      id: payload.deviceId,
      name: payload.deviceName,
      type: DeviceType.androidTv,
      address: payload.address,
      port: payload.port,
      status: DeviceStatus.unpaired,
    );

    return _executePairing(
      targetDevice: targetDevice,
      connection: connection,
      sessionToken: payload.sessionToken,
      pinCode: null,
      timeout: timeout,
    );
  }

  /// Executes pairing using a 6-digit numeric PIN code against a discovered TV.
  Future<PairingResult> pairWithPin({
    required Device tvDevice,
    required String pinCode,
    required LanConnection connection,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return _executePairing(
      targetDevice: tvDevice,
      connection: connection,
      sessionToken: null,
      pinCode: pinCode.trim(),
      timeout: timeout,
    );
  }

  Future<PairingResult> _executePairing({
    required Device targetDevice,
    required LanConnection connection,
    String? sessionToken,
    String? pinCode,
    required Duration timeout,
  }) async {
    if (!connection.currentState.isConnected) {
      await connection.connect(targetDevice);
    }

    final pairReqMsg = NetworkMessage.pairRequest(
      senderId: localDeviceId,
      clientDeviceName: localDeviceName,
      clientDeviceType: localDeviceType,
      sessionToken: sessionToken,
      pinCode: pinCode,
    );

    final completer = Completer<PairResponsePayload>();
    late final StreamSubscription sub;

    sub = connection.messages.listen((msg) {
      if (msg.type == MessageType.pairResponse) {
        final resp = msg.asPairResponsePayload();
        if (!completer.isCompleted) {
          completer.complete(resp);
        }
      }
    });

    try {
      await connection.send(pairReqMsg);
      final response = await completer.future.timeout(
        timeout,
        onTimeout: () => throw TimeoutException('Pairing request timed out after ${timeout.inSeconds}s'),
      );

      if (response.success && response.pairedAuthToken != null) {
        // Send PAIR_COMPLETE confirmation
        await connection.send(
          NetworkMessage.pairComplete(
            senderId: localDeviceId,
            clientDeviceId: localDeviceId,
            confirmed: true,
          ),
        );

        final pairedDevice = targetDevice.copyWith(
          id: response.tvDeviceId ?? targetDevice.id,
          name: response.tvDeviceName ?? targetDevice.name,
          status: DeviceStatus.paired,
          authToken: response.pairedAuthToken,
          pairedAt: DateTime.now().toUtc(),
        );

        return PairingResult(
          success: true,
          status: response.status,
          authToken: response.pairedAuthToken,
          pairedDevice: pairedDevice,
        );
      } else {
        return PairingResult(
          success: false,
          status: response.status,
          errorMessage: response.errorMessage ?? 'Pairing rejected by TV',
        );
      }
    } finally {
      await sub.cancel();
    }
  }
}
