// ABOUTME: Web-specific NostrService factory with basic NostrService only
// ABOUTME: Used on web platforms where EmbeddedRelayService is not supported

import 'package:openvine/services/nostr_key_manager.dart';
import 'package:openvine/services/nostr_service_interface.dart';
import 'package:openvine/services/nostr_service.dart';

/// Create basic NostrService instance for web platforms
INostrService createEmbeddedRelayService(NostrKeyManager keyManager) {
  // Return basic NostrService on web (embedded relay not supported)
  return NostrService(keyManager);
}
