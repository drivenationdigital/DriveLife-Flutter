import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';

import 'package:drivelife/api/chat_key_api.dart';
import 'package:drivelife/api/cloudflare_images.dart';
import 'package:drivelife/api/moderation_api.dart';
import 'package:drivelife/config/feature_flags.dart';
import 'package:drivelife/services/chat_readiness.dart';
import 'package:drivelife/services/message_crypto.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:drivelife/providers/account_provider.dart';
import 'package:drivelife/widgets/image_viewer_screen.dart';
import 'package:drivelife/widgets/moderation/report_sheet.dart';
import 'package:drivelife/widgets/nav/dl_haptics.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/services/content_filter.dart';
import 'package:drivelife/services/revealed_messages.dart';
import 'package:drivelife/services/supabase_session.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/screens/chat/ChatProfileCache.dart';
import 'package:drivelife/screens/chat/SupabaseClasses.dart';
import 'package:drivelife/screens/chat/widgets/GroupInfo.dart';
import 'package:drivelife/screens/chat/message_actions.dart';
import 'package:drivelife/services/media_compressor.dart';
import 'package:drivelife/widgets/gif/gif_picker.dart';
import 'package:drivelife/services/upload_quality_prefs.dart';
import 'package:drivelife/widgets/share/shared_post_card.dart';
import 'package:drivelife/widgets/share/shared_post_link.dart';
import 'package:drivelife/screens/chat/message_grouping.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

// ConversationPreview used to be declared here as well as in
// ChatList.dart. Nothing in this file referenced it, and two different
// types of the same name in one import graph is a trap worth closing: the
// tile in ChatProfileCache takes the other one, and an accidental use of
// this would have failed with a message about ConversationPreview not
// being assignable to ConversationPreview.

/// The faces in a group, for the naming dialog.
///
/// A Wrap, deliberately. AlertDialog puts its content inside an
/// IntrinsicWidth, and no scrollable can answer an intrinsic-width
/// query — a ListView there throws rather than scrolls. A Row cannot be
/// used either: it has no way to stop, which is how this overflowed by
/// 308 pixels before.
///
/// So: wrap, and draw at most [_max] of them. Nobody recognises a group
/// from its twelfth thumbnail, and the count says what the rest are.
class _MemberPreview extends StatelessWidget {
  const _MemberPreview({required this.members});

  final List<UserProfile> members;

  /// Seven faces, so the grid is two rows at most.
  ///
  /// Four fit across a dialog, and the "+N" tile takes a slot of its
  /// own — so seven plus the counter is exactly eight, and eight is two
  /// full rows with no stray third.
  static const int _max = 7;

