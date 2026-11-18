enum StoreItemKind { coinPack, gift, emojiPack }

class StoreItem {
  const StoreItem({
    required this.id,
    required this.name,
    required this.kind,
    this.priceCoins,
    this.priceLabel,
    this.description = '',
    this.emoji = '',
    this.imageUrl = '',
    this.emojis = const [],
    this.giftCategory = '',
    this.coinAmount,
  });

  final String id;
  final String name;
  final StoreItemKind kind;
  final int? priceCoins;
  final String? priceLabel;
  final String description;
  final String emoji;
  final String imageUrl;
  final List<String> emojis;
  final String giftCategory;
  final int? coinAmount;

  bool get isFreeGift =>
      kind == StoreItemKind.gift && (priceCoins == null || priceCoins == 0);

  String get displayGlyph =>
      emoji.isNotEmpty ? emoji : (emojis.isNotEmpty ? emojis.first : '🎁');
}

class StoreWallet {
  const StoreWallet({
    required this.coinBalance,
    this.ownedPackIds = const [],
    this.giftInventory = const [],
  });

  final int coinBalance;
  final List<String> ownedPackIds;

  /// Gift item ids already purchased and ready to send.
  final List<String> giftInventory;

  bool ownsPack(String packId) => ownedPackIds.contains(packId);

  bool ownsGift(String giftId) => giftInventory.contains(giftId);
}

class StoreHistoryItem {
  const StoreHistoryItem({
    required this.id,
    required this.title,
    required this.at,
    this.coinsDelta,
  });

  final String id;
  final String title;
  final DateTime at;
  final int? coinsDelta;
}

class StoreCheckout {
  const StoreCheckout({
    required this.checkoutId,
    required this.productId,
    required this.platform,
  });

  final String checkoutId;
  final String productId;
  final String platform;
}
