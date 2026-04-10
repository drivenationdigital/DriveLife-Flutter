import 'dart:async';
import 'package:drivelife/api/posts_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/chat/ChatProfileCache.dart';
import 'package:drivelife/screens/chat/SupabaseClasses.dart';
import 'package:drivelife/screens/chat/widgets/AddGroupMember.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';


class GroupInfoScreen extends StatefulWidget {
  final String conversationId;
  final String myUserId;
  final String groupName;
  final List<String> participantIds;
  final void Function(List<String> participantIds, String groupName)? onChanged; 

  const GroupInfoScreen({
    super.key,
    required this.conversationId,
    required this.myUserId,
    required this.groupName,
    required this.participantIds,
    this.onChanged,
  });

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late List<String> _participantIds;
  late TextEditingController _nameController;
  bool _savingName = false;
  String _removingId = '';

  @override
  void initState() {
    super.initState();
    _participantIds = List.from(widget.participantIds);
    _nameController = TextEditingController(text: widget.groupName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _didUpdate() {
    widget.onChanged?.call(_participantIds, _nameController.text.trim());
  }

  // ── Save group name ──────────────────────────────────────────

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _savingName = true);

    try {
      await SupabaseConfig.client
          .from('conversations')
          .update({'group_name': name})
          .eq('id', widget.conversationId)
          .select()
          .single();

      if (mounted) {
        setState(() => _savingName = false);
        _didUpdate();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Group name updated.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _savingName = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Remove member ────────────────────────────────────────────

  Future<void> _removeMember(String userId) async {
    final profile = UserProfileCache.instance.getCached(userId);
    final name = profile?.bestName ?? 'User $userId';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove member'),
        content: Text('Remove $name from this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade400),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    setState(() => _removingId = userId);

    try {
      final newIds = _participantIds.where((id) => id != userId).toList();

      await SupabaseConfig.client
          .from('conversations')
          .update({'participant_ids': newIds})
          .eq('id', widget.conversationId)
          .select()
          .single();

      setState(() {
        _participantIds = newIds;
        _removingId = '';
      });
      _didUpdate();
    } catch (e) {
      setState(() => _removingId = '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Add member bottom sheet ──────────────────────────────────

  void _showAddMemberSheet() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddMemberPage(
          myUserId: widget.myUserId,
          existingIds: _participantIds,
          onAdd: _addMember,
        ),
      ),
    );
  }

  Future<void> _addMember(UserProfile profile) async {
    if (_participantIds.contains(profile.id)) return;

    final newIds = [..._participantIds, profile.id];

    try {
      await SupabaseConfig.client
          .from('conversations')
          .update({'participant_ids': newIds})
          .eq('id', widget.conversationId)
          .select()
          .single();

      await UserProfileCache.instance.resolve([
        profile.id]);

      setState(() => _participantIds = newIds);
      _didUpdate();

      if (mounted) {
        Navigator.pop(context); // close sheet
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${profile.bestName} added.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.of(context).pop(_participantIds),
        ),
        title: const Text('Group Info'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          // ── Group icon ───────────────────────────────────────
          Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: theme.primaryColor.withOpacity(0.12),
              child: Icon(Icons.group, size: 40, color: theme.primaryColor),
            ),
          ),
          const SizedBox(height: 20),

          // ── Editable name ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: 'Group name',
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _saveName(),
                  ),
                ),
                const SizedBox(width: 8),
                _savingName
                    ? SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.primaryColor,
                        ),
                      )
                    : IconButton.filled(
                        onPressed: _saveName,
                        icon: const Icon(Icons.check_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          Center(
            child: Text(
              '${_participantIds.length} members',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),

          const SizedBox(height: 24),
          const Divider(height: 1),

          // ── Members header ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'MEMBERS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.8,
              ),
            ),
          ),

          // ── Member list ──────────────────────────────────────
          ..._participantIds.map((id) {
            final profile = UserProfileCache.instance.getCached(id);
            final imageUrl = profile?.imageUrl;
            final name = profile?.bestName ?? 'User $id';
            final isMe = id == widget.myUserId;
            final removing = _removingId == id;

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 2,
              ),
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: theme.primaryColor.withOpacity(0.1),
                backgroundImage: imageUrl != null && imageUrl.isNotEmpty
                    ? NetworkImage(imageUrl)
                    : null,
                child: imageUrl == null || imageUrl.isEmpty
                    ? Text(
                        name[0].toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.primaryColor,
                        ),
                      )
                    : null,
              ),
              title: Text(
                isMe ? '$name (You)' : name,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: profile != null
                  ? Text(
                      '@${profile.username}',
                      style: const TextStyle(fontSize: 12),
                    )
                  : null,
              trailing: isMe
                  ? null
                  : removing
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.red.shade400,
                      ),
                    )
                  : IconButton(
                      icon: Icon(
                        Icons.remove_circle_outline,
                        color: Colors.red.shade400,
                      ),
                      onPressed: () => _removeMember(id),
                      tooltip: 'Remove',
                    ),
            );
          }),

          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),

          // ── Add member button ────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: OutlinedButton.icon(
              onPressed: _showAddMemberSheet,
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Add Member'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: theme.primaryColor),
                foregroundColor: theme.primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddMemberSheet extends StatefulWidget {
  final String myUserId;
  final List<String> existingIds;
  final void Function(UserProfile) onAdd;

  const _AddMemberSheet({
    required this.myUserId,
    required this.existingIds,
    required this.onAdd,
  });

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  String _lastQuery = '';
  Timer? _debounce;

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

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Title row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(
                  'Add Member',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Search field
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
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

          // Results
          if (_loading)
            Padding(
              padding: const EdgeInsets.all(24),
              child: CircularProgressIndicator(color: theme.primaryColor),
            )
          else if (_results.isEmpty && _searchController.text.trim().isNotEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No users found.', textAlign: TextAlign.center),
            )
          else if (_results.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Type a name to search...',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.builder(
                shrinkWrap: true,
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
                      vertical: 2,
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    trailing: FilledButton(
                      onPressed: () => widget.onAdd(
                        UserProfile(
                          id: userId,
                          username: username,
                          displayName: name,
                          firstName: '',
                          lastName: '',
                          imageUrl: profileImage,
                        ),
                      ),
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
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
