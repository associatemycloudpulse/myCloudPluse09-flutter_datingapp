import 'dart:io';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/json.dart';
import '../../domain/entities/subscription.dart';
import '../../domain/repositories/subscription_repository.dart';
import '../models/subscription_dto.dart';

class ApiSubscriptionRepository implements SubscriptionRepository {
  ApiSubscriptionRepository(this._client);

  final ApiClient _client;

  String get _platform => Platform.isIOS ? 'IOS' : 'ANDROID';

  @override
  Future<List<SubscriptionProduct>> getProducts() async => [
    for (final json in asJsonList(
      asJson(await _client.get(ApiEndpoints.subscriptionProducts))['items'],
    ))
      SubscriptionProductDto.fromJson(json),
  ];

  @override
  Future<Entitlement> getEntitlement() async => EntitlementDto.fromJson(
    asJson(await _client.get(ApiEndpoints.subscriptionEntitlement)),
  );

  /// Prefers checkout → verify (demo). Falls back to legacy verify body.
  @override
  Future<Entitlement> purchase(String productId) async {
    try {
      final started = await checkout(productId: productId, platform: _platform);
      return await verifyCheckout(
        checkoutId: started.checkoutId,
        outcome: 'SUCCESS',
      );
    } catch (_) {
      return EntitlementDto.fromJson(
        asJson(
          await _client.post(
            ApiEndpoints.subscriptionVerify,
            body: {
              'platform': _platform,
              'productId': productId,
              'transactionProof':
                  'dev-local-$productId-${DateTime.now().millisecondsSinceEpoch}',
            },
          ),
        ),
      );
    }
  }

  @override
  Future<Entitlement> restore() async => EntitlementDto.fromJson(
    asJson(
      await _client.post(
        ApiEndpoints.subscriptionRestore,
        body: {
          'platform': _platform,
          'transactionProofs': <String>[],
        },
      ),
    ),
  );

  @override
  Future<List<SubscriptionHistoryItem>> history() async {
    final data = asJson(await _client.get(ApiEndpoints.subscriptionHistory));
    return [
      for (final json in asJsonList(data['items'], 'items'))
        SubscriptionHistoryItem(
          id: json.req<String>('id'),
          productId: json.opt<String>('productId') ?? '',
          status: json.opt<String>('status') ?? 'UNKNOWN',
          at: json.reqDate('createdAt'),
        ),
    ];
  }

  @override
  Future<SubscriptionCheckout> checkout({
    required String productId,
    required String platform,
  }) async {
    final json = asJson(
      await _client.post(
        ApiEndpoints.subscriptionCheckout,
        body: {'productId': productId, 'platform': platform},
      ),
    );
    return SubscriptionCheckout(
      checkoutId: json.req<String>('checkoutId'),
      productId: productId,
      platform: platform,
    );
  }

  @override
  Future<Entitlement> verifyCheckout({
    required String checkoutId,
    required String outcome,
  }) async => EntitlementDto.fromJson(
    asJson(
      await _client.post(
        ApiEndpoints.subscriptionVerify,
        body: {
          'checkoutId': checkoutId,
          'providerProof': {'outcome': outcome},
        },
      ),
    ),
  );

  @override
  Future<Entitlement> cancel() async => EntitlementDto.fromJson(
    asJson(await _client.post(ApiEndpoints.subscriptionCancel)),
  );
}
