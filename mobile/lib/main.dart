import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/providers/social_providers.dart' as social_providers;
import 'package:openvine/providers/tab_visibility_provider.dart';
import 'package:openvine/screens/activity_screen.dart';
import 'package:openvine/screens/explore_screen.dart';
import 'package:openvine/screens/profile_screen.dart';
import 'package:openvine/screens/search_screen.dart';
import 'package:openvine/screens/universal_camera_screen.dart';
import 'package:openvine/screens/video_feed_screen.dart';
import 'package:openvine/screens/web_auth_screen.dart';
import 'package:openvine/services/auth_service.dart';
import 'package:openvine/services/background_activity_manager.dart';
import 'package:openvine/services/crash_reporting_service.dart';
import 'package:openvine/services/global_video_registry.dart';
import 'package:openvine/services/logging_config_service.dart';
import 'package:openvine/services/video_stop_navigator_observer.dart';
import 'package:openvine/theme/vine_theme.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:openvine/widgets/age_verification_dialog.dart';
import 'package:openvine/widgets/app_lifecycle_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io' as io;
import 'package:openvine/network/vine_cdn_http_overrides.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

// Global navigation key for hashtag navigation
final GlobalKey<MainNavigationScreenState> mainNavigationKey =
    GlobalKey<MainNavigationScreenState>();

