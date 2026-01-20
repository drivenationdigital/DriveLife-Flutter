import 'package:flutter/material.dart';
import 'package:drivelife/api/posts_api.dart';

class CaptionSearchViewModel {
  late final ValueNotifier<List<Map<String, dynamic>>> _users = ValueNotifier(
    [],
  );
  ValueNotifier<List<Map<String, dynamic>>> get users => _users;

  late final ValueNotifier<List<String>> _hashtags = ValueNotifier([]);
  ValueNotifier<List<String>> get hashtags => _hashtags;

  late final ValueNotifier<bool> _loading = ValueNotifier(false);
  ValueNotifier<bool> get loading => _loading;

  late final ValueNotifier<SearchResultView> _activeView = ValueNotifier(
    SearchResultView.none,
  );
  ValueNotifier<SearchResultView> get activeView => _activeView;

  void _setLoading(bool val) {
    if (val != _loading.value) {
      _loading.value = val;
    }
  }

  Future<void> searchUser(String query) async {
    _activeView.value = SearchResultView.users;
    if (query.isEmpty) {
      _users.value = [];
      return;
    }

    _setLoading(true);

    try {
      // Use your existing API - same as in TagEntitiesScreen
      final results = await PostsAPI.fetchTaggableEntities(
        search: query,
        entityType: 'users',
        taggedEntities: [], // No need to filter already tagged in caption
      );

      _users.value = [...results];
    } catch (e) {
      print('Error searching users: $e');
      _users.value = [];
    } finally {
      _setLoading(false);
    }
  }

  Future<void> searchHashtag(String query) async {
    _activeView.value = SearchResultView.hashtag;
    if (query.isEmpty) {
      _hashtags.value = [];
      return;
    }

    // Hashtags don't need API search - they're created as you type
    // Just show the query as a suggestion
    _hashtags.value = [query];
  }

  void dispose() {
    _users.dispose();
    _hashtags.dispose();
    _loading.dispose();
    _activeView.dispose();
  }
}

enum SearchResultView { users, hashtag, none }

// Global instance
final captionSearchViewModel = CaptionSearchViewModel();
