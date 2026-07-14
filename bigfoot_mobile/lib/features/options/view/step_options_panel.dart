import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/dio_client.dart';
import '../data/trailer_options_api.dart';

/// The options a worker sees at their step.
///
/// Drew's rule, implemented literally:
///   • Options THIS department fits must be acknowledged before the step can
///     be completed (the API enforces it — this is the UI for it).
///   • Options another department fits are shown, greyed, and skippable.
///
/// [onChanged] fires after an acknowledgement so the parent screen can
/// re-enable its "complete step" button.
class StepOptionsPanel extends StatefulWidget {
  final int stepId;
  final VoidCallback? onChanged;

  const StepOptionsPanel({super.key, required this.stepId, this.onChanged});

  @override
  State<StepOptionsPanel> createState() => _StepOptionsPanelState();
}

class _StepOptionsPanelState extends State<StepOptionsPanel> {
  late final TrailerOptionsApi _api;
  bool _loading = true;
  int? _busyId;
  List<TrailerOption> _options = const [];

  @override
  void initState() {
    super.initState();
    _api = TrailerOptionsApi(context.read<DioClient>());
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final o = await _api.forStep(widget.stepId);
      if (!mounted) return;
      setState(() => _options = o);
    } catch (_) {
      if (mounted) setState(() => _options = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _acknowledge(TrailerOption o) async {
    final ackId = o.myAckId;
    if (ackId == null) return; // not this department's to acknowledge
    setState(() => _busyId = o.id);
    try {
      // Acknowledge THIS department's part. Other departments acknowledge
      // their own parts separately.
      await _api.acknowledge(ackId);
      await _load();
      widget.onChanged?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Acknowledged: ${o.addonName}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// How many options this worker still has to tick off.
  int get outstanding => _options.where((o) => o.mustAcknowledge).length;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.amber))),
      );
    }
    if (_options.isEmpty) return const SizedBox.shrink();

    final blocking = outstanding > 0;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: blocking ? AppColors.error : AppColors.divider,
          width: blocking ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  blocking ? Icons.warning_amber_rounded : Icons.checklist,
                  size: 18,
                  color: blocking ? AppColors.error : AppColors.navy,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    blocking
                        ? 'OPTIONS TO FIT — $outstanding to acknowledge'
                        : 'OPTIONS ON THIS TRAILER',
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 0.4,
                      fontWeight: FontWeight.w700,
                      color: blocking ? AppColors.error : AppColors.navy,
                    ),
                  ),
                ),
              ],
            ),
            if (blocking) ...[
              const SizedBox(height: 6),
              const Text(
                'You fit these. Acknowledge each one before you can complete '
                'this step.',
                style: TextStyle(fontSize: 12, color: AppColors.disabled),
              ),
            ],
            const SizedBox(height: 10),
            for (final o in _options) _optionRow(o),
          ],
        ),
      ),
    );
  }

  Widget _optionRow(TrailerOption o) {
    // Not this department's job → show it, grey it, let them move on.
    final mine = o.forThisDepartment;
    final done = o.isAcknowledgedByMe;
    final busy = _busyId == o.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            done
                ? Icons.check_circle
                : mine
                    ? Icons.radio_button_unchecked
                    : Icons.remove_circle_outline,
            size: 20,
            color: done
                ? AppColors.success
                : mine
                    ? AppColors.error
                    : AppColors.disabled,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o.addonName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: mine ? FontWeight.w700 : FontWeight.w400,
                    color: mine ? AppColors.navy : AppColors.disabled,
                  ),
                ),
                if (o.notes?.isNotEmpty == true)
                  Text(o.notes!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.disabled)),
                Text(
                  done
                      ? 'You fitted this'
                      : mine
                          ? (o.outstanding.length > 1
                              ? 'Yours to fit (also needs ${o.outstanding.where((c) => true).length - 1} other dept)'
                              : 'Yours to fit')
                          : 'Fitted by ${o.fittedBy.map((f) => f.code).join(', ')} — you can skip',
                  style: TextStyle(
                    fontSize: 11,
                    color: done
                        ? AppColors.success
                        : mine
                            ? AppColors.error
                            : AppColors.disabled,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (o.mustAcknowledge)
            FilledButton(
              onPressed: busy ? null : () => _acknowledge(o),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.success,
                minimumSize: const Size(96, 36),
              ),
              child: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('I fitted it'),
            ),
        ],
      ),
    );
  }
}
