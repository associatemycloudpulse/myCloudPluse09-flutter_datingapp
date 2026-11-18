import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/config/app_config.dart';
import '../../../../core/di/repository_providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/realtime/chat_events.dart';
import '../../../../core/realtime/chat_socket.dart';
import '../../../../core/realtime/presence.dart';
import '../../../auth/presentation/viewmodels/session_view_model.dart';
import '../../../calls/domain/entities/call.dart';
import '../../../onboarding/domain/entities/onboarding.dart';
import '../../domain/entities/chat.dart';
import 'conversations_view_model.dart';

class ConversationState {
  const ConversationState({
    required this.conversation,
    required this.messages,
    this.isSending = false,
    this.otherIsTyping = false,
    this.sendFailure,
  });

  final Conversation conversation;
  final List<Message> messages;
  final bool isSending;
  final bool otherIsTyping;
  final Failure? sendFailure;

  ConversationState copyWith({
    List<Message>? messages,
    bool? isSending,
    bool? otherIsTyping,
    Failure? sendFailure,
    bool clearFailure = false,
  }) => ConversationState(
    conversation: conversation,
    messages: messages ?? this.messages,
    isSending: isSending ?? this.isSending,
    otherIsTyping: otherIsTyping ?? this.otherIsTyping,
    sendFailure: clearFailure ? null : (sendFailure ?? this.sendFailure),
  );
}

class ConversationViewModel extends AsyncNotifier<ConversationState> {
  ConversationViewModel(this.conversationId);

  final String conversationId;

  static const _uuid = Uuid();

  @override
  Future<ConversationState> build() async {
    final repository = ref.watch(chatRepositoryProvider);
    final socket = ref.watch(chatSocketProvider);
    final pending = <ChatEvent>[];
    var ready = false;
    final sub = socket.events.listen((event) {
      if (!ready) {
        pending.add(event);
        return;
      }
      _apply(event);
    });
    ref.onDispose(sub.cancel);

    final conversation = await repository.getConversation(conversationId);
    ref
        .read(presenceProvider.notifier)
        .seed(conversation.otherUser.id, conversation.otherIsOnline);
    final page = await repository.getMessages(conversationId);
    final myUserId = ref.read(sessionViewModelProvider).value?.userId ?? '';
    final messages = await _mergeCallHistory(
      page.items,
      myUserId: myUserId,
    );
    final incoming = messages.where(
      (message) =>
          message.senderId == conversation.otherUser.id &&
          !message.isUnsent &&
          !message.isCallEvent,
    );
    if (incoming.isNotEmpty) {
      unawaited(
        repository.markRead(incoming.last.id).then((_) {}, onError: (_, _) {}),
      );
    }
    var state = ConversationState(
      conversation: conversation,
      messages: messages,
    );
    ready = true;
    for (final event in pending) {
      state = _reduce(state, event);
    }
    return state;
  }

  Future<List<Message>> _mergeCallHistory(
    List<Message> messages, {
    required String myUserId,
  }) async {
    final config = ref.read(appConfigProvider);
    if (!config.featureFlags.calls || myUserId.isEmpty) return messages;
    try {
      final history = await ref
          .read(callRepositoryProvider)
          .listHistory(limit: 50);
      final callMessages = [
        for (final call in history)
          if (call.conversationId == conversationId && call.isTerminal)
            Message.fromCallSession(call, myUserId: myUserId),
      ];
      if (callMessages.isEmpty) return messages;
      return _mergeMessages(messages, callMessages);
    } catch (_) {
      return messages;
    }
  }

  List<Message> _mergeMessages(List<Message> a, List<Message> b) {
    final byId = <String, Message>{
      for (final message in a) message.id: message,
    };
    for (final message in b) {
      byId.putIfAbsent(message.id, () => message);
      if (message.call != null) {
        byId.putIfAbsent('call_${message.call!.callId}', () => message);
      }
    }
    final merged = byId.values.toList()
      ..sort((left, right) => left.sentAt.compareTo(right.sentAt));
    return merged;
  }

  void _apply(ChatEvent event) {
    final current = state.value;
    if (current == null || !ref.mounted) return;
    final next = _reduce(current, event);
    if (!identical(next, current)) state = AsyncData(next);
    if (event is MessageArrived &&
        event.message.conversationId == conversationId &&
        event.message.senderId == current.conversation.otherUser.id &&
        !event.message.isUnsent) {
      unawaited(
        ref
            .read(chatRepositoryProvider)
            .markRead(event.message.id)
            .then((_) {}, onError: (_, _) {}),
      );
    }
  }

