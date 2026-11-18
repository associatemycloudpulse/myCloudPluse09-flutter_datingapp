import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/repository_providers.dart';
import '../../../../core/network/pagination.dart';
import '../../../../core/realtime/chat_events.dart';
import '../../../../core/realtime/chat_socket.dart';
import '../../../../core/realtime/presence.dart';
import '../../../auth/presentation/viewmodels/session_view_model.dart';
import '../../../calls/domain/entities/call.dart';
import '../../domain/entities/chat.dart';

class ConversationsViewModel extends AsyncNotifier<List<Conversation>> {
  @override
  Future<List<Conversation>> build() async {
    final socket = ref.watch(chatSocketProvider);
    final sub = socket.events.listen(_onEvent);
    ref.onDispose(sub.cancel);

    final page = await ref
        .watch(chatRepositoryProvider)
        .getConversations(page: const PageRequest(limit: 50));
    final presence = ref.read(presenceProvider.notifier);
    for (final conversation in page.items) {
      presence.seed(conversation.otherUser.id, conversation.otherIsOnline);
    }
    return page.items;
  }

  void _onEvent(ChatEvent event) {
    final current = state.value;
    if (current == null || !ref.mounted) return;
    switch (event) {
      case CallRejected(:final call):
      case CallCancelled(:final call):
      case CallEnded(:final call):
      case CallMissed(:final call):
      case CallBusy(:final call):
        _applyCall(current, call);
      case MessageArrived(:final message):
        _applyMessage(current, message);
      default:
        break;
    }
  }

  void _applyCall(List<Conversation> current, CallSession call) {
    if (!call.isTerminal) return;
    final myUserId = ref.read(sessionViewModelProvider).value?.userId ?? '';
    if (myUserId.isEmpty) return;
    final eventMessage = Message.fromCallSession(call, myUserId: myUserId);
    final next = [
      for (final conversation in current)
        if (conversation.id == call.conversationId)
          conversation.copyWith(lastMessage: eventMessage)
        else
          conversation,
    ];
    // Keep the updated conversation near the top.
    next.sort((a, b) {
      final aAt = a.lastMessage?.sentAt;
      final bAt = b.lastMessage?.sentAt;
      if (aAt == null && bAt == null) return 0;
      if (aAt == null) return 1;
      if (bAt == null) return -1;
      return bAt.compareTo(aAt);
    });
    state = AsyncData(next);
  }

  void _applyMessage(List<Conversation> current, Message message) {
    final next = [
      for (final conversation in current)
        if (conversation.id == message.conversationId)
          conversation.copyWith(
            lastMessage: message,
            unreadCount:
                message.senderId == conversation.otherUser.id
                    ? conversation.unreadCount + 1
                    : conversation.unreadCount,
          )
        else
          conversation,
    ]..sort((a, b) {
      final aAt = a.lastMessage?.sentAt;
      final bAt = b.lastMessage?.sentAt;
      if (aAt == null && bAt == null) return 0;
      if (aAt == null) return 1;
      if (bAt == null) return -1;
      return bAt.compareTo(aAt);
    });
    state = AsyncData(next);
  }
}

final conversationsViewModelProvider =
    AsyncNotifierProvider.autoDispose<
      ConversationsViewModel,
      List<Conversation>
    >(ConversationsViewModel.new);
