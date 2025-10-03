// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'home_feed_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Home feed provider - shows videos only from people you follow
/// keepAlive: true prevents disposal and unnecessary rebuilds during navigation
///
/// Rebuilds occur when:
/// - Contact list changes (follow/unfollow)
/// - 10 minutes have passed since last refresh
/// - User pulls to refresh

@ProviderFor(HomeFeed)
const homeFeedProvider = HomeFeedProvider._();

/// Home feed provider - shows videos only from people you follow
/// keepAlive: true prevents disposal and unnecessary rebuilds during navigation
///
/// Rebuilds occur when:
/// - Contact list changes (follow/unfollow)
/// - 10 minutes have passed since last refresh
/// - User pulls to refresh
final class HomeFeedProvider
    extends $AsyncNotifierProvider<HomeFeed, VideoFeedState> {
  /// Home feed provider - shows videos only from people you follow
  /// keepAlive: true prevents disposal and unnecessary rebuilds during navigation
  ///
  /// Rebuilds occur when:
  /// - Contact list changes (follow/unfollow)
  /// - 10 minutes have passed since last refresh
  /// - User pulls to refresh
  const HomeFeedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'homeFeedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$homeFeedHash();

  @$internal
  @override
  HomeFeed create() => HomeFeed();
}

String _$homeFeedHash() => r'0321bbbe7d72d313234ed6575118155f14ee96dc';

/// Home feed provider - shows videos only from people you follow
/// keepAlive: true prevents disposal and unnecessary rebuilds during navigation
///
/// Rebuilds occur when:
/// - Contact list changes (follow/unfollow)
/// - 10 minutes have passed since last refresh
/// - User pulls to refresh

abstract class _$HomeFeed extends $AsyncNotifier<VideoFeedState> {
  FutureOr<VideoFeedState> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<VideoFeedState>, VideoFeedState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<VideoFeedState>, VideoFeedState>,
              AsyncValue<VideoFeedState>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Provider to check if home feed is loading

@ProviderFor(homeFeedLoading)
const homeFeedLoadingProvider = HomeFeedLoadingProvider._();

/// Provider to check if home feed is loading

final class HomeFeedLoadingProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Provider to check if home feed is loading
  const HomeFeedLoadingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'homeFeedLoadingProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$homeFeedLoadingHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return homeFeedLoading(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$homeFeedLoadingHash() => r'e4c96dfd94b15fc125ecebf90f53a52a20081cd1';

/// Provider to get current home feed video count

@ProviderFor(homeFeedCount)
const homeFeedCountProvider = HomeFeedCountProvider._();

/// Provider to get current home feed video count

final class HomeFeedCountProvider extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  /// Provider to get current home feed video count
  const HomeFeedCountProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'homeFeedCountProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$homeFeedCountHash();

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    return homeFeedCount(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$homeFeedCountHash() => r'fa005197b095b160691887155a79988cbc15f8d4';

/// Provider to check if we have home feed videos

@ProviderFor(hasHomeFeedVideos)
const hasHomeFeedVideosProvider = HasHomeFeedVideosProvider._();

/// Provider to check if we have home feed videos

final class HasHomeFeedVideosProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Provider to check if we have home feed videos
  const HasHomeFeedVideosProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'hasHomeFeedVideosProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$hasHomeFeedVideosHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return hasHomeFeedVideos(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$hasHomeFeedVideosHash() => r'7785c6a7ebf4bc3bcd84129c6b1fda16e7f72edf';
