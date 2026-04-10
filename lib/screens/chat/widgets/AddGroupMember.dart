import 'dart:async';

import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/chat/ChatProfileCache.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AddMemberPage extends StatefulWidget {
  final String myUserId;
  final List<String> existingIds;
  final void Function(UserProfile) onAdd;

  const AddMemberPage({
    required this.myUserId,
    required this.existingIds,
    required this.onAdd,
  });

  @override
  State<AddMemberPage> createState() => AddMemberPageState();
}

class AddMemberPageState extends State<AddMemberPage> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  String _lastQuery = '';
  Timer? _debounce;
  final Set<String> _addedIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        _results = [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(v.trim()),
    );
  }

  Future<void> _search(String query) async {
    if (query == _lastQuery) return;
    _lastQuery = query;

    try {
      final results = await PostsAPI.fetchTaggableEntities(
        search: query,
        entityType: 'users',
        taggedEntities: [],
      );
      final filtered = results
          .where((u) => !widget.existingIds.contains(u['entity_id'].toString()))
          .toList();

      if (mounted)
        setState(() {
          _results = filtered;
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Add Member'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search by name or username...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _results = [];
                            _loading = false;
                          });
                        },
                      )
                    : null,
              ),
              onChanged: _onChanged,
            ),
          ),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
          : _results.isEmpty && _searchController.text.trim().isNotEmpty
          ? const Center(child: Text('No users found.'))
          : _results.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search,
                    size: 48,
                    color: scheme.onSurfaceVariant.withOpacity(0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Search for people to add',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final user = _results[i];
                final profileImage = user['image'] as String?;
                final name = user['name'] as String? ?? 'Unknown';
                final userId = user['entity_id'].toString();
                final username = user['username'] as String? ?? '';

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: CircleAvatar(
                    radius: 22,
                    backgroundImage:
                        profileImage != null && profileImage != 'search_q'
                        ? NetworkImage(profileImage)
                        : null,
                    backgroundColor: Colors.grey.shade200,
                    child: profileImage == null || profileImage == 'search_q'
                        ? const Icon(
                            Icons.person,
                            size: 20,
                            color: Colors.black38,
                          )
                        : null,
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    '@$username',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  trailing: _addedIds.contains(userId)
                      ? FilledButton.icon(
                          onPressed: null, // disabled
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: const Text('Added'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.grey.shade300,
                            foregroundColor: Colors.grey.shade600,
                            disabledBackgroundColor: Colors.grey.shade300,
                            disabledForegroundColor: Colors.grey.shade600,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                      : FilledButton(
                          onPressed: () async {
                            widget.onAdd(
                              UserProfile(
                                id: userId,
                                username: username,
                                displayName: name,
                                firstName: '',
                                lastName: '',
                                imageUrl: profileImage,
                              ),
                            );
                            // Mark as added and show toast
                            setState(() => _addedIds.add(userId));
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(
                                        Icons.check_circle,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text('$name added to the group'),
                                    ],
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 2),
                                  backgroundColor: Colors.green.shade600,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              );
                            }
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.primaryColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Add'),
                        ),
                );
              },
            ),
    );
  }
}
