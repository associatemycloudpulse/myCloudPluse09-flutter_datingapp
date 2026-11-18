import '../entities/call.dart';

abstract class CallRepository {
  Future<CallStartResult> start({
    required String conversationId,
    required CallType type,
  });

  Future<CallAcceptResult> accept(String callId);

  Future<CallSession> reject(String callId);

  Future<CallSession> cancel(String callId);

  Future<CallSession> end(String callId);

  Future<ActiveCallSnapshot> getActive();

  Future<List<CallSession>> listHistory({int limit = 20});

  /// Sends a store gift during an active call.
  Future<void> sendGift({
    required String callId,
    required String giftItemId,
  });
}
