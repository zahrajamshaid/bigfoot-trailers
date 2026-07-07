import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/delivery.dart';
import '../../../data/models/delivery_batch.dart';
import '../../../data/models/user.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../utils/delivery_actions.dart';
import '../viewmodel/deliveries_viewmodel.dart';
import '../widgets/complete_delivery_dialog.dart';
import '../widgets/fail_reason_dialog.dart';
import '../../../shared/widgets/status_badge.dart';

class DeliveryDetailScreen extends StatefulWidget {
  final int deliveryId;

  const DeliveryDetailScreen({super.key, required this.deliveryId});

  @override
  State<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends State<DeliveryDetailScreen> {
  Delivery? _delivery;
  DeliveryBatch? _batch;
  bool _loading = true;
  bool _actionBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final vm = context.read<DeliveriesViewModel>();
      final d = await vm.getById(widget.deliveryId);

      // If this delivery belongs to a batch, pull the batch so we can show
      // every trailer travelling with it.
      DeliveryBatch? batch;
      if (d.deliveryBatchId != null) {
        try {
          final batches = await vm.getBatches();
          for (final b in batches) {
            if (b.id == d.deliveryBatchId) {
              batch = b;
              break;
            }
          }
        } catch (_) {
          // Batch context is supplementary — don't fail the detail view.
        }
      }

      if (!mounted) return;
      setState(() {
        _delivery = d;
        _batch = batch;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.amber)),
      );
    }

    final l = AppLocalizations.of(context);
    final d = _delivery;
    if (d == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.deliveryDetailTitle(widget.deliveryId))),
        body: Center(child: Text(l.deliveryDetailNotFound)),
      );
    }

    final auth = context.read<AuthViewModel>().state;
    final role = auth is Authenticated ? auth.user.role : '';
    final isOpen = d.status == 'scheduled' || d.status == 'in_transit';
    final canAct = role == UserRole.driver || role == UserRole.transportManager;
    final canDelete =
        role == UserRole.transportManager || role == UserRole.owner;
    final hasPhone = deliveryHasCustomerPhone(d);
    // Factory-pickup deliveries are auto-created when sales marks a
    // trailer sold + pickup. They land in `scheduled` and used to have
    // no completion button for anyone but a driver / transport manager
    // — so hundreds sat forever. This gate exposes a dedicated
    // "Complete pickup" button to every role that can legitimately close
    // one out (owner / office / sales / production_manager / transport
    // manager) whenever the row is still scheduled.
    final isFactoryPickup = d.deliveryType == 'factory_pickup';
    final canCompletePickup = isFactoryPickup &&
        d.status == 'scheduled' &&
        (role == UserRole.owner ||
            role == UserRole.office ||
            role == UserRole.sales ||
            role == UserRole.productionManager ||
            role == UserRole.transportManager);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.deliveryDetailTitle(d.id)),
        actions: [
          if (canDelete)
            IconButton(
              tooltip: l.deliveryDetailDeleteTooltip,
              icon: const Icon(Icons.delete_outline),
              onPressed: _actionBusy ? null : () => _delete(d),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _TimelineHeader(status: d.status),
            const SizedBox(height: 14),
            _SectionCard(
              title: l.deliveryDetailSectionTrailer,
              children: [
                Text(l.deliveryDetailSo(d.soNumber)),
                Text(l.deliveryDetailModel(d.modelName)),
                Text(l.deliveryDetailCustomer(d.customerName)),
              ],
            ),
            if (_batch != null)
              _BatchSection(
                batch: _batch!,
                currentTrailerId: d.trailerId,
                canComplete: role == UserRole.owner ||
                    role == UserRole.transportManager,
                busy: _actionBusy,
                onComplete: () => _completeBatch(_batch!),
              ),
            _SectionCard(
              title: l.deliveryDetailSectionDriver,
              children: [Text(l.deliveryDetailAssigned(d.driverName))],
            ),
            // Customer contact + balance — surfaced as its own section so a
            // dispatcher / driver looking at a scheduled delivery can see at
            // a glance who to call and what's still owed without bouncing to
            // the trailer detail. Phone is tap-to-call and long-press to
            // copy; balance reads "Paid in full" when zero so we don't
            // imply "no info" on prepaid orders.
            _SectionCard(
              title: 'Customer',
              children: [
                _PhoneRow(phone: deliveryContactPhone(d)),
                const SizedBox(height: 6),
                _BalanceRow(amount: d.balanceDue),
              ],
            ),
            _SectionCard(
              title: l.deliveryDetailSectionDestination,
              children: [
                Text(d.destinationLabel),
                if (d.destinationLocation?.city != null)
                  Text(
                    '${d.destinationLocation!.city}, ${d.destinationLocation!.state ?? ''}',
                    style: const TextStyle(color: AppColors.disabled),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openMaps(d),
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: Text(l.deliveryDetailOpenMaps),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: hasPhone ? () => _textCustomer(d) : null,
                        icon: const Icon(Icons.sms_outlined, size: 18),
                        label: Text(l.deliveryDetailTextCustomer),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // Balance is now rendered inside the Customer section above,
            // unconditionally (with "Paid in full" when zero), so the old
            // standalone Balance card is gone.
            if ((d.pickedUpByName ?? '').isNotEmpty)
              _SectionCard(
                title: l.deliveryDetailSectionPickedUp,
                children: [Text(d.pickedUpByName!)],
              ),
            if (d.status == 'failed' && (d.failReason ?? '').isNotEmpty)
              _SectionCard(
                title: l.deliveryDetailSectionFailReason,
                children: [Text(d.failReason!)],
              ),
            const SizedBox(height: 8),
            // Factory-pickup fast path — dedicated "Complete pickup" for
            // owner / office / sales / PM / transport. Same terminal
            // effect (delivery → delivered, trailer → delivered) but
            // routes through /deliveries/factory-pickup/:id/complete
            // which the auto-created pickup row expects.
            if (canCompletePickup)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _actionBusy ? null : () => _completePickup(d),
                    icon: _actionBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.done_all_outlined),
                    label: const Text('Complete pickup'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            if (canAct && isOpen)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _actionBusy ? null : () => _complete(d),
                    icon: _actionBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.task_alt_outlined),
                    label: Text(l.deliveryDetailCompleteAction),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _actionBusy ? null : _markFailed,
                    icon: const Icon(Icons.report_gmailerrorred),
                    label: Text(l.deliveryDetailMarkFailed),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMaps(Delivery d) async {
    final ok = await openDeliveryInMaps(d);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context).deliveryDetailNoAddress)),
      );
    }
  }

  Future<void> _textCustomer(Delivery d) async {
    final ok = await textDeliveryCustomer(d);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(AppLocalizations.of(context).deliveryDetailNoPhone)),
      );
    }
  }

  Future<void> _complete(Delivery d) async {
    final result = await showCompleteDeliveryDialog(context, d);
    if (result == null || !mounted) return;

    setState(() => _actionBusy = true);
    try {
      await context.read<DeliveriesViewModel>().completeDelivery(
            widget.deliveryId,
            paymentCollected: result.paymentCollected,
          );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)
                .deliveryDetailCompleteFail('$e'))),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  /// Closes out an auto-created factory-pickup delivery. Uses the same
  /// complete-dialog as regular deliveries so operators can also record
  /// who physically picked the trailer up + any payment collected. On
  /// success the API flips both the delivery and trailer to `delivered`
  /// atomically — the trailer detail refreshes automatically off the ws
  /// event, so the "Mark completed" shortcut on the trailer detail
  /// disappears in the same beat.
  Future<void> _completePickup(Delivery d) async {
    final result = await showCompleteDeliveryDialog(context, d);
    if (result == null || !mounted) return;

    setState(() => _actionBusy = true);
    try {
      await context.read<DeliveriesViewModel>().completeFactoryPickup(
            widget.deliveryId,
            pickedUpByName: d.customerName,
            paymentCollected: result.paymentCollected,
          );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)
                .deliveryDetailCompleteFail('$e'))),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  /// Completes the whole batch this delivery belongs to in one action — every
  /// trailer in the batch is marked delivered. Available to owner / transport
  /// manager so they don't have to complete each delivery individually.
  Future<void> _completeBatch(DeliveryBatch batch) async {
    final l = AppLocalizations.of(context);
    final count = (batch.deliveries ?? const []).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deliveryDetailCompleteBatchTitle),
        content: Text(l.deliveryDetailCompleteBatchBody(count, batch.batchNumber)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.deliveryDetailMarkAllDelivered),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _actionBusy = true);
    try {
      await context.read<DeliveriesViewModel>().completeBatch(batch.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.deliveryDetailBatchAllDelivered(batch.batchNumber))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.deliveryDetailBatchFail('$e'))),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _delete(Delivery d) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deliveryDetailDeleteTitle),
        content: Text(l.deliveryDetailDeleteBody(d.soNumber)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.commonDelete),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _actionBusy = true);
    try {
      await context.read<DeliveriesViewModel>().deleteDelivery(widget.deliveryId);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l.deliveryDetailDeleted(d.soNumber))),
      );
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionBusy = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l.deliveryDetailDeleteFail('$e'))),
      );
    }
  }

  Future<void> _markFailed() async {
    final l = AppLocalizations.of(context);
    final reason =
        await showFailReasonDialog(context, title: l.deliveryDetailMarkFailedTitle);

    if (!mounted) return;
    if (reason == null || reason.isEmpty) return;
    setState(() => _actionBusy = true);
    try {
      await context.read<DeliveriesViewModel>().markFailed(widget.deliveryId, reason);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.deliveryDetailMarkFailedError('$e'))),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }
}

