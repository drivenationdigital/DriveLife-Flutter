import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/global_groups_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/clubs/global_group_screen.dart';
import 'package:drivelife/widgets/groups/group_chrome.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Every group of one or more kinds, paginated.
///
/// Behind the "See all" on the groups page, which shows six. Six is a
/// taster; this is the catalogue, and it is a plain paged list because
/// somebody who got here is looking for something specific rather than
/// browsing what we chose to put in front of them.
class GroupBrowseScreen extends StatefulWidget {
  const GroupBrowseScreen({
    super.key,
    required this.title,
    required this.kinds,
  });

  final String title;

  /// 'scene', or 'marque' and 'model' together — the same pairing the
  /// groups page uses, because they share a section there too.
  final List<String> kinds;

  @override
  State<GroupBrowseScreen> createState() => _GroupBrowseScreenState();
}

class _GroupBrowseScreenState extends State<GroupBrowseScreen> {
  static const int _pageSize = 20;

  final ScrollController _scroll = ScrollController();
  final List<GlobalGroup> _groups = [];

  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadFirst();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// Fetch the next page a screenful before the end, so the list has
  /// usually grown by the time somebody reaches the bottom.
  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore || _exhausted) return;

    final position = _scroll.position;

    if (position.pixels < position.maxScrollExtent - 600) return;

    _loadMore();
  }

  Future<void> _loadFirst() async {
    final groups = await GlobalGroupsApi.fetchGroups(
      kinds: widget.kinds,
      page: 1,
      perPage: _pageSize,
    );

    if (!mounted) return;

    setState(() {
      _groups
        ..clear()
        ..addAll(groups);
      _page = 1;
      _loading = false;
      // A short page is the last page. Saves a request that returns
      // nothing, which is otherwise guaranteed on every exact multiple.
      _exhausted = groups.length < _pageSize;
    });
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);

    final next = _page + 1;

    final groups = await GlobalGroupsApi.fetchGroups(
      kinds: widget.kinds,
      page: next,
      perPage: _pageSize,
    );

    if (!mounted) return;

    setState(() {
      _groups.addAll(groups);
      _page = next;
      _loadingMore = false;
      _exhausted = groups.length < _pageSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        title: Text(
          widget.title,
          style: TextStyle(fontWeight: FontWeight.w800, color: theme.textColor),
        ),
      ),
      body: _loading
          ? const SingleChildScrollView(child: GroupRowsSkeleton(count: 8))
          : _groups.isEmpty
          ? Center(
              child: Text(
                'Nothing here yet.',
                style: TextStyle(color: theme.subtextColor),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadFirst,
              child: ListView.separated(
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 40),
                itemCount: _groups.length + (_exhausted ? 0 : 1),
                separatorBuilder: (_, _) => Padding(
                  padding: const EdgeInsets.only(left: 92, right: 16),
                  child: Divider(height: 1, color: theme.dividerColor),
                ),
                itemBuilder: (_, i) {
                  if (i >= _groups.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 22),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  return _row(theme, _groups[i]);
                },
              ),
            ),
    );
  }

  Widget _row(ThemeProvider theme, GlobalGroup group) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GlobalGroupScreen(slug: group.slug, initial: group),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 64,
                height: 48,
                child: (group.image ?? '').isEmpty
                    ? Container(
                        color: theme.cardColor,
                        child: Icon(
                          Icons.groups_outlined,
                          color: theme.subtextColor,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: group.image!,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) =>
                            Container(color: theme.cardColor),
                      ),
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    group.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                      color: theme.textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    group.isMember
                        ? 'Joined · ${_members(group.memberCount)}'
                        : _members(group.memberCount),
                    style: TextStyle(fontSize: 14, color: theme.subtextColor),
                  ),
                ],
              ),
            ),

            Icon(Icons.chevron_right, color: theme.subtextColor),
          ],
        ),
      ),
    );
  }

  /// "188 members", "3.2k members".
  String _members(int n) {
    if (n < 1000) return '$n member${n == 1 ? '' : 's'}';

    final thousands = n / 1000;

    final label = thousands >= 10
        ? '${thousands.round()}k'
        : '${thousands.toStringAsFixed(1)}k';

    return '$label members';
  }
}
