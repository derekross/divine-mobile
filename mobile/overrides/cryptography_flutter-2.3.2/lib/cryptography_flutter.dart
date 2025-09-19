// ABOUTME: Main library file for cryptography_flutter plugin override
// ABOUTME: Provides cross-platform cryptography implementations

library cryptography_flutter;

// Export web implementation when available
export 'cryptography_flutter_web.dart'
    if (dart.library.html) 'cryptography_flutter_web.dart';
