import 'dart:io';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/json.dart';
import '../../domain/entities/store.dart';
import '../../domain/repositories/store_repository.dart';

class ApiStoreRepository implements StoreRepository {
  ApiStoreRepository(this._client);

  final ApiClient _client;

  StoreItemKind _kind(String raw) => switch (raw.toUpperCase()) {
    'GIFT' => StoreItemKind.gift,
    'EMOJI_PACK' || 'EMOJI' => StoreItemKind.emojiPack,
    _ => StoreItemKind.coinPack,
  };

  StoreItem _item(Json json) => StoreItem(
    id: json.req<String>('id'),
    name:
        json.opt<String>('title') ??
        json.opt<String>('name') ??
        json.req<String>('id'),
    kind: _kind(
      json.opt<String>('kind') ?? json.opt<String>('type') ?? 'COIN_PACK',
    ),
    priceCoins: json.opt<num>('priceCoins')?.toInt(),
    priceLabel: json.opt<String>('priceLabel'),
    description: json.opt<String>('description') ?? '',
    emoji: json.opt<String>('emoji') ?? '',
    imageUrl: json.opt<String>('imageUrl') ?? '',
    emojis: json.stringList('emojis'),
    giftCategory: json.opt<String>('giftCategory') ?? '',
    coinAmount: json.opt<num>('coinAmount')?.toInt(),
  );

  StoreWallet _wallet(Json json) => StoreWallet(
    coinBalance:
        json.opt<num>('coinBalance')?.toInt() ??
        json.opt<num>('balance')?.toInt() ??
        0,
    ownedPackIds: json.stringList('ownedPackIds'),
    giftInventory: _giftInventory(json),
  );

  List<String> _giftInventory(Json json) {
    final ids = json.stringList('giftInventory');
    if (ids.isNotEmpty) return ids;
    final raw = json['giftInventory'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is String)
          item
        else if (item is Map && item['id'] is String)
          item['id'] as String
        else if (item is Map && item['itemId'] is String)
          item['itemId'] as String,
    ];
  }

  @override
  Future<List<StoreItem>> catalog() async {
    final data = asJson(await _client.get(ApiEndpoints.storeCatalog));
    final items = asJsonList(data['items'], 'items');
    if (items.isNotEmpty) {
      return [for (final json in items) _item(json)];
    }
    // Some backends also split packs/gifts alongside `items`.
    return [
      for (final json in asJsonList(data['coinPacks'] ?? const [], 'coinPacks'))
        _item(json),
      for (final json in asJsonList(data['emojiPacks'] ?? const [], 'emojiPacks'))
        _item(json),
      for (final json in asJsonList(data['gifts'] ?? const [], 'gifts'))
        _item(json),
    ];
  }

  @override
  Future<StoreWallet> wallet() async =>
      _wallet(asJson(await _client.get(ApiEndpoints.storeWallet)));

  @override
  Future<List<StoreHistoryItem>> history() async {
    final data = asJson(await _client.get(ApiEndpoints.storeHistory));
    return [
      for (final json in asJsonList(data['items'], 'items'))
        StoreHistoryItem(
          id: json.req<String>('id'),
          title:
              json.opt<String>('title') ??
              json.opt<String>('description') ??
              'Purchase',
          at: json.reqDate('createdAt'),
          coinsDelta: json.opt<num>('coinsDelta')?.toInt(),
        ),
    ];
  }

  @override
  Future<StoreCheckout> checkout({
    required String productId,
    required String platform,
  }) async {
    final json = asJson(
      await _client.post(
        ApiEndpoints.storeCheckout,
        body: {
          'productId': productId,
          'platform': platform.isEmpty
              ? (Platform.isIOS ? 'IOS' : 'ANDROID')
              : platform,
        },
      ),
    );
    return StoreCheckout(
      checkoutId: json.req<String>('checkoutId'),
      productId: productId,
      platform: platform,
    );
  }

  @override
  Future<StoreWallet> verify({
    required String checkoutId,
    required String outcome,
  }) async => _wallet(
    asJson(
      await _client.post(
        ApiEndpoints.storeVerify,
        body: {
          'checkoutId': checkoutId,
          'providerProof': {'outcome': outcome},
        },
      ),
    ),
  );

  @override
  Future<StoreWallet> buyWithCoins({required String itemId}) async => _wallet(
    asJson(
      await _client.post(
        ApiEndpoints.storeBuyWithCoins,
        body: {'itemId': itemId},
      ),
    ),
  );
}
