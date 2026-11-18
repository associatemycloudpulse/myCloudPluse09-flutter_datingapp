import '../../../../core/errors/failure.dart';
import '../../domain/entities/store.dart';
import '../../domain/repositories/store_repository.dart';

class MockStoreRepository implements StoreRepository {
  var _coins = 120;
  final _owned = <String>{};
  final _giftInventory = <String>{};
  final _history = <StoreHistoryItem>[];

  static const catalogItems = [
    StoreItem(
      id: 'coins_100',
      name: '100 Coins',
      kind: StoreItemKind.coinPack,
      priceLabel: '₹49',
      emoji: '🪙',
      coinAmount: 100,
      description: 'A small top-up for gifts and emoji packs.',
    ),
    StoreItem(
      id: 'emoji_pack_hearts',
      name: 'Hearts Pack',
      kind: StoreItemKind.emojiPack,
      priceCoins: 80,
      emoji: '💕',
      emojis: ['💕', '💖', '💗', '💓', '💞', '💘'],
      description: 'Premium heart emojis for your matches.',
    ),
    StoreItem(
      id: 'emoji_pack_neon',
      name: 'Neon Pack',
      kind: StoreItemKind.emojiPack,
      priceCoins: 120,
      emoji: '✨',
      emojis: ['✨', '🔥', '⚡', '🌟', '💫', '🪩'],
      description: 'Bold neon vibes for late-night chats.',
    ),
    StoreItem(
      id: 'gift_wave',
      name: 'Wave',
      kind: StoreItemKind.gift,
      priceCoins: 0,
      emoji: '👋',
      giftCategory: 'FREE',
      description: 'A free hello during calls and chat.',
    ),
    StoreItem(
      id: 'gift_rose',
      name: 'Rose',
      kind: StoreItemKind.gift,
      priceCoins: 10,
      emoji: '🌹',
      giftCategory: 'POPULAR',
      description: 'A classic first move.',
    ),
    StoreItem(
      id: 'gift_teddy',
      name: 'Teddy',
      kind: StoreItemKind.gift,
      priceCoins: 50,
      emoji: '🧸',
      giftCategory: 'POPULAR',
      description: 'Soft and thoughtful.',
    ),
    StoreItem(
      id: 'gift_crown',
      name: 'Crown',
      kind: StoreItemKind.gift,
      priceCoins: 1000,
      emoji: '👑',
      giftCategory: 'PREMIUM',
      description: 'Make them feel special.',
    ),
  ];

  @override
  Future<List<StoreItem>> catalog() async => catalogItems;

  @override
  Future<StoreWallet> wallet() async => StoreWallet(
    coinBalance: _coins,
    ownedPackIds: _owned.toList(growable: false),
    giftInventory: _giftInventory.toList(growable: false),
  );

  @override
  Future<List<StoreHistoryItem>> history() async =>
      List.unmodifiable(_history);

  @override
  Future<StoreCheckout> checkout({
    required String productId,
    required String platform,
  }) async => StoreCheckout(
    checkoutId: 'chk_mock_${DateTime.now().millisecondsSinceEpoch}',
    productId: productId,
    platform: platform,
  );

  @override
  Future<StoreWallet> verify({
    required String checkoutId,
    required String outcome,
  }) async {
    if (outcome.toUpperCase() != 'SUCCESS') {
      throw const Failure(
        ErrorCode.validationError,
        message: 'Payment was not completed.',
      );
    }
    final pack = catalogItems
        .where((item) => item.id == checkoutId.replaceFirst('chk_mock_', ''))
        .firstOrNull;
    final amount = pack?.coinAmount ?? 100;
    _coins += amount;
    _history.insert(
      0,
      StoreHistoryItem(
        id: checkoutId,
        title: pack?.name ?? 'Coin pack',
        at: DateTime.now().toUtc(),
        coinsDelta: amount,
      ),
    );
    return wallet();
  }

  @override
  Future<StoreWallet> buyWithCoins({required String itemId}) async {
    final item = catalogItems.where((entry) => entry.id == itemId).firstOrNull;
    if (item == null) throw const Failure(ErrorCode.notFound);
    if (item.kind == StoreItemKind.coinPack) {
      throw const Failure(
        ErrorCode.validationError,
        message: 'Buy coin packs with checkout, not coins.',
      );
    }
    if (item.kind == StoreItemKind.emojiPack && _owned.contains(item.id)) {
      return wallet();
    }
    if (item.kind == StoreItemKind.gift && _giftInventory.contains(item.id)) {
      return wallet();
    }
    final cost = item.priceCoins ?? 0;
    if (_coins < cost) {
      throw const Failure(
        ErrorCode.conflict,
        message: 'Not enough coins. Buy a coin pack first.',
      );
    }
    _coins -= cost;
    if (item.kind == StoreItemKind.emojiPack) _owned.add(item.id);
    if (item.kind == StoreItemKind.gift) _giftInventory.add(item.id);
    _history.insert(
      0,
      StoreHistoryItem(
        id: 'buy_$itemId',
        title: item.name,
        at: DateTime.now().toUtc(),
        coinsDelta: -cost,
      ),
    );
    return wallet();
  }

  /// Mock helper used by chat/call gift send to consume inventory or coins.
  Future<void> consumeGiftForSend(String giftItemId) async {
    final item = catalogItems.where((entry) => entry.id == giftItemId).firstOrNull;
    if (item == null || item.kind != StoreItemKind.gift) {
      throw const Failure(ErrorCode.notFound, message: 'Gift not found.');
    }
    if (_giftInventory.remove(giftItemId)) return;
    final cost = item.priceCoins ?? 0;
    if (_coins < cost) {
      throw const Failure(
        ErrorCode.conflict,
        message: 'Buy this gift first, or top up coins.',
      );
    }
    _coins -= cost;
  }
}
