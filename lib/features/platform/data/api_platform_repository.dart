import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/json.dart';
import '../../../core/push/push_notifications.dart';
import '../../profile/data/models/profile_dto.dart';
import '../domain/platform_models.dart';
import '../domain/platform_repository.dart';

class ApiPlatformRepository implements PlatformRepository {
  ApiPlatformRepository(this._client);

  final ApiClient _client;
  static const _deviceIdKey = 'dating_cloud_device_id';

  @override
  Future<List<LikedPerson>> likesReceived() async => _likes(
    await _client.get(ApiEndpoints.likesReceived),
  );

  @override
  Future<List<LikedPerson>> likesSent() async =>
      _likes(await _client.get(ApiEndpoints.likesSent));

  List<LikedPerson> _likes(Object? data) => [
    for (final json in asJsonList(asJson(data)['items']))
      LikedPerson(
        user: UserProfileDto.fromJson(asJson(json['user'], 'user')).toEntity(),
        action: json.req<String>('action'),
        likedAt: json.reqDate('likedAt'),
      ),
  ];

  @override
  Future<void> blockUser(String userId) async {
    await _client.post(ApiEndpoints.blockUser(userId));
  }

  @override
  Future<void> unblockUser(String userId) async {
    await _client.delete(ApiEndpoints.blockUser(userId));
  }

  @override
  Future<List<BlockedMember>> blocks() async => [
    for (final json in asJsonList(asJson(await _client.get(ApiEndpoints.blocks))['items']))
      BlockedMember(
        id: asJson(json['user'], 'user').req<String>('id'),
        displayName: asJson(json['user'], 'user').req<String>('displayName'),
        blockedAt: json.reqDate('blockedAt'),
      ),
  ];

  @override
  Future<void> reportUser({
    required String userId,
    required String reason,
    String? details,
    bool alsoBlock = true,
  }) async {
    await _client.post(
      ApiEndpoints.reports,
      body: {
        'targetType': 'USER',
        'targetId': userId,
        'reason': reason,
        if (details != null && details.trim().isNotEmpty) 'details': details.trim(),
        'alsoBlock': alsoBlock,
      },
    );
  }

  @override
  Future<void> reportMessage({
    required String messageId,
    required String reason,
    bool alsoBlock = true,
  }) async {
    await _client.post(
      ApiEndpoints.messageReport(messageId),
      body: {'reason': reason, 'alsoBlock': alsoBlock},
    );
  }

  @override
  Future<List<InboxNotification>> notifications() async => [
    for (final json in asJsonList(
      asJson(await _client.get(ApiEndpoints.notifications))['items'],
    ))
      InboxNotification(
        id: json.req<String>('id'),
        title: json.req<String>('title'),
        body: json.req<String>('body'),
        createdAt: json.reqDate('createdAt'),
        readAt: json.optDate('readAt'),
      ),
  ];

  @override
  Future<void> markNotificationRead(String notificationId) async {
    await _client.post(ApiEndpoints.notificationRead(notificationId));
  }

  NotificationPreferences _prefs(Json json) => NotificationPreferences(
    newMatches: json.opt<bool>('newMatches') ?? true,
    messages: json.opt<bool>('messages') ?? true,
    likes: json.opt<bool>('likes') ?? true,
    promotions: json.opt<bool>('promotions') ?? false,
  );

  @override
  Future<NotificationPreferences> notificationPreferences() async =>
      _prefs(asJson(await _client.get(ApiEndpoints.notificationPreferences)));

  @override
  Future<NotificationPreferences> updateNotificationPreferences(
    NotificationPreferences preferences,
  ) async => _prefs(
    asJson(
      await _client.patch(
        ApiEndpoints.notificationPreferences,
        body: {
          'newMatches': preferences.newMatches,
          'messages': preferences.messages,
          'likes': preferences.likes,
          'promotions': preferences.promotions,
        },
      ),
    ),
  );

  @override
  Future<String?> registerDevice() async {
    final fcmToken = await PushNotifications.resolvePushToken();
    // Backend rejects tokens shorter than 8 chars. Prefer real FCM; fall back
    // only so local/dev builds without Firebase still pass device upsert.
    final pushToken =
        (fcmToken != null && fcmToken.length >= 8)
            ? fcmToken
            : 'local-device-dating-cloud';
    final json = asJson(
      await _client.post(
        ApiEndpoints.devices,
        body: {
          'platform': Platform.isIOS ? 'IOS' : 'ANDROID',
          'pushToken': pushToken,
          'appVersion': '1.0.0',
          'locale': Platform.localeName,
        },
      ),
    );
    final id = json.opt<String>('id');
    if (id != null && id.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  @override
  Future<void> unregisterDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_deviceIdKey);
    if (id == null || id.isEmpty) return;
    try {
      await _client.delete(ApiEndpoints.device(id));
    } finally {
      await prefs.remove(_deviceIdKey);
    }
  }

  @override
  Future<List<FaqItem>> faqs() async => [
    for (final json in asJsonList(
      asJson(
        await _client.get(ApiEndpoints.supportFaqs, ),
      )['items'],
    ))
      FaqItem(
        id: json.req<String>('id'),
        category: json.req<String>('category'),
        question: json.req<String>('question'),
        answer: json.req<String>('answer'),
      ),
  ];

  @override
  Future<SupportTicketCreated> createTicket({
    required String category,
    required String subject,
    required String message,
  }) async {
    final json = asJson(
      await _client.post(
        ApiEndpoints.supportTickets,
        body: {'category': category, 'subject': subject, 'message': message},
      ),
    );
    return SupportTicketCreated(
      id: json.req<String>('id'),
      subject: json.req<String>('subject'),
    );
  }

  @override
  Future<DeletionSchedule> requestDeletion({String? reason}) async {
    final json = asJson(
      await _client.post(
        ApiEndpoints.accountDeletionRequest,
        body: {
          'confirm': true,
          if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        },
      ),
    );
    return DeletionSchedule(
      scheduledFor: json.reqDate('scheduledFor'),
      activeStoreSubscription: json.opt<bool>('activeStoreSubscription') ?? false,
    );
  }

  @override
  Future<String> exportStatus() async {
    final json = asJson(await _client.get(ApiEndpoints.accountExportStatus));
    return json.opt<String>('status') ?? 'NONE';
  }

  @override
  Future<void> submitVerification(String selfieMediaId) async {
    await _client.post(
      ApiEndpoints.profileVerification,
      body: {'selfieMediaId': selfieMediaId},
    );
  }
}