  @override
  Widget build(BuildContext context) {
    final shown = members.take(_max).toList();
    final extra = members.length - shown.length;

    return Wrap(
      spacing: 6,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: [
        for (final m in shown)
          SizedBox(
            // Fixed, so one long first name cannot make its column
            // wider than the rest and leave the grid ragged.
            width: 52,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundImage: m.imageUrl != null
                      ? NetworkImage(m.imageUrl!)
                      : null,
                  child: m.imageUrl == null
                      ? Text(_initial(m.bestName))
                      : null,
                ),
                const SizedBox(height: 4),
                Text(
                  m.bestName.split(' ').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),

        if (extra > 0)
          SizedBox(
            width: 52,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.grey.shade200,
                  child: Text(
                    '+$extra',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.black54,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'more',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// The first letter, or a dash.
  ///
  /// bestName falls back to displayName, which can be empty — the
  /// profile cache guards this same call for that reason. Unguarded,
  /// `[0]` on an empty name is a RangeError, and it would fire here
  /// only for a member with no photograph AND no name, which is
  /// exactly the case nobody tests.
  static String _initial(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '–' : trimmed[0].toUpperCase();
  }
}

class GroupNameDialog extends StatefulWidget {
  final List<UserProfile> members;

  const GroupNameDialog({super.key, required this.members});

  @override
  State<GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<GroupNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    // Auto-suggest group name from member names
    final names = widget.members
        .map((m) => m.bestName.split(' ').first)
        .toList();

    // Three names, then a count. Joining all of them gave a twelve-name
    // default for a group of twelve — longer than the field, and not
    // something anybody would keep.
    final suggestion = names.length <= 3
        ? names.join(', ')
        : '${names.take(3).join(', ')} +${names.length - 3}';

    _controller = TextEditingController(text: suggestion);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Scrollable, because the content is not a fixed height: the
      // member preview grows a row at a time, and on a short screen
      // with the keyboard up there was 48 pixels more of it than the
      // dialog had room for.
      //
      // Safe here where a ListView was not. scrollable: true uses a
      // VERTICAL SingleChildScrollView, whose intrinsic width comes
      // from its child — so AlertDialog's IntrinsicWidth still gets an
      // answer.
      scrollable: true,
      title: const Text('Name this group'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Member preview as a WRAP, with a count for the rest.
          //
          // NOT a ListView, and not any other scrollable. AlertDialog
          // wraps its content in IntrinsicWidth, and a viewport throws
          // when asked for an intrinsic dimension — which is why the
          // horizontal list that replaced the overflowing Row crashed
          // the dialog outright. Worse than the overflow it fixed.
          //
          // A Wrap answers intrinsics happily, and capping the number
          // drawn means it cannot grow unbounded either: the first
          // eight faces, then "+5". Nobody identifies a group from the
          // twelfth thumbnail.
          _MemberPreview(members: widget.members),

          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Group name',
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String? conversationId;
  final String myUserId;
  final String? otherUserId;
  final String otherUserName;
  final bool isGroup; // ← NEW
  final String? groupName; // ← NEW
  final List<String> participantIds; // ← NEW

  const ChatScreen({
    super.key,
    this.conversationId,
    required this.myUserId,
    this.otherUserId,
    required this.otherUserName,
    this.isGroup = false,
    this.groupName,
    this.participantIds = const [],
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  /// Parsed shared-post links, keyed by the message content.
  ///
  /// The bubble asks four times while it builds — once to decide whether
  /// to draw a card, once for the card, once for the spacer and once for
  /// the text — and every bubble rebuilds on every scroll frame. A
  /// regex four times per message per frame is work nobody needs.
  ///
  /// Keyed on the content rather than the message id because the content
  /// is what determines the answer, and an edited or deleted message
  /// changes it.
  final Map<String, SharedPostLink?> _sharedPostCache = {};

  /// The DriveLife post this message is sharing, or null.
  SharedPostLink? _sharedPost(String content) {
    return _sharedPostCache.putIfAbsent(
      content,
      () => SharedPostLink.parse(content),
    );
  }

  /// What the bubble should print under the card.
  ///
  /// For a shared post that is the sender's note with the link removed,
  /// so the URL is not repeated underneath a card that already shows
  /// where it goes. For everything else it is the message as sent.
  String _bubbleText(ChatMessage msg) {
    final shared = _sharedPost(msg.content);

    return (shared != null ? shared.note : msg.content).trim();
  }

  ChatNotifier? _notifier;
  List<ChatMessage> _cachedMessages = [];
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  UserProfile? otherProfile; // 1-to-1 only
  Map<String, UserProfile> _groupProfiles = {}; // group only

  /// Everyone in the group, me included, as the conversations row has it.
  ///
  /// The one list. Seeded from the widget so the title bar has something
  /// to draw on the first frame, and replaced by [_refreshGroup] from
  /// then on.
  late List<String> _participants = List.of(widget.participantIds);

  /// Same reasoning for the name, which the info screen can also change.
  late String _groupName = widget.groupName ?? 'Group';

  /// The group's picture. Null until the conversation row has loaded,
  /// and again after that if nobody has set one.
  String? _groupImage;

  /// Everyone but me — the avatar stack, and who needs a profile.
  List<String> get _others =>
      _participants.where((id) => id != widget.myUserId).toList();

  @override
  void initState() {
    super.initState();

    // The key is fetched without blocking this screen, so it can land
    // after the thread has been drawn. decrypt() is synchronous and
    // nothing else would rebuild the list — a realtime event only fires
    // if somebody happens to send something — so without this a thread
    // opened during the very first key fetch would sit there showing
    // base64 until it was closed and reopened.
    MessageCrypto.revision.addListener(_onKeyChanged);

    _init();
  }

  void _onKeyChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    // A thread is reachable without ever opening the inbox — the
    // Message button on a profile, and a tapped push notification both
    // land straight here. The inbox was the only thing applying the
    // Supabase token, so arriving by either of those routes meant
    // talking to PostgREST as anon and subscribing a realtime socket
    // that would never fire.
    //
    // Idempotent: a no-op when the shell or the inbox has already done
    // it, which is the usual case.
    if (mounted) {
      await SupabaseSession.ensure(
        Provider.of<AccountManager>(context, listen: false),
      );
    }

    // Same shape of bug as the token above: the message key was fetched
    // once, at app start, and only if somebody was already signed in.
    // Sign in during a session and there was no key until the next cold
    // start — so a sealed message would have been unreadable on screen
    // for the rest of that run.
    //
    // NOT awaited. This was, on the grounds that decrypt is
    // synchronous and a key arriving late leaves unreadable bubbles —
    // but awaiting it put a network request in front of the thread on
    // the first run after an install, so the messages did not appear
    // until the screen was closed and opened again.
    //
    // MessageCrypto.revision covers the late arrival instead: the
    // listener in initState rebuilds once the key lands.
    unawaited(ChatKeyAPI.load());

    if (!mounted) return;

    _loadBlockedState();

    // Before the first messages arrive, so a message revealed earlier
    // does not flash its warning while the set is still on disk.
    _loadRevealed();

    String convId = widget.conversationId ?? '';
    print(
      convId.isEmpty
          ? 'No conversation ID provided, will attempt to find or create based on otherUserId'
          : 'Conversation ID provided: $convId',
    );

    // ── Show cached messages INSTANTLY before any async work ──
    if (convId.isNotEmpty) {
      final cached = MessageCache.instance.get(convId);
      print('Cached conversation messages for $convId: ${cached?.length ?? 0}');
      if (cached != null && cached.isNotEmpty) {
        setState(() => _cachedMessages = cached.reversed.toList());
      }
    }

    if (convId.isEmpty && widget.otherUserId != null) {
      final conv = await ChatRepository().getOrCreateConversation(
        myUserId: widget.myUserId,
        otherUserId: widget.otherUserId!,
      );
      convId = conv.id;
    }

    // ── FOR TESTING ENCRYPTION ──────────────────────────────────────
    //
    // Says whether this thread will be sealed, which is otherwise
    // invisible: a sealed message looks completely normal to the person
    // who sent it, so without this the only way to tell is to go and
    // look at the row in Supabase.
    if (convId.isNotEmpty && FeatureFlags.encryptChatMessages) {
      // Started here so the first send does not wait on the two queries
      // behind it, and NEVER awaited — nothing on screen depends on the
      // answer, and awaiting it was what stopped a thread loading until
      // it had been closed and reopened. The send path shares the same
      // in-flight future if it gets there first.
      final pending = ChatReadiness.everyoneCanRead(convId);

      if (kDebugMode) {
        unawaited(
          pending.then((bool sealing) {
            debugPrint(
              '[ChatCrypto] conversation $convId — new messages will be '
              '${sealing ? 'SEALED' : 'plaintext'}'
              '${MessageCrypto.ready ? '' : ' (no key loaded)'}',
            );
          }),
        );
      }
    }

    // Resolve profiles
    if (widget.isGroup) {
      _groupProfiles = await UserProfileCache.instance.resolve(_others);

      // And the conversation row itself, for the group's picture.
      //
      // _refreshGroup used to run only when Group Info was opened or
      // closed, so _groupImage was null for the whole first visit — and
      // the picture appeared on the SECOND trip into Group Info and
      // nowhere else, which is exactly how it looked: sometimes.
      unawaited(_refreshGroup());
    } else {
      otherProfile = UserProfileCache.instance.getCached(
        widget.otherUserId ?? '',
      );
    }

    await ChatRepository().markAsRead(convId, widget.myUserId);

    if (!mounted) return;

    setState(() {
      _notifier =
          ChatNotifier(conversationId: convId, myUserId: widget.myUserId)
            ..addListener(_onStateChange)
            ..initialize();
    });
  }

  void _onStateChange() {
    if (mounted && _notifier != null) {
      setState(() {});
      if (_scrollController.hasClients &&
          _scrollController.position.pixels < 200) {
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// A photograph chosen but not yet sent.
  File? _pendingImage;

  /// Messages whose warning the reader has chosen to look past.
  ///
  /// Persisted per account — see [RevealedMessages]. Held here as well
  /// so build() can test membership without awaiting disk.
  Set<String> _revealed = const {};

  /// Remember a reveal, and redraw.
  ///
  /// The set is replaced rather than mutated because it may be the
  /// const empty one from the cache, and because assigning a new set
  /// inside setState is what makes the rebuild honest.
  Future<void> _reveal(ChatMessage msg) async {
    setState(() => _revealed = {..._revealed, msg.id});
    await RevealedMessages.add(widget.myUserId, msg.id);
  }

  Future<void> _loadRevealed() async {
    final revealed = await RevealedMessages.forUser(widget.myUserId);
    if (!mounted) return;

    setState(() => _revealed = revealed);
  }

  /// True while it is on its way to Cloudflare.
  bool _uploading = false;

  /// Message ids that have already been drawn once.
  ///
  /// The entrance animation is for messages that ARRIVE while you are
  /// looking, not for the backlog that was already there when the thread
  /// opened.
  final Set<String> _seen = {};

  /// Whether the opening backlog has been recorded as already seen.
  bool _seeded = false;

  /// The photograph currently uploading, drawn at the bottom of the
  /// thread as a real bubble until the server has a URL for it.
  File? _uploadingImage;

  /// Its caption, so the optimistic bubble reads the way the sent one
  /// will rather than appearing to lose the text and get it back.
  String _uploadingCaption = '';

  Future<void> _pickImage() async {
    // One, and a photograph. pickImage rather than pickMultiImage
    // because a thread is a sequence of messages, and a batch would
    // have to decide whether five pictures are five messages or one.
    //
    // ── NO maxWidth / maxHeight / imageQuality ───────────────────────
    //
    // They used to be 2048/2048/88, and that is what stopped GIFs
    // working: any of the three makes image_picker DECODE the file and
    // re-encode it as a still JPEG. An animated GIF came out as a
    // single frame, and nothing downstream could tell it had ever been
    // one.
    //
    // The compression is done in _send() instead, by MediaCompressor,
    // which already knows that 'gif' is a format Cloudflare takes as it
    // is and passes it through untouched. The rest of the app picks
    // this way for the same reason; chat was the odd one out.
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);

    if (picked == null || !mounted) return;

    setState(() => _pendingImage = File(picked.path));
  }

  /// Pick a GIF and send it, in one step.
  ///
  /// ── NOTHING IS UPLOADED ──────────────────────────────────────────
  ///
  /// A pick is a URL on the provider's own CDN, so it goes straight
  /// into the message's image_url. There is no Cloudflare round trip,
  /// no compression, and no question of animation surviving a
  /// re-encode, because nothing re-encodes it — which is why this is a
  /// completely different path from _pickImage().
  ///
  /// It also sends IMMEDIATELY rather than sitting in the composer like
  /// a chosen photograph. Picking a GIF is already a two-step choice
  /// with a search in the middle; making somebody then press send is a
  /// third, and every other messenger sends on pick.
  ///
  /// Any text already typed goes with it as the caption, so a GIF is
  /// not a way to silently lose a half-written message.
  Future<void> _pickGif() async {
    final picked = await showModalBottomSheet<GifPick>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const GifPicker(),
    );

    if (picked == null || !mounted) return;

    final text = _inputController.text;
    _inputController.clear();

    await _notifier?.sendMessage(text, imageUrl: picked.url);
  }

  /// The file extension, lower-cased and without the dot.
  ///
  /// Cloudflare works out what it has been sent from the filename on
  /// the multipart part, so this has to be the REAL extension. It was
  /// hardcoded to 'jpg', which is the other half of why a GIF could not
  /// survive the trip: even an untouched one arrived announcing itself
  /// as a JPEG.
  String _extensionOf(File file) {
    final name = file.path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');

    if (dot < 0 || dot == name.length - 1) return 'jpg';

    final ext = name.substring(dot + 1).toLowerCase();

    // A closed list, matching MediaCompressor's pass-through set plus
    // the one it transcodes. Anything else is named jpg because that is
    // what the compressor will have turned it into.
    return const {'jpg', 'jpeg', 'png', 'webp', 'gif'}.contains(ext)
        ? ext
        : 'jpg';
  }

  Future<void> _send() async {
    final text = _inputController.text;
    final image = _pendingImage;

    if (text.trim().isEmpty && image == null) return;

    String? url;

    if (image != null) {
      // Into the thread immediately, at the bottom, with a spinner over
      // it — the same moment the tap happens.
      //
      // It used to stay in the composer with the spinner down there
      // while Cloudflare worked, which on a slow connection looked like
      // the send had simply not happened: nothing moved, nothing
      // appeared, and the obvious response is to tap Send again.
      setState(() {
        _uploading = true;
        _uploadingImage = image;
        _uploadingCaption = text.trim();
        _pendingImage = null;
      });
      _inputController.clear();

      // Prepared the way every other upload in the app is prepared.
      //
      // MediaCompressor keeps 'gif' in its pass-through set, so an
      // animated one is handed on byte for byte; a large photograph is
      // re-encoded down to something Cloudflare will accept. Chat used
      // to do neither — image_picker re-encoded everything to JPEG on
      // the way in, which was quietly flattening GIFs.
      final prepared = await MediaCompressor.compressImage(
        image,
        quality: await UploadQualityPrefs.current(),
      );

      if (!mounted) return;

      final ext = _extensionOf(prepared.file);

      // A GIF big enough to miss MediaCompressor's pass-through limit
      // goes down the re-encode ladder, and that ladder writes JPEG —
      // so it arrives as a single frame.
      //
      // Said out loud. Silently turning somebody's animation into a
      // still is exactly the kind of quiet substitution that leaves
      // them wondering whether the app is broken.
      if (_extensionOf(image) == 'gif' && ext != 'gif') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That GIF was too large to animate — sent as a still image.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      url = await CloudflareImages.uploadAndGetUrl(
        bytes: await prepared.file.readAsBytes(),
        // The real extension, because Cloudflare reads the type off
        // this name. Hardcoding .jpg told it a GIF was a JPEG.
        fileName: 'chat_${DateTime.now().microsecondsSinceEpoch}.$ext',
        // Not the default. That one is square, and a photograph of a
        // car is almost never square.
        variant: CloudflareImages.photo,
      );

      if (!mounted) return;

      if (url == null) {
        // Put it back exactly as it was. Sending the text without the
        // photograph would quietly drop the thing the message was
        // about, and losing the caption as well adds insult.
        setState(() {
          _uploading = false;
          _uploadingImage = null;
          _pendingImage = image;
        });
        _inputController.text = text;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not upload that photo.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      setState(() {
        _uploading = false;
        _uploadingImage = null;
      });
    } else {
      _inputController.clear();
    }

    await _notifier?.sendMessage(text, imageUrl: url);
  }

  /// The chosen photograph, above the composer, until it is sent.
  Widget _pendingImageStrip() {
    final image = _pendingImage;

    // AnimatedSize around the whole thing, so picking a photo opens the
    // strip and removing it closes it, instead of the composer jumping
    // 74 pixels taller between two frames.
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: image == null
          ? const SizedBox(width: double.infinity)
          : _pendingImageBody(image),
    );
  }

  /// A message photograph, at a variant that is not a square crop.
  ///
  /// New messages are uploaded at CloudflareImages.photo already. This
  /// is for every one sent before that, whose Supabase row holds a
  /// /thumbnail URL and cannot be rewritten from the app — the same
  /// upload is re-asked for uncropped as it is displayed.
  static String _photoUrl(String stored) =>
      CloudflareImages.asVariant(stored, CloudflareImages.photo) ?? stored;

  Widget _pendingImageBody(File image) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  image,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () => setState(() => _pendingImage = null),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 11,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _uploading ? 'Uploading…' : 'Ready to send',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    MessageCrypto.revision.removeListener(_onKeyChanged);
    _notifier?.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── AppBar ──────────────────────────────────────────────────

  Widget _buildAppBar(ThemeProvider theme) {
    return AppBar(
      titleSpacing: 0,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      // A hairline instead of a shadow. The thread is white and the bar is
      // white; a drop shadow between them is the only thing that would say
      // otherwise, and it reads as heavier than it is.
      shape: const Border(bottom: BorderSide(color: Color(0xFFEFEFEF))),
      foregroundColor: const Color(0xFF111111),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: widget.isGroup ? _buildGroupAppBarTitle() : _buildDmAppBarTitle(),

      // One-to-one only. A group's equivalents live in Group Info,
      // where the member list is — blocking one person out of eight
      // from a bar at the top of the thread would be ambiguous about
      // who.
      actions: widget.isGroup
          ? null
          : [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, size: 22),
                onSelected: (value) {
                  if (value == 'report') _reportPerson();
                  if (value == 'block') _blockPerson();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'report', child: Text('Report')),
                  PopupMenuItem(
                    value: 'block',
                    child: Text(
                      'Block',
                      style: TextStyle(color: Color(0xFFD93025)),
                    ),
                  ),
                ],
              ),
            ],
    );
  }

  /// Report the person on the other end.
  /// Whether I have blocked the person on the other side of this thread.
  ///
  /// Only ever about blocks I made. Whether THEY have blocked me is not
  /// knowable here and should not be — if it were, the thread could show
  /// it, and being told you have been blocked is what provokes the next
  /// account. Their side simply refuses the insert, and the message shows
  /// as failed.
  bool _iBlockedThem = false;

  Future<void> _loadBlockedState() async {
    if (widget.isGroup) return;

    final id = int.tryParse(widget.otherUserId ?? '');
    if (id == null) return;

    final blocked = await ModerationAPI.blockedIds();
    if (!mounted || !blocked.contains(id)) return;

    setState(() => _iBlockedThem = true);
  }

  /// Lift the block from inside the thread.
  ///
  /// The same place it is shown, because somebody who has decided to
  /// undo this should not have to find a settings screen to do it.
  Future<void> _unblockPerson() async {
    final id = int.tryParse(widget.otherUserId ?? '');
    if (id == null) return;

    final ok = await ModerationAPI.unblock(id);
    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not unblock them. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _iBlockedThem = false);
  }

  Future<void> _reportPerson() async {
    final id = widget.otherUserId;
    if (id == null || id.isEmpty) return;

    await ReportSheet.show(
      context,
      subjectType: 'user',
      subjectId: id,
      title: 'Report ${otherProfile?.bestName ?? 'this person'}',
      subjectUserId: int.tryParse(id),
    );
  }

  /// Block them, and leave the thread.
  ///
  /// Leaving is the point: staying in a conversation with somebody you
  /// have just blocked is a screen that cannot do anything useful, and
  /// the silence looks like the block failing.
  Future<void> _blockPerson() async {
    final id = int.tryParse(widget.otherUserId ?? '');
    if (id == null) return;

    final name = otherProfile?.bestName ?? 'this person';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Block $name?'),
        content: const Text(
          'Neither of you will be able to message the other, and you '
          'will stop seeing notifications from them. They are not told.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD93025),
            ),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final ok = await ModerationAPI.block(id);
    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not block them. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.of(context).pop();
  }

  // 1-to-1 title: avatar + name
  /// Open somebody's profile.
  ///
  /// Takes both id and username because the profile screen will find a
  /// person by either, and which one is to hand depends on whether the
  /// profile cache has answered yet.
  void _openProfile({String? userId, String? username}) {
    if ((userId == null || userId.isEmpty) &&
        (username == null || username.isEmpty)) {
      return;
    }

    Navigator.pushNamed(
      context,
      AppRoutes.viewProfile,
      arguments: {'userId': userId, 'username': username ?? ''},
    );
  }

  Widget _buildDmAppBarTitle() {
    final name = otherProfile?.bestName ?? widget.otherUserName;
    final imageUrl = otherProfile?.imageUrl;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    // The whole title, not just the face. In a one-to-one the header
    // IS the other person, so the name should be as live as the avatar —
    // aiming for a 32pt circle to reach a profile is a worse target than
    // the row it sits in.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openProfile(
        userId: widget.otherUserId,
        username: otherProfile?.username,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFFEFEFEF),
            backgroundImage: hasImage ? NetworkImage(imageUrl) : null,
            child: hasImage
                ? null
                : Text(
                    name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // Group title: stacked avatars + group name + member count
  Widget _buildGroupAppBarTitle() {
    final others = _others.take(3).toList();

    return GestureDetector(
      onTap: () async {
        await Navigator.push<List<String>>(
          context,
          MaterialPageRoute(
            builder: (_) => GroupInfoScreen(
              conversationId: widget.conversationId!,
              myUserId: widget.myUserId,
              groupName: _groupName,
              participantIds: _participants,
              groupImage: _groupImage,
              // Fires on each change while the screen is open, so the bar
              // behind it is already right by the time it is popped.
              onChanged: (_, __) => _refreshGroup(),
            ),
          ),
        );

        // And again on the way out, in case the last change landed after
        // the callback -- and because somebody else may have edited the
        // group while that screen was open.
        await _refreshGroup();
      },
      child: Row(
        children: [
          // The group's own picture if it has one, and the members
          // stacked up if it does not. A group that has chosen a photo
          // should be recognised by it here as well as in the list —
          // the stack is a fallback for groups with nothing set, not the
          // group's identity.
          if (_groupImage != null && _groupImage!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: _groupImage!,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    const ColoredBox(color: Color(0xFFEFEFEF)),
                errorWidget: (_, __, ___) =>
                    const ColoredBox(color: Color(0xFFEFEFEF)),
              ),
            )
          else
            SizedBox(
              width: 46,
              height: 36,
              child: Stack(
                children: [
                  for (int i = 0; i < others.length && i < 3; i++)
                    Positioned(
                      left: i * 12.0,
                      child: _buildStackedAvatar(others[i], i),
                    ),
                ],
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _groupName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_participants.length} members · tap for info',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Re-reads the group from the server and rebuilds what depends on it.
  ///
  /// Whole-list, not a patch. Profiles are REPLACED rather than added to,
  /// which is what finally drops a removed member out of the avatar stack
  /// — the old code only ever called addAll, so leaving a group was
  /// invisible here.
  Future<void> _refreshGroup() async {
    if (!widget.isGroup || widget.conversationId == null) return;

    try {
      final conv = await ChatRepository().getConversation(
        widget.conversationId!,
      );

      final profiles = await UserProfileCache.instance.resolve(
        conv.participantIds.where((id) => id != widget.myUserId).toList(),
      );

      if (!mounted) return;

      setState(() {
        _participants = conv.participantIds;
        _groupName = conv.groupName ?? _groupName;
        _groupImage = conv.groupImage;
        _groupProfiles = profiles;
      });
    } catch (e) {
      debugPrint('[Chat] could not refresh group: $e');
    }
  }

  Widget _buildStackedAvatar(String userId, int index) {
    final profile = _groupProfiles[userId];
    final imageUrl = profile?.imageUrl;
    final initial = profile?.bestName.isNotEmpty == true
        ? profile!.bestName[0].toUpperCase()
        : '?';

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: CircleAvatar(
        radius: 16,
        backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
        child: imageUrl == null
            ? Text(initial, style: const TextStyle(fontSize: 12))
            : null,
      ),
    );
  }

  /// One message, drawn as part of a run rather than on its own.
  ///
  /// [startsRun] is the first message of a block from one sender and gets
  /// the name, in a group. [endsRun] is the last and gets the avatar and
  /// the squared-off corner. The ones between get neither, which is what
  /// makes a block read as one turn in a conversation rather than six
  /// separate announcements.
  ///
  /// No timestamp anywhere: the day separator carries the time, the way
  /// Instagram does it.
  Widget _buildBubble(
    ChatMessage msg,
    ThemeProvider theme, {
    required bool startsRun,
    required bool endsRun,
  }) {
    final isMe = msg.senderId == widget.myUserId;
    final showAvatar = widget.isGroup && !isMe;

    // Behind a warning until tapped.
    //
    // Never your own message: you know what you wrote, and a warning on
    // it reads as an accusation rather than a protection. Never a
    // deleted one either — it has no content left to warn about.
    //
    // Two sources agree on this. ContentFilter is the word list on this
    // device, instant and free; msg.isFlagged is the Gemini pass in
    // chat_webhook.php, which lands a beat later and catches what a list
    // cannot. Either one is enough.
    final concealed =
        !isMe &&
        !msg.isDeleted &&
        !_revealed.contains(msg.id) &&
        (msg.isFlagged || ContentFilter.shouldVeil(msg.content));

    /// The shared post this message is, for LAYOUT purposes.
    ///
    /// Null for a deleted or concealed message even when the link is
    /// still in the content: both of those have their own bubble
    /// treatment — a tombstone outline and the veil — and a shared post
    /// must not take it away from them. The flagged one matters: a post
    /// shared with an abusive note should still be veiled.
    final sharedLayout = (msg.isDeleted || concealed)
        ? null
        : _sharedPost(msg.content);

    /// Does this message carry its own surface?
    ///
    /// A photograph and a shared post are both things with edges of
    /// their own — rounded corners, their own background — and a bubble
    /// around either of them is a frame, not a container. On the
    /// sender's side that frame is gold, which tinted the photo's
    /// surround and made the picture look like part of the chrome.
    ///
    /// So both drop the bubble. The caption, where there is one, then
    /// sits under the image as text on the thread's own background,
    /// which is how every other messenger draws it.
    ///
    /// Deleted and concealed are excluded for the same reason as above:
    /// the tombstone outline and the veil are their bubble, and a photo
    /// must not take it away from them.
    final bareBubble =
        sharedLayout != null ||
        (msg.hasImage && !msg.isDeleted && !concealed);

    const round = Radius.circular(20);
    const tail = Radius.circular(5);

    return Padding(
      padding: EdgeInsets.only(top: startsRun ? 10 : 2),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showAvatar) ...[
            // The slot is held whether or not the avatar is drawn, so the
            // bubbles in a block line up instead of stepping sideways.
            SizedBox(
              width: 26,
              height: 26,
              child: endsRun
                  ? _buildSenderAvatar(msg.senderId)
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 8),
          ],

          Flexible(
            child: ConstrainedBox(
              // A share of the width rather than a fixed inset, so a
              // bubble is the same proportion of the screen on any phone.
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.72,
              ),
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (widget.isGroup && !isMe && startsRun)
                    Padding(
                      padding: const EdgeInsets.only(left: 14, bottom: 4),
                      child: Text(
                        _groupProfiles[msg.senderId]?.bestName ??
                            'User ${msg.senderId}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),

                  Opacity(
                    // In flight, and saying so quietly. A spinner on a
                    // bubble that will land in 200ms is more alarming
                    // than the wait it describes.
                    opacity: msg.status == MessageStatus.pending ? 0.55 : 1,
                    child: GestureDetector(
                      // Nothing to do to a message that is not there yet
                      // or has already gone: an optimistic bubble has no
                      // server id to react to, and a tombstone has
                      // nothing to copy.
                      onLongPress:
                          msg.status == MessageStatus.sent && !msg.isDeleted
                          ? () => _showMessageActions(msg)
                          : null,
                      child: Container(
                        // No padding around a shared post. The card is
                        // the message, and 14px of gold around it framed
                        // it rather than containing it.
                        padding: bareBubble
                            ? EdgeInsets.zero
                            : const EdgeInsets.fromLTRB(14, 9, 14, 10),
                        decoration: BoxDecoration(
                          // A concealed message borrows the tombstone's
                          // look — outline, no fill. It is the existing
                          // visual language for "there is something here
                          // you are not being shown", and inventing a
                          // second one would say less.
                          //
                          // A SHARED POST HAS NO BUBBLE EITHER, for a
                          // different reason: it already is a card, with
                          // its own surface, border and corners. Sitting
                          // that inside the gold sender bubble gave it a
                          // thick gold frame and tinted the card to
                          // match — so the thing being shared looked
                          // like part of the chrome rather than content.
                          // This is how Instagram draws one, and it is
                          // why.
                          color: msg.isDeleted || concealed || bareBubble
                              ? Colors.transparent
                              : isMe
                              ? theme.primaryColor
                              : const Color(0xFFEFEFEF),
                          border: msg.isDeleted || concealed
                              ? Border.all(color: const Color(0xFFE0E0E0))
                              : null,
                          borderRadius: BorderRadius.only(
                            topLeft: round,
                            topRight: round,
                            // Only the corner nearest the sender squares off,
                            // and only on the last of a block.
                            bottomLeft: !isMe && endsRun ? tail : round,
                            bottomRight: isMe && endsRun ? tail : round,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: concealed
                              ? [_veilContent(msg)]
                              : [
                                  if (msg.hasImage && !msg.isDeleted) ...[
                                    GestureDetector(
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => ImageViewerScreen(
                                            images: [_photoUrl(msg.imageUrl!)],
                                          ),
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        // A BOX it fits inside, not a width
                                        // it must match.
                                        //
                                        // It was `width: 210` with
                                        // BoxFit.cover and no height. With
                                        // the height free that happens not
                                        // to crop — the image sizes to its
                                        // own ratio and cover has nothing to
                                        // trim — but it meant a tall
                                        // portrait came out 210 wide and
                                        // several hundred tall, filling the
                                        // screen on its own.
                                        //
                                        // maxWidth AND maxHeight with
                                        // contain shows the whole photo
                                        // either way: a wide one is limited
                                        // by the width, a tall one by the
                                        // height, and neither is cut.
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 210,
                                            maxHeight: 280,
                                          ),
                                          child: CachedNetworkImage(
                                            imageUrl: _photoUrl(msg.imageUrl!),
                                            fit: BoxFit.contain,
                                            placeholder: (_, _) => Container(
                                              width: 210,
                                              height: 150,
                                              color: Colors.black12,
                                            ),
                                            errorWidget: (_, _, _) => Container(
                                              width: 210,
                                              height: 150,
                                              color: Colors.black12,
                                              child: const Icon(
                                                Icons.broken_image_outlined,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Only when there is something to
                                    // separate: a photograph sent on its own
                                    // should not carry an empty line.
                                    if (msg.content.trim().isNotEmpty)
                                      const SizedBox(height: 8),
                                  ],

                                  // ── A SHARED POST ────────────────
                                  //
                                  // Recognised from the link in the
                                  // message rather than from a column:
                                  // see SharedPostLink for why it is
                                  // done that way round.
                                  //
                                  // NOT for a deleted message. The
                                  // content is blanked on delete, so
                                  // there is no link left to find — but
                                  // being explicit stops a future change
                                  // to how deletes are stored from
                                  // resurrecting the card.
                                  if (sharedLayout != null) ...[
                                    // onDarkBubble is false now whoever
                                    // sent it: there is no bubble behind
                                    // the card any more, so its own
                                    // light surface and dark text are
                                    // right on both sides.
                                    SharedPostCard(
                                      link: sharedLayout,
                                      onDarkBubble: false,
                                    ),

                                    // Only when they wrote something as
                                    // well. A post sent on its own is
                                    // the card and nothing else.
                                    if (sharedLayout.note.isNotEmpty)
                                      const SizedBox(height: 7),
                                  ],

                                  if (msg.isDeleted ||
                                      _bubbleText(msg).isNotEmpty)
                                    Padding(
                                      // The note needs the inset the
                                      // bubble used to give it. Without
                                      // a bubble it would otherwise sit
                                      // hard against the card's left
                                      // edge and under the thread's own
                                      // margin.
                                      padding: bareBubble
                                          ? const EdgeInsets.fromLTRB(2, 0, 2, 2)
                                          : EdgeInsets.zero,
                                      child: Text(
                                        msg.isDeleted
                                            ? 'This message was deleted'
                                            : _bubbleText(msg),
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          height: 1.35,
                                          fontStyle: msg.isDeleted
                                              ? FontStyle.italic
                                              : FontStyle.normal,
                                          // Dark on a shared post
                                          // whoever sent it — white was
                                          // for the gold bubble, which
                                          // is no longer behind it.
                                          color: msg.isDeleted
                                              ? const Color(0xFF9A9A9A)
                                              : (isMe && !bareBubble)
                                              ? Colors.white
                                              : const Color(0xFF111111),
                                        ),
                                      ),
                                    ),
                                ],
                        ),
                      ),
                    ),
                  ),

                  if (!msg.isDeleted) _reactionRow(msg, isMe: isMe),

                  if (endsRun) _meta(msg, isMe: isMe),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What stands in for a message that has been flagged.
  ///
  /// It does not say what was in it, and it does not quote any of it.
  /// The whole value of a warning is that the reader gets to decide
  /// before seeing it, and a preview hands them the content anyway.
  ///
  /// Tapping View is deliberately the only way through — no "always
  /// show", because the next flagged message is a different message and
  /// consenting to one is not consenting to all of them.
  /// The warning line.
  ///
  /// Says "photo" when there is nothing but a photo, because "this
  /// message may contain nudity" over a hidden picture reads as though
  /// there is text to be found somewhere.
  ///
  /// The reason comes from the server when it is the server that flagged
  /// it. The word list has no reason to give — it knows a word matched,
  /// not what the message is — so the generic line is the honest one.
  String _veilText(ChatMessage msg) {
    final noun = msg.hasImage && msg.content.trim().isEmpty
        ? 'photo'
        : 'message';

    final reason = msg.flagReason?.trim();

    if (reason != null && reason.isNotEmpty) {
      return 'This $noun may contain ${reason.toLowerCase()}';
    }

    return 'This $noun may contain harsh or inappropriate content';
  }

  Widget _veilContent(ChatMessage msg) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 230),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.visibility_off_outlined,
                size: 15,
                color: Color(0xFF9A9A9A),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _veilText(msg),
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.3,
                    color: Color(0xFF6B6B6B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Are you sure you want to view it?',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => _reveal(msg),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: const Color(0xFF111111),
                ),
                child: const Text(
                  'View',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
              // Reporting without reading it first. Somebody should not
              // have to look at something to tell us it should not have
              // been sent.
              TextButton(
                onPressed: () => _reportMessage(msg),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: const Color(0xFFD93025),
                ),
                child: const Text('Report', style: TextStyle(fontSize: 13.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The reactions on a message, if any.
  ///
  /// Tapping one toggles yours, which is the same gesture as picking it
  /// from the long-press row — a reaction already on screen should not
  /// need a menu to join.
  Widget _reactionRow(ChatMessage msg, {required bool isMe}) {
    final summaries = _notifier?.reactionsFor(msg.id) ?? const [];
    if (summaries.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        children: [
          for (final r in summaries)
            GestureDetector(
              onTap: () => _notifier?.toggleReaction(msg.id, r.emoji),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F3F3),
                  borderRadius: BorderRadius.circular(11),
                  // Yours is outlined rather than filled differently:
                  // the emoji is already carrying the colour, and a
                  // second fill makes the row look like two components.
                  border: Border.all(
                    color: r.mine
                        ? const Color(0xFF111111)
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  r.count > 1 ? '${r.emoji} ${r.count}' : r.emoji,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The long-press sheet: a row of emoji, then what can be done.
  Future<void> _showMessageActions(ChatMessage msg) async {
    // Fired here rather than in the GestureDetector so it lands with the
    // sheet, not with whatever Flutter decided a long press was. It is
    // the only confirmation the gesture registered — nothing moves
    // while you are holding still.
    DLHaptics.longPressMenu();

    final canDelete = canDeleteMessage(
      senderId: msg.senderId,
      createdAt: msg.createdAt,
      myUserId: widget.myUserId,
      alreadyDeleted: msg.isDeleted,
    );

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final emoji in kQuickReactions)
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _notifier?.toggleReaction(msg.id, emoji);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const Divider(height: 1),

            ListTile(
              leading: const Icon(Icons.copy_rounded, size: 20),
              title: const Text('Copy'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await Clipboard.setData(ClipboardData(text: msg.content));
              },
            ),

            // Somebody else's message only. Reporting your own is not a
            // thing anybody wants, and the option sitting there invites
            // a mis-tap on the one gesture that should feel deliberate.
            if (msg.senderId != widget.myUserId)
              ListTile(
                leading: const Icon(Icons.flag_outlined, size: 20),
                title: const Text('Report'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _reportMessage(msg);
                },
              ),

            // Offered only inside the delete window — and the window is
            // only enforced by the RLS policy, which this number has to
            // match. See kMessageDeleteWindow.
            if (canDelete)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: Color(0xFFD93025),
                ),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: Color(0xFFD93025)),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deleteMessage(msg);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Report a message, with the conversation around it.
  ///
  /// The twenty messages before it travel with the report. One line out
  /// of a conversation rarely shows what was wrong with it, and the
  /// server keeps the copy — which matters because the message somebody
  /// reports is often the one that gets deleted next.
  Future<void> _reportMessage(ChatMessage msg) async {
    final all = _notifier?.messages ?? const <ChatMessage>[];
    final at = all.indexWhere((m) => m.id == msg.id);

    // `messages` is newest-first, so the ones BEFORE this in the
    // conversation are the ones after it in the list.
    final around = at < 0
        ? <ChatMessage>[msg]
        : all.skip(at).take(20).toList().reversed.toList();

    await ReportSheet.show(
      context,
      subjectType: 'message',
      subjectId: msg.id,
      title: 'Report this message',
      subjectUserId: int.tryParse(msg.senderId),
      messageContext: around
          .map(
            (m) => {
              'id': m.id,
              'sender_id': m.senderId,
              'content': m.content,
              'has_image': m.hasImage,
              'created_at': m.createdAt.toIso8601String(),
            },
          )
          .toList(),
    );
  }

  Future<void> _deleteMessage(ChatMessage msg) async {
    final ok = await _notifier?.deleteMessage(msg) ?? false;
    if (ok || !mounted) return;

    // The database declined. In practice this means the window closed
    // between the menu opening and the tap, or the two clocks disagree —
    // the app would not have offered the option otherwise.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('That message is too old to delete now')),
    );
  }

  /// Time, and what became of the message.
  ///
  /// Only under the last bubble of a run. A time under every bubble turns
  /// a conversation into a log, and the run is already the unit this
  /// screen groups by.
  Widget _meta(ChatMessage msg, {required bool isMe}) {
    const style = TextStyle(fontSize: 11, color: Color(0xFF9A9A9A));

    if (msg.status == MessageStatus.failed) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
        child: InkWell(
          onTap: () => _notifier?.retry(msg),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.error_outline_rounded,
                  size: 13,
                  color: Color(0xFFD93025),
                ),
                SizedBox(width: 4),
                Text(
                  'Not sent. Tap to try again',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFFD93025),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final time = TimeOfDay.fromDateTime(msg.createdAt).format(context);

    final parts = <String>[
      time,
      if (isMe && msg.status == MessageStatus.pending)
        'Sending'
      // Read state for one-to-one only. read_at is a single column on the
      // message, so in a group it is set by whoever opened the thread
      // first — showing "Seen" off it would claim everyone has read
      // something one person glanced at.
      else if (isMe && !widget.isGroup && msg.isRead)
        'Seen',
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 6, right: 6),
      child: Text(parts.join('  ·  '), style: style),
    );
  }

  Widget _buildSenderAvatar(String senderId) {
    final profile = _groupProfiles[senderId];
    final imageUrl = profile?.imageUrl;
    final initial = profile?.bestName.isNotEmpty == true
        ? profile!.bestName[0].toUpperCase()
        : '?';

    return GestureDetector(
      // In a group the face beside a bubble is the only thing naming who
      // said it — the name label only appears on the first of a run — so
      // it is the natural place to tap to find out more about them.
      onTap: () => _openProfile(userId: senderId, username: profile?.username),
      child: CircleAvatar(
        radius: 13,
        backgroundColor: const Color(0xFFEFEFEF),
        backgroundImage: imageUrl != null && imageUrl.isNotEmpty
            ? NetworkImage(imageUrl)
            : null,
        child: imageUrl == null || imageUrl.isEmpty
            ? Text(
                initial,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    // Still connecting. The cached messages are shown meanwhile, and the
    // composer is there but not yet usable — one screen either way, rather
    // than a second copy of it that quietly differs.
    final connecting = _notifier == null;

    final messages = connecting ? _cachedMessages : _notifier!.messages;
    final loading = connecting ? _cachedMessages.isEmpty : _notifier!.loading;

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: _buildAppBar(theme) as PreferredSizeWidget,
      body: Column(
        children: [
          if (!connecting && _notifier!.error != null) _errorBanner(theme),

          // The refresh indicator FLOATS over the list rather than
          // sitting in the Column. In the Column it was a real child
          // with real height, so every background refresh shrank the
          // list and pushed every message down a few pixels, then let
          // them spring back — a visible shove on a screen nobody
          // asked to be interrupted on.
          //
          // Overlaid, it costs the layout nothing and the messages do
          // not move at all.
          Expanded(
            child: Stack(
              children: [
                _messageList(theme, messages, loading),

                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  // Without this the pill would eat taps on the top
                  // message even when it is fully transparent.
                  child: IgnorePointer(
                    child: _refreshingPill(
                      theme,
                      visible: !connecting && _notifier!.refreshing,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // A composer that cannot send is worse than no composer: you
          // type, you tap, and nothing tells you why. So the block
          // replaces it rather than disabling it.
          if (_iBlockedThem)
            _blockedBar(theme)
          else
            _composer(theme, enabled: !connecting),
        ],
      ),
    );
  }

  Widget _errorBanner(ThemeProvider theme) {
    return MaterialBanner(
      content: Text(_notifier!.error!),
      actions: [
        TextButton(
          // Was `() => ()`, which is a function returning an empty record:
          // valid Dart, does nothing, so the banner could not be dismissed.
          onPressed: () => setState(() => _notifier!.clearError()),
          child: const Text('Dismiss'),
        ),
      ],
    );
  }

  /// "Loading new messages", as a pill that floats over the thread.
  ///
  /// Always built, never conditionally inserted — that is the point.
  /// A widget that appears and disappears changes the layout; one that
  /// fades and slides in place does not, and the messages behind it stay
  /// exactly where they were.
  Widget _refreshingPill(ThemeProvider theme, {required bool visible}) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      offset: visible ? Offset.zero : const Offset(0, -1),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: visible ? 1 : 0,
        child: Center(
          child: Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.dividerColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.primaryColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Loading new messages…',
                  style: TextStyle(fontSize: 11, color: theme.subtextColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _messageList(
    ThemeProvider theme,
    List<ChatMessage> messages,
    bool loading,
  ) {
    if (loading) {
      return Center(
        child: CircularProgressIndicator(color: theme.primaryColor),
      );
    }

    if (messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.waving_hand_outlined,
                size: 40,
                color: Colors.grey.shade300,
              ),
              const SizedBox(height: 12),
              Text(
                'No messages yet',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Say hello.',
                style: TextStyle(fontSize: 13.5, color: Colors.grey.shade400),
              ),
            ],
          ),
        ),
      );
    }

    // Everything already on screen the first time round is NOT new, and
    // must not animate. Without this, opening a thread plays an entrance
    // on all fifty messages at once, which looks like a fault rather
    // than a flourish.
    if (!_seeded && messages.isNotEmpty) {
      _seen.addAll(messages.map((m) => m.id));
      _seeded = true;
    }

    // The uploading photograph sits at index 0, which in a reversed list
    // is the bottom — exactly where the message it becomes will land.
    final pending = _uploadingImage != null ? 1 : 0;

    return ListView.builder(
      controller: _scrollController,
      // Newest first: index 0 is the bottom of the screen, so "the message
      // above this one" is i + 1 and "below" is i - 1. Everything about
      // runs and day separators below reads in those terms.
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: messages.length + pending,
      itemBuilder: (context, index) {
        if (pending == 1 && index == 0) {
          return _uploadingBubble(theme);
        }

        final i = index - pending;
        final msg = messages[i];

        final at = runPositionAt<ChatMessage>(
          messages,
          i,
          senderOf: (m) => m.senderId,
          timeOf: (m) => m.createdAt,
        );

        // Only the first sight of a message animates. ListView.builder
        // rebuilds an item every time it scrolls back into view, and
        // without this record a message would play its entrance again
        // on every pass.
        final isNew = _seen.add(msg.id);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // First child is the top of the item, and the list is
            // reversed, so this lands above the message it labels.
            if (at.startsDay) _daySeparator(msg.createdAt),
            _MessageEntrance(
              animate: isNew,
              fromRight: msg.senderId == widget.myUserId,
              child: _buildBubble(
                msg,
                theme,
                startsRun: at.startsRun,
                endsRun: at.endsRun,
              ),
            ),
          ],
        );
      },
    );
  }

  /// The photograph that is still uploading, drawn as the message it is
  /// about to become.
  ///
  /// Deliberately the same shape, side and corner radius as a real
  /// bubble: the point is that nothing jumps when the upload finishes
  /// and the actual message takes its place.
  Widget _uploadingBubble(ThemeProvider theme) {
    final image = _uploadingImage;
    if (image == null) return const SizedBox.shrink();

    return _MessageEntrance(
      animate: true,
      fromRight: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Container(
                // No gold, and no padding, matching what a sent photo
                // now looks like -- see bareBubble in _bubble().
                //
                // This is a SECOND bubble, drawn only while the upload
                // is in flight, and it was left behind when the real
                // one lost its background. The result was a photo that
                // sat in a gold frame until Cloudflare answered and
                // then jumped out of it, which is precisely the jump
                // this widget exists to prevent.
                padding: EdgeInsets.zero,
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.file(image, width: 220, fit: BoxFit.cover),
                          // A scrim under the spinner, because a white
                          // indicator over a white sky is invisible and
                          // the photograph is whatever the user picked.
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.28),
                              ),
                            ),
                          ),
                          const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_uploadingCaption.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 0, 2, 2),
                        child: Text(
                          _uploadingCaption,
                          style: const TextStyle(
                            fontSize: 14.5,
                            height: 1.35,
                            // Dark, like the sent caption. White was for
                            // the gold behind it.
                            color: Color(0xFF111111),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The date, and the time of the first message under it.
  ///
  /// This is the only clock in the thread. Instagram puts it here and
  /// nowhere else, and it is right: a timestamp on every message turns a
  /// conversation into a log, and the one thing anybody actually wants to
  /// know is roughly when a run of messages happened.
  Widget _daySeparator(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(DateTime(dt.year, dt.month, dt.day)).inDays;

    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final String day;
    if (days == 0) {
      day = 'Today';
    } else if (days == 1) {
      day = 'Yesterday';
    } else if (days < 7) {
      const names = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      day = names[dt.weekday - 1];
    } else if (dt.year == now.year) {
      day = '${dt.day} ${months[dt.month - 1]}';
    } else {
      day = '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Center(
        child: Text(
          '$day  ${_formatTime(dt)}',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500,
          ),
        ),
      ),
    );
  }

  /// The one input bar.
  ///
  /// [enabled] is false while the socket is still connecting — the field
  /// greys out, rather than the whole composer being a different widget
  /// that happens to look similar. It used to be exactly that, and the two
  /// had drifted: the loading one had no send button at all, so the bar
  /// changed shape the moment the connection landed.
  /// What sits where the composer was, once you have blocked them.
  ///
  /// States the consequence in both directions, because "blocked" on its
  /// own leaves people unsure which way it runs — plenty of users assume
  /// blocking someone still lets them send one last message.
  Widget _blockedBar(ThemeProvider theme) {
    final name = otherProfile?.bestName ?? 'this person';

    return Container(
      // Explicit, because the Column above lays its children out centred
      // rather than stretched — without this the fill and the top border
      // stop at the width of the longest line, which reads as a stray
      // grey box rather than as the bar that replaced the composer.
      // _composer only avoids this by accident: the Expanded inside its
      // Row forces it wide.
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAFA),
        border: Border(top: BorderSide(color: Color(0xFFEFEFEF))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'You blocked $name',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111111),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Neither of you can message the other.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: _unblockPerson,
                child: Text(
                  'Unblock',
                  // The app's accent, not a blue invented for this one
                  // button — it was the only 0xFF0A66FF in the codebase.
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composer(ThemeProvider theme, {required bool enabled}) {
    final sending = _notifier?.sending ?? false;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEFEFEF))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pendingImageStrip(),
            Padding(
              // Tighter than it was (12,8,12,8). Two icon buttons at
              // Material's default 48x48 plus this padding pushed the
              // field a quarter of the way across a 360dp screen before
              // it started -- see the compact constraints below.
              padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
              child: Row(
                // centre, not end. The icons and a single-line field are
                // the same height, so `end` only mattered once the field
                // grew -- and then it pinned the icons to the bottom of a
                // five-line box, which is where the row looked unbalanced.
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Only one photograph travels with a message, so the
                  // button goes away once there is one waiting rather than
                  // silently replacing it.
                  if (_pendingImage == null)
                    IconButton(
                      onPressed: enabled && !_uploading ? _pickImage : null,
                      // 44 square: Apple's minimum touch target, and the
                      // smallest this can be without being hard to hit.
                      // The default is 48 plus 8 of padding each side.
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.photo_outlined,
                        size: 23,
                        color: enabled
                            ? const Color(0xFF666666)
                            : Colors.grey.shade300,
                      ),
                      tooltip: 'Send a photo',
                    ),

                  // The same picker comments use, from
                  // widgets/gif/gif_picker.dart.
                  //
                  // Hidden while a photograph is waiting, like the
                  // button above and for the same reason: one piece of
                  // media per message, so offering a second way to
                  // attach one would only raise the question of which
                  // wins.
                  if (_pendingImage == null)
                    IconButton(
                      onPressed: enabled && !_uploading ? _pickGif : null,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.gif_box_outlined,
                        size: 25,
                        color: enabled
                            ? const Color(0xFF666666)
                            : Colors.grey.shade300,
                      ),
                      tooltip: 'Send a GIF',
                    ),

                  // One gap, here, rather than relying on each button's
                  // own padding to make it. Four invisible paddings
                  // adding up is why the spacing read as arbitrary.
                  const SizedBox(width: 4),

                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      enabled: enabled,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 5,
                      style: const TextStyle(fontSize: 14.5, height: 1.35),
                      // Rebuilds on every keystroke so the send button can
                      // appear the moment there is something to send.
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: enabled ? 'Message…' : 'Connecting…',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        // A bordered pill rather than a filled box: against a
                        // white thread the fill read as another bubble.
                        filled: false,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(
                            color: Color(0xFFDBDBDB),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(color: theme.primaryColor),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(
                            color: Color(0xFFEFEFEF),
                          ),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: (_) => enabled ? _send() : null,
                    ),
                  ),

                  // Only once there is something to send. An always-on send
                  // button on an empty field is a button that does nothing.
                  //
                  // A waiting photograph counts as something to send. Both
                  // _send() and the notifier already treat an image with no
                  // caption as a message — this button was the only thing
                  // that disagreed, so attaching a photo and sending it on
                  // its own left you with nothing to tap.
                  //
                  // It now grows in rather than appearing between one
                  // frame and the next. AnimatedSwitcher also means the
                  // swap to the spinner on send is a crossfade instead
                  // of a flicker, and the SizeTransition stops the text
                  // field snapping narrower as it goes.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SizeTransition(
                        axis: Axis.horizontal,
                        sizeFactor: animation,
                        axisAlignment: -1,
                        child: ScaleTransition(scale: animation, child: child),
                      ),
                    ),
                    child: sending
                        ? const Padding(
                            key: ValueKey('sending'),
                            padding: EdgeInsets.fromLTRB(12, 0, 4, 10),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : (enabled &&
                              (_inputController.text.trim().isNotEmpty ||
                                  _pendingImage != null))
                        ? TextButton(
                            key: const ValueKey('send'),
                            onPressed: _send,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 42),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              foregroundColor: theme.primaryColor,
                            ),
                            child: const Text(
                              'Send',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        // A keyed empty box, so the switcher has
                        // something to animate OUT to rather than the
                        // child simply vanishing.
                        : const SizedBox(key: ValueKey('idle'), height: 42),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// The way a message arrives.
///
/// iOS does not pop a bubble into place: it eases up from under the
/// composer, growing from slightly small to full size while it fades in.
/// The whole thing takes about a fifth of a second and the curve
/// decelerates, which is what makes it read as the message settling
/// rather than as an animation playing.
///
/// [animate] false renders the child directly with no wrapper state and
/// no controller, so the backlog of a freshly opened thread costs
/// nothing.
class _MessageEntrance extends StatefulWidget {
  final Widget child;

  /// Whether this is the first time the message has been drawn.
  final bool animate;

  /// Yours comes up the right-hand side, theirs the left. A small
  /// horizontal offset is most of what sells it as having come FROM the
  /// composer rather than simply appearing.
  final bool fromRight;

  const _MessageEntrance({
    required this.child,
    required this.animate,
    required this.fromRight,
  });

  @override
  State<_MessageEntrance> createState() => _MessageEntranceState();
}

class _MessageEntranceState extends State<_MessageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 260),
    vsync: this,
  );

  late final Animation<double> _eased = CurvedAnimation(
    parent: _controller,
    // easeOutBack overshoots very slightly, which is the difference
    // between a bubble that lands and one that slides to a halt.
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();

    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) return widget.child;

    return AnimatedBuilder(
      animation: _eased,
      // Built once and reused: the child does not depend on the
      // animation, only the transforms wrapped around it do, so
      // rebuilding it on every frame would be wasted work.
      child: widget.child,
      builder: (context, child) {
        final t = _eased.value;

        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(
              (widget.fromRight ? 18 : -18) * (1 - t),
              14 * (1 - t),
            ),
            child: Transform.scale(
              scale: 0.88 + (0.12 * t),
              // From the bottom corner it came from, not the middle —
              // growing from the centre looks like a zoom, growing from
              // the corner looks like it arrived.
              alignment: widget.fromRight
                  ? Alignment.bottomRight
                  : Alignment.bottomLeft,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
