import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/json.dart';
import '../../../../core/network/pagination.dart';
import '../../domain/entities/chat.dart';
import '../../domain/repositories/chat_repository.dart';
import '../models/chat_dto.dart';

class ApiChatRepository implements ChatRepository {
  ApiChatRepository(this._client);

  final ApiClient _client;

  @override
  Future<Paginated<Conversation>> getConversations({
    PageRequest page = const PageRequest(),
  }) async => Paginated.fromJson(
    await _client.get(ApiEndpoints.conversations, query: page.toQuery()),
    ConversationDto.fromJson,
  );

  @override
  Future<Conversation> getConversation(String conversationId) async =>
      ConversationDto.fromJson(
        asJson(await _client.get(ApiEndpoints.conversation(conversationId))),
      );

  @override
  Future<Paginated<Message>> getMessages(
    String conversationId, {
    PageRequest page = const PageRequest(limit: 50),
  }) async => Paginated.fromJson(
    await _client.get(
      ApiEndpoints.messages(conversationId),
      query: page.toQuery(),
    ),
    MessageDto.fromJson,
  );

  @override
  Future<Message> sendMessage({
    required String conversationId,
    required String text,
    required String clientMessageId,
    String? attachmentMediaId,
    String? giftItemId,
    String? emojiPackId,
  }) async => MessageDto.fromJson(
    asJson(
      await _client.post(
        ApiEndpoints.messages(conversationId),
        body: {
          'text': text.trim(),
          'clientMessageId': clientMessageId,
          'attachmentMediaId': ?attachmentMediaId,
          'giftItemId': ?giftItemId,
          'emojiPackId': ?emojiPackId,
          if (giftItemId != null) 'type': 'GIFT',
        },
        idempotencyKey: clientMessageId,
      ),
    ),
  );

  @override
  Future<Message> sendGift({
    required String conversationId,
    required String giftItemId,
    required String clientMessageId,
  }) async {
    // Prefer conversation gifts (mirrors call gifts). Fall back to message
    // payload / store send-gift for backends that use those shapes.
    try {
      final data = asJson(
        await _client.post(
          ApiEndpoints.conversationGifts(conversationId),
          body: {
            'giftItemId': giftItemId,
            'clientMessageId': clientMessageId,
          },
          idempotencyKey: clientMessageId,
        ),
      );
      if (data.containsKey('id') && data.containsKey('conversationId')) {
        return MessageDto.fromJson(data);
      }
      final nested = data['message'];
      if (nested is Map) return MessageDto.fromJson(asJson(nested, 'message'));
    } on Failure catch (failure) {
      if (failure.code != ErrorCode.notFound) rethrow;
    }

    try {
      final data = asJson(
        await _client.post(
          ApiEndpoints.storeSendGift,
          body: {
            'giftItemId': giftItemId,
            'conversationId': conversationId,
            'clientMessageId': clientMessageId,
          },
          idempotencyKey: clientMessageId,
        ),
      );
      if (data.containsKey('id') && data.containsKey('conversationId')) {
        return MessageDto.fromJson(data);
      }
      final nested = data['message'];
      if (nested is Map) return MessageDto.fromJson(asJson(nested, 'message'));
    } on Failure catch (failure) {
      if (failure.code != ErrorCode.notFound) rethrow;
    }

    return sendMessage(
      conversationId: conversationId,
      text: '',
      clientMessageId: clientMessageId,
      giftItemId: giftItemId,
    );
  }

  @override
  Future<void> markRead(String messageId) async {
    await _client.post(ApiEndpoints.messageRead(messageId));
  }

  @override
  Future<void> deleteConversation(String conversationId) async {
    await _client.delete(ApiEndpoints.conversation(conversationId));
  }

  @override
  Future<void> deleteMessageForMe(String messageId) async {
    await _client.delete(ApiEndpoints.message(messageId));
  }

  @override
  Future<Message> unsendMessage(String messageId) async => MessageDto.fromJson(
    asJson(await _client.post(ApiEndpoints.messageUnsend(messageId))),
  );
}
