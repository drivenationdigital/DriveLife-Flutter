import 'package:drivelife/api/posts_api.dart';
import 'package:flutter/material.dart';

class LikesModal extends StatefulWidget {
  final String postId;

  const LikesModal({super.key, required this.postId});

  @override
  State<LikesModal> createState() => _LikesModalState();
}

class _LikesModalState extends State<LikesModal> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _users = [];

  // 🔁 Replace with real API call later
  static const _dummyUsers = [
    {
      'id': 1,
      'display_name': 'James Whitmore',
      'username': 'jwhitmore',
      'profile_image': 'https://i.pravatar.cc/150?img=1',
    },
    {
      'id': 2,
      'display_name': 'Sofia Reyes',
      'username': 'sofiareyes',
      'profile_image': 'https://i.pravatar.cc/150?img=2',
    },
    {
      'id': 3,
      'display_name': 'Marcus Lane',
      'username': 'marcuslane',
      'profile_image': 'https://i.pravatar.cc/150?img=3',
    },
    {
      'id': 4,
      'display_name': 'Priya Nair',
      'username': 'priyanair',
      'profile_image': 'https://i.pravatar.cc/150?img=4',
    },
    {
      'id': 5,
      'display_name': 'Tom Bridges',
      'username': 'tombridges',
      'profile_image': 'https://i.pravatar.cc/150?img=5',
    },
    {
      'id': 6,
      'display_name': 'Elena Voss',
      'username': 'elenavoss',
      'profile_image': 'https://i.pravatar.cc/150?img=6',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadLikes();
  }

  Future<void> _loadLikes() async {
    final users = await PostsAPI.loadLikes(
      postId: widget.postId,
    );
    if (!mounted) return;
    setState(() {
      _users = users;
      _isLoading = false;
    });
  }


  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                const Text(
                  'Liked by',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                if (!_isLoading) ...[
                  const SizedBox(width: 6),
                  Text(
                    '${_users.length}',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 1),

          // Content
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (_users.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Text(
                'No likes yet',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _users.length,
                itemBuilder: (context, index) {
                  final user = _users[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    leading: CircleAvatar(
                      radius: 22,
                      backgroundImage: user['profile_image'] != null
                          ? NetworkImage(user['profile_image'])
                          : null,
                      backgroundColor: Colors.grey.shade200,
                      child: user['profile_image'] == null
                          ? const Icon(Icons.person, color: Colors.grey)
                          : null,
                    ),
                    title: Text(
                      user['display_name'] ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      '@${user['username']}',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(
                        context,
                        '/view-profile',
                        arguments: {
                          'userId': user['id'],
                          'username': user['username'],
                        },
                      );
                    },
                  );
                },
              ),
            ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}
