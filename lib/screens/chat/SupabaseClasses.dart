import 'dart:convert';
import 'package:drivelife/screens/chat/ChatList.dart';
import 'package:drivelife/screens/chat/ChatProfileCache.dart';
import 'package:drivelife/screens/chat/models.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:http/http.dart' as http;

class AppConfig {
  static const wpBaseUrl = 'https://www.carevents.com/uk';

  // Supabase project details
  // Found at: Supabase Dashboard → Settings → API
  static const supabaseUrl = 'https://hekpfyxiduypovcvwffm.supabase.co';
  static const supabaseAnonKey =
      'sb_publishable_HSLwe3eiV6K_DCfgCwfSLw_YUM5HQ9F'; // safe to expose
}

class SupabaseConfig {
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
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

    final data = json.decode(response.body);

    print('[SupabaseTokenManager] Received token data: $data');
    final token = data['token'] as String;
    final expiresAt = data['expires_at'] as int;
    final userId = data['user_id'] as String;

    // Cache locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setInt(_expiresAtKey, expiresAt);
    await prefs.setString(_userIdKey, userId);

    // Tell Supabase to use this token for all future requests
    await _applyToken(token);
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

class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final DateTime createdAt;
  final bool isRead;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    required this.isRead,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      senderId: map['sender_id'] as String,
      content: map['content'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      isRead: map['read_at'] != null,
    );
  }
}

class ChatRepository {
  final _db = SupabaseConfig.client;

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

  /// Send a message.
  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String senderId,
    required String content,
  }) async {
    final row = await _db
        .from('messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': senderId,
          'content': content,
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

// class ChatNotifier extends ChangeNotifier {
//   final ChatRepository _repo;
//   final String conversationId;
//   final String myUserId;

//   ChatNotifier({
//     required this.conversationId,
//     required this.myUserId,
//     ChatRepository? repo,
//   }) : _repo = repo ?? ChatRepository();

//   List<ChatMessage> _messages = [];
//   bool _loading = true;
//   bool _sending = false;
//   String? _error;
//   StreamSubscription? _sub;

//   List<ChatMessage> get messages => _messages.reversed.toList();

//   bool get loading => _loading;
//   bool get sending => _sending;
//   String? get error => _error;

//   Future<void> initialize() async {
//     try {
//       _sub = _repo.messageStream(conversationId).listen((messages) {
//         print(
//           '[ChatNotifier] Received ${messages.length} messages from stream',
//         );
//         _messages = messages; // already sorted oldest→newest from the query
//         _loading = false;
//         notifyListeners();
//       });
//     } catch (e) {
//       _error = e.toString();
//       _loading = false;
//       notifyListeners();
//     }
//   }

//   Future<void> sendMessage(String content) async {
//     if (content.trim().isEmpty || _sending) return;

//     _sending = true;
//     notifyListeners();

//     try {
//       final sent = await _repo.sendMessage(
//         conversationId: conversationId,
//         senderId: myUserId,
//         content: content.trim(),
//       );

//       // Optimistically add to list immediately
//       if (!_messages.any((m) => m.id == sent.id)) {
//         _messages = [..._messages, sent];
//         notifyListeners();
//       }
//     } catch (e) {
//       _error = e.toString();
//     } finally {
//       _sending = false;
//       notifyListeners();
//     }
//   }

//   @override
//   void dispose() {
//     _sub?.cancel();
//     super.dispose();
//   }
// }
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
  bool _loading = true; // true only on first ever load
  bool _refreshing = false; // true when silently fetching new
  bool _sending = false;
  String? _error;
  StreamSubscription? _sub;

  List<ChatMessage> get messages => _messages.reversed.toList();
  bool get loading => _loading;
  bool get refreshing => _refreshing;
  bool get sending => _sending;
  String? get error => _error;
  

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
      _sub = _repo.messageStream(conversationId).listen((messages) {
        // Stream fires on new inserts — merge into cache
        MessageCache.instance.set(conversationId, messages);
        _messages = messages;
        notifyListeners();
      });
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty || _sending) return;
    _sending = true;
    notifyListeners();

    try {
      final sent = await _repo.sendMessage(
        conversationId: conversationId,
        senderId: myUserId,
        content: content.trim(),
      );
      if (!_messages.any((m) => m.id == sent.id)) {
        final updated = [..._messages, sent]
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _messages = updated;
        MessageCache.instance.set(conversationId, updated);
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

class InboxRepository {
  final _db = SupabaseConfig.client;

  /// Fetch all conversations with last message + unread count.
  Future<List<ConversationPreview>> getInbox(String myUserId) async {
    final data = await _db.rpc('get_inbox', params: {'p_user_id': myUserId});

    return (data as List).map((row) {
      final conv = Conversation(
        id: row['conv_id'] as String,
        participantIds: List<String>.from(row['participant_ids']),
        updatedAt: DateTime.parse(row['updated_at']),
        isGroup: row['is_group'] as bool? ?? false,
        groupName: row['group_name'] as String?,
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
        otherUserId: otherUserId ?? '',
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

  List<ConversationPreview> _previews = [];
  bool _loading = true;
  String? _error;
  StreamSubscription? _sub;

  List<ConversationPreview> get previews => _previews;
  bool get loading => _loading;
  String? get error => _error;
  Timer? _debounceTimer;

  InboxNotifier({required this.myUserId});

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
      final ids = _previews
          .map((p) => p.otherUserId)
          .whereType<String>()
          .toList();

      if (ids.isNotEmpty) {
        await UserProfileCache.instance.refresh(ids);
      }
      
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
}
