enum CallType { audio, video }

enum CallStatus {
  ringing,
  accepted,
  rejected,
  cancelled,
  missed,
  busy,
  ended,
}

enum CallDirection { incoming, outgoing }

class CallCredentials {
  const CallCredentials({
    required this.appId,
    required this.channelName,
    required this.token,
    required this.uid,
    required this.expiresAt,
  });

  final String appId;
  final String channelName;
  final String token;
  final int uid;
  final DateTime expiresAt;

  bool get isJoinable =>
      appId.isNotEmpty &&
      channelName.isNotEmpty &&
      token.isNotEmpty &&
      !appId.startsWith('mock');
}

class CallSession {
  const CallSession({
    required this.id,
    required this.conversationId,
    required this.callerId,
    required this.calleeId,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.ringExpiresAt,
    this.acceptedAt,
    this.endedAt,
  });

  final String id;
  final String conversationId;
  final String callerId;
  final String calleeId;
  final CallType type;
  final CallStatus status;
  final DateTime createdAt;
  final DateTime ringExpiresAt;
  final DateTime? acceptedAt;
  final DateTime? endedAt;

  bool get isTerminal => switch (status) {
    CallStatus.rejected ||
    CallStatus.cancelled ||
    CallStatus.missed ||
    CallStatus.busy ||
    CallStatus.ended => true,
    CallStatus.ringing || CallStatus.accepted => false,
  };

  /// Connected talk time when the call was accepted and later ended.
  Duration? get talkDuration {
    final start = acceptedAt;
    final end = endedAt;
    if (start == null || end == null) return null;
    final value = end.difference(start);
    return value.isNegative ? Duration.zero : value;
  }

  String get mediaLabel => type == CallType.video ? 'Video call' : 'Voice call';

  String get durationLabel {
    final duration = talkDuration;
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

  /// Chat / inbox preview text for this call relative to [myUserId].
  String chatLabel({required String myUserId}) {
    final outgoing = callerId == myUserId;
    final media = mediaLabel;
    return switch (status) {
      CallStatus.missed =>
        outgoing ? '$media · No answer' : 'Missed ${media.toLowerCase()}',
      CallStatus.rejected =>
        outgoing ? '$media declined' : 'Declined ${media.toLowerCase()}',
      CallStatus.cancelled =>
        outgoing ? 'Cancelled ${media.toLowerCase()}' : '$media cancelled',
      CallStatus.busy => '$media · Busy',
      CallStatus.ended =>
        talkDuration == null ? '$media · Ended' : '$media · $durationLabel',
      CallStatus.ringing || CallStatus.accepted => media,
    };
  }

  CallSession copyWith({
    CallStatus? status,
    DateTime? acceptedAt,
    DateTime? endedAt,
  }) => CallSession(
    id: id,
    conversationId: conversationId,
    callerId: callerId,
    calleeId: calleeId,
    type: type,
    status: status ?? this.status,
    createdAt: createdAt,
    ringExpiresAt: ringExpiresAt,
    acceptedAt: acceptedAt ?? this.acceptedAt,
    endedAt: endedAt ?? this.endedAt,
  );
}

class CallStartResult {
  const CallStartResult({required this.call, this.credentials});

  final CallSession call;
  final CallCredentials? credentials;
}

class ActiveCallSnapshot {
  const ActiveCallSnapshot({
    required this.call,
    required this.direction,
    this.credentials,
  });

  final CallSession? call;
  final CallDirection? direction;
  final CallCredentials? credentials;

  bool get hasCall => call != null;
}

class CallAcceptResult {
  const CallAcceptResult({required this.call, required this.credentials});

  final CallSession call;
  final CallCredentials credentials;
}