/// Two-step progress: a delivery is either still open or delivered. There is
/// no separate "in transit" stage in the UI.
class _TimelineHeader extends StatelessWidget {
  final String status;

  const _TimelineHeader({required this.status});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final delivered = status == 'delivered';
    final failed = status == 'failed';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l.deliveryDetailStatusLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              StatusBadge(status: status),
            ],
          ),
          if (!failed) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _Dot(active: true, label: '1'),
                Expanded(
                  child: Container(
                    height: 2,
                    color: delivered ? AppColors.success : AppColors.divider,
                  ),
                ),
                _Dot(active: delivered, label: '2'),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(l.deliveryListTabScheduled),
                const Spacer(),
                Text(l.statusDelivered),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool active;
  final String label;
  const _Dot({required this.active, required this.label});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 11,
      backgroundColor: active ? AppColors.success : AppColors.divider,
      child: Text(label,
          style: const TextStyle(fontSize: 11, color: AppColors.white)),
    );
  }
}

/// Shows the batch this delivery belongs to and every trailer travelling with
/// it. The current delivery's trailer is highlighted.
class _BatchSection extends StatelessWidget {
  final DeliveryBatch batch;
  final int currentTrailerId;
  final bool canComplete;
  final bool busy;
  final VoidCallback onComplete;

