import '../../../../core/errors/failure.dart';
import '../../../../dev/mock/mock_backend.dart';
import '../../../../dev/mock/mock_fixtures.dart';
import '../../domain/entities/subscription.dart';
import '../../domain/repositories/subscription_repository.dart';

/// Purchases here are simulated: no store is contacted and the resulting
/// entitlement is flagged `isSimulated`.
class MockSubscriptionRepository implements SubscriptionRepository {
  MockSubscriptionRepository(this._backend);

  final MockBackend _backend;
  final _history = <SubscriptionHistoryItem>[];

  @override
  Future<List<SubscriptionProduct>> getProducts() =>
      _backend.run('getProducts', () => MockFixtures.products);

  @override
  Future<Entitlement> getEntitlement() =>
      _backend.run('getEntitlement', () => _backend.entitlement);

  @override
  Future<Entitlement> purchase(String productId) =>
      _backend.run('purchase', () {
        final product =
            MockFixtures.products.where((p) => p.id == productId).firstOrNull ??
            (throw const Failure(ErrorCode.notFound));
        final entitlement = Entitlement(
          tier: product.tier,
          expiresAt: _backend.now().add(
            product.period == BillingPeriod.yearly
                ? const Duration(days: 365)
                : const Duration(days: 30),
          ),
          isSimulated: true,
        );
        _backend.entitlement = entitlement;
        _history.insert(
          0,
          SubscriptionHistoryItem(
            id: 'sub_${_history.length + 1}',
            productId: productId,
            status: 'ACTIVE',
            at: _backend.now(),
          ),
        );
        return entitlement;
      });

  @override
  Future<Entitlement> restore() =>
      _backend.run('restore', () => _backend.entitlement);

  @override
  Future<List<SubscriptionHistoryItem>> history() =>
      _backend.run('subscriptionHistory', () => List.unmodifiable(_history));

  @override
  Future<SubscriptionCheckout> checkout({
    required String productId,
    required String platform,
  }) => _backend.run(
    'subscriptionCheckout',
    () => SubscriptionCheckout(
      checkoutId: 'chk_$productId',
      productId: productId,
      platform: platform,
    ),
  );

  @override
  Future<Entitlement> verifyCheckout({
    required String checkoutId,
    required String outcome,
  }) async {
    if (outcome.toUpperCase() != 'SUCCESS') {
      throw const Failure(
        ErrorCode.validationError,
        message: 'Payment was not completed.',
      );
    }
    return purchase(checkoutId.replaceFirst('chk_', ''));
  }

  @override
  Future<Entitlement> cancel() => _backend.run('cancelSubscription', () {
    _backend.entitlement = const Entitlement.free();
    return _backend.entitlement;
  });
}
