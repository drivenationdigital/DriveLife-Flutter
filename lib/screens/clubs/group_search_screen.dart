import 'dart:async';

import 'package:drivelife/api/club_api_service.dart';
import 'package:drivelife/api/global_groups_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/screens/clubs/groups_screen.dart' show GroupSummary;
import 'package:drivelife/theme/dl_type.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/clubs/global_group_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Search results for communities and clubs, on their own page.
///
/// This used to happen in place: typing in the box on the groups screen
/// replaced everything below it, which meant the results shared a
/// scroll with the thing they had replaced and there was no way back
/// except clearing the field.
///
/// It also only ever searched CLUBS — `fetchClubs(search: ...)` — while
/// the empty state said "No groups match", which is the sort of thing
/// nobody notices until they search for a group by name and are told it
/// does not exist.
///
/// Both halves are searched now, in parallel, and kept apart under
/// their own headings. A community and a club are different things and
/// a merged list would make somebody read each row to work out which
/// they were looking at.
class GroupSearchScreen extends StatefulWidget {
  const GroupSearchScreen({super.key, required this.query});

  /// What was typed on the screen before this one. The field here opens
  /// with it, so the first thing somebody sees is their own search
  /// rather than an empty box.
  final String query;

  @override
  State<GroupSearchScreen> createState() => _GroupSearchScreenState();
}

