import '../../../calls/domain/entities/call.dart';
import '../../../profile/domain/entities/user_profile.dart';

enum MessageStatus { sent, delivered, read, unsent }

class MessageAttachment {
  const MessageAttachment({required this.mediaId, required this.url});

  final String mediaId;
  final String url;
}

class MessageGift {
  const MessageGift({
    required this.itemId,
    required this.name,
    this.emoji = '',
    this.imageUrl = '',
  });

  final String itemId;
  final String name;
  final String emoji;
  final String imageUrl;
}

class MessageCall {
  const MessageCall({
    required this.callId,
    required this.type,
    required this.status,
    required this.outgoing,
    this.duration,
  });

  final String callId;
  final CallType type;
  final CallStatus status;
  final bool outgoing;
  final Duration? duration;

  bool get isMissed => status == CallStatus.missed;

  bool get isVideo => type == CallType.video;

  String get label {
    final media = isVideo ? 'Video call' : 'Voice call';
    final durationLabel = _formatDuration(duration);
    return switch (status) {
      CallStatus.missed =>
        outgoing ? '$media · No answer' : 'Missed ${media.toLowerCase()}',
      CallStatus.rejected =>
        outgoing ? '$media declined' : 'Declined ${media.toLowerCase()}',
      CallStatus.cancelled =>
        outgoing ? 'Cancelled ${media.toLowerCase()}' : '$media cancelled',
      CallStatus.busy => '$media · Busy',
      CallStatus.ended =>
        durationLabel.isEmpty ? '$media · Ended' : '$media · $durationLabel',
      CallStatus.ringing || CallStatus.accepted => media,
    };
  }

  static MessageCall fromSession(CallSession call, {required String myUserId}) =>
      MessageCall(
        callId: call.id,
        type: call.type,
        status: call.status,
        outgoing: call.callerId == myUserId,
        duration: call.talkDuration,
      );

  static String _formatDuration(Duration? duration) {
    if (duration == null) return '';
    final total = duration.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.text,
    required this.sentAt,
    this.status = MessageStatus.sent,
    this.clientMessageId,
    this.attachment,
    this.gift,
    this.call,
    this.unsentAt,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String text;
  final DateTime sentAt;
  final MessageStatus status;
  final String? clientMessageId;
  final MessageAttachment? attachment;
  final MessageGift? gift;
  final MessageCall? call;
  final DateTime? unsentAt;

  bool get isUnsent => status == MessageStatus.unsent;
  bool get isCallEvent => call != null;

  String get preview {
    if (isUnsent) return 'This message was deleted';
    if (call != null) return call!.label;
    if (gift != null) {
      final glyph = gift!.emoji.isNotEmpty ? '${gift!.emoji} ' : '';
      return '$glyph${gift!.name}'.trim();
    }
    if (text.isNotEmpty) return text;
    return attachment == null ? '' : 'Photo';
  }

  Message copyWith({
    String? text,
    MessageStatus? status,
    MessageAttachment? attachment,
    MessageGift? gift,
    MessageCall? call,
    bool clearAttachment = false,
    bool clearGift = false,
    bool clearCall = false,
    DateTime? unsentAt,
  }) => Message(
    id: id,
    conversationId: conversationId,
    senderId: senderId,
    text: text ?? this.text,
    sentAt: sentAt,
    status: status ?? this.status,
    clientMessageId: clientMessageId,
    attachment: clearAttachment ? null : (attachment ?? this.attachment),
    gift: clearGift ? null : (gift ?? this.gift),
    call: clearCall ? null : (call ?? this.call),
    unsentAt: unsentAt ?? this.unsentAt,
  );

  static Message fromCallSession(
    CallSession call, {
    required String myUserId,
  }) => Message(
    id: 'call_${call.id}',
    conversationId: call.conversationId,
    senderId: call.callerId,
    text: '',
    sentAt: call.endedAt ?? call.acceptedAt ?? call.createdAt,
    call: MessageCall.fromSession(call, myUserId: myUserId),
  );
}

class Conversation {
  const Conversation({
    required this.id,
    required this.matchId,
    required this.otherUser,
    this.lastMessage,
    this.unreadCount = 0,
    this.otherIsOnline,
  });

  final String id;
  final String matchId;
  final UserProfile otherUser;
  final Message? lastMessage;
  final int unreadCount;

  /// `null` until the API or a presence event says online or offline.
  final bool? otherIsOnline;

  Conversation copyWith({
    Message? lastMessage,
    int? unreadCount,
    bool? otherIsOnline,
  }) => Conversation(
    id: id,
    matchId: matchId,
    otherUser: otherUser,
    lastMessage: lastMessage ?? this.lastMessage,
    unreadCount: unreadCount ?? this.unreadCount,
    otherIsOnline: otherIsOnline ?? this.otherIsOnline,
  );
}
