// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'video_events_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$videoEventsNostrServiceHash() =>
    r'04277d1a60fe84fec2e2c0e25e06300b39d64f24';

/// Provider for NostrService instance (Video Events specific)
///
/// Copied from [videoEventsNostrService].
@ProviderFor(videoEventsNostrService)
final videoEventsNostrServiceProvider =
    AutoDisposeProvider<INostrService>.internal(
  videoEventsNostrService,
  name: r'videoEventsNostrServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$videoEventsNostrServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef VideoEventsNostrServiceRef = AutoDisposeProviderRef<INostrService>;
String _$videoEventsSubscriptionManagerHash() =>
    r'b316afd0b391f09b481040d69432fd9e88fe15ae';

/// Provider for SubscriptionManager instance (Video Events specific)
///
/// Copied from [videoEventsSubscriptionManager].
@ProviderFor(videoEventsSubscriptionManager)
final videoEventsSubscriptionManagerProvider =
    AutoDisposeProvider<SubscriptionManager>.internal(
  videoEventsSubscriptionManager,
  name: r'videoEventsSubscriptionManagerProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$videoEventsSubscriptionManagerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef VideoEventsSubscriptionManagerRef
    = AutoDisposeProviderRef<SubscriptionManager>;
String _$videoEventsLoadingHash() =>
    r'722f24635d8119c0b6611f2dd799443d50043f19';

/// Provider to check if video events are loading
///
/// Copied from [videoEventsLoading].
@ProviderFor(videoEventsLoading)
final videoEventsLoadingProvider = AutoDisposeProvider<bool>.internal(
  videoEventsLoading,
  name: r'videoEventsLoadingProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$videoEventsLoadingHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef VideoEventsLoadingRef = AutoDisposeProviderRef<bool>;
String _$videoEventCountHash() => r'22ffcb27b11aa7cc89ace71a9d11f975c4aaf652';

/// Provider to get video event count
///
/// Copied from [videoEventCount].
@ProviderFor(videoEventCount)
final videoEventCountProvider = AutoDisposeProvider<int>.internal(
  videoEventCount,
  name: r'videoEventCountProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$videoEventCountHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef VideoEventCountRef = AutoDisposeProviderRef<int>;
String _$videoEventsHash() => r'bfdc98aa9487af4d650359c40dfbcd9e6f8bfcee';

/// Stream provider for video events from Nostr
///
/// Copied from [VideoEvents].
@ProviderFor(VideoEvents)
final videoEventsProvider =
    AutoDisposeStreamNotifierProvider<VideoEvents, List<VideoEvent>>.internal(
  VideoEvents.new,
  name: r'videoEventsProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$videoEventsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$VideoEvents = AutoDisposeStreamNotifier<List<VideoEvent>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
