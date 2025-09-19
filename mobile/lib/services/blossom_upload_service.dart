// ABOUTME: Service for uploading videos to user-configured Blossom media servers
// ABOUTME: Supports NIP-98 authentication and returns media URLs from any Blossom server

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:nostr_sdk/event.dart';
import 'package:nostr_sdk/event_kind.dart';
import 'package:openvine/services/auth_service.dart';
import 'package:openvine/services/direct_upload_service.dart';
import 'package:openvine/services/nostr_service_interface.dart';
import 'package:openvine/utils/hash_util.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BlossomUploadService {
  static const String _blossomServerKey = 'blossom_server_url';
  static const String _useBlossomKey = 'use_blossom_upload';
  
  final AuthService authService;
  final INostrService nostrService;
  final Dio dio;
  
  BlossomUploadService({
    required this.authService, 
    required this.nostrService,
    Dio? dio,
  }) : dio = dio ?? Dio();
  
  /// Get the configured Blossom server URL
  Future<String?> getBlossomServer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_blossomServerKey);
  }
  
  /// Set the Blossom server URL
  Future<void> setBlossomServer(String? serverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    if (serverUrl != null && serverUrl.isNotEmpty) {
      await prefs.setString(_blossomServerKey, serverUrl);
    } else {
      await prefs.remove(_blossomServerKey);
    }
  }
  
  /// Check if Blossom upload is enabled
  Future<bool> isBlossomEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useBlossomKey) ?? false;
  }
  
  /// Enable or disable Blossom upload
  Future<void> setBlossomEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useBlossomKey, enabled);
  }
  
  /// Sign an event locally using the private key
  Future<Event?> _signEventLocally(Event event) async {
    try {
      // Get the private key from the key manager
      final privateKey = nostrService.keyManager.privateKey;
      if (privateKey == null) {
        Log.error('No private key available for signing',
            name: 'BlossomUploadService', category: LogCategory.video);
        return null;
      }
      
      // Sign the event using the Event's built-in sign method
      event.sign(privateKey);
      
      // Verify the signature was added
      if (event.sig.isEmpty) {
        Log.error('Event signing failed - no signature',
            name: 'BlossomUploadService', category: LogCategory.video);
        return null;
      }
      
      return event;
    } catch (e) {
      Log.error('Error signing event: $e',
          name: 'BlossomUploadService', category: LogCategory.video);
      return null;
    }
  }

  /// Create a NIP-98 authentication event for Blossom upload
  Future<Event?> _createNip98AuthEvent({
    required String url,
    required String method,
    required String fileHash,
    required int fileSize,
  }) async {
    try {
      // NIP-98 requires these tags:
      // - u: The URL being requested
      // - method: The HTTP method (PUT for upload)
      // - payload: SHA-256 hash for PUT requests
      // Additional Blossom-specific tags:
      // - t: "upload" to indicate upload request
      // - x: SHA-256 hash of the file
      // - size: File size in bytes
      // - expiration: Unix timestamp when auth expires (optional but recommended)
      
      final now = DateTime.now();
      final expiration = now.add(const Duration(minutes: 5)); // 5 minute expiration
      final expirationTimestamp = expiration.millisecondsSinceEpoch ~/ 1000;
      
      // Build tags for NIP-98 event
      final tags = [
        ['u', url],
        ['method', method],
        ['payload', fileHash], // SHA-256 of request body for PUT
        ['t', 'upload'], // Blossom-specific: indicates upload request
        ['x', fileHash], // Blossom-specific: file hash
        ['size', fileSize.toString()], // Blossom-specific: file size
        ['expiration', expirationTimestamp.toString()],
      ];
      
      // Create the event content (empty for NIP-98)
      const content = '';
      
      // Get the public key from auth service
      final pubkey = authService.currentPublicKeyHex;
      if (pubkey == null) {
        Log.error('No public key available for NIP-98 auth',
            name: 'BlossomUploadService', category: LogCategory.video);
        return null;
      }
      
      // Create unsigned event with kind 27235 (HTTP Auth)
      final unsignedEvent = Event(
        pubkey,
        EventKind.BLOSSOM_HTTP_AUTH, // 27235
        tags,
        content,
        createdAt: now.millisecondsSinceEpoch ~/ 1000,
      );
      
      // Sign the event
      // Note: Since NostrKeyManager doesn't expose a signEvent method directly,
      // we need to sign it using the private key manually
      final signedEvent = await _signEventLocally(unsignedEvent);
      
      if (signedEvent == null) {
        Log.error('Failed to sign NIP-98 auth event',
            name: 'BlossomUploadService', category: LogCategory.video);
        return null;
      }
      
      Log.info('Created NIP-98 auth event: ${signedEvent.id}',
          name: 'BlossomUploadService', category: LogCategory.video);
      
      return signedEvent;
    } catch (e) {
      Log.error('Error creating NIP-98 auth event: $e',
          name: 'BlossomUploadService', category: LogCategory.video);
      return null;
    }
  }

  /// Upload a video file to the configured Blossom server
  /// 
  /// This method currently returns a placeholder implementation.
  /// The actual Blossom upload will be implemented using the SDK's
  /// BolssomUploader when the Nostr service integration is ready.
  Future<DirectUploadResult> uploadVideo({
    required File videoFile,
    required String nostrPubkey,
    required String title,
    String? description,
    List<String>? hashtags,
    void Function(double)? onProgress,
  }) async {
    try {
      // Check if Blossom is enabled and configured
      final isEnabled = await isBlossomEnabled();
      if (!isEnabled) {
        return DirectUploadResult(
          success: false,
          errorMessage: 'Blossom upload is not enabled',
        );
      }
      
      final serverUrl = await getBlossomServer();
      if (serverUrl == null || serverUrl.isEmpty) {
        return DirectUploadResult(
          success: false,
          errorMessage: 'No Blossom server configured',
        );
      }
      
      // Parse and validate server URL
      final uri = Uri.tryParse(serverUrl);
      if (uri == null) {
        return DirectUploadResult(
          success: false,
          errorMessage: 'Invalid Blossom server URL',
        );
      }
      
      // Check authentication after URL validation
      if (!authService.isAuthenticated) {
        return DirectUploadResult(
          success: false,
          errorMessage: 'Not authenticated',
        );
      }
      
      Log.info('Uploading to Blossom server: $serverUrl',
          name: 'BlossomUploadService', category: LogCategory.video);
      
      // Check if we have keys
      if (!nostrService.hasKeys) {
        return DirectUploadResult(
          success: false,
          errorMessage: 'No Nostr keys available for signing',
        );
      }
      
      // For now, we'll use a simplified approach since the embedded relay doesn't expose Nostr SDK
      // We'll need to create the upload using direct HTTP calls with NIP-98 auth
      Log.warning('Blossom upload using SDK integration is pending - needs NostrService refactoring',
          name: 'BlossomUploadService', category: LogCategory.video);
      
      // Report initial progress
      onProgress?.call(0.1);
      
      // Calculate file hash for Blossom
      final fileBytes = await videoFile.readAsBytes();
      final fileHash = HashUtil.sha256Hash(fileBytes);
      final fileSize = fileBytes.length;
      
      Log.info('File hash: $fileHash, size: $fileSize bytes',
          name: 'BlossomUploadService', category: LogCategory.video);
      
      // Create NIP-98 auth event
      final authEvent = await _createNip98AuthEvent(
        url: '$serverUrl/upload',
        method: 'PUT',
        fileHash: fileHash,
        fileSize: fileSize,
      );
      
      if (authEvent == null) {
        return DirectUploadResult(
          success: false,
          errorMessage: 'Failed to create NIP-98 authentication',
        );
      }
      
      // Prepare authorization header
      final authEventJson = jsonEncode(authEvent.toJson());
      final authHeader = 'Nostr ${base64.encode(utf8.encode(authEventJson))}';
      
      Log.info('Making PUT request to Blossom server',
          name: 'BlossomUploadService', category: LogCategory.video);
      
      // Make PUT request to Blossom server
      try {
        final response = await dio.put(
          '$serverUrl/upload',
          data: fileBytes,
          options: Options(
            headers: {
              'Authorization': authHeader,
              'Content-Type': 'application/octet-stream',
            },
            validateStatus: (status) => status != null && status < 500,
          ),
          onSendProgress: (sent, total) {
            if (total > 0) {
              final progress = sent / total;
              onProgress?.call(progress * 0.9); // Reserve last 10% for finalization
            }
          },
        );
        
        Log.info('Blossom server response: ${response.statusCode}',
            name: 'BlossomUploadService', category: LogCategory.video);
        
        if (response.statusCode == 200 || response.statusCode == 201) {
          // Parse successful response
          final responseData = response.data;
          String? mediaUrl;
          
          if (responseData is Map) {
            mediaUrl = responseData['url'] as String?;
          } else if (responseData is String) {
            // Some servers return just the URL as a string
            mediaUrl = responseData;
          }
          
          if (mediaUrl != null && mediaUrl.isNotEmpty) {
            // Extract video ID from URL (last component typically)
            final videoId = mediaUrl.split('/').last;
            
            onProgress?.call(1.0);
            
            Log.info('✅ Blossom upload successful: $mediaUrl',
                name: 'BlossomUploadService', category: LogCategory.video);
            
            return DirectUploadResult(
              success: true,
              cdnUrl: mediaUrl,
              videoId: videoId,
            );
          } else {
            return DirectUploadResult(
              success: false,
              errorMessage: 'Invalid response from Blossom server: missing URL',
            );
          }
        } else if (response.statusCode == 401) {
          return DirectUploadResult(
            success: false,
            errorMessage: 'Authentication failed - check your Nostr keys',
          );
        } else if (response.statusCode == 413) {
          return DirectUploadResult(
            success: false,
            errorMessage: 'File too large for this Blossom server',
          );
        } else {
          return DirectUploadResult(
            success: false,
            errorMessage: 'Blossom server error: ${response.statusCode} - ${response.statusMessage}',
          );
        }
      } on DioException catch (e) {
        Log.error('Blossom upload network error: ${e.message}',
            name: 'BlossomUploadService', category: LogCategory.video);
        
        if (e.type == DioExceptionType.connectionTimeout) {
          return DirectUploadResult(
            success: false,
            errorMessage: 'Connection timeout - check server URL',
          );
        } else if (e.type == DioExceptionType.connectionError) {
          return DirectUploadResult(
            success: false,
            errorMessage: 'Cannot connect to Blossom server',
          );
        } else {
          return DirectUploadResult(
            success: false,
            errorMessage: 'Network error: ${e.message}',
          );
        }
      }
      
    } catch (e) {
      Log.error('Blossom upload error: $e',
          name: 'BlossomUploadService', category: LogCategory.video);
      
      return DirectUploadResult(
        success: false,
        errorMessage: 'Blossom upload failed: $e',
      );
    }
  }
}