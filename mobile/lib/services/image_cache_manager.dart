// ABOUTME: Custom cache manager for network images with iOS-optimized timeout and connection settings
// ABOUTME: Prevents network image loading deadlocks by limiting concurrent connections and setting appropriate timeouts

import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/io_client.dart';

class ImageCacheManager extends CacheManager {
  static const key = 'openvine_image_cache';

  static ImageCacheManager? _instance;

  factory ImageCacheManager() {
    return _instance ??= ImageCacheManager._();
  }

  ImageCacheManager._() : super(
    Config(
      key,
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 200,
      repo: JsonCacheInfoRepository(databaseName: key),
      fileService: _createHttpFileService(),
    ),
  );

  static HttpFileService _createHttpFileService() {
    // Create HttpClient with iOS-optimized settings
    final httpClient = HttpClient();

    // Set connection timeout - prevents hanging on slow connections
    httpClient.connectionTimeout = const Duration(seconds: 10);

    // Set idle timeout - prevents keeping connections open too long
    httpClient.idleTimeout = const Duration(seconds: 30);

    // Limit concurrent connections to prevent resource exhaustion
    httpClient.maxConnectionsPerHost = 6;

    return HttpFileService(
      httpClient: IOClient(httpClient),
    );
  }
}

// Singleton instance for easy access across the app
final openVineImageCache = ImageCacheManager();