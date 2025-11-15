// ABOUTME: Riverpod providers for user lists (kind 30000) and curated video lists (kind 30005)
// ABOUTME: Manages list state and provides reactive updates for the Lists tab

import 'package:openvine/models/video_event.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/providers/video_events_providers.dart';
import 'package:openvine/services/curated_list_service.dart';
import 'package:openvine/services/user_list_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'list_providers.g.dart';

/// Provider for all user lists (kind 30000 - people lists)
@riverpod
Future<List<UserList>> userLists(Ref ref) async {
  final service = await ref.watch(userListServiceProvider.future);
  return service.lists;
}

/// Provider for all curated video lists (kind 30005)
@riverpod
Future<List<CuratedList>> curatedLists(Ref ref) async {
  final service = await ref.watch(curatedListServiceProvider.future);
  return service.lists;
}

/// Combined provider for both types of lists
@riverpod
Future<({List<UserList> userLists, List<CuratedList> curatedLists})> allLists(
    Ref ref) async {
  // Fetch both in parallel for better performance
  final results = await Future.wait([
    ref.watch(userListsProvider.future),
    ref.watch(curatedListsProvider.future),
  ]);

  return (
    userLists: results[0] as List<UserList>,
    curatedLists: results[1] as List<CuratedList>,
  );
}

/// Provider for videos in a specific curated list
@riverpod
Future<List<String>> curatedListVideos(Ref ref, String listId) async {
  final service = await ref.watch(curatedListServiceProvider.future);
  final list = service.getListById(listId);

  if (list == null) {
    return [];
  }

  // Return video IDs in the order specified by the list's playOrder setting
  return service.getOrderedVideoIds(listId);
}

/// Provider for videos from all members of a user list
@riverpod
Stream<List<VideoEvent>> userListMemberVideos(
    Ref ref, List<String> pubkeys) async* {
  // Watch discovery videos and filter to only those from list members
  final allVideosAsync = ref.watch(videoEventsProvider);

  await for (final _ in Stream.value(null)) {
    if (allVideosAsync.hasValue) {
      final allVideos = allVideosAsync.value!;

      // Filter videos to only those authored by list members
      final listMemberVideos = allVideos
          .where((video) => pubkeys.contains(video.pubkey))
          .toList();

      // Sort by creation time (newest first)
      listMemberVideos.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      yield listMemberVideos;
    }
  }
}
