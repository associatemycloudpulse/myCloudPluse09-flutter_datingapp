import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../core/di/repository_providers.dart';
import '../../../core/errors/failure.dart';
import '../../settings/presentation/account_sheets.dart';
import '../domain/entities/store.dart';

class StoreSheet extends ConsumerStatefulWidget {
  const StoreSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const StoreSheet(),
    );
  }

  @override
  ConsumerState<StoreSheet> createState() => _StoreSheetState();
}

class _StoreSheetState extends ConsumerState<StoreSheet> {
  late Future<_StoreSnapshot> _future;
  var _busyId = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_StoreSnapshot> _load() async {
    final store = ref.read(storeRepositoryProvider);
    final wallet = await store.wallet();
    final catalog = await store.catalog();
    final history = await store.history();
    return _StoreSnapshot(wallet: wallet, catalog: catalog, history: history);
  }

  Future<void> _buyCoins(StoreItem item) async {
    setState(() => _busyId = item.id);
    try {
      final store = ref.read(storeRepositoryProvider);
      final checkout = await store.checkout(
        productId: item.id,
        platform: Platform.isIOS ? 'IOS' : 'ANDROID',
      );
      await store.verify(checkoutId: checkout.checkoutId, outcome: 'SUCCESS');
      if (!mounted) return;
      setState(() => _future = _load());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coins added.')),
      );
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busyId = '');
    }
  }

  Future<void> _buyWithCoins(StoreItem item) async {
    setState(() => _busyId = item.id);
    try {
      await ref.read(storeRepositoryProvider).buyWithCoins(itemId: item.id);
      if (!mounted) return;
      setState(() => _future = _load());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.name} unlocked.')),
      );
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busyId = '');
    }
  }

  String _subtitle(StoreItem item, StoreWallet wallet) {
    if (item.kind == StoreItemKind.coinPack) {
      return item.priceLabel ?? item.description;
    }
    if (item.kind == StoreItemKind.emojiPack && wallet.ownsPack(item.id)) {
      return 'Owned';
    }
    if (item.kind == StoreItemKind.gift &&
        (item.isFreeGift || wallet.ownsGift(item.id))) {
      return item.isFreeGift ? 'Free' : 'In inventory — send from chat';
    }
    return item.priceLabel ??
        (item.priceCoins == null
            ? item.description
            : '${item.priceCoins} coins');
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (context, controller) => FutureBuilder<_StoreSnapshot>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                snapshot.error is Failure
                    ? (snapshot.error! as Failure).message
                    : 'Could not load store.',
              ),
            );
          }
          final data = snapshot.data!;
          return ListView(
            controller: controller,
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text('Store', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text('Balance: ${data.wallet.coinBalance} coins'),
              const SizedBox(height: AppSpacing.md),
              Text('Catalog', style: Theme.of(context).textTheme.titleMedium),
              for (final item in data.catalog)
                ListTile(
                  leading: Text(
                    item.displayGlyph,
                    style: const TextStyle(fontSize: 28),
                  ),
                  title: Text(item.name),
                  subtitle: Text(_subtitle(item, data.wallet)),
                  trailing: TextButton(
                    onPressed: _busyId == item.id
                        ? null
                        : item.kind == StoreItemKind.coinPack
                            ? () => _buyCoins(item)
                            : (item.kind == StoreItemKind.emojiPack &&
                                    data.wallet.ownsPack(item.id)) ||
                                (item.kind == StoreItemKind.gift &&
                                    (item.isFreeGift ||
                                        data.wallet.ownsGift(item.id)))
                                ? null
                                : () => _buyWithCoins(item),
                    child: Text(
                      _busyId == item.id
                          ? '…'
                          : item.kind == StoreItemKind.coinPack
                              ? 'Buy'
                              : (item.kind == StoreItemKind.emojiPack &&
                                      data.wallet.ownsPack(item.id)) ||
                                  (item.kind == StoreItemKind.gift &&
                                      (item.isFreeGift ||
                                          data.wallet.ownsGift(item.id)))
                                  ? 'Owned'
                                  : 'Buy',
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              Text('History', style: Theme.of(context).textTheme.titleMedium),
              if (data.history.isEmpty)
                const ListTile(title: Text('No purchases yet.')),
              for (final entry in data.history)
                ListTile(
                  title: Text(entry.title),
                  subtitle: Text(entry.at.toLocal().toString()),
                  trailing: entry.coinsDelta == null
                      ? null
                      : Text('${entry.coinsDelta}'),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StoreSnapshot {
  const _StoreSnapshot({
    required this.wallet,
    required this.catalog,
    required this.history,
  });

  final StoreWallet wallet;
  final List<StoreItem> catalog;
  final List<StoreHistoryItem> history;
}
