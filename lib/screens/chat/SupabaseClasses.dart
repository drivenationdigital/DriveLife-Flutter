import 'dart:convert';
import 'package:drivelife/screens/chat/ChatList.dart';
import 'package:drivelife/screens/chat/ChatProfileCache.dart';
import 'package:drivelife/screens/chat/message_actions.dart';
import 'package:drivelife/screens/chat/models.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:drivelife/config/app_environment.dart';

class AppConfig {
  static String get wpBaseUrl => AppEnvironment.wordpressBase;

  // Supabase project details
  // Found at: Supabase Dashboard → Settings → API
  static const supabaseUrl = 'https://hekpfyxiduypovcvwffm.supabase.co';
  // Safe to expose, but only because of something that lives elsewhere:
  // this key gets you to PostgREST, and the only thing standing between it
  // and every row of every table in `public` is row level security. The
  // day a table ships without RLS, this key is that table's contents.
  //
  // That is not hypothetical — public.message_reads shipped without it and
  // was readable by anyone holding this string, which is everyone who has
  // installed the app. See supabase/sql/message-reads-rls.sql.
  //
  // So: new table in Supabase, new policy, every time.
  static const supabaseAnonKey =
      'sb_publishable_HSLwe3eiV6K_DCfgCwfSLw_YUM5HQ9F';
}

class SupabaseConfig {
  static bool _started = false;

  /// Whether [initialize] has run. Everything that touches [client] has to
  /// wait for this: Supabase.instance throws rather than returning null,
  /// and the field initialisers on ChatRepository and InboxNotifier read
  /// it at construction, so an un-initialised Supabase takes those down
  /// before their first method is called.
  static bool get isReady => _started;

  /// Safe to call more than once.
  ///
  /// Supabase.initialize throws if it has already run, and this is called
  /// both from main() and, defensively, from the inbox -- which has to
  /// cope with main()'s attempt having failed.
  static Future<void> initialize() async {
    if (_started) return;

    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );

    _started = true;
  }

  static SupabaseClient get client => Supabase.instance.client;
}

/// What `/myapp/v1/supabase-token` hands back.
///
/// A named type with its own parsing, so the shapes it accepts can be
/// tested without an HTTP call. That matters here: this payload was read
/// with `data['user_id'] as String` while the endpoint sends user_id as a
/// JSON *number*, so the cast threw every single time and took the whole
/// of messaging down with it.
///
/// Nothing surfaced, because the only caller was
/// `fetchAndStore(...).then(...)` with no catch: the throw became an
/// unhandled async error, the inbox notifier was never built, and the
/// screen sat on a spinner that could not finish.
///
/// Coerced rather than cast, in both directions. Which of these arrive as
/// numbers and which as strings is the server's business, and it has
/// already changed its mind once.
class SupabaseCredentials {
  final String token;
  final int expiresAt;
  final String userId;

  const SupabaseCredentials({
    required this.token,
    required this.expiresAt,
    required this.userId,
  });

  factory SupabaseCredentials.fromJson(Map<String, dynamic> json) {
    final token = json['token'];
    if (token is! String || token.isEmpty) {
      throw FormatException('supabase-token: no token in $json');
    }

    final rawExpiry = json['expires_at'];
    final expiresAt = rawExpiry is int ? rawExpiry : int.tryParse('$rawExpiry');
    if (expiresAt == null) {
      throw FormatException('supabase-token: bad expires_at "$rawExpiry"');
    }

    final rawUserId = json['user_id'];
    if (rawUserId == null || '$rawUserId'.isEmpty) {
      throw FormatException('supabase-token: no user_id in $json');
    }

    return SupabaseCredentials(
      token: token,
      expiresAt: expiresAt,
      userId: '$rawUserId',
    );
  }
}

class SupabaseTokenManager {
  static const _tokenKey = 'supabase_token';
  static const _expiresAtKey = 'supabase_token_expires_at';
  static const _userIdKey = 'supabase_user_id';

  // Call this right after the user logs in to WordPress.
  // Pass in the WordPress JWT your app already has.
  static Future<void> fetchAndStore(String wordpressJwt) async {
    final response = await http.post(
      Uri.parse('${AppConfig.wpBaseUrl}/wp-json/myapp/v1/supabase-token'),
      headers: {
        'Authorization': 'Bearer $wordpressJwt',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to get Supabase token: ${response.body}');
    }

    final creds = SupabaseCredentials.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );

    // Cache locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, creds.token);
    await prefs.setInt(_expiresAtKey, creds.expiresAt);
    await prefs.setString(_userIdKey, creds.userId);

    // Tell Supabase to use this token for all future requests
    await _applyToken(creds.token);
  }

