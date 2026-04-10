// ── Search Results Widget ────────────────────────────────────

import 'dart:async';

import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/chat/ChatProfileCache.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class NewChatSearchResults extends StatefulWidget {
  final String query;
  final String myUserId;
  final void Function(String userId, String userName, String? conversationId) onDirectMessage;
  final void Function(UserProfile profile) onAddToGroup;
  final List<String> selectedIds; // already picked
  final int maxReached;

  const NewChatSearchResults({
    required this.query,
    required this.myUserId,
    required this.onDirectMessage,
    required this.onAddToGroup,
    required this.selectedIds,
    required this.maxReached,
  });

  @override
  State<NewChatSearchResults> createState() => NewChatSearchResultsState();
}

class NewChatSearchResultsState extends State<NewChatSearchResults> {
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  String? _error;
  String _lastQuery = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _onQueryChanged(widget.query);
  }

  @override
  void didUpdateWidget(NewChatSearchResults old) {
    super.didUpdateWidget(old);
    if (widget.query != old.query) _onQueryChanged(widget.query);
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _loading = false;
      });
      return;
    }
    // 400ms debounce — won't fire on every keystroke
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (query == _lastQuery) return;
    _lastQuery = query;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Reuses your existing PostsAPI — same as TagEntitiesScreen
      final results = await PostsAPI.fetchTaggableEntities(
        search: query,
        entityType: 'users',
        taggedEntities: [],
      );

      // Filter out the current user from results
      final filtered = results
          .where((u) => u['entity_id'].toString() != widget.myUserId)
          .toList();

      if (mounted)
        setState(() {
          _results = filtered;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: theme.primaryColor),
      );
    }
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          widget.query.length < 2
              ? 'Type to search users...'
              : 'No users found for "${widget.query}"',
          style: TextStyle(color: Colors.grey.shade500),
        ),
      );
    }

    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final user = _results[i];
        final profileImage = user['image'] as String?;
        final name = user['name'] as String? ?? 'Unknown';
        final userId = user['entity_id'].toString();
        final alreadySelected = widget.selectedIds.contains(userId);

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: CircleAvatar(
            radius: 22,
            backgroundImage: profileImage != null && profileImage != 'search_q'
                ? NetworkImage(profileImage)
                : null,
            backgroundColor: Colors.grey.shade300,
            child: profileImage == null || profileImage == 'search_q'
                ? const Icon(Icons.person, size: 20, color: Colors.black38)
                : null,
          ),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            '@${user['name'] ?? ''}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),

          // ── Two action icons ──
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Direct message
              IconButton(
                tooltip: 'Send message',
                icon: const Icon(Icons.send_rounded, size: 20),
                onPressed: () => widget.onDirectMessage(userId, name, ''),
              ),

              // Add to group
              alreadySelected
                  ? const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 22,
                    )
                  : IconButton(
                      tooltip: widget.maxReached > 0
                          ? 'Max members reached'
                          : 'Add to group',
                      icon: Icon(
                        Icons.group_add_rounded,
                        size: 22,
                        color: widget.maxReached > 0 ? Colors.grey : null,
                      ),
                      onPressed: widget.maxReached > 0
                          ? null
                          : () => widget.onAddToGroup(
                              UserProfile(
                                id: userId,
                                username: user['username'] ?? name,
                                displayName: name,
                                firstName: '',
                                lastName: '',
                                imageUrl: profileImage,
                              ),
                            ),
                    ),
            ],
          ),
        );
      },
    );
  }
}
