import 'dart:async';

import 'package:drivelife/screens/chat/SupabaseClasses.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sending a message, and what happens when it does not go.
///
/// The bug these start from: the composer was cleared before the insert
/// was awaited, so a failure left the user with no message, no text, and
/// a banner reading "PostgrestException(...)". They typed something and
/// it vanished. The send is optimistic now, which means there is local
/// state to get wrong — chiefly that the realtime subscription replaces
/// the server list wholesale on every insert, so anything local kept in
/// that list is deleted by the next event.
class _FakeRepo extends ChatRepository {
  /// Messages this repo accepted, in order.
  final sent = <String>[];

  /// When true, every send throws, the way a dropped connection does.
  bool failing = false;

  /// Lets a test hold a send open and look at the thread mid-flight.
  Completer<void>? gate;

  int _id = 0;

  @override
  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String senderId,
    required String content,
    String? imageUrl,
  }) async {
    if (gate != null) await gate!.future;
    if (failing) throw Exception('no connection');

    sent.add(content);

    return ChatMessage(
      id: 'server-${++_id}',
      conversationId: conversationId,
      senderId: senderId,
      content: content,
      createdAt: DateTime.now(),
      isRead: false,
      imageUrl: imageUrl,
    );
  }
}

void main() {
  late _FakeRepo repo;
  late ChatNotifier thread;

  setUp(() {
    repo = _FakeRepo();
    thread = ChatNotifier(
      conversationId: 'conv-1',
      myUserId: '67004',
      repo: repo,
    );
    MessageCache.instance.clear('conv-1');
  });

  group('a send that works', () {
    test('the message is in the thread before the server answers', () async {
      repo.gate = Completer<void>();

      final send = thread.sendMessage('on my way');
      // Not awaited: the point is that it is visible already.
      expect(thread.messages, hasLength(1));
      expect(thread.messages.first.content, 'on my way');
      expect(thread.messages.first.status, MessageStatus.pending);

      repo.gate!.complete();
      await send;
    });

    test('the local copy is replaced, not duplicated', () async {
      await thread.sendMessage('on my way');

      expect(thread.messages, hasLength(1));
      expect(thread.messages.first.status, MessageStatus.sent);
      expect(thread.messages.first.id, startsWith('server-'));
    });

    test('two messages typed quickly both go', () async {
      // The old code had `if (_sending) return`, which dropped the second
      // one on the floor — no error, no bubble, nothing.
      await Future.wait([thread.sendMessage('one'), thread.sendMessage('two')]);

      expect(repo.sent, ['one', 'two']);
      expect(thread.messages, hasLength(2));
    });

    test('every pending message gets its own id', () async {
      // The id is interpolated, and an escaped dollar would make every
      // one of them the same literal string — at which point removing
      // one by id empties the outbox.
      repo.gate = Completer<void>();

      final sends = [thread.sendMessage('a'), thread.sendMessage('b')];
      final ids = thread.messages.map((m) => m.id).toSet();

      expect(ids, hasLength(2));
      expect(ids.every((id) => id.startsWith('local:')), isTrue);

      repo.gate!.complete();
      await Future.wait(sends);
    });
  });

  group('a send that fails', () {
    test('the message stays, marked failed', () async {
      repo.failing = true;
      await thread.sendMessage('did you see this');

      expect(thread.messages, hasLength(1));
      expect(thread.messages.first.content, 'did you see this');
      expect(thread.messages.first.status, MessageStatus.failed);
    });

    test('it does not raise the error banner', () async {
      // It used to show the raw PostgrestException, which told the user
      // nothing and buried the part that mattered: the message is gone.
      // The bubble carries it now.
      repo.failing = true;
      await thread.sendMessage('hello');

      expect(thread.error, isNull);
    });

    test('retry sends it and clears the failure', () async {
      repo.failing = true;
      await thread.sendMessage('hello');

      repo.failing = false;
      await thread.retry(thread.messages.first);

      expect(repo.sent, ['hello']);
      expect(thread.messages, hasLength(1));
      expect(thread.messages.first.status, MessageStatus.sent);
    });

    test('retrying twice does not send twice', () async {
      repo.failing = true;
      await thread.sendMessage('hello');

      repo.failing = false;
      final failed = thread.messages.first;
      await thread.retry(failed);
      // The same bubble again — already gone from the outbox.
      await thread.retry(failed);

      expect(repo.sent, ['hello']);
      expect(thread.messages, hasLength(1));
    });
  });

  test('a failed message survives a realtime refresh', () async {
    // The reason the outbox exists. ChatRepository.messageStream
    // re-fetches the whole conversation on every insert and the notifier
    // assigns it wholesale, so a local message kept in that list would be
    // wiped by the next event — including, usually, the one caused by
    // somebody else's message arriving a second later.
    repo.failing = true;
    await thread.sendMessage('mine, unsent');

    thread.applyServerMessages([
      ChatMessage(
        id: 'server-99',
        conversationId: 'conv-1',
        senderId: '12345',
        content: 'theirs, arriving',
        createdAt: DateTime.now(),
        isRead: false,
      ),
    ]);

    final contents = thread.messages.map((m) => m.content).toList();
    expect(contents, contains('mine, unsent'));
    expect(contents, contains('theirs, arriving'));
  });
}