  // Call this at app startup to restore session
  static Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final expiresAt = prefs.getInt(_expiresAtKey) ?? 0;

    if (token == null) return false;

    final isExpired =
        DateTime.now().millisecondsSinceEpoch / 1000 > expiresAt - 60;
    if (isExpired) return false; // caller should re-fetch

    await _applyToken(token);
    return true;
  }

  static Future<void> _applyToken(String token) async {
    SupabaseConfig.client.headers['Authorization'] = 'Bearer $token';
    SupabaseConfig.client.realtime.setAuth(token); // ← add this
  }

  static Future<String?> get currentUserId async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_expiresAtKey);
    await prefs.remove(_userIdKey);
    await SupabaseConfig.client.auth.signOut();
  }
}

/// Where a message is between the composer and the server.
///
/// Only ever [sent] for anything that came back from Supabase — the other
/// two exist for the moments a message is ours alone, and are never
/// parsed from a row.
enum MessageStatus { sent, pending, failed }

class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final DateTime createdAt;
  final bool isRead;

  /// Defaults to [MessageStatus.sent], so every server row is correct
  /// without fromMap having to say so.
  final MessageStatus status;

  /// A photograph sent with this message, as a Cloudflare delivery
  /// URL, or null.
  ///
  /// One per message and images only — see
  /// supabase/sql/message-images.sql for why that is a column rather
  /// than a media table, and why video is not a later value for it.
  final String? imageUrl;

  bool get hasImage => (imageUrl ?? '').isNotEmpty;

  /// When the sender took it back, or null while it stands.
  ///
  /// The row survives a delete so that every client has something to draw
  /// and the realtime subscription has something to push; the content is
  /// blanked server-side, so what is left is a tombstone rather than a
  /// copy of what was said.
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    required this.isRead,
    this.status = MessageStatus.sent,
    this.deletedAt,
    this.imageUrl,
  });

  ChatMessage copyWith({
    MessageStatus? status,
    DateTime? deletedAt,
    String? imageUrl,
  }) => ChatMessage(
    id: id,
    conversationId: conversationId,
    senderId: senderId,
    content: content,
    createdAt: createdAt,
    isRead: isRead,
    status: status ?? this.status,
    deletedAt: deletedAt ?? this.deletedAt,
    imageUrl: imageUrl ?? this.imageUrl,
  );

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      senderId: map['sender_id'] as String,
      content: map['content'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      isRead: map['read_at'] != null,
      // Tolerated as missing: the column is newer than some of the rows
      // and than some of the clients, and a thread that throws because a
      // key is absent is worse than one that treats it as not deleted.
      deletedAt: map['deleted_at'] == null
          ? null
          : DateTime.tryParse('${map['deleted_at']}'),
      // Tolerated as missing, like deleted_at: the column is newer than
      // some clients and some rows.
      imageUrl: map['image_url'] as String?,
    );
  }
}

class ChatRepository {
  // `late`, so the client is only reached when a method actually uses
  // it. As a plain field initialiser this ran at construction, which is
  // the documented reason an un-initialised Supabase used to take these
  // classes down before their first method was called — and it also made
  // the repository impossible to stand in for in a test without a live
  // client in the room.
  late final _db = SupabaseConfig.client;

  // ChatRepository — fetch only messages after a given time
  Future<List<ChatMessage>> getMessagesSince(
    String conversationId, {
    DateTime? after,
  }) async {
    final currentUserId = await SupabaseTokenManager.currentUserId;
    if (currentUserId == null) {
      throw Exception('No current user ID found');
    }

    // Check if this user previously deleted this conversation
    DateTime? deletedAt;
    try {
      final deleteRecord = await _db
          .from('conversation_deletes')
          .select('deleted_at')
          .eq('conversation_id', conversationId)
          .eq('user_id', currentUserId)
          .maybeSingle();

      if (deleteRecord != null) {
        deletedAt = DateTime.parse(deleteRecord['deleted_at']);
      }
    } catch (_) {}

    // Use the later of: cache cutoff vs deletion cutoff
    DateTime? since = after;
    if (deletedAt != null) {
      since = since == null
          ? deletedAt
          : (deletedAt.isAfter(since) ? deletedAt : since);
    }

    var query = _db
        .from('messages')
        .select()
        .eq('conversation_id', conversationId);

    if (since != null) {
      query = query.gt('created_at', since.toIso8601String());
    }

    final data = await query.order('created_at', ascending: true);
    return (data as List).map((r) => ChatMessage.fromMap(r)).toList();
  }

