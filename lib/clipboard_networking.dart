/// Clipboard Sharer Networking plugin.
/// Provides LAN-only discovery (mDNS), WebSocket transport, authentication,
/// pairing protocols (QR & PIN), and domain models for cross-device clipboard sharing.
library;

export 'models/models.dart';
export 'protocol/protocol.dart';
export 'discovery/discovery.dart';
export 'transport/transport.dart';
export 'pairing/pairing.dart';
export 'clipboard_receiver.dart';
export 'clipboard_client.dart';
