// ABOUTME: Riverpod providers for managing comment state with reactive updates
// ABOUTME: Handles comment threads, reply chains, and optimistic UI updates using pure @riverpod functions

import 'package:nostr_sdk/nostr_sdk.dart';
import 'package:openvine/models/comment.dart';
import 'package:openvine/providers/app_providers.dart';
import 'package:openvine/utils/unified_logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'comments_provider.g.dart';

/// Comment tree node for organizing threaded comments
class CommentNode {
  CommentNode({
    required this.comment,
    List<CommentNode>? replies,
    this.isExpanded = true,
  }) : replies = replies ?? [];
  final Comment comment;
  final List<CommentNode> replies;
  bool isExpanded;

  /// Get total reply count including nested replies
  int get totalReplyCount {
    var count = replies.length;
    for (final reply in replies) {
      count += reply.totalReplyCount;
    }
    return count;
  }
}

/// State class for managing comments for a specific video
class CommentsState {
  const CommentsState({
    required this.rootEventId,
    this.topLevelComments = const [],
    this.isLoading = false,
    this.error,
    this.totalCommentCount = 0,
    this.commentCache = const {},
  });
  final String rootEventId;
  final List<CommentNode> topLevelComments;
  final bool isLoading;
  final String? error;
  final int totalCommentCount;
  final Map<String, Comment> commentCache;

  CommentsState copyWith({
    List<CommentNode>? topLevelComments,
    bool? isLoading,
    String? error,
    int? totalCommentCount,
    Map<String, Comment>? commentCache,
  }) =>
      CommentsState(
        rootEventId: rootEventId,
        topLevelComments: topLevelComments ?? this.topLevelComments,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        totalCommentCount: totalCommentCount ?? this.totalCommentCount,
        commentCache: commentCache ?? this.commentCache,
      );
}

/// Notifier for managing comments for a specific video
@riverpod
class CommentsNotifier extends _$CommentsNotifier {
  late String _rootEventId;
  late String _rootAuthorPubkey;

  @override
  CommentsState build(String rootEventId, String rootAuthorPubkey) {
    _rootEventId = rootEventId;
    _rootAuthorPubkey = rootAuthorPubkey;

    // Load comments on initialization
    Future.microtask(() => _loadComments());

    return CommentsState(rootEventId: rootEventId);
  }

  /// Load comments for the video
  Future<void> _loadComments() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final socialService = ref.read(socialServiceProvider);
      final commentsStream = socialService.fetchCommentsForEvent(_rootEventId);
      final commentMap = <String, Comment>{};
      final replyMap = <String, List<String>>{}; // parentId -> [childIds]

      await for (final event in commentsStream.take(100)) {
        // Limit to first 100 comments
        // Convert Nostr event to Comment model
        final comment = _eventToComment(event);
        if (comment != null) {
          commentMap[comment.id] = comment;

          // Track parent-child relationships
          if (comment.replyToEventId != null) {
            replyMap[comment.replyToEventId!] =
                (replyMap[comment.replyToEventId!] ?? [])..add(comment.id);
          }
        }
      }

      // Build comment tree
      final topLevelComments = _buildCommentTree(commentMap, replyMap);