  Future<Conversation> createGroupConversation({
    required String myUserId,
    required List<String> otherUserIds,
    required String groupName,
  }) async {
    final participants = [myUserId, ...otherUserIds];

    final created = await _db
        .from('conversations')
        .insert({
          'participant_ids': participants,
          'is_group': true,
          'group_name': groupName,
          'created_by': myUserId,
        })
        .select()
        .single();

    return Conversation.fromMap(created);
  }

  /// Get or create a 1-to-1 conversation between two users.
  Future<Conversation> getOrCreateConversation({
    required String myUserId,
    required String otherUserId,
  }) async {
    final participants = [myUserId, otherUserId]..sort();

    final existing = await _db
        .from('conversations')
        .select()
        .contains('participant_ids', participants)
        .eq('is_group', false) // ← add this
        .eq(
          'participant_ids',
          '{${participants.join(',')}}',
        ) // exact match, not just contains
        .limit(1)
        .maybeSingle();

    if (existing != null) return Conversation.fromMap(existing);

    final created = await _db
        .from('conversations')
        .insert({
          'participant_ids': participants,
          'is_group': false, // ← explicit
        })
        .select()
        .single();

    return Conversation.fromMap(created);
  }

  /// Fetch all conversations for the current user (for inbox screen).
  Future<List<Conversation>> getMyConversations(String myUserId) async {
    final data = await _db
        .from('conversations')
        .select()
        .contains('participant_ids', [myUserId])
        .order('updated_at', ascending: false);

    return (data as List).map((row) => Conversation.fromMap(row)).toList();
  }

  /// One conversation, straight from the table.
  ///
  /// Membership and the group name change underneath an open chat -- a
  /// member is added or removed from the info screen, or by somebody else
  /// entirely -- and the only honest answer to "who is in this group" is
  /// the row, not whatever was passed in when the screen was built.
  Future<Conversation> getConversation(String conversationId) async {
    final row = await _db
        .from('conversations')
        .select()
        .eq('id', conversationId)
        .single();

    return Conversation.fromMap(row);
  }

  Future<void> deleteConversation(String conversationId) async {
    final currentUserId = await SupabaseTokenManager.currentUserId;
    if (currentUserId == null) throw Exception('No current user ID found');

    await _db.from('conversation_deletes').upsert({
      'conversation_id': conversationId,
      'user_id': currentUserId,
      'deleted_at': DateTime.now().toUtc().toIso8601String(), // ← toUtc()
    });

    MessageCache.instance.clear(conversationId);
  }

  /// Fetch message history for a conversation (paginated).
  Future<List<ChatMessage>> getMessages(
    String conversationId, {
    int limit = 50,
    DateTime? before,
  }) async {
    var query = _db
        .from('messages')
        .select()
        .eq('conversation_id', conversationId);

    if (before != null) {
      query = query.lt('created_at', before.toIso8601String());
    }

    final data = await query.order('created_at', ascending: false).limit(limit);

    final messages = (data as List)
        .map((row) => ChatMessage.fromMap(row))
        .toList()
        .reversed
        .toList(); // reverse so oldest is first

    return messages;
  }

  Stream<List<ChatMessage>> messageStream(String conversationId) {
    final controller = StreamController<List<ChatMessage>>();
    List<ChatMessage> current = [];

    Future<void> fetchAll() async {
      final data = await _db
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);
      current = (data as List).map((r) => ChatMessage.fromMap(r)).toList();
      if (!controller.isClosed) controller.add(current);
    }

    fetchAll();

