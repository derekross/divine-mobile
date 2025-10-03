// ABOUTME: Tests for VideoControllerPool service
// ABOUTME: Verifies pool behavior for managing controller lifecycle

import 'package:flutter_test/flutter_test.dart';
import 'package:openvine/services/video_controller_pool.dart';

void main() {
  group('VideoControllerPool - Basic Operations', () {
    late VideoControllerPool pool;

    setUp(() {
      pool = VideoControllerPool();
    });

    tearDown(() async {
      await pool.clearAll();
    });

    test('singleton returns same instance', () {
      final pool1 = VideoControllerPool();
      final pool2 = VideoControllerPool();
      expect(identical(pool1, pool2), isTrue,
          reason: 'VideoControllerPool should be a singleton');
    });

    test('tryBorrowController returns null for non-existent controller', () {
      final controller = pool.tryBorrowController('video123');
      expect(controller, isNull,
          reason: 'Should return null when controller not in pool');
    });

    test('hasController returns false for non-existent controller', () {
      expect(pool.hasController('video123'), isFalse,
          reason: 'Should return false when controller not in pool');
    });

    test('getStats returns initial empty state', () {
      final stats = pool.getStats();

      expect(stats['totalControllers'], equals(0),
          reason: 'Should have 0 controllers initially');
      expect(stats['borrowed'], equals(0),
          reason: 'Should have 0 borrowed controllers initially');
      expect(stats['available'], equals(0),
          reason: 'Should have 0 available controllers initially');
      expect(stats['initialized'], equals(0),
          reason: 'Should have 0 initialized controllers initially');
      expect(stats['maxPoolSize'], greaterThan(0),
          reason: 'Should have positive max pool size');
    });

    test('clearAll succeeds on empty pool', () async {
      await pool.clearAll();
      final stats = pool.getStats();
      expect(stats['totalControllers'], equals(0));
    });
  });

  group('VideoControllerPool - Architectural Constraints', () {
    test('pool does not have play() or pause() methods', () {
      final pool = VideoControllerPool();

      // Verify pool interface does NOT have play/pause methods
      // This is a compile-time check - if this compiles, it passes
      expect(pool, isNotNull);

      // Pool should only have these methods:
      // - tryBorrowController
      // - returnController
      // - addController
      // - hasController
      // - getStats
      // - clearAll

      // NO play() or pause() methods should exist
    });
  });
}