      state = state.copyWith(
        topLevelComments: topLevelComments,
        isLoading: false,
        totalCommentCount: commentMap.length,
        commentCache: commentMap,
      );
    } catch (e) {
      Log.error('Error loading comments: $e',
          name: 'CommentsNotifier', category: LogCategory.ui);
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load comments',
      );
    }
  }

  /// Convert Nostr event to Comment model
  Comment? _eventToComment(Event event) {
    try {
      String? rootEventId;
      String? replyToEventId;
      String? rootAuthorPubkey;
      String? replyToAuthorPubkey;

      // Parse tags to determine comment relationships
      for (final tag in event.tags) {
        if (tag.length < 2) continue;

        if (tag[0] == 'e') {
          // Event reference tag
          if (tag.length >= 4 && tag[3] == 'root') {
            rootEventId = tag[1];
          } else if (tag.length >= 4 && tag[3] == 'reply') {
            replyToEventId = tag[1];
          } else {
            // First e tag without marker is assumed to be root
            rootEventId ??= tag[1];
          }
        } else if (tag[0] == 'p') {
          // Pubkey reference tag
          if (rootAuthorPubkey == null) {
            rootAuthorPubkey = tag[1];
          } else {
            replyToAuthorPubkey = tag[1];
          }
        }
      }

      return Comment(
        id: event.id,
        content: event.content,
        authorPubkey: event.pubkey,
        createdAt: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
        rootEventId: rootEventId ?? _rootEventId,
        replyToEventId: replyToEventId,
        rootAuthorPubkey: rootAuthorPubkey ?? '',
        replyToAuthorPubkey: replyToAuthorPubkey,
      );
    } catch (e) {
      Log.error('Error parsing comment event: $e',
          name: 'CommentsNotifier', category: LogCategory.ui);
      return null;
    }
  }

  /// Build hierarchical comment tree from flat comment list
  List<CommentNode> _buildCommentTree(
    Map<String, Comment> commentMap,
    Map<String, List<String>> replyMap,
  ) {
    final topLevel = <CommentNode>[];
    final nodeMap = <String, CommentNode>{};

    // Create nodes for all comments
    for (final comment in commentMap.values) {
      nodeMap[comment.id] = CommentNode(comment: comment);
    }

    // Build tree structure
    for (final comment in commentMap.values) {
      if (comment.replyToEventId == null ||
          comment.replyToEventId == _rootEventId) {
        // Top-level comment
        topLevel.add(nodeMap[comment.id]!);
      } else if (nodeMap.containsKey(comment.replyToEventId)) {
        // Add as reply to parent comment
        nodeMap[comment.replyToEventId]!.replies.add(nodeMap[comment.id]!);
      } else {
        // Parent comment not found, treat as top-level
        topLevel.add(nodeMap[comment.id]!);
      }
    }

    // Sort by creation time (newest first)
    topLevel.sort((a, b) => b.comment.createdAt.compareTo(a.comment.createdAt));

    // Sort replies recursively
    void sortReplies(CommentNode node) {
      node.replies
          .sort((a, b) => a.comment.createdAt.compareTo(b.comment.createdAt));
      for (final reply in node.replies) {
        sortReplies(reply);
      }
    }

    for (final node in topLevel) {
      sortReplies(node);
    }

    return topLevel;
  }

  /// Post a new comment
  Future<void> postComment({
    required String content,
    String? replyToEventId,
    String? replyToAuthorPubkey,
  }) async {
    final authService = ref.read(authServiceProvider);
    if (!authService.isAuthenticated) {
      state = state.copyWith(error: 'Please sign in to comment');
      return;
    }

    if (content.trim().isEmpty) {
      state = state.copyWith(error: 'Comment cannot be empty');
      return;
    }

    try {
      state = state.copyWith(error: null);

      // Get current user's public key for optimistic update
      final currentUserPubkey = authService.currentPublicKeyHex;
      if (currentUserPubkey == null) {
        throw Exception('User public key not found');
      }

      // Create optimistic comment
      final optimisticComment = Comment(
        id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
        content: content,
        authorPubkey: currentUserPubkey,
        createdAt: DateTime.now(),
        rootEventId: _rootEventId,
        replyToEventId: replyToEventId,
        rootAuthorPubkey: '', // Will be updated when event is broadcast
        replyToAuthorPubkey: replyToAuthorPubkey,
      );

      // Add optimistic comment to state
      final updatedCache = Map<String, Comment>.from(state.commentCache);
      updatedCache[optimisticComment.id] = optimisticComment;

      // Add to tree structure
      List<CommentNode> updatedTopLevel;
      if (replyToEventId == null) {
        // Top-level comment
        updatedTopLevel = [
          CommentNode(comment: optimisticComment),
          ...state.topLevelComments,
        ];
      } else {
        // Reply to existing comment
        updatedTopLevel = _addReplyToTree(
          state.topLevelComments,
          optimisticComment,
          replyToEventId,
        );
      }

      state = state.copyWith(
        topLevelComments: updatedTopLevel,
        totalCommentCount: state.totalCommentCount + 1,
        commentCache: updatedCache,
      );

      // Use the root author pubkey passed to the provider
      final socialService = ref.read(socialServiceProvider);

      // Post the actual comment
      await socialService.postComment(
        content: content,
        rootEventId: _rootEventId,
        rootEventAuthorPubkey: _rootAuthorPubkey,
        replyToEventId: replyToEventId,
        replyToAuthorPubkey: replyToAuthorPubkey,
      );

      // Reload comments to get the real event ID
      await _loadComments();
    } catch (e) {
      Log.error('Error posting comment: $e',
          name: 'CommentsNotifier', category: LogCategory.ui);
      state = state.copyWith(error: 'Failed to post comment');

      // Remove optimistic comment on error
      await _loadComments();
    }
  }

  /// Add a reply to the comment tree
  List<CommentNode> _addReplyToTree(
    List<CommentNode> nodes,
    Comment reply,
    String parentId,
  ) =>
      nodes.map((node) {
        if (node.comment.id == parentId) {
          // Found parent, add reply
          return CommentNode(
            comment: node.comment,
            replies: [
              CommentNode(comment: reply),
              ...node.replies,
            ],
            isExpanded: node.isExpanded,
          );
        } else if (node.replies.isNotEmpty) {
          // Recursively search in replies
          return CommentNode(
            comment: node.comment,
            replies: _addReplyToTree(node.replies, reply, parentId),
            isExpanded: node.isExpanded,
          );
        }
        return node;
      }).toList();

  /// Toggle expansion state of a comment node
  void toggleCommentExpansion(String commentId) {
    List<CommentNode> toggleInTree(List<CommentNode> nodes) =>
        nodes.map((node) {
          if (node.comment.id == commentId) {
            return CommentNode(
              comment: node.comment,
              replies: node.replies,
              isExpanded: !node.isExpanded,
            );
          } else if (node.replies.isNotEmpty) {
            return CommentNode(
              comment: node.comment,
              replies: toggleInTree(node.replies),
              isExpanded: node.isExpanded,
            );
          }
          return node;
        }).toList();

    state = state.copyWith(
      topLevelComments: toggleInTree(state.topLevelComments),
    );
  }

  /// Refresh comments
  Future<void> refresh() async {
    await _loadComments();
  }

  /// Get comment count for UI display
  int get commentCount => state.totalCommentCount;
}