Future<void> _startOpenVineApp() async {
  // Add timing logs for startup diagnostics
  final startTime = DateTime.now();

  // Ensure bindings are initialized first (required for everything)
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize video_player_media_kit globally (replaces AVPlayer on iOS)
  VideoPlayerMediaKit.ensureInitialized(iOS: true, android: true, macOS: true);

  // Initialize crash reporting ASAP so we can use it for logging
  await CrashReportingService.instance.initialize();

  // Now we can start logging
  Log.info('[STARTUP] App initialization started at $startTime',
      name: 'Main', category: LogCategory.system);
  CrashReportingService.instance.logInitializationStep('Bindings initialized');

  // Enable DNS override for legacy Vine CDN domains if configured
  const bool enableVineCdnFix = bool.fromEnvironment('VINE_CDN_DNS_FIX', defaultValue: true);
  const String cdnIp = String.fromEnvironment('VINE_CDN_IP', defaultValue: '151.101.244.157');
  if (enableVineCdnFix) {
    final ip = io.InternetAddress.tryParse(cdnIp);
    if (ip != null) {
      io.HttpOverrides.global = VineCdnHttpOverrides(overrideAddress: ip);
      Log.info('Enabled Vine CDN DNS override to $cdnIp', name: 'Networking');
    } else {
      Log.warning('Invalid VINE_CDN_IP "$cdnIp". DNS override not applied.', name: 'Networking');
    }
  }

  // Initialize window manager for macOS to control actual window size
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    try {
      CrashReportingService.instance.logInitializationStep('Initializing window manager');
      await windowManager.ensureInitialized();

      // Set initial window size for desktop vine experience
      const initialWindowOptions = WindowOptions(
        size: Size(750, 950), // Wider, better proportioned for desktop
        minimumSize:
            Size(ResponsiveWrapper.baseWidth, ResponsiveWrapper.baseHeight),
        center: true,
        backgroundColor: Colors.black,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
      );

      await windowManager.waitUntilReadyToShow(initialWindowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      // If window_manager fails, continue without it - ResponsiveWrapper will still work
      Log.error('Window manager initialization failed: $e', name: 'main');
    }
  }

  // Initialize logging configuration
  CrashReportingService.instance.logInitializationStep('Initializing logging configuration');
  await LoggingConfigService.instance.initialize();

  // Log that core startup is complete
  CrashReportingService.instance.logInitializationStep('Core app startup complete');

  // Log startup time tracking
  final initDuration = DateTime.now().difference(startTime).inMilliseconds;
  CrashReportingService.instance.log('[STARTUP] Initial setup took ${initDuration}ms');

  // Set default log level based on build mode if not already configured
  if (const String.fromEnvironment('LOG_LEVEL').isEmpty) {
    if (kDebugMode) {
      // Debug builds: enable debug logging for development visibility
      // Note: LogCategory.relay excluded to prevent verbose WebSocket message logging
      UnifiedLogger.setLogLevel(LogLevel.debug);
      UnifiedLogger.enableCategories(
          {LogCategory.system, LogCategory.auth, LogCategory.video});
    } else {
      // Release builds: minimal logging to reduce performance impact
      UnifiedLogger.setLogLevel(LogLevel.warning);
      UnifiedLogger.enableCategories({LogCategory.system, LogCategory.auth});
    }
  }

  // Store original debugPrint to avoid recursion
  final originalDebugPrint = debugPrint;

  // Override debugPrint to respect logging levels
  debugPrint = (message, {wrapWidth}) {
    if (message != null && UnifiedLogger.isLevelEnabled(LogLevel.debug)) {
      originalDebugPrint(message, wrapWidth: wrapWidth);
    }
  };

  // Configure global error widget builder for user-friendly error display
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // In debug mode, show detailed error information
    if (kDebugMode) {
      return Container(
        color: const Color(0xFF1A1A1A),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.bug_report,
                  color: Colors.orange,
                  size: 48,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Debug Error',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      details.exception.toString(),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    // In debug mode, just log the error
                    Log.warning(
                        'User acknowledged debug error: ${details.exception}',
                        name: 'ErrorWidget');
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Restart App'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // In release mode, show user-friendly error message
    return Container(
      color: const Color(0xFF1A1A1A),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 64,
              ),
              const SizedBox(height: 24),
              const Text(
                'Something went wrong',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'We encountered an unexpected issue. Please try restarting the app.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  // Log error for analytics in release mode
                  Log.error(
                      'User encountered widget error: ${details.exception}',
                      name: 'ErrorWidget');
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  };

  // Handle Flutter framework errors more gracefully
  final previousOnError = FlutterError.onError; // Preserve Crashlytics handler
  FlutterError.onError = (details) {
    // Log all errors for debugging
    Log.error('Flutter Error: ${details.exception}',
        name: 'Main', category: LogCategory.system);

    // Log the error but don't crash the app for known framework issues
    if (details.exception.toString().contains('KeyDownEvent') ||
        details.exception.toString().contains('HardwareKeyboard')) {
      Log.warning(
          'Known Flutter framework keyboard issue (ignoring): ${details.exception}',
          name: 'Main');
      return;
    }

    // For other errors, forward to any existing handler (e.g., Crashlytics),
    // then use default presentation which will now use our ErrorWidget.builder
    try {
      if (previousOnError != null) {
        previousOnError(details);
      }
    } catch (_) {}
    FlutterError.presentError(details);
  };

  // Initialize Hive for local data storage
  await Hive.initFlutter();

  Log.info('divine starting...', name: 'Main');
  Log.info('Log level: ${UnifiedLogger.currentLevel.name}', name: 'Main');

  runApp(const DivineApp());
}

void main() {
  // Capture any uncaught Dart errors (foreground or background zones)
  runZonedGuarded(() async {
    await _startOpenVineApp();
  }, (error, stack) async {
    // Best-effort logging; if Crashlytics isn't ready, still print
    try {
      await CrashReportingService.instance
          .recordError(error, stack, reason: 'runZonedGuarded');
    } catch (_) {}
  });
}

class DivineApp extends StatelessWidget {
  const DivineApp({super.key});

  @override
  Widget build(BuildContext context) {
    const bool crashProbe = bool.fromEnvironment('CRASHLYTICS_PROBE', defaultValue: false);
    final app = MaterialApp(
      title: 'divine',
      debugShowCheckedModeBanner: false,
      theme: VineTheme.theme,
      home: const ResponsiveWrapper(child: AppInitializer()),
      navigatorObservers: [VideoStopNavigatorObserver()],
    );

    Widget wrapped = AppLifecycleHandler(child: app);

    if (crashProbe) {
      // Invisible crash probe: tap top-left corner 7 times within 5s to crash
      wrapped = Stack(
        children: [
          wrapped,
          Positioned(
            left: 0,
            top: 0,
            width: 44,
            height: 44,
            child: _CrashProbeHotspot(),
          ),
        ],
      );
    }

    return ProviderScope(child: wrapped);
  }
}

class _CrashProbeHotspot extends StatefulWidget {
  @override
  State<_CrashProbeHotspot> createState() => _CrashProbeHotspotState();
}

class _CrashProbeHotspotState extends State<_CrashProbeHotspot> {
  int _taps = 0;
  DateTime? _windowStart;

  void _onTap() async {
    final now = DateTime.now();
    if (_windowStart == null || now.difference(_windowStart!) > const Duration(seconds: 5)) {
      _windowStart = now;
      _taps = 0;
    }
    _taps++;
    if (_taps >= 7) {
      // Record a breadcrumb, then crash the app (TestFlight validation)
      try {
        FirebaseCrashlytics.instance.log('CrashProbe: triggering test crash');
      } catch (_) {}
      // Force a native crash to ensure reporting in TF
      FirebaseCrashlytics.instance.crash();
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _onTap,
        child: const SizedBox.expand(),
      );
}

/// AppInitializer handles the async initialization of services
class AppInitializer extends ConsumerStatefulWidget {
  const AppInitializer({super.key});

  @override
  ConsumerState<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends ConsumerState<AppInitializer> {
  bool _isInitialized = false;
  String _initializationStatus = 'Initializing services...';
  bool _hasCriticalError = false;
  String? _criticalErrorMessage;
  bool _canRetry = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    final initStartTime = DateTime.now();
    Timer? timeoutTimer;
    var hasTimedOut = false;

    try {
      // Start timeout detection
      timeoutTimer = Timer(const Duration(seconds: 10), () {
        if (!_isInitialized && !hasTimedOut) {
          hasTimedOut = true;
          Log.warning('[STARTUP] WARNING: Initialization taking > 10 seconds',
              name: 'AppInitializer', category: LogCategory.system);
          // Safe call to CrashReportingService since it's initialized early now
          CrashReportingService.instance.log('Startup timeout detected');
          Log.warning('Initialization timeout: > 10 seconds elapsed',
              name: 'AppInitializer');
        }
      });

      if (!mounted) return;
      setState(() => _initializationStatus =
          'Initializing background activity manager...');

      // Initialize background activity manager early
      try {
        CrashReportingService.instance.logInitializationStep('Starting BackgroundActivityManager');
        final serviceStart = DateTime.now();
        await BackgroundActivityManager().initialize();
        final serviceDuration = DateTime.now().difference(serviceStart).inMilliseconds;
        CrashReportingService.instance.logInitializationStep(
            '✓ BackgroundActivityManager initialized in ${serviceDuration}ms');
      } catch (e) {
        CrashReportingService.instance.logInitializationStep(
            '✗ BackgroundActivityManager failed: $e');
        Log.warning('Failed to initialize background activity manager: $e',
            name: 'AppInitializer');
      }

      if (!mounted) return;
      setState(() => _initializationStatus = 'Checking authentication...');
      CrashReportingService.instance.logInitializationStep('Starting AuthService');
      final authStart = DateTime.now();
      await ref.read(authServiceProvider).initialize();
      final authDuration = DateTime.now().difference(authStart).inMilliseconds;
      CrashReportingService.instance.logInitializationStep(
          '✓ AuthService initialized in ${authDuration}ms');

      if (!mounted) return;
      setState(() => _initializationStatus = 'Connecting to Nostr network...');
      try {
        CrashReportingService.instance.logInitializationStep('Starting NostrService');
        final nostrStart = DateTime.now();
        await ref.read(nostrServiceProvider).initialize();
        final nostrDuration = DateTime.now().difference(nostrStart).inMilliseconds;
        CrashReportingService.instance.logInitializationStep(
            '✓ NostrService initialized in ${nostrDuration}ms');
      } catch (e) {
        CrashReportingService.instance.logInitializationStep('✗ NostrService failed: $e');
        Log.error('Nostr service initialization failed: $e',
            name: 'Main', category: LogCategory.system);
        // This is critical - rethrow
        rethrow;
      }

      // NotificationServiceEnhanced is initialized automatically via provider

      if (!mounted) return;
      setState(
          () => _initializationStatus = 'Initializing seen videos tracker...');
      CrashReportingService.instance.logInitializationStep('Starting SeenVideosService');
      final seenStart = DateTime.now();
      await ref.read(seenVideosServiceProvider).initialize();
      final seenDuration = DateTime.now().difference(seenStart).inMilliseconds;
      CrashReportingService.instance.logInitializationStep(
          '✓ SeenVideosService initialized in ${seenDuration}ms');

      if (!mounted) return;
      setState(() => _initializationStatus = 'Initializing upload manager...');
      CrashReportingService.instance.logInitializationStep('Starting UploadManager');
      final uploadStart = DateTime.now();
      await ref.read(uploadManagerProvider).initialize();
      final uploadDuration = DateTime.now().difference(uploadStart).inMilliseconds;
      CrashReportingService.instance.logInitializationStep(
          '✓ UploadManager initialized in ${uploadDuration}ms');

      if (!mounted) return;
      setState(
          () => _initializationStatus = 'Starting background publisher...');
      try {
        CrashReportingService.instance.logInitializationStep('Starting VideoEventPublisher');
        final publisherStart = DateTime.now();
        await ref.read(videoEventPublisherProvider).initialize();
        final publisherDuration = DateTime.now().difference(publisherStart).inMilliseconds;
        CrashReportingService.instance.logInitializationStep(
            '✓ VideoEventPublisher initialized in ${publisherDuration}ms');
      } catch (e) {
        CrashReportingService.instance.logInitializationStep(
            '✗ VideoEventPublisher failed: $e');
        Log.error(
            'VideoEventPublisher initialization failed (backend endpoint missing): $e',
            name: 'Main',
            category: LogCategory.system);
        // Continue anyway - this is for background publishing optimization
      }

      if (!mounted) return;
      setState(() => _initializationStatus = 'Loading curated content...');
      CrashReportingService.instance.logInitializationStep('Starting CurationService');
      final curationStart = DateTime.now();
      await ref.read(curationServiceProvider).subscribeToCurationSets();
      final curationDuration = DateTime.now().difference(curationStart).inMilliseconds;
      CrashReportingService.instance.logInitializationStep(
          '✓ CurationService initialized in ${curationDuration}ms');

      // Cancel timeout timer
      timeoutTimer.cancel();

      // Log total initialization time
      final totalDuration = DateTime.now().difference(initStartTime).inMilliseconds;
      CrashReportingService.instance.logInitializationStep(
          'All services initialized successfully in ${totalDuration}ms');
      Log.info('[STARTUP] All services initialized in ${totalDuration}ms',
          name: 'AppInitializer', category: LogCategory.system);

      if (!mounted) return;
      setState(() {
        _isInitialized = true;
        _initializationStatus = 'Ready!';
      });

      // Initialize social provider synchronously to ensure it's ready for feed
      if (!mounted) return;
      setState(() => _initializationStatus = 'Loading social connections...');
      try {
        CrashReportingService.instance.logInitializationStep('Starting SocialProvider');
        final socialStart = DateTime.now();
        await ref
            .read(social_providers.socialNotifierProvider.notifier)
            .initialize();
        final socialDuration = DateTime.now().difference(socialStart).inMilliseconds;
        CrashReportingService.instance.logInitializationStep(
            '✓ SocialProvider initialized in ${socialDuration}ms');
        Log.info('Social provider initialized successfully',
            name: 'Main', category: LogCategory.system);
      } catch (e) {
        CrashReportingService.instance.logInitializationStep('✗ SocialProvider failed: $e');
        Log.warning('Social provider initialization failed: $e',
            name: 'Main', category: LogCategory.system);
        // Continue anyway - social features will work with empty following list
      }

      Log.info('All services initialized successfully',
          name: 'Main', category: LogCategory.system);
    } catch (e, stackTrace) {
      // Cancel timeout timer on error
      timeoutTimer?.cancel();

      final errorDuration = DateTime.now().difference(initStartTime).inMilliseconds;
      CrashReportingService.instance.logInitializationStep(
          'Initialization failed after ${errorDuration}ms: $e');
      Log.error('[STARTUP] Initialization failed after ${errorDuration}ms',
          name: 'AppInitializer', category: LogCategory.system);

      Log.error('Service initialization failed: $e',
          name: 'Main', category: LogCategory.system);
      Log.verbose('📱 Stack trace: $stackTrace',
          name: 'Main', category: LogCategory.system);

      // Record non-fatal initialization error to Crashlytics
      try {
        await CrashReportingService.instance
            .recordError(e, stackTrace, reason: 'App initialization');
      } catch (_) {}

      if (mounted) {
        // Determine if this is a critical error that should block navigation
        final errorMessage = e.toString();
        final isCriticalError = _isCriticalServiceFailure(errorMessage);

        setState(() {
          if (isCriticalError) {
            // Critical errors block navigation - show error screen with retry option
            _hasCriticalError = true;
            _criticalErrorMessage = _getFriendlyErrorMessage(errorMessage);
            _canRetry = true;
            // DO NOT set _isInitialized = true for critical errors
            _initializationStatus = 'Critical service failure';
          } else {
            // Non-critical errors allow navigation with degraded functionality
            _isInitialized = true;
            _initializationStatus = 'Initialization completed with warnings';
          }
        });
      }
    }
  }

  /// Determines if a service failure is critical and should block navigation
  bool _isCriticalServiceFailure(String errorMessage) {
    // Critical services that must work for the app to function
    return errorMessage.contains('Nostr service') ||
        errorMessage.contains('Authentication') ||
        errorMessage.contains('AuthService') ||
        errorMessage.contains('Critical service') ||
        errorMessage.contains('auth') && errorMessage.contains('failed');
  }

  /// Converts technical error messages to user-friendly messages
  String _getFriendlyErrorMessage(String technicalError) {
    if (technicalError.contains('Nostr')) {
      return 'Unable to connect to the Nostr network. Please check your internet connection.';
    } else if (technicalError.contains('auth') ||
        technicalError.contains('Authentication')) {
      return 'Authentication service failed to initialize. Your identity could not be loaded.';
    } else {
      return 'A critical service failed to start. The app cannot function properly.';
    }
  }

  /// Retry initialization after a critical error
  Future<void> _retryInitialization() async {
    setState(() {
      _hasCriticalError = false;
      _criticalErrorMessage = null;
      _canRetry = false;
      _initializationStatus = 'Retrying initialization...';
    });

    // Retry on next frame to avoid blocking UI without arbitrary delay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeServices();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show critical error screen if we have critical errors (blocks navigation)
    if (_hasCriticalError) {
      return Scaffold(
        backgroundColor: VineTheme.backgroundColor,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 64,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Unable to Start App',
                  style: TextStyle(
                    color: VineTheme.primaryText,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  _criticalErrorMessage ??
                      'A critical service failed to initialize.',
                  style: const TextStyle(
                    color: VineTheme.secondaryText,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (_canRetry) ...[
                  ElevatedButton.icon(
                    onPressed: _retryInitialization,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: VineTheme.vineGreen,
                      foregroundColor: VineTheme.whiteText,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => _initializeServices(),
                    child: Text(
                      'Skip and try anyway (may not work properly)',
                      style: TextStyle(
                        color: VineTheme.secondaryText.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: VineTheme.backgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: VineTheme.vineGreen),
              const SizedBox(height: 16),
              Text(
                _initializationStatus,
                style:
                    const TextStyle(color: VineTheme.primaryText, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Use Consumer to watch AuthService state
    return Consumer(
      builder: (context, ref, child) {
        final authService = ref.watch(authServiceProvider);

        switch (authService.authState) {
          case AuthState.unauthenticated:
            // On web platform, show the web authentication screen
            if (kIsWeb) {
              return const WebAuthScreen();
            }

            // Show error screen only if there's an actual error, not for TikTok-style auto-creation
            if (authService.lastError != null) {
              return Scaffold(
                backgroundColor: VineTheme.backgroundColor,
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      const Text(
                        'Authentication Error',
                        style: TextStyle(
                            color: VineTheme.primaryText,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        authService.lastError!,
                        style: const TextStyle(
                            color: VineTheme.secondaryText, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => authService.initialize(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: VineTheme.vineGreen,
                          foregroundColor: VineTheme.whiteText,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }
            // If no error, fall through to loading screen (auto-creation in progress)
            return const Scaffold(
              backgroundColor: VineTheme.backgroundColor,
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: VineTheme.vineGreen),
                    SizedBox(height: 16),
                    Text(
                      'Creating your identity...',
                      style:
                          TextStyle(color: VineTheme.primaryText, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          case AuthState.checking:
          case AuthState.authenticating:
            return Scaffold(
              backgroundColor: VineTheme.backgroundColor,
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: VineTheme.vineGreen),
                    const SizedBox(height: 16),
                    Text(
                      authService.authState == AuthState.checking
                          ? 'Getting things ready...'
                          : 'Setting up your identity...',
                      style: const TextStyle(
                          color: VineTheme.primaryText, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          case AuthState.authenticated:
            return MainNavigationScreen(key: mainNavigationKey);
        }
      },
    );
  }
}

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({
    super.key,
    this.initialTabIndex,
    this.startingVideo,
    this.initialHashtag,
  });
  final int? initialTabIndex;
  final VideoEvent? startingVideo;
  final String? initialHashtag;

  @override
  ConsumerState<MainNavigationScreen> createState() =>
      MainNavigationScreenState();
}

class MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _currentIndex = 0;
  final GlobalKey<State<VideoFeedScreen>> _feedScreenKey =
      GlobalKey<State<VideoFeedScreen>>();
  DateTime? _lastFeedTap;

  late List<Widget> _screens; // Created once to preserve state
  final GlobalKey<ExploreScreenState> _exploreScreenKey =
      GlobalKey<ExploreScreenState>();

  // Profile viewing state
  String? _viewingProfilePubkey; // null means viewing own profile

  @override
  void initState() {
    super.initState();

    // Set initial tab based on whether user is following anyone
    if (widget.initialTabIndex != null) {
      _currentIndex = widget.initialTabIndex!;
    } else {
      // Default to feed tab - social data will load and update the feed
      _currentIndex = 0;
      Log.info(
        'MainNavigation: Defaulting to feed tab',
        name: 'MainNavigation',
        category: LogCategory.ui,
      );
    }

    // Initialize tab visibility provider with initial tab
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(tabVisibilityProvider.notifier).setActiveTab(_currentIndex);
    });

    // Create screens once - IndexedStack will preserve their state
    // ProfileScreen is created lazily to avoid unnecessary profile stats loading during startup
    // UNLESS we're starting on the profile tab
    _screens = [
      VideoFeedScreen(
        key: _feedScreenKey,
        startingVideo: widget.startingVideo,
      ),
      const ActivityScreen(),
      ExploreScreen(key: _exploreScreenKey),
      // If starting on profile tab, create it immediately; otherwise use placeholder
      widget.initialTabIndex == 3
          ? const ProfileScreen(profilePubkey: null) // null means current user
          : Container(), // Placeholder for ProfileScreen - will be replaced when needed
    ];

    Log.info(
        '📱 MainNavigation: Created screens array with ${_screens.length} screens',
        name: 'MainNavigation',
        category: LogCategory.ui);
    Log.info(
        '📱 MainNavigation: Screen at index 0 is ${_screens[0].runtimeType}',
        name: 'MainNavigation',
        category: LogCategory.ui);

    // If initial hashtag is provided, navigate to explore tab after build
    if (widget.initialHashtag != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigateToHashtag(widget.initialHashtag!);
      });
    }
  }

  void _onTabTapped(int index) {
    // Update tab visibility provider FIRST to trigger reactive video pausing
    ref.read(tabVisibilityProvider.notifier).setActiveTab(index);

    // Let tab visibility provider handle video pausing reactively
    // No need for manual pause calls - VideoFeedItem handles this via _getTabActiveStatus()

    // Notify screens of visibility changes (schedule to avoid provider re-entrancy)
    if (_currentIndex == 2 && index != 2) {
      // Leaving explore screen
      Future.microtask(() => _exploreScreenKey.currentState?.onScreenHidden());
    } else if (_currentIndex != 2 && index == 2) {
      // Entering explore screen
      Future.microtask(() => _exploreScreenKey.currentState?.onScreenVisible());
    }

    // When tapping the profile tab directly, always show current user's profile
    if (index == 3) {
      // Reset to current user's profile when tapping the tab
      _viewingProfilePubkey = null;

      // Lazy load ProfileScreen when profile tab is first accessed
      if (_screens[3] is Container) {
        setState(() {
          _screens[3] =
              ProfileScreen(profilePubkey: null); // null means current user
        });
      } else {
        // Update existing ProfileScreen to show current user
        setState(() {
          _screens[3] =
              ProfileScreen(profilePubkey: null); // null means current user
        });
      }
    }

    // Check for double-tap on feed icon
    if (index == 0 && _currentIndex == 0) {
      final now = DateTime.now();
      if (_lastFeedTap != null &&
          now.difference(_lastFeedTap!).inMilliseconds < 500) {
        // Double tap detected - scroll to top and refresh
        _scrollToTopAndRefresh();
        _lastFeedTap = null; // Reset to prevent triple tap
        return;
      }
      _lastFeedTap = now;
    }

    // Check for tap on explore tab while already on explore tab
    if (index == 2 && _currentIndex == 2) {
      Log.debug(
          '🔄 Explore tab tapped while on explore (index: $index, current: $_currentIndex)',
          name: 'MainNavigation',
          category: LogCategory.ui);
      // Tell explore screen to exit feed mode and return to grid (only if in feed mode)
      final exploreState = _exploreScreenKey.currentState;
      if (exploreState != null) {
        Log.debug(
            '✅ Found explore screen state, isInFeedMode: ${exploreState.isInFeedMode}',
            name: 'MainNavigation',
            category: LogCategory.ui);
        if (exploreState.isInFeedMode) {
          Log.debug('🔄 Calling exitFeedMode() to return to grid',
              name: 'MainNavigation', category: LogCategory.ui);
          exploreState.exitFeedMode();
        } else {
          Log.debug('📱 Already in grid mode, no action needed',
              name: 'MainNavigation', category: LogCategory.ui);
        }
      } else {
        Log.warning('❌ Explore screen state is null - key: $_exploreScreenKey',
            name: 'MainNavigation', category: LogCategory.ui);
      }
      return;
    }

    // Tab visibility provider will handle pausing via reactive VideoFeedItem updates
    // No manual pause calls needed

    // Tab visibility provider will handle resuming via reactive VideoFeedItem updates
    // No manual resume calls needed

    setState(() {
      _currentIndex = index;
    });
  }

  void _scrollToTopAndRefresh() {
    try {
      // Use the static method to scroll to top and refresh
      VideoFeedScreen.scrollToTopAndRefresh(_feedScreenKey);
      Log.info('🔄 Double-tap: Scrolling to top and refreshing feed',
          name: 'Main', category: LogCategory.ui);
    } catch (e) {
      Log.error('Error scrolling to top and refreshing: $e',
          name: 'Main', category: LogCategory.ui);
    }
  }

  void navigateToHashtag(String hashtag) {
    // Switch to explore tab
    setState(() {
      _currentIndex = 2;
    });

    // Pass hashtag to explore screen
    _exploreScreenKey.currentState?.showHashtagVideos(hashtag);
  }

  /// Public method to switch to a specific tab
  void switchToTab(int index) {
    if (index >= 0 && index < _screens.length) {
      _onTabTapped(index);
    }
  }

  /// Navigate to a user's profile
  /// Called from other screens to view a specific user's profile
  void navigateToProfile(String? profilePubkey) {
    // IMMEDIATELY pause ALL videos on profile navigation
    GlobalVideoRegistry().pauseAllControllers();
    Log.info('⏸️ Paused all videos when navigating to profile',
        name: 'Main', category: LogCategory.system);

    setState(() {
      _viewingProfilePubkey = profilePubkey;
      // Always create or update the profile screen
      _screens[3] = ProfileScreen(profilePubkey: _viewingProfilePubkey);
      // Switch to profile tab
      _currentIndex = 3;
    });
  }

  /// Navigate to search functionality within explore
  /// Called from other screens to open search functionality
  void navigateToSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SearchScreen()),
    );
  }

  /// Play a specific video in the explore tab with context videos
  /// Called from search results to play a video within its result set
  void playSpecificVideo(List<VideoEvent> videos, int startIndex) {
    // IMMEDIATELY pause ALL videos before playing specific video
    GlobalVideoRegistry().pauseAllControllers();
    Log.info('⏸️ Paused all videos before playing specific video',
        name: 'Main', category: LogCategory.system);

    // Switch to explore tab first
    _onTabTapped(2);

    // After switching tabs, play the specific video with its context
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _exploreScreenKey.currentState?.playSpecificVideo(videos, startIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    Log.info('📱 MainNavigation: build() - currentIndex=$_currentIndex',
        name: 'MainNavigation', category: LogCategory.ui);

    // React to social data readiness
    ref.listen(social_providers.socialNotifierProvider, (prev, next) {
      if (mounted &&
          next.isInitialized &&
          next.followingPubkeys.isEmpty &&
          _currentIndex != 2) {
        // Use post frame callback to avoid setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _currentIndex = 2;
            });
            Log.info(
              'MainNavigation: User not following anyone, switching to explore tab',
              name: 'MainNavigation',
              category: LogCategory.ui,
            );
          }
        });
      }
    });

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        backgroundColor: VineTheme.vineGreen,
        selectedItemColor: VineTheme.whiteText,
        unselectedItemColor: VineTheme.whiteText.withValues(alpha: 0.7),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'FEED',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications),
            label: 'ACTIVITY',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.explore),
            label: 'EXPLORE',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'PROFILE',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // Capture context before async operations
          final scaffoldContext = context;

          // IMMEDIATELY pause ALL videos before opening camera
          GlobalVideoRegistry().pauseAllControllers();
          Log.info('⏸️ Paused all videos before camera',
              name: 'Main', category: LogCategory.system);

          // Check age verification before opening camera
          final ageVerificationService =
              ref.read(ageVerificationServiceProvider);
          final isVerified =
              await ageVerificationService.checkAgeVerification();

          if (!isVerified && mounted) {
            // Show age verification dialog
            if (!scaffoldContext.mounted) return;
            final result = await AgeVerificationDialog.show(scaffoldContext);
            if (result) {
              // User confirmed they are 16+
              await ageVerificationService.setAgeVerified(true);
              if (mounted) {
                // Use universal camera screen that works on all platforms
                if (scaffoldContext.mounted) {
                  await Navigator.push(
                    scaffoldContext,
                    MaterialPageRoute(
                        builder: (context) => const UniversalCameraScreen()),
                  );
                }

                // After returning from camera, refresh profile if on profile tab
                if (mounted && _currentIndex == 3) {
                  Log.debug('Refreshing profile after camera return',
                      name: 'Main', category: LogCategory.system);
                  // Profile videos will auto-refresh when screen is rebuilt
                }
              }
            } else {
              // User is under 16 or declined
              if (mounted) {
                if (scaffoldContext.mounted) {
                  ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                    const SnackBar(
                      content:
                          Text('You must be 16 or older to create content'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            }
          } else if (mounted) {
            // Already verified, go to camera
            if (scaffoldContext.mounted) {
              await Navigator.push(
                scaffoldContext,
                MaterialPageRoute(
                    builder: (context) => const UniversalCameraScreen()),
              );
            }

            // After returning from camera, refresh profile if on profile tab
            if (mounted && _currentIndex == 3) {
              Log.debug('Refreshing profile after camera return',
                  name: 'Main', category: LogCategory.system);
              // Profile videos will auto-refresh when screen is rebuilt
            }
          }
        },
        backgroundColor: VineTheme.vineGreen,
        foregroundColor: VineTheme.whiteText,
        child: const Icon(Icons.videocam, size: 32),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}

/// ResponsiveWrapper adapts app size based on available screen space
class ResponsiveWrapper extends StatefulWidget {
  const ResponsiveWrapper({required this.child, super.key});
  final Widget child;

  // Base dimensions for desktop vine experience (1x scale)
  static const double baseWidth = 450; // Wider for better desktop experience
  static const double baseHeight =
      700; // Taller but more proportionate for desktop

  // Calculate optimal dimensions based on screen size
  static Size getOptimalSize(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    // For desktop vine experience, use more width while keeping vine feel
    // On web, be more generous with space since browsers can handle larger content
    final isWeb = kIsWeb;
    final targetWidth = screenSize.width *
        (isWeb
            ? 0.7
            : 0.6); // More generous width for better desktop experience
    final targetHeight =
        screenSize.height * (isWeb ? 0.9 : 0.85); // Use most of screen height

    // Calculate scale factor to fit within target dimensions
    final widthScale = targetWidth / baseWidth;
    final heightScale = targetHeight / baseHeight;

    // Use the smaller scale to ensure both dimensions fit, but prioritize the classic vine aspect ratio
    final scaleFactor =
        (widthScale < heightScale ? widthScale : heightScale).clamp(1.2, 4.0);

    return Size(
      baseWidth * scaleFactor,
      baseHeight * scaleFactor,
    );
  }

  @override
  State<ResponsiveWrapper> createState() => _ResponsiveWrapperState();
}

class _ResponsiveWrapperState extends State<ResponsiveWrapper> {
  @override
  void initState() {
    super.initState();

    // Update window size after first frame when we have screen info
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }

    // Force rebuilds on window resize for web
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Listen to media query changes which includes window resizing
        MediaQuery.of(context);
      });
    }
  }

  Future<void> _updateWindowSize() async {
    if (!mounted) return;

    try {
      final optimalSize = ResponsiveWrapper.getOptimalSize(context);

      // Update window size to accommodate the scaled content
      await windowManager.setSize(Size(
        optimalSize.width + 20, // Minimal padding for window chrome
        optimalSize.height + 80, // Padding for title bar and chrome
      ));

      // Re-center the window
      await windowManager.center();
    } catch (e) {
      // Silently fail if window manager isn't available
      Log.error('Failed to update window size: $e', name: 'main');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // Web needs to fill the entire browser viewport with no gaps
      return Container(
        color: Colors.black,
        width: double.infinity,
        height: double.infinity,
        child: widget.child,
      );
    } else if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      // On desktop platforms, just return the child to fill the window
      // Window size is managed by windowManager, no need for containers or centering
      return widget.child;
    }

    // On mobile, return child as-is (no constraints)
    return widget.child;
  }
}