  const _BatchSection({
    required this.batch,
    required this.currentTrailerId,
    required this.canComplete,
    required this.busy,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final deliveries = batch.deliveries ?? const [];
    final isComplete = batch.status == 'complete';
    return _SectionCard(
      title: l.deliveryDetailBatchTitle(batch.batchNumber),
      children: [
        Row(
          children: [
            Text(l.deliveryDetailBatchStatus(batch.statusLabel),
                style: const TextStyle(color: AppColors.disabled)),
            const Spacer(),
            Text(l.deliveryDetailTrailerCount(deliveries.length),
                style: const TextStyle(color: AppColors.disabled)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l.deliveryListDriverLabel(
              batch.driverUser?.fullName ?? l.deliveryDetailUnassigned),
          style: const TextStyle(color: AppColors.disabled),
        ),
        const SizedBox(height: 8),
        ...deliveries.map((item) {
          final isCurrent = item.trailerId == currentTrailerId;
          final so = item.trailer?.soNumber ?? '#${item.trailerId}';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  isCurrent
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: isCurrent ? AppColors.amber : AppColors.disabled,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    so,
                    style: TextStyle(
                      fontWeight:
                          isCurrent ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
                StatusBadge(status: item.status),
              ],
            ),
          );
        }),
        if (canComplete && !isComplete) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.success),
              onPressed: busy ? null : onComplete,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.task_alt_outlined),
              label: Text(l.deliveryDetailCompleteEntireBatch),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

/// Customer phone — tap-to-call, long-press-to-copy. Reads "Not on file"
/// when neither delivery.contactPhone nor trailer.customer.smsPhone is set.
class _PhoneRow extends StatelessWidget {
  final String? phone;

  const _PhoneRow({required this.phone});

  @override
  Widget build(BuildContext context) {
    final p = phone?.trim();
    if (p == null || p.isEmpty) {
      return Row(
        children: const [
          Icon(Icons.phone_outlined,
              size: 18, color: AppColors.disabled),
          SizedBox(width: 8),
          Text('Phone: Not on file',
              style: TextStyle(color: AppColors.disabled)),
        ],
      );
    }
    final tel = Uri.parse('tel:$p');
    return InkWell(
      onTap: () => launchUrl(tel),
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: p));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Phone copied')),
        );
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.phone_outlined, size: 18, color: AppColors.navy),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                p,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Amount due — formatted as "$X.XX". Renders "Paid in full" in green
/// when the balance is zero (or absent) so a prepaid delivery doesn't
/// look like data is missing.
class _BalanceRow extends StatelessWidget {
  final double? amount;

  const _BalanceRow({required this.amount});

  @override
  Widget build(BuildContext context) {
    final due = amount ?? 0;
    final isPaid = due <= 0;
    return Row(
      children: [
        Icon(
          isPaid ? Icons.check_circle_outline : Icons.account_balance_wallet_outlined,
          size: 18,
          color: isPaid ? AppColors.success : AppColors.amber,
        ),
        const SizedBox(width: 8),
        Text(
          isPaid
              ? 'Amount due: Paid in full'
              : 'Amount due: \$${due.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isPaid ? AppColors.success : AppColors.amber,
          ),
        ),
      ],
    );
  }
}