  ConversationState _reduce(ConversationState current, ChatEvent event) {
    switch (event) {
      case MessageArrived(:final message):
        if (message.conversationId != conversationId) return current;
        final duplicate = current.messages.any(
          (item) =>
              item.id == message.id ||
              (item.clientMessageId != null &&
                  item.clientMessageId == message.clientMessageId),
        );
        if (duplicate) return current;
        return current.copyWith(
          messages: [...current.messages, message],
          otherIsTyping: message.senderId == current.conversation.otherUser.id
              ? false
              : current.otherIsTyping,
        );
      case TypingChanged(:final conversationId, :final userId, :final isTyping):
        if (conversationId != this.conversationId ||
            userId != current.conversation.otherUser.id) {
          return current;
        }
        return current.copyWith(otherIsTyping: isTyping);
      case MessagesRead(:final conversationId, :final readerId, :final upToMessageId):
        if (conversationId != this.conversationId) return current;
        final index = current.messages.indexWhere((item) => item.id == upToMessageId);
        if (index < 0) return current;
        final boundary = current.messages[index].sentAt;
        return current.copyWith(
          messages: [
            for (final message in current.messages)
              if (message.senderId != readerId && !message.sentAt.isAfter(boundary))
                message.copyWith(status: MessageStatus.read)
              else
                message,
          ],
        );
      case MessageDeleted(:final conversationId, :final messageId):
        if (conversationId != this.conversationId) return current;
        return current.copyWith(
          messages: [
            for (final message in current.messages)
              if (message.id != messageId) message,
          ],
        );
      case MessageUnsent(:final conversationId, :final messageId, :final message):
        if (conversationId != this.conversationId) return current;
        return current.copyWith(
          messages: [
            for (final item in current.messages)
              if (item.id == messageId) message else item,
          ],
        );
      case ConversationDeleted(:final conversationId):
        if (conversationId != this.conversationId) return current;
        return current;
      case CallRejected(:final call):
      case CallCancelled(:final call):
      case CallEnded(:final call):
      case CallMissed(:final call):
      case CallBusy(:final call):
        return _upsertCallEvent(current, call);
      case CallIncoming():
      case CallAccepted():
      case PresenceChanged():
      case SocketConnected():
      case SessionLost():
      case MatchArrived():
      case MatchRemoved():
      case EntitlementChanged():
        return current;
    }
  }

  ConversationState _upsertCallEvent(
    ConversationState current,
    CallSession call,
  ) {
    if (call.conversationId != conversationId || !call.isTerminal) {
      return current;
    }
    final myUserId = ref.read(sessionViewModelProvider).value?.userId ?? '';
    if (myUserId.isEmpty) return current;
    final event = Message.fromCallSession(call, myUserId: myUserId);
    final without = [
      for (final message in current.messages)
        if (message.id != event.id &&
            message.call?.callId != call.id)
          message,
    ];
    return current.copyWith(messages: [...without, event]);
  }

  Future<Failure?> deleteConversation() async {
    try {
      await ref.read(chatRepositoryProvider).deleteConversation(conversationId);
      if (!ref.mounted) return null;
      ref.invalidate(conversationsViewModelProvider);
      return null;
    } on Failure catch (failure) {
      return failure;
    }
  }

