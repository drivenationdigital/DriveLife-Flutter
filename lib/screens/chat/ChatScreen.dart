import 'dart:async';
import 'dart:convert';
import 'package:drivelife/screens/chat/ChatProfileCache.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── 0. Configuration ─────────────────────────────────────────

class AppConfig {
  // Your WordPress site
  static const wpBaseUrl = 'https://www.carevents.com/uk';

  // Supabase project details
  // Found at: Supabase Dashboard → Settings → API
  static const supabaseUrl = 'https://hekpfyxiduypovcvwffm.supabase.co';
  static const supabaseAnonKey =
      'sb_publishable_HSLwe3eiV6K_DCfgCwfSLw_YUM5HQ9F'; // safe to expose
}

// ── 1. Supabase Initializer ───────────────────────────────────

class SupabaseConfig {
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}

// ── 2. Token Manager ─────────────────────────────────────────
// Fetches a Supabase JWT from your WordPress backend,
// caches it, and refreshes before it expires.

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

  // static Future<void> _applyToken(String token) async {
  //   // Sets a custom Authorization header on the Supabase client
  //   await SupabaseConfig.client.auth.setSession(token);
  //   // Note: if setSession isn't available in your version, use:
  //   // SupabaseConfig.client.headers['Authorization'] = 'Bearer $token';
  // }
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

// ── 3. Data Models ───────────────────────────────────────────
class Conversation {
  final String id;
  final List<String> participantIds;
  final DateTime updatedAt;

  Conversation({
    required this.id,
    required this.participantIds,
    required this.updatedAt,
  });

  factory Conversation.fromMap(Map<String, dynamic> map) {
    return Conversation(
      id: map['id'] as String,
      participantIds: List<String>.from(map['participant_ids'] ?? []),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
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

// ── 4. Chat Repository ───────────────────────────────────────
// All Supabase interactions live here. UI never touches Supabase directly.

class ChatRepository {
  final _db = SupabaseConfig.client;

  // ── Conversations ──

  /// Get or create a 1-to-1 conversation between two users.
  Future<Conversation> getOrCreateConversation({
    required String myUserId,
    required String otherUserId,
  }) async {
    final participants = [myUserId, otherUserId]..sort();

    // Check if conversation already exists
    final existing = await _db
        .from('conversations')
        .select()
        .contains('participant_ids', participants)
        .limit(1) // ← add this
        .maybeSingle();

    if (existing != null) return Conversation.fromMap(existing);

    // Create new
    final created = await _db
        .from('conversations')
        .insert({'participant_ids': participants})
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

  // ── Messages ──

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

    print('[ChatRepository] Marking conversation $conversationId as read for user $myUserId');
    await _db
        .from('messages')
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('conversation_id', conversationId)
        .neq('sender_id', myUserId)
        .isFilter('read_at', null);
  }
}

// ── 5. Chat State Management ─────────────────────────────────
// Simple ChangeNotifier — swap for Bloc/Riverpod if you prefer.

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
  bool _loading = true;
  bool _sending = false;
  String? _error;
  StreamSubscription? _sub;

  List<ChatMessage> get messages => _messages.reversed.toList();

  bool get loading => _loading;
  bool get sending => _sending;
  String? get error => _error;

  Future<void> initialize() async {
    try {
      _sub = _repo.messageStream(conversationId).listen((messages) {
        print(
          '[ChatNotifier] Received ${messages.length} messages from stream',
        );
        _messages = messages; // already sorted oldest→newest from the query
        _loading = false;
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

      // Optimistically add to list immediately
      if (!_messages.any((m) => m.id == sent.id)) {
        _messages = [..._messages, sent];
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

// ── 6. Chat Screen ───────────────────────────────────────────

class ChatScreen extends StatefulWidget {
  final String? conversationId; // nullable now
  final String myUserId;
  final String? otherUserId; // used when conversationId is null
  final String otherUserName;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.myUserId,
    required this.otherUserId,
    required this.otherUserName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  ChatNotifier? _notifier;
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  UserProfile? otherProfile;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    String convId = widget.conversationId ?? '';

    if (convId.isEmpty && widget.otherUserId != null) {
      final conv = await ChatRepository().getOrCreateConversation(
        myUserId: widget.myUserId,
        otherUserId: widget.otherUserId!,
      );
      convId = conv.id;
    }

    otherProfile = UserProfileCache.instance.getCached(widget.otherUserId ?? '');

    // Mark as read
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
      if (_scrollController.hasClients) {
        final nearBottom = _scrollController.position.pixels < 200;
        if (nearBottom) _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0, // ← was maxScrollExtent
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _inputController.text;
    _inputController.clear();
    await _notifier?.sendMessage(text);
  }

  @override
  void dispose() {
    _notifier?.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              child: otherProfile != null
                  ? otherProfile?.imageUrl != null
                      ? ClipOval(
                          child: Image.network(
                            otherProfile!.imageUrl!,
                            width: 34,
                            height: 34,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Text(
                          otherProfile!.displayName.isNotEmpty
                              ? otherProfile!.displayName[0]
                              : '?',
                          style: const TextStyle(fontSize: 18),
                        )
                  : const Icon(Icons.person, size: 18),
            ),
            const SizedBox(width: 10),
            Text(otherProfile?.bestName ?? widget.otherUserName, style: const TextStyle(fontSize: 18),),
          ],
        ),
      ),
      body: _notifier == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_notifier?.error != null)
                  MaterialBanner(
                    content: Text(_notifier!.error!),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            setState(() => _notifier!._error = null),
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),

                // Message list
                Expanded(
                  child: _notifier!.loading
                      ? const Center(child: CircularProgressIndicator())
                      : _notifier!.messages.isEmpty
                      ? const Center(
                          child: Text('No messages yet. Say hello! 👋'),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          reverse: true, // ← add this
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                          itemCount: _notifier!.messages.length,
                          itemBuilder: (context, i) {
                            final msg = _notifier!.messages[i];
                            final isMe = msg.senderId == widget.myUserId;
                            final scheme = Theme.of(context).colorScheme;

                            return Align(
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: EdgeInsets.only(
                                  top: 3,
                                  bottom: 3,
                                  left: isMe ? 60 : 0,
                                  right: isMe ? 0 : 60,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? scheme.primary
                                      : scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(18),
                                    topRight: const Radius.circular(18),
                                    bottomLeft: Radius.circular(isMe ? 18 : 4),
                                    bottomRight: Radius.circular(isMe ? 4 : 18),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: isMe
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      msg.content,
                                      style: TextStyle(
                                        color: isMe
                                            ? scheme.onPrimary
                                            : scheme.onSurface,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _formatTime(msg.createdAt),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color:
                                            (isMe
                                                    ? scheme.onPrimary
                                                    : scheme.onSurface)
                                                .withOpacity(0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Input bar
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _inputController,
                            textCapitalization: TextCapitalization.sentences,
                            minLines: 1,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: 'Message...',
                              filled: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _notifier!.sending
                            ? const Padding(
                                padding: EdgeInsets.all(8),
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : IconButton.filled(
                                onPressed: _send,
                                icon: const Icon(Icons.send_rounded),
                              ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
