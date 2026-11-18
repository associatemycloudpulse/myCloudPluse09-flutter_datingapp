import '../../../../core/network/json.dart';
import '../../../calls/data/models/call_dto.dart';
import '../../../calls/domain/entities/call.dart';
import '../../../profile/data/models/profile_dto.dart';
import '../../domain/entities/chat.dart';

class MessageDto {
  static Message fromJson(Json json, {String? myUserId}) {
    final call = _call(json, myUserId: myUserId);
    return Message(
      id: json.req<String>('id'),
      conversationId: json.req<String>('conversationId'),
      senderId: json.req<String>('senderId'),
      text: json.opt<String>('text') ?? '',
      sentAt: json.reqDate('sentAt'),
      status: switch (json.opt<String>('status')) {
        'READ' => MessageStatus.read,
        'DELIVERED' => MessageStatus.delivered,
        'UNSENT' => MessageStatus.unsent,
        _ => MessageStatus.sent,
      },
      clientMessageId: json.opt<String>('clientMessageId'),
      attachment: _attachment(json['attachment']),
      gift: _gift(json),
      call: call,
      unsentAt: json.optDate('unsentAt'),
    );
  }

  static MessageAttachment? _attachment(Object? value) {
    if (value == null) return null;
    final json = asJson(value, 'attachment');
    return MessageAttachment(
      mediaId: json.req<String>('mediaId'),
      url: json.req<String>('url'),
    );
  }

  static MessageGift? _gift(Json json) {
    final nested = json['gift'];
    if (nested is Map) {
      final gift = asJson(nested, 'gift');
      return MessageGift(
        itemId:
            gift.opt<String>('itemId') ??
            gift.opt<String>('giftItemId') ??
            gift.opt<String>('id') ??
            '',
        name: gift.opt<String>('title') ?? gift.opt<String>('name') ?? 'Gift',
        emoji: gift.opt<String>('emoji') ?? '',
        imageUrl: gift.opt<String>('imageUrl') ?? '',
      );
    }
    final type = (json.opt<String>('type') ?? '').toUpperCase();
    final giftItemId =
        json.opt<String>('giftItemId') ?? json.opt<String>('itemId');
    if (type == 'GIFT' || (giftItemId != null && giftItemId.isNotEmpty)) {
      return MessageGift(
        itemId: giftItemId ?? '',
        name:
            json.opt<String>('giftTitle') ??
            json.opt<String>('title') ??
            'Gift',
        emoji: json.opt<String>('emoji') ?? '',
        imageUrl: json.opt<String>('imageUrl') ?? '',
      );
    }
    return null;
  }

  static MessageCall? _call(Json json, {String? myUserId}) {
    final type = (json.opt<String>('type') ?? '').toUpperCase();
    final nested = json['call'];
    CallSession? session;
    if (nested is Map) {
      try {
        session = CallDto.fromJson(asJson(nested, 'call'));
      } catch (_) {
        session = null;
      }
    }
    if (session == null &&
        (type == 'CALL' ||
            type == 'CALL_EVENT' ||
            type.startsWith('CALL_'))) {
      final callId =
          json.opt<String>('callId') ??
          json.opt<String>('id') ??
          '';
      final callType = switch ((json.opt<String>('callType') ?? type)
          .toUpperCase()) {
        'VIDEO' || 'CALL_VIDEO' => CallType.video,
        _ => CallType.audio,
      };
      final status = switch ((json.opt<String>('callStatus') ??
              json.opt<String>('status') ??
              '')
          .toUpperCase()) {
        'MISSED' => CallStatus.missed,
        'REJECTED' => CallStatus.rejected,
        'CANCELLED' => CallStatus.cancelled,
        'BUSY' => CallStatus.busy,
        'ENDED' => CallStatus.ended,
        'ACCEPTED' => CallStatus.accepted,
        _ => CallStatus.ended,
      };
      final durationSeconds = json.opt<num>('durationSeconds')?.toInt();
      return MessageCall(
        callId: callId,
        type: callType,
        status: status,
        outgoing: (json.opt<String>('direction') ?? '').toUpperCase() ==
            'OUTGOING',
        duration: durationSeconds == null
            ? null
            : Duration(seconds: durationSeconds),
      );
    }
    if (session == null) return null;
    return MessageCall.fromSession(
      session,
      myUserId: myUserId ?? session.callerId,
    );
  }

  static Json toJson(Message m) => {
    'id': m.id,
    'conversationId': m.conversationId,
    'senderId': m.senderId,
    'text': m.text,
    'sentAt': m.sentAt.toUtc().toIso8601String(),
    'status': m.status.name.toUpperCase(),
    'clientMessageId': m.clientMessageId,
    if (m.attachment != null)
      'attachment': {
        'mediaId': m.attachment!.mediaId,
        'url': m.attachment!.url,
      },
    if (m.gift != null)
      'gift': {
        'itemId': m.gift!.itemId,
        'title': m.gift!.name,
        'emoji': m.gift!.emoji,
        'imageUrl': m.gift!.imageUrl,
      },
    if (m.call != null)
      'type': 'CALL',
    if (m.call != null)
      'callId': m.call!.callId,
    if (m.call != null)
      'callType': m.call!.isVideo ? 'VIDEO' : 'AUDIO',
    if (m.call != null)
      'callStatus': m.call!.status.name.toUpperCase(),
    if (m.call?.duration != null)
      'durationSeconds': m.call!.duration!.inSeconds,
    if (m.unsentAt != null) 'unsentAt': m.unsentAt!.toUtc().toIso8601String(),
  };
}

class ConversationDto {
  static Conversation fromJson(Json json, {String? myUserId}) {
    final last = json['lastMessage'];
    return Conversation(
      id: json.req<String>('id'),
      matchId: json.req<String>('matchId'),
      otherUser: UserProfileDto.fromJson(asJson(json['otherUser'], 'otherUser'))
          .toEntity(),
      lastMessage: last == null
          ? null
          : MessageDto.fromJson(asJson(last, 'lastMessage'), myUserId: myUserId),
      unreadCount: json.opt<num>('unreadCount')?.toInt() ?? 0,
      otherIsOnline: _online(json['otherUser']),
    );
  }

  static bool? _online(Object? user) {
    if (user is! Map) return null;
    final value = user['isOnline'] ?? user['online'];
    if (value is bool) return value;
    final status = user['status'] ?? user['presence'];
    if (status is String) {
      switch (status.toLowerCase()) {
        case 'online':
          return true;
        case 'offline':
          return false;
      }
    }
    return null;
  }
}