    final channel = _db.channel('room-$conversationId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'conversation_id',
          value: conversationId,
        ),
        callback: (payload) => fetchAll(), // ← just always re-fetch, no parsing
      )
      ..subscribe((status, [error]) {
        debugPrint('Realtime status: $status error: $error');
      });

    controller.onCancel = () {
      _db.removeChannel(channel);
      controller.close();
    };

    return controller.stream;
  }

  /// Reactions in a conversation, re-read whenever one changes.
  ///
  /// Re-fetches rather than applying the payload, matching
  /// [messageStream]: a reaction arrives as an insert or a delete, and
  /// rebuilding the small set is simpler than maintaining it from two
  /// kinds of event — the whole set for a thread is a few dozen rows.
  ///
  /// The filter is why conversation_id is denormalised onto the row.
  /// Realtime filters one column of one table and cannot join, so
  /// without it this would have to listen to every reaction in the
  /// database and discard almost all of them.
  Stream<List<MessageReaction>> reactionStream(String conversationId) {
    final controller = StreamController<List<MessageReaction>>();

    Future<void> fetchAll() async {
      try {
        final rows = await getReactions(conversationId);
        if (!controller.isClosed) controller.add(rows);
      } catch (e) {
        debugPrint('[Reactions] refresh failed: $e');
      }
    }

    final channel = _db.channel('reactions-$conversationId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'message_reactions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'conversation_id',
          value: conversationId,
        ),
        callback: (_) => fetchAll(),
      )
      ..subscribe();

    controller.onCancel = () {
      _db.removeChannel(channel);
      controller.close();
    };

    return controller.stream;
  }

  /// Send a message.
  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String senderId,
    required String content,
    String? imageUrl,
  }) async {
    final row = await _db
        .from('messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': senderId,
          'content': content,
          if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
        })
        .select()
        .single();

    // Bump the conversation's updated_at for inbox ordering
    await _db
        .from('conversations')
        .update({'updated_at': DateTime.now().toIso8601String()})
        .eq('id', conversationId);

    return ChatMessage.fromMap(row);
  }

  /// Take a message back.
  ///
  /// The content is blanked in the same statement as the timestamp. The
  /// row has to survive — every other client needs something to redraw
  /// and realtime needs something to push — but what survives should not
  /// be the sentence somebody just withdrew.
  ///
  /// Whether this is allowed is not decided here. The RLS policy only
  /// matches the sender's own messages inside the delete window, and an
  /// update that matches no row is not an error, so a refusal arrives as
  /// a message that simply does not change.
  /// Returns false when the database declined — which it does by
  /// matching no row rather than by raising, so .select() is the only way
  /// to tell the difference between "deleted" and "not allowed".
  Future<bool> deleteMessage(String messageId) async {
    final rows = await _db
        .from('messages')
        .update({
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
          'content': '',
          // The photograph as well. A tombstone that still carries its
          // image is not a deleted message, and nothing in the database
          // enforces this — the RLS policy decides WHO may delete, not
          // what deleting leaves behind.
          'image_url': null,
        })
        .eq('id', messageId)
        .select('id');

    return (rows as List).isNotEmpty;
  }

  /// Every reaction in a conversation.
  Future<List<MessageReaction>> getReactions(String conversationId) async {
    final rows = await _db
        .from('message_reactions')
        .select()
        .eq('conversation_id', conversationId);

    return (rows as List)
        .map((r) => MessageReaction.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Add this emoji, or take it off if it is already mine.
  ///
  /// Returns true if it was added. The unique key on
  /// (message_id, user_id, emoji) is what makes the add safe to repeat:
  /// two taps racing cannot leave two rows.
  Future<bool> toggleReaction({
    required String messageId,
    required String conversationId,
    required String userId,
    required String emoji,
  }) async {
    final existing = await _db
        .from('message_reactions')
        .select('id')
        .eq('message_id', messageId)
        .eq('user_id', userId)
        .eq('emoji', emoji)
        .maybeSingle();

    if (existing != null) {
      await _db.from('message_reactions').delete().eq('id', existing['id']);
      return false;
    }

    await _db.from('message_reactions').insert({
      'message_id': messageId,
      'conversation_id': conversationId,
      'user_id': userId,
      'emoji': emoji,
    });

    return true;
  }

  /// Mark all messages in a conversation as read.
  Future<void> markAsRead(String conversationId, String myUserId) async {
    print(
      '[ChatRepository] Marking conversation $conversationId as read for user $myUserId',
    );
    await _db
        .from('messages')
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('conversation_id', conversationId)
        .neq('sender_id', myUserId)
        .isFilter('read_at', null);
  }
}

class ChatNotifier extends ChangeNotifier {
  final ChatRepository _repo;
  final String conversationId;
  final String myUserId;

  ChatNotifier({
    required this.conversationId,
    required this.myUserId,
    ChatRepository? repo,
  }) : _repo = repo ?? ChatRepository();

  List<ChatMessage> _messages = [];

  /// Messages typed here that the server has not confirmed: still going,
  /// or failed and waiting to be retried.
  ///
  /// Kept apart from _messages because the realtime subscription replaces
  /// that list wholesale on every insert — ChatRepository.messageStream
  /// re-fetches rather than appending — so a local message living in it
  /// would be deleted by the next event, frequently the one its own
  /// insert caused.
  final List<ChatMessage> _outbox = [];

  bool _loading = true; // true only on first ever load
  bool _refreshing = false; // true when silently fetching new
  bool _sending = false;
  String? _error;
  StreamSubscription? _sub;

  /// The server's messages and ours, newest first.
  List<ChatMessage> get messages {
    final all = [..._messages, ..._outbox]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return all.reversed.toList();
  }

  bool get loading => _loading;
  bool get refreshing => _refreshing;
  bool get sending => _sending;
  String? get error => _error;

  /// Puts the error banner away.
  ///
  /// The banner's Dismiss button had no way to do this: _error is private
  /// and there was no setter, so the handler was left as `() => ()` -- a
  /// function returning an empty record, which compiles and does nothing.
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<void> initialize() async {
    try {
      final cached = MessageCache.instance.get(conversationId);

      if (cached != null && cached.isNotEmpty) {
        // ── Cached path: show instantly, fetch new in background ──
        _messages = cached;
        _loading = false;
        notifyListeners();

        // Silently fetch anything newer than last cached message
        _refreshing = true;
        notifyListeners();

        await Future.delayed(
          const Duration(milliseconds: 300),
        ); // ← lets UI render

        final lastTime = cached.last.createdAt;
        final newMsgs = await _repo.getMessagesSince(
          conversationId,
          after: lastTime,
        );

        if (newMsgs.isNotEmpty) {
          MessageCache.instance.append(conversationId, newMsgs);
          _messages = MessageCache.instance.get(conversationId)!;
        }

        _refreshing = false;
        notifyListeners();
      } else {
        // ── Cold load: fetch everything ──
        _loading = true;
        notifyListeners();

        final msgs = await _repo.getMessagesSince(conversationId);
        MessageCache.instance.set(conversationId, msgs);
        _messages = msgs;
        _loading = false;
        notifyListeners();
      }

      await _repo.markAsRead(conversationId, myUserId);

      // Subscribe to real-time new messages
      _sub = _repo.messageStream(conversationId).listen(applyServerMessages);

      // Reactions are a separate table, so they need their own
      // subscription — the messages channel will never fire for one.
      _reactions = await _repo.getReactions(conversationId);
      notifyListeners();

      _reactionSub = _repo
          .reactionStream(conversationId)
          .listen(applyReactions);
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
    }
  }

  /// Makes outbox ids unique when the clock does not.
  static int _localSeq = 0;

  /// Every reaction in this conversation, flat. Small enough that a
  /// per-message index would cost more in bookkeeping than it saves.
  List<MessageReaction> _reactions = [];

  StreamSubscription? _reactionSub;

  /// What the bubble for [messageId] draws, counted and ordered.
  List<ReactionSummary> reactionsFor(String messageId) => summariseReactions(
    _reactions
        .where((r) => r.messageId == messageId)
        .map((r) => (emoji: r.emoji, userId: r.userId)),
    myUserId,
  );

  /// Put this emoji on the message, or take mine off if it is there.
  ///
  /// Optimistic, and reverted if the write fails. A reaction is the
  /// cheapest thing in the app to undo, and waiting a round trip to see
  /// one appear is the difference between a tap that feels connected and
  /// one that feels broken.
  Future<void> toggleReaction(String messageId, String emoji) async {
    final mineIndex = _reactions.indexWhere(
      (r) =>
          r.messageId == messageId && r.userId == myUserId && r.emoji == emoji,
    );

    final before = List<MessageReaction>.from(_reactions);

    if (mineIndex >= 0) {
      _reactions = List.of(_reactions)..removeAt(mineIndex);
    } else {
      _reactions = [
        ..._reactions,
        MessageReaction(
          id: 'local:${_localSeq++}',
          messageId: messageId,
          conversationId: conversationId,
          userId: myUserId,
          emoji: emoji,
        ),
      ];
    }
    notifyListeners();

    try {
      await _repo.toggleReaction(
        messageId: messageId,
        conversationId: conversationId,
        userId: myUserId,
        emoji: emoji,
      );
    } catch (e) {
      debugPrint('[Thread] reaction failed: $e');
      _reactions = before;
      notifyListeners();
    }
  }

  /// Take one of my messages back.
  ///
  /// Returns false when the database declined. It declines by matching no
  /// row rather than by raising — the RLS policy only covers the sender's
  /// own messages inside the delete window — so without the row count
  /// coming back, a refusal and a success look identical from here and
  /// the bubble would clear optimistically and then reappear on the next
  /// realtime refresh.
  Future<bool> deleteMessage(ChatMessage message) async {
    final before = List<ChatMessage>.from(_messages);

    _messages = _messages
        .map(
          (m) => m.id == message.id ? m.copyWith(deletedAt: DateTime.now()) : m,
        )
        .toList();
    notifyListeners();

    try {
      final done = await _repo.deleteMessage(message.id);
      if (!done) {
        _messages = before;
        notifyListeners();
      }
      return done;
    } catch (e) {
      debugPrint('[Thread] delete failed: $e');
      _messages = before;
      notifyListeners();
      return false;
    }
  }

  /// Replace the reaction set wholesale, the way the message stream does.
  void applyReactions(List<MessageReaction> reactions) {
    _reactions = reactions;
    notifyListeners();
  }

  /// Take a fresh server list, keeping anything of ours that is still
  /// unsent.
  ///
  /// ChatRepository.messageStream re-fetches the whole conversation on
  /// every insert rather than appending, so this replaces _messages
  /// wholesale — which is precisely why pending and failed messages live
  /// in _outbox instead, and why this method does not touch it.
  void applyServerMessages(List<ChatMessage> messages) {
    MessageCache.instance.set(conversationId, messages);
    _messages = messages;
    notifyListeners();
  }

  /// Show the message immediately, then try to send it.
  ///
  /// No re-entry guard any more. Each send carries its own outbox entry,
  /// so two messages typed quickly both go — the old `if (_sending)
  /// return` silently dropped the second one.
  /// Show the message immediately, then try to send it.
  ///
  /// [imageUrl] is already on Cloudflare by the time this is called —
  /// the composer uploads before sending, so the optimistic bubble can
  /// draw the real photograph rather than a local file that the server
  /// copy would then replace with a flicker.
  Future<void> sendMessage(String content, {String? imageUrl}) async {
    final text = content.trim();

    // A photograph on its own is a message. Only an empty one with no
    // image is nothing to send.
    if (text.isEmpty && (imageUrl ?? '').isEmpty) return;

    final local = ChatMessage(
      // Prefixed so nothing matching on id mistakes it for a server
      // uuid, and with a counter after the clock because the clock alone
      // is not enough: two sends in the same microsecond got identical
      // ids, and _outbox.removeWhere(id) then dropped both of them.
      id: 'local:${DateTime.now().microsecondsSinceEpoch}-${_localSeq++}',
      conversationId: conversationId,
      senderId: myUserId,
      content: text,
      createdAt: DateTime.now(),
      isRead: false,
      status: MessageStatus.pending,
      imageUrl: imageUrl,
    );

    _outbox.add(local);
    _sending = true;
    notifyListeners();

    await _deliver(local);
  }

  /// Try a failed message again.
  Future<void> retry(ChatMessage failed) async {
    final i = _outbox.indexWhere((m) => m.id == failed.id);
    if (i < 0 || _outbox[i].status != MessageStatus.failed) return;

    // It may have landed after all. A send can throw on a connection that
    // dropped AFTER the insert committed, and re-sending then puts the
    // message in the thread twice — which is worse than the failure it is
    // recovering from. Matching on content is crude and is only reached
    // here, where a false positive costs one more tap.
    final already = _messages.any(
      (m) =>
          m.senderId == failed.senderId &&
          m.content == failed.content &&
          m.createdAt.difference(failed.createdAt).abs() <
              const Duration(minutes: 5),
    );

    if (already) {
      _outbox.removeAt(i);
      notifyListeners();
      return;
    }

    _outbox[i] = _outbox[i].copyWith(status: MessageStatus.pending);
    _sending = true;
    notifyListeners();

    await _deliver(_outbox[i]);
  }

  Future<void> _deliver(ChatMessage local) async {
    try {
      final sent = await _repo.sendMessage(
        conversationId: conversationId,
        senderId: myUserId,
        content: local.content,
        imageUrl: local.imageUrl,
      );

      _outbox.removeWhere((m) => m.id == local.id);

      // The realtime re-fetch usually gets here first; this covers the
      // case where it has not yet.
      if (!_messages.any((m) => m.id == sent.id)) {
        _messages = [..._messages, sent]
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        MessageCache.instance.set(conversationId, _messages);
      }
    } catch (e) {
      // Deliberately not _error. The banner used to show the raw
      // PostgrestException, which told the user nothing and hid the fact
      // that their message was gone. The bubble says it now, where they
      // are looking, with something to do about it.
      debugPrint('[Thread] send failed: $e');

      final i = _outbox.indexWhere((m) => m.id == local.id);
      if (i >= 0) {
        _outbox[i] = _outbox[i].copyWith(status: MessageStatus.failed);
      }
    } finally {
      _sending = _outbox.any((m) => m.status == MessageStatus.pending);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _reactionSub?.cancel();
    super.dispose();
  }
}

class InboxRepository {
  // `late`, so the client is only reached when a method actually uses
  // it. As a plain field initialiser this ran at construction, which is
  // the documented reason an un-initialised Supabase used to take these
  // classes down before their first method was called — and it also made
  // the repository impossible to stand in for in a test without a live
  // client in the room.
  late final _db = SupabaseConfig.client;

  /// Fetch all conversations with last message + unread count.
  Future<List<ConversationPreview>> getInbox(String myUserId) async {
    final data = await _db.rpc('get_inbox', params: {'p_user_id': myUserId});

    final previews = (data as List).map((row) {
      final conv = Conversation(
        id: row['conv_id'] as String,
        participantIds: List<String>.from(row['participant_ids']),
        updatedAt: DateTime.parse(row['updated_at']),
        isGroup: row['is_group'] as bool? ?? false,
        groupName: row['group_name'] as String?,
        groupImage: row['group_image'] as String?,
      );

      final otherUserId = conv.isGroup
          ? null
          : conv.participantIds.firstWhere(
              (id) => id != myUserId,
              orElse: () => '',
            );

      final hasLastMsg = row['last_message_content'] != null;

      return ConversationPreview(
        conversation: conv,
        otherUserId: otherUserId,
        isGroup: conv.isGroup,
        unreadCount: (row['unread_count'] as num).toInt(),
        lastMessage: hasLastMsg
            ? ChatMessage(
                id: '',
                conversationId: conv.id,
                senderId: row['last_message_sender'] as String,
                content: row['last_message_content'] as String,
                createdAt: DateTime.parse(row['last_message_at']),
                isRead: true,
              )
            : null,
      );
    }).toList();

    // get_inbox is a function with a fixed column list, so adding
    // group_image to the conversations TABLE does not add it to what
    // this returns. Until that function is updated the rows arrive
    // without the key at all — not null, absent — and every group draws
    // an initial however it has been set up.
    //
    // So: if the key is missing, read the images directly. One extra
    // query, and only while the function is behind. The moment it starts
    // returning the column this costs nothing, because the check is for
    // the key rather than for a null value.
    final rpcHasColumn =
        data.isEmpty || (data.first as Map).containsKey('group_image');

    if (rpcHasColumn) return previews;

    return _fillGroupImages(previews);
  }

  /// Read group_image for the group conversations in [previews].
  ///
  /// A stopgap for an out-of-date get_inbox; see the note in [getInbox].
  Future<List<ConversationPreview>> _fillGroupImages(
    List<ConversationPreview> previews,
  ) async {
    final groupIds = previews
        .where((p) => p.isGroup)
        .map((p) => p.conversation.id)
        .toList();

    if (groupIds.isEmpty) return previews;

    try {
      final rows = await _db
          .from('conversations')
          .select('id, group_image')
          .inFilter('id', groupIds);

      final byId = {
        for (final r in rows as List) '${r['id']}': r['group_image'] as String?,
      };

      return previews.map((p) {
        final url = byId[p.conversation.id];
        if (url == null || url.isEmpty) return p;

        return ConversationPreview(
          conversation: p.conversation.copyWith(groupImage: url),
          otherUserId: p.otherUserId,
          isGroup: p.isGroup,
          unreadCount: p.unreadCount,
          lastMessage: p.lastMessage,
        );
      }).toList();
    } catch (e) {
      debugPrint('[Inbox] could not read group images: $e');
      return previews;
    }
  }

  /// Real-time stream that fires whenever any conversation updates.
  Stream<void> conversationUpdates(String myUserId) {
    final controller = StreamController<void>.broadcast();

    final channel = _db.channel('inbox:$myUserId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (_) => controller.add(null),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'messages',
        callback: (_) => controller.add(null),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'conversations',
        callback: (_) => controller.add(null),
      )
      ..subscribe(); // ← no status callback here — don't react to channel events

    controller.onCancel = () {
      _db.removeChannel(channel);
      controller.close();
    };

    return controller.stream;
  }
}

class InboxNotifier extends ChangeNotifier {
  final String myUserId;
  final _repo = InboxRepository();
  final UnreadCountProvider? unreadCountProvider;

  List<ConversationPreview> _previews = [];
  bool _loading = true;
  String? _error;
  StreamSubscription? _sub;

  List<ConversationPreview> get previews => _previews;
  bool get loading => _loading;
  String? get error => _error;
  Timer? _debounceTimer;

  InboxNotifier({required this.myUserId, this.unreadCountProvider});

  Future<void> initialize() async {
    await _loadInbox();

    _sub = _repo.conversationUpdates(myUserId).listen((_) {
      // Debounce — ignore events fired within 1 second of each other
      // This prevents the chat screen closing from triggering a reload
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(seconds: 1), () {
        _loadInbox();
      });
    });
  }

  Future<void> _loadInbox() async {
    try {
      _previews = await _repo.getInbox(myUserId);
      // whereType drops the nulls, which is every group. Before
      // otherUserId was nullable they arrived as '' and were asked for by
      // name, one failed lookup per group in the list.
      final ids = _previews
          .map((p) => p.otherUserId)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toList();

      if (ids.isNotEmpty) {
        await UserProfileCache.instance.refresh(ids);
      }

      // Push total unread count up to provider
      final total = _previews.fold<int>(0, (sum, p) => sum + p.unreadCount);
      unreadCountProvider?.update(total);

      _loading = false;
      _error = null;
    } catch (e) {
      _error = e.toString();
      _loading = false;
    }
    notifyListeners();
  }

  Future<void> refresh() => _loadInbox();

  void removePreview(String conversationId) {
    _previews = _previews
        .where((p) => p.conversation.id != conversationId)
        .toList();
    notifyListeners();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}

/// One emoji, from one person, on one message.
///
/// conversationId is carried on the row rather than looked up. Supabase
/// realtime filters on a single column of a single table and cannot join,
/// so a subscription to "reactions in this conversation" needs the column
/// to exist — see supabase/sql/message-reactions-and-delete.sql.
class MessageReaction {
  final String id;
  final String messageId;
  final String conversationId;
  final String userId;
  final String emoji;

  const MessageReaction({
    required this.id,
    required this.messageId,
    required this.conversationId,
    required this.userId,
    required this.emoji,
  });

  factory MessageReaction.fromMap(Map<String, dynamic> map) => MessageReaction(
    id: '${map['id']}',
    messageId: '${map['message_id']}',
    conversationId: '${map['conversation_id']}',
    // Coerced rather than cast. sender_id and user_id have arrived as
    // both a JSON number and a string from this backend before, and a
    // cast that throws takes the whole thread down with it.
    userId: '${map['user_id']}',
    emoji: '${map['emoji']}',
  );
}

class MessageCache {
  MessageCache._();
  static final MessageCache instance = MessageCache._();

  final Map<String, List<ChatMessage>> _cache = {};

  List<ChatMessage>? get(String conversationId) => _cache[conversationId];

  void set(String conversationId, List<ChatMessage> messages) {
    _cache[conversationId] = messages;
  }

  void append(String conversationId, List<ChatMessage> newMessages) {
    final existing = _cache[conversationId] ?? [];
    final existingIds = existing.map((m) => m.id).toSet();
    final merged = [
      ...existing,
      ...newMessages.where((m) => !existingIds.contains(m.id)),
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _cache[conversationId] = merged;
  }

  void clear(String conversationId) => _cache.remove(conversationId);

  /// Forget every thread.
  ///
  /// For an account switch: these are somebody else's conversations the
  /// moment the active account changes, and a conversation id alone does
  /// not say whose it was.
  void clearAll() => _cache.clear();
}

class UnreadCountProvider extends ChangeNotifier {
  int _count = 0;
  int get count => _count;

  void update(int count) {
    if (_count == count) return;
    _count = count;
    notifyListeners();
  }
}