  Future<Failure?> deleteMessageForMe(String messageId) async {
    final current = state.value;
    if (current == null) return null;
    try {
      await ref.read(chatRepositoryProvider).deleteMessageForMe(messageId);
      if (!ref.mounted) return null;
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          messages: [
            for (final message in latest.messages)
              if (message.id != messageId) message,
          ],
        ),
      );
      ref.invalidate(conversationsViewModelProvider);
      return null;
    } on Failure catch (failure) {
      return failure;
    }
  }

  Future<Failure?> unsendMessage(String messageId) async {
    final current = state.value;
    if (current == null) return null;
    try {
      final updated =
          await ref.read(chatRepositoryProvider).unsendMessage(messageId);
      if (!ref.mounted) return null;
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          messages: [
            for (final message in latest.messages)
              if (message.id == messageId) updated else message,
          ],
        ),
      );
      ref.invalidate(conversationsViewModelProvider);
      return null;
    } on Failure catch (failure) {
      return failure;
    }
  }

  /// Returns true when the message was accepted.
  Future<bool> send(String text) => _send(text.trim());

  Future<bool> sendPhoto(LocalImage image) async {
    final current = state.value;
    if (current == null) return false;
    final myUserId = ref.read(sessionViewModelProvider).value?.userId ?? '';
    if (myUserId.isEmpty) return false;
    final clientId = _uuid.v4();
    final optimistic = Message(
      id: 'local_$clientId',
      conversationId: conversationId,
      senderId: myUserId,
      text: '',
      sentAt: DateTime.now().toUtc(),
      clientMessageId: clientId,
      attachment: MessageAttachment(
        mediaId: 'local',
        url: Uri.file(image.path).toString(),
      ),
    );
    state = AsyncData(
      current.copyWith(
        messages: [...current.messages, optimistic],
        isSending: true,
        clearFailure: true,
      ),
    );
    try {
      final uploaded = await ref
          .read(onboardingRepositoryProvider)
          .uploadPhoto(image, purpose: 'CHAT_ATTACHMENT');
      final message = await ref.read(chatRepositoryProvider).sendMessage(
        conversationId: conversationId,
        text: '',
        clientMessageId: clientId,
        attachmentMediaId: uploaded.mediaId,
      );
      if (!ref.mounted) return true;
      return _replaceOptimistic(clientId, message);
    } on Failure catch (failure) {
      if (!ref.mounted) return false;
      _removeOptimistic(clientId, failure);
      return false;
    }
  }

  /// Sends a store gift (must already be owned / affordable on the server).
  Future<bool> sendGift(String giftItemId) async {
    final current = state.value;
    if (current == null || current.isSending || giftItemId.isEmpty) return false;
    state = AsyncData(current.copyWith(isSending: true, clearFailure: true));
    try {
      final message = await ref.read(chatRepositoryProvider).sendGift(
        conversationId: conversationId,
        giftItemId: giftItemId,
        clientMessageId: _uuid.v4(),
      );
      if (!ref.mounted) return true;
      return _appendSent(current, message);
    } on Failure catch (failure) {
      if (!ref.mounted) return false;
      state = AsyncData(current.copyWith(isSending: false, sendFailure: failure));
      return false;
    }
  }

  /// Sends one emoji from an owned paid pack.
  Future<bool> sendPaidEmoji({
    required String emoji,
    required String packId,
  }) => _send(emoji, emojiPackId: packId);

  Future<bool> _send(
    String text, {
    String? attachmentMediaId,
    String? giftItemId,
    String? emojiPackId,
  }) async {
    final current = state.value;
    if (current == null) return false;
    if (text.isEmpty && attachmentMediaId == null && giftItemId == null) {
      return false;
    }
    final myUserId = ref.read(sessionViewModelProvider).value?.userId ?? '';
    if (myUserId.isEmpty) return false;
    final clientId = _uuid.v4();
    final optimistic = Message(
      id: 'local_$clientId',
      conversationId: conversationId,
      senderId: myUserId,
      text: text,
      sentAt: DateTime.now().toUtc(),
      clientMessageId: clientId,
    );
    // Show the bubble immediately — don't wait for the network round-trip.
    state = AsyncData(
      current.copyWith(
        messages: [...current.messages, optimistic],
        isSending: true,
        clearFailure: true,
      ),
    );
    try {
      final message = await ref.read(chatRepositoryProvider).sendMessage(
        conversationId: conversationId,
        text: text,
        clientMessageId: clientId,
        attachmentMediaId: attachmentMediaId,
        giftItemId: giftItemId,
        emojiPackId: emojiPackId,
      );
      if (!ref.mounted) return true;
      return _replaceOptimistic(clientId, message);
    } on Failure catch (failure) {
      if (!ref.mounted) return false;
      _removeOptimistic(clientId, failure);
      return false;
    }
  }

  bool _replaceOptimistic(String clientId, Message message) {
    final latest = state.value;
    if (latest == null) return true;
    final withoutLocal = [
      for (final item in latest.messages)
        if (item.clientMessageId != clientId && item.id != message.id) item,
    ];
    state = AsyncData(
      latest.copyWith(
        messages: [...withoutLocal, message],
        isSending: false,
        clearFailure: true,
      ),
    );
    ref.invalidate(conversationsViewModelProvider);
    return true;
  }

  void _removeOptimistic(String clientId, Failure failure) {
    final latest = state.value;
    if (latest == null) return;
    state = AsyncData(
      latest.copyWith(
        messages: [
          for (final item in latest.messages)
            if (item.clientMessageId != clientId) item,
        ],
        isSending: false,
        sendFailure: failure,
      ),
    );
  }

  bool _appendSent(ConversationState current, Message message) {
    final latest = state.value ?? current;
    final duplicate = latest.messages.any(
      (item) =>
          item.id == message.id ||
          (item.clientMessageId != null &&
              item.clientMessageId == message.clientMessageId),
    );
    state = AsyncData(
      latest.copyWith(
        messages: duplicate ? latest.messages : [...latest.messages, message],
        isSending: false,
        clearFailure: true,
      ),
    );
    ref.invalidate(conversationsViewModelProvider);
    return true;
  }
}

final conversationViewModelProvider = AsyncNotifierProvider.autoDispose
    .family<ConversationViewModel, ConversationState, String>(
      ConversationViewModel.new,
    );