class _GroupSearchScreenState extends State<GroupSearchScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );

  Timer? _debounce;

  List<GroupSummary> _groups = const [];
  List<GroupSummary> _clubs = const [];
  bool _searching = true;

  /// Which half, if either, could not be reached.
  ///
  /// Tracked so a failure can SAY so. Without it a search that half
  /// worked looks identical to one where that half genuinely had no
  /// matches — and "no clubs called Audi" is a very different answer
  /// from "we could not ask".
  bool _groupsFailed = false;
  bool _clubsFailed = false;

  /// What the visible results are FOR.
  ///
  /// Held separately from the field so a slower response cannot land on
  /// top of a newer one — see the check in [_run].
  String _shown = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _run(widget.query);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();

    final query = _controller.text.trim();

    if (query.isEmpty) {
      setState(() {
        _groups = const [];
        _clubs = const [];
        _searching = false;
        _shown = '';
      });
      return;
    }

    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(query));
  }

  /// The communities half, which never throws.
  ///
  /// The try/catch is INSIDE the async body on purpose: that is what
  /// makes the returned future safe to hold before awaiting it. A
  /// catch wrapped around the await instead would be too late — the
  /// error fires when the request fails, not when somebody looks.
  Future<List<GlobalGroup>> _searchGroups(String query) async {
    try {
      return await GlobalGroupsApi.fetchGroups(search: query, perPage: 20);
    } catch (e) {
      debugPrint('[Search] groups failed: $e');
      _groupsFailed = true;
      return const [];
    }
  }

  /// The clubs half, which never throws either.
  Future<List<dynamic>> _searchClubs(String query) async {
    try {
      return await ClubApiService.fetchClubs(search: query, perPage: 20) ??
          const [];
    } catch (e) {
      debugPrint('[Search] clubs failed: $e');
      _clubsFailed = true;
      return const [];
    }
  }

  Future<void> _run(String query) async {
    query = query.trim();

    if (query.isEmpty) return;

    // Per search, not for the life of the screen: one failed request
    // should not leave every later one wearing its error.
    _groupsFailed = false;
    _clubsFailed = false;

    // Both START together, each catching its OWN failure.
    //
    // This matters more than it looks. Both API methods rethrow, and
    // the clubs request was being created before the groups one was
    // awaited — so when it failed, nothing was listening yet and it
    // became an UNHANDLED async error: an exception dialog, and then
    // the same error again when the await reached it, taking the
    // groups half down with it.
    //
    // A connection reset is a thing that happens. One source being
    // unreachable should cost its own half of the results and nothing
    // else.
    final groupsRequest = _searchGroups(query);
    final clubsRequest = _searchClubs(query);

    final rawGroups = await groupsRequest;
    final rawClubs = await clubsRequest;

    // Dropped if the box has moved on. Two keystrokes in flight finish
    // in whatever order the network decides, and the slower one must
    // not land on top of the newer answer.
    if (!mounted || _controller.text.trim() != query) return;

    final groups = rawGroups.map(GroupSummary.fromGlobalGroup).toList();

    // The shared parser, not a second copy of it. The one here read
    // only a lowercase 'id' — and the endpoint sends 'ID' — so every
    // club came back with an empty id, failed the check and vanished
    // without an error. Search listed groups only, and looked like it
    // was never asking.
    final clubs = rawClubs
        .whereType<Map>()
        .map(GroupSummary.fromClubRow)
        .whereType<GroupSummary>()
        .toList();

    // Biggest first, like every other list on these screens.
    groups.sort((a, b) => b.memberCount.compareTo(a.memberCount));
    clubs.sort((a, b) => b.memberCount.compareTo(a.memberCount));

    setState(() {
      _groups = groups;
      _clubs = clubs;
      _searching = false;
      _shown = query;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final empty = _groups.isEmpty && _clubs.isEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            controller: _controller,
            autofocus: widget.query.isEmpty,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search groups and clubs',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: _controller.clear,
                    ),
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ),
      ),
      body: _searching
          ? Center(
              child: CircularProgressIndicator(
                color: theme.primaryColor,
                strokeWidth: 2.5,
              ),
            )
          : empty
          ? _nothing(theme)
          : ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                // Communities first. They are national and the more
                // likely answer to a name typed into a search box; a
                // club is usually found by where it is.
                if (_groups.isNotEmpty) ...[
                  _heading(theme, 'Communities', _groups.length),
                  for (final group in _groups) _row(theme, group),
                ],

                if (_clubs.isNotEmpty) ...[
                  _heading(theme, 'Clubs', _clubs.length),
                  for (final club in _clubs) _row(theme, club),
                ],

                // Said out loud. A half that could not be reached is
                // not a half with no matches, and showing nothing for
                // both reads as the second.
                if (_clubsFailed) _halfFailed(theme, 'clubs'),
                if (_groupsFailed) _halfFailed(theme, 'communities'),
              ],
            ),
    );
  }

  /// Open whichever kind this is.
  ///
  /// The same rule groups_screen uses, and for the same reason: a club
  /// id and a group id are both bare integers from different tables, so
  /// group 42 and club 42 both exist. Only a global group has a slug,
  /// and that is what tells them apart.
  void _open(GroupSummary item) {
    if (item.isGlobal) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GlobalGroupScreen(slug: item.slug)),
      );
      return;
    }

    // Checked here rather than left to the route: AppRoutes.clubDetail
    // does int.parse on what it is handed and throws on anything else.
    if (int.tryParse(item.id) == null) {
      debugPrint('[Search] ${item.title} has a non-numeric id: ${item.id}');
      return;
    }

    Navigator.pushNamed(
      context,
      AppRoutes.clubDetail,
      arguments: {'clubId': item.id},
    );
  }

  /// One source could not be reached.
  Widget _halfFailed(ThemeProvider theme, String what) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 18, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Could not search $what.',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ),
          TextButton(
            onPressed: () => _run(_controller.text),
            child: Text(
              'Retry',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: theme.primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heading(ThemeProvider theme, String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: DlHeading(title, fontSize: 22, color: theme.textColor),
          ),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(ThemeProvider theme, GroupSummary item) {
    return InkWell(
      // isGlobal is the only thing that tells the two apart: a club id
      // and a group id are both small integers from different tables,
      // and only a global group has a slug.
      onTap: () => _open(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: item.image == null
                    ? Container(
                        color: const Color(0xFFEFEFEF),
                        child: Icon(
                          Icons.groups_2_outlined,
                          color: Colors.grey.shade400,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: item.image!,
                        fit: BoxFit.cover,
                        // Drawn at 56.
                        memCacheWidth: 180,
                        errorWidget: (_, _, _) => Container(
                          color: const Color(0xFFEFEFEF),
                          child: Icon(
                            Icons.groups_2_outlined,
                            color: Colors.grey.shade400,
                          ),
                        ),
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
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: theme.textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.memberCount} members',
                    style: TextStyle(fontSize: 13, color: theme.subtextColor),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _nothing(ThemeProvider theme) {
    // Centred in the page, not pinned 60 pixels from the top of it.
    //
    // A Column fills the height it is given and stacks from the top,
    // so this sat high and looked left of centre against the wide
    // empty space below it. Center with a min-height Column puts it
    // in the middle of what is actually empty.
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 54, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            Text(
              _shown.isEmpty
                  ? 'Search for a community or a club'
                  : (_groupsFailed && _clubsFailed)
                  ? 'Could not search just now.'
                  : 'Nothing matches “$_shown”',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
