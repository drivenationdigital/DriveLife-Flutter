import 'package:drivelife/models/search_view_model.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:fluttertagger/fluttertagger.dart';
import 'package:provider/provider.dart';

class UserListView extends StatelessWidget {
  const UserListView({
    Key? key,
    required this.tagController,
    required this.animation,
  }) : super(key: key);

  final FlutterTaggerController tagController;
  final Animation<Offset> animation;

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: captionSearchViewModel.users,
      builder: (_, users, __) {
        if (users.isEmpty) {
          return ValueListenableBuilder<bool>(
            valueListenable: captionSearchViewModel.loading,
            builder: (_, loading, __) {
              if (loading) {
                return Container(
                  height: 200,
                  color: theme.backgroundColor,
                  child: Center(
                    child: CircularProgressIndicator(color: theme.primaryColor),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          );
        }

        return Container(
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final profileImage = user['image'];

              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 18,
                  backgroundImage:
                      profileImage != null && profileImage != 'search_q'
                      ? NetworkImage(profileImage)
                      : null,
                  backgroundColor: Colors.grey.shade300,
                  child: profileImage == null || profileImage == 'search_q'
                      ? const Icon(Icons.person, size: 18, color: Colors.black12,)
                      : null,
                ),
                title: Text(
                  user['name'] ?? 'Unknown',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  tagController.addTag(
                    id: user['entity_id'].toString(),
                    name: user['name'] ?? 'Unknown',
                  );
                  captionSearchViewModel.users.value = [];
                  captionSearchViewModel.activeView.value =
                      SearchResultView.none;
                },
              );
            },
          ),
        );
      },
    );
  }
}

class HashtagListView extends StatelessWidget {
  const HashtagListView({
    Key? key,
    required this.tagController,
    required this.animation,
  }) : super(key: key);

  final FlutterTaggerController tagController;
  final Animation<Offset> animation;

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return ValueListenableBuilder<List<String>>(
      valueListenable: captionSearchViewModel.hashtags,
      builder: (_, hashtags, __) {
        if (hashtags.isEmpty) return const SizedBox.shrink();

        return Container(
          constraints: const BoxConstraints(
            maxHeight: 10,
          ), // fits exactly 1 row
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListView.builder(
            shrinkWrap: true,
            scrollDirection: Axis.horizontal, // horizontal pill list
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: hashtags.length,
            itemBuilder: (context, index) {
              final hashtag = hashtags[index];

              return GestureDetector(
                onTap: () {
                  tagController.addTag(id: hashtag, name: hashtag);
                  captionSearchViewModel.hashtags.value = [];
                  captionSearchViewModel.activeView.value =
                      SearchResultView.none;
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: theme.primaryColor.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.tag_rounded,
                        size: 14,
                        color: theme.primaryColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        hashtag,
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class SearchResultOverlay extends StatelessWidget {
  const SearchResultOverlay({
    Key? key,
    required this.tagController,
    required this.animation,
  }) : super(key: key);

  final FlutterTaggerController tagController;
  final Animation<Offset> animation;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SearchResultView>(
      valueListenable: captionSearchViewModel.activeView,
      builder: (_, view, __) {
        if (view == SearchResultView.users) {
          return UserListView(
            tagController: tagController,
            animation: animation,
          );
        }
        if (view == SearchResultView.hashtag) {
          return HashtagListView(
            tagController: tagController,
            animation: animation,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
