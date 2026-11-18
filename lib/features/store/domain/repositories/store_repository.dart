import '../entities/store.dart';

abstract class StoreRepository {
  Future<List<StoreItem>> catalog();

  Future<StoreWallet> wallet();

  Future<List<StoreHistoryItem>> history();

  Future<StoreCheckout> checkout({
    required String productId,
    required String platform,
  });

  Future<StoreWallet> verify({
    required String checkoutId,
    required String outcome,
  });

  Future<StoreWallet> buyWithCoins({required String itemId});
}
