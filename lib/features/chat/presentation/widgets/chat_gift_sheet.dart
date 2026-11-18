import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/di/repository_providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../settings/presentation/account_sheets.dart';
import '../../../store/domain/entities/store.dart';
import '../../../store/presentation/store_sheet.dart';
import '../viewmodels/conversation_view_model.dart';

/// Buy coins / packs / gifts, then send paid emoji or virtual gifts in chat.
class ChatGiftSheet extends ConsumerStatefulWidget {
  const ChatGiftSheet({super.key, required this.conversationId});

  final String conversationId;

  static Future<void> show(
    BuildContext context, {
    required String conversationId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ChatGiftSheet(conversationId: conversationId),
    );
  }

  @override
  ConsumerState<ChatGiftSheet> createState() => _ChatGiftSheetState();
}

class _ChatGiftSheetState extends ConsumerState<ChatGiftSheet> {
  late Future<_ChatStoreSnapshot> _future;
  var _busyId = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ChatStoreSnapshot> _load() async {
    final store = ref.read(storeRepositoryProvider);
    final wallet = await store.wallet();
    final catalog = await store.catalog();
    return _ChatStoreSnapshot(wallet: wallet, catalog: catalog);
  }

  Future<void> _reload() async {
    setState(() => _future = _load());
  }

  Future<void> _buyCoins(StoreItem item) async {
    setState(() => _busyId = item.id);
    try {
      if (!mounted) return;
      await StoreSheet.show(context);
      if (mounted) await _reload();
    } finally {
      if (mounted) setState(() => _busyId = '');
    }
  }

  Future<void> _buyItem(StoreItem item) async {
    setState(() => _busyId = item.id);
    try {
      await ref.read(storeRepositoryProvider).buyWithCoins(itemId: item.id);
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.name} added to your inventory.')),
      );
    } catch (error) {
      if (!mounted) return;
      if (error is Failure &&
          error.message.toLowerCase().contains('coin')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Not enough coins. Buy a coin pack first.'),
          ),
        );
        if (!mounted) return;
        await StoreSheet.show(context);
        if (mounted) await _reload();
      } else if (mounted) {
        showFailure(context, error);
      }
    } finally {
      if (mounted) setState(() => _busyId = '');
    }
  }

  Future<void> _sendGift(StoreItem item, StoreWallet wallet) async {
    final needsBuy = !item.isFreeGift && !wallet.ownsGift(item.id);
    if (needsBuy) {
      await _buyItem(item);
      final refreshed = await _load();
      if (!refreshed.wallet.ownsGift(item.id) && !item.isFreeGift) return;
    }
    setState(() => _busyId = item.id);
    try {
      final ok = await ref
          .read(conversationViewModelProvider(widget.conversationId).notifier)
          .sendGift(item.id);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop();
      } else {
        final failure = ref
            .read(conversationViewModelProvider(widget.conversationId))
            .value
            ?.sendFailure;
        if (failure != null) showFailure(context, failure);
      }
    } finally {
      if (mounted) setState(() => _busyId = '');
    }
  }

  Future<void> _sendEmoji(StoreItem pack, String emoji, StoreWallet wallet) async {
    if (!wallet.ownsPack(pack.id)) {
      await _buyItem(pack);
      final refreshed = await _load();
      if (!refreshed.wallet.ownsPack(pack.id)) return;
    }
    setState(() => _busyId = '$emoji-${pack.id}');
    try {
      final ok = await ref
          .read(conversationViewModelProvider(widget.conversationId).notifier)
          .sendPaidEmoji(emoji: emoji, packId: pack.id);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop();
      } else {
        final failure = ref
            .read(conversationViewModelProvider(widget.conversationId))
            .value
            ?.sendFailure;
        if (failure != null) showFailure(context, failure);
      }
    } finally {
      if (mounted) setState(() => _busyId = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, controller) => FutureBuilder<_ChatStoreSnapshot>(
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
                    : 'Could not load gifts.',
              ),
            );
          }
          final data = snapshot.data!;
          final gifts = data.catalog
              .where((item) => item.kind == StoreItemKind.gift)
              .toList();
          final packs = data.catalog
              .where((item) => item.kind == StoreItemKind.emojiPack)
              .toList();
          final coins = data.catalog
              .where((item) => item.kind == StoreItemKind.coinPack)
              .toList();

          return ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            children: [
              Text('Gifts & paid emoji', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Buy with coins first, then send in this chat.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.monetization_on_outlined),
                title: Text('${data.wallet.coinBalance} coins'),
                trailing: TextButton(
                  onPressed: coins.isEmpty
                      ? null
                      : () => _buyCoins(coins.first),
                  child: const Text('Buy coins'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Virtual gifts', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final gift in gifts)
                    _GiftTile(
                      item: gift,
                      owned: gift.isFreeGift || data.wallet.ownsGift(gift.id),
                      busy: _busyId == gift.id,
                      onTap: () => _sendGift(gift, data.wallet),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Paid emoji packs', style: theme.textTheme.titleMedium),
              for (final pack in packs) ...[
                const SizedBox(height: AppSpacing.sm),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Text(pack.displayGlyph, style: const TextStyle(fontSize: 28)),
                  title: Text(pack.name),
                  subtitle: Text(
                    data.wallet.ownsPack(pack.id)
                        ? 'Owned — tap an emoji to send'
                        : (pack.priceLabel ?? '${pack.priceCoins ?? 0} coins'),
                  ),
                  trailing: data.wallet.ownsPack(pack.id)
                      ? const Icon(Icons.check_circle_outline)
                      : TextButton(
                          onPressed: _busyId == pack.id
                              ? null
                              : () => _buyItem(pack),
                          child: Text(_busyId == pack.id ? '…' : 'Buy'),
                        ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final emoji in pack.emojis)
                      ActionChip(
                        label: Text(emoji, style: const TextStyle(fontSize: 22)),
                        onPressed: _busyId.isNotEmpty
                            ? null
                            : () => _sendEmoji(pack, emoji, data.wallet),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _GiftTile extends StatelessWidget {
  const _GiftTile({
    required this.item,
    required this.owned,
    required this.busy,
    required this.onTap,
  });

  final StoreItem item;
  final bool owned;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        width: 104,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            if (item.imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  item.imageUrl,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Text(
                    item.displayGlyph,
                    style: const TextStyle(fontSize: 36),
                  ),
                ),
              )
            else
              Text(item.displayGlyph, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 6),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
            Text(
              busy
                  ? 'Sending…'
                  : (owned
                        ? 'Send'
                        : (item.priceLabel ?? '${item.priceCoins ?? 0} coins')),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatStoreSnapshot {
  const _ChatStoreSnapshot({required this.wallet, required this.catalog});

  final StoreWallet wallet;
  final List<StoreItem> catalog;
}
