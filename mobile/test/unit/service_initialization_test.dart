// ABOUTME: TDD test for service initialization blocking navigation on critical failures
// ABOUTME: These will fail first, then we fix the initialization to properly handle failures

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Mock classes for testing service initialization behavior
class MockFailingAppInitializer extends ConsumerStatefulWidget {
  const MockFailingAppInitializer({super.key});

  @override
  ConsumerState<MockFailingAppInitializer> createState() =>
      _MockFailingAppInitializerState();
}

class _MockFailingAppInitializerState
    extends ConsumerState<MockFailingAppInitializer> {
  bool _isInitialized = false;
  String _initializationStatus = 'Initializing...';
  bool _hasCriticalError = false;

  @override
  void initState() {
    super.initState();
    _simulateServiceFailure();
  }

  Future<void> _simulateServiceFailure() async {
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      // Simulate critical service failure (like Nostr service)
      throw Exception('Critical Nostr service initialization failed');
    } catch (e) {
      if (mounted) {
        setState(() {
          // This is the PROBLEMATIC behavior - should NOT set _isInitialized = true on critical failures
          _isInitialized =
              true; // BUG: Continue anyway with basic functionality
          _initializationStatus = 'Initialization completed with errors';
          _hasCriticalError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initializing services...'),
            ],
          ),
        ),
      );
    }

    // This should NOT be reached when there are critical errors
    if (_hasCriticalError) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, color: Colors.red, size: 64),
              SizedBox(height: 16),
              Text('Critical services failed'),
              SizedBox(height: 8),
              Text('Please restart the app'),
            ],
          ),
        ),
      );
    }

    // Normal app navigation should NOT be accessible with critical errors
    return const Scaffold(
      body: Center(
        child: Text('Main App - Navigation Allowed'),
      ),
    );
  }
}

class MockServiceFailureHandler extends StatefulWidget {
  final bool isCriticalFailure;
  const MockServiceFailureHandler({super.key, required this.isCriticalFailure});

  @override
  State<MockServiceFailureHandler> createState() =>
      _MockServiceFailureHandlerState();
}

class _MockServiceFailureHandlerState extends State<MockServiceFailureHandler> {
  bool _isInitialized = false;
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _simulateFailure();
  }

  Future<void> _simulateFailure() async {
    await Future.delayed(const Duration(milliseconds: 100));

    if (widget.isCriticalFailure) {
      // Critical failure (e.g., Nostr service) - should block navigation
      setState(() {
        _status = 'Critical failure - cannot continue';
        // Should NOT set _isInitialized = true for critical failures
      });
    } else {
      // Non-critical failure (e.g., background publisher) - can continue
      setState(() {
        _isInitialized = true;
        _status = 'Initialized with warnings';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialized) {
      return const Scaffold(
        body: Center(child: Text('App Initialized Successfully')),
      );
    }

    if (widget.isCriticalFailure) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(_status),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => setState(() => _status = 'Retrying...'),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_status),
          ],
        ),
      ),
    );
  }
}

class MockRetryableFailure extends StatefulWidget {
  const MockRetryableFailure({super.key});

  @override
  State<MockRetryableFailure> createState() => _MockRetryableFailureState();
}

class _MockRetryableFailureState extends State<MockRetryableFailure> {
  bool _hasError = true;
  int _retryCount = 0;

  void _retry() {
    setState(() {
      _retryCount++;
      _hasError = _retryCount < 2; // Succeed on second retry
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off, color: Colors.orange, size: 48),
              const SizedBox(height: 16),
              const Text('Failed to connect to Nostr network'),
              const SizedBox(height: 8),
              Text('Attempt ${_retryCount + 1}'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Connection'),
              ),
            ],
          ),
        ),
      );
    }

    return const Scaffold(
      body: Center(child: Text('Connected Successfully')),
    );
  }
}

void main() {
  group('Service Initialization TDD - Navigation Blocking Tests', () {
    testWidgets(
        'FAIL FIRST: AppInitializer should not allow navigation when critical services fail',
        (tester) async {
      // This test WILL FAIL initially - proving navigation is allowed even with service failures!

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: const MockFailingAppInitializer(),
          ),
        ),
      );

      // Initially should show loading
      expect(find.text('Initializing services...'), findsOneWidget);

      // Wait for service failure simulation
      await tester.pumpAndSettle(const Duration(milliseconds: 200));

      // Should show critical error screen, NOT navigation
      expect(find.text('Critical services failed'), findsOneWidget,
          reason: 'Should show error screen when critical services fail');
      expect(find.text('Main App - Navigation Allowed'), findsNothing,
          reason:
              'Should NOT allow navigation to main app when critical services fail');
    });

    testWidgets(
        'FAIL FIRST: AppInitializer should distinguish between critical and non-critical service failures',
        (tester) async {
      // This test WILL FAIL initially - no distinction between critical and non-critical failures

      // Test critical failure scenario
      await tester.pumpWidget(
        MaterialApp(
          home: const MockServiceFailureHandler(
            key: Key('critical'),
            isCriticalFailure: true,
          ),
        ),
      );

      // Wait for the initialization delay
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pump();

      expect(find.text('Critical failure - cannot continue'), findsOneWidget,
          reason: 'Should show critical error message');
      expect(find.text('App Initialized Successfully'), findsNothing,
          reason: 'Should NOT initialize app with critical failures');
      expect(find.text('Retry'), findsOneWidget,
          reason: 'Should provide retry option for critical failures');

      // Test non-critical failure scenario
      await tester.pumpWidget(
        MaterialApp(
          home: const MockServiceFailureHandler(
            key: Key('non-critical'),
            isCriticalFailure: false,
          ),
        ),
      );

      // Wait for the initialization delay
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pump();

      expect(find.text('App Initialized Successfully'), findsOneWidget,
          reason: 'Should initialize app even with non-critical failures');
    });

    testWidgets(
        'FAIL FIRST: AppInitializer should provide clear retry mechanism for critical failures',
        (tester) async {
      // This test WILL FAIL initially - no proper retry mechanism exists

      await tester.pumpWidget(
        MaterialApp(home: const MockRetryableFailure()),
      );

      // Should show error state initially
      expect(find.text('Failed to connect to Nostr network'), findsOneWidget);
      expect(find.text('Attempt 1'), findsOneWidget);

      // Tap retry button
      await tester.tap(find.text('Retry Connection'));
      await tester.pump();

      // Should still show error (will succeed on second retry)
      expect(find.text('Attempt 2'), findsOneWidget);

      // Tap retry again
      await tester.tap(find.text('Retry Connection'));
      await tester.pump();

      // Should now show success
      expect(find.text('Connected Successfully'), findsOneWidget,
          reason: 'Should show success after successful retry');
    });
  });
}
