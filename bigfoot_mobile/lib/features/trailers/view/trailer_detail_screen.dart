import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/websocket/ws_client.dart';
import '../../../data/models/trailer.dart';
import '../../../data/models/user.dart';
import '../../../domain/repositories/production_repository.dart';
import '../../../domain/repositories/storage_repository.dart';
import '../../../domain/repositories/trailer_repository.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../../trailers/viewmodel/trailer_detail_viewmodel.dart';
import '../../../core/router/route_names.dart';
import '../../../shared/widgets/pdf_viewer_screen.dart';
import '../../../shared/widgets/status_badge.dart';

class TrailerDetailScreen extends StatelessWidget {
  final int trailerId;
  const TrailerDetailScreen({super.key, required this.trailerId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TrailerDetailViewModel(
        repository: context.read<TrailerRepository>(),
        storageRepository: context.read<StorageRepository>(),
        productionRepository: context.read<ProductionRepository>(),
        ws: context.read<WsClient>(),
        trailerId: trailerId,
      )..load(),
      child: _TrailerDetailBody(trailerId: trailerId),
    );
  }
}

class _TrailerDetailBody extends StatelessWidget {
  final int trailerId;
  const _TrailerDetailBody({required this.trailerId});

  @override
  Widget build(BuildContext context) {
    final canViewStagePhotos = _canViewStagePhotos(context);

    return BlocBuilder<TrailerDetailViewModel, TrailerDetailState>(
      builder: (context, state) {
        return switch (state) {
          TrailerDetailInitial() || TrailerDetailLoading() => Scaffold(
              appBar: AppBar(title: Text('Trailer #$trailerId')),
              body: const Center(
                  child: CircularProgressIndicator(color: AppColors.amber)),
            ),
          TrailerDetailError(message: final msg) => Scaffold(
              appBar: AppBar(title: Text('Trailer #$trailerId')),
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text(msg),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => context.read<TrailerDetailViewModel>().load(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          TrailerDetailLoaded(
            trailer: final trailer,
            steps: final steps,
            history: final history,
            stagePhotos: final stagePhotos,
          ) =>
            DefaultTabController(
              length: canViewStagePhotos ? 4 : 3,
              child: Scaffold(
                appBar: AppBar(
                  title: Row(
                    children: [
                      Text(trailer.soNumber),
                      const SizedBox(width: 8),
                      if (trailer.isHot)
                        const Icon(Icons.local_fire_department,
                            color: AppColors.error, size: 18),
                    ],
                  ),
                  actions: [
                    PopupMenuButton<String>(
                      onSelected: (v) => _onAction(context, v, trailer),
                      itemBuilder: (_) => [
                        if (_canEditTrailer(context))
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined,
                                    size: 20, color: AppColors.navy),
                                SizedBox(width: 8),
                                Text('Edit Trailer'),
                              ],
                            ),
                          ),
                        PopupMenuItem(
                          value: 'hot',
                          child: Row(
                            children: [
                              Icon(
                                trailer.isHot
                                    ? Icons.local_fire_department
                                    : Icons.local_fire_department_outlined,
                                size: 20,
                                color: trailer.isHot
                                    ? AppColors.error
                                    : AppColors.warning,
                              ),
                              const SizedBox(width: 8),
                              Text(trailer.isHot ? 'Remove Hot' : 'Mark Hot'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'priority',
                          child: Row(
                            children: [
                              Icon(
                                Icons.low_priority,
                                size: 20,
                                color: AppColors.warning,
                              ),
                              SizedBox(width: 8),
                              Text('Set Priority'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'addon',
                          child: Row(
                            children: [
                              Icon(
                                Icons.add_circle_outline,
                                size: 20,
                                color: AppColors.success,
                              ),
                              SizedBox(width: 8),
                              Text('Add Addon'),
                            ],
                          ),
                        ),
                        if (trailer.qbSoPdfStorageKey != null)
                          const PopupMenuItem(
                            value: 'pdf',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.picture_as_pdf_outlined,
                                  size: 20,
                                  color: AppColors.error,
                                ),
                                SizedBox(width: 8),
                                Text('View QB PDF'),
                              ],
                            ),
                          ),
                        if (_canDeleteTrailer(context)) ...[
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline,
                                    size: 20, color: AppColors.error),
                                SizedBox(width: 8),
                                Text('Delete Trailer',
                                    style: TextStyle(color: AppColors.error)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                  bottom: TabBar(
                    tabs: _buildTabs(canViewStagePhotos),
                    indicatorColor: AppColors.amber,
                    labelColor: AppColors.white,
                    unselectedLabelColor: Colors.white60,
                  ),
                ),
                body: TabBarView(
                  children: [
                    _InfoTab(trailer: trailer, steps: steps),
                    _WorkflowTab(steps: steps),
                    _HistoryTab(history: history),
                    if (canViewStagePhotos)
                      _StagePhotosTab(stagePhotos: stagePhotos),
                  ],
                ),
              ),
            ),
        };
      },
    );
  }

  static List<Widget> _buildTabs(bool canViewStagePhotos) {
    return [
      const Tab(text: 'Info'),
      const Tab(text: 'Workflow'),
      const Tab(text: 'History'),
      if (canViewStagePhotos) const Tab(text: 'Photos'),
    ];
  }

  void _onAction(BuildContext context, String action, dynamic trailer) {
    final cubit = context.read<TrailerDetailViewModel>();
    switch (action) {
      case 'edit':
        _openEdit(context, trailer, cubit);
        return;
      case 'hot':
        cubit.toggleHot();
        return;
      case 'priority':
        _showPriorityDialog(context, cubit);
        return;
      case 'addon':
        _showAddonDialog(context, cubit);
        return;
      case 'pdf':
        final storageKey = trailer.qbSoPdfStorageKey as String?;
        if (storageKey == null) return;
        context.pushNamed(
          RouteNames.pdfViewer,
          extra: PdfViewerArgs(
            storageKey: storageKey,
            title: trailer.soNumber,
          ),
        );
        return;
      case 'delete':
        _confirmAndDelete(context, trailer);
        return;
    }
  }

  Future<void> _openEdit(
    BuildContext context,
    dynamic trailer,
    TrailerDetailViewModel cubit,
  ) async {
    final result = await context.pushNamed<bool>(
      RouteNames.trailerEdit,
      pathParameters: {'id': '${trailer.id}'},
      extra: trailer,
    );
    if (result == true) {
      await cubit.load();
    }
  }

  /// Trailer delete is restricted to owner and production_manager roles —
  /// matches DELETE /trailers/:id RBAC on the backend.
  static bool _canDeleteTrailer(BuildContext context) {
    final auth = context.read<AuthViewModel>().state;
    if (auth is! Authenticated) return false;
    return auth.user.role == UserRole.owner ||
        auth.user.role == UserRole.productionManager;
  }

  /// Edit visibility mirrors PATCH /trailers/:id RBAC — owner and
  /// production_manager (the same roles that can create a trailer).
  static bool _canEditTrailer(BuildContext context) {
    final auth = context.read<AuthViewModel>().state;
    if (auth is! Authenticated) return false;
    return auth.user.role == UserRole.owner ||
        auth.user.role == UserRole.productionManager;
  }

  static bool _canViewStagePhotos(BuildContext context) {
    final auth = context.read<AuthViewModel>().state;
    if (auth is! Authenticated) return false;
    return auth.user.role == UserRole.owner ||
        auth.user.role == UserRole.productionManager;
  }

  Future<void> _confirmAndDelete(BuildContext context, dynamic trailer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete trailer?'),
        content: Text(
          'This permanently deletes ${trailer.soNumber} and ALL related '
          'records — production steps, QC inspections, deliveries, photos, '
          'addons, and history.\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final repo = context.read<TrailerRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    try {
      await repo.deleteTrailer(trailer.id is int ? trailer.id as int : (trailer.id as num).toInt());
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('${trailer.soNumber} deleted'),
          backgroundColor: AppColors.success,
        ),
      );
      router.go('/trailers');
    } on ApiException catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Delete failed: ${e.displayMessage}'),
          backgroundColor: AppColors.error,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Delete failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showPriorityDialog(BuildContext context, TrailerDetailViewModel cubit) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Priority'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Priority number',
            hintText: '1 = highest',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final val = int.tryParse(controller.text);
              if (val != null) {
                cubit.setPriority(val);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  void _showAddonDialog(BuildContext context, TrailerDetailViewModel cubit) {
    final nameController = TextEditingController();
    final notesController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Addon'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Addon name *'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                cubit.addAddon(
                  nameController.text.trim(),
                  notesController.text.trim().isNotEmpty
                      ? notesController.text.trim()
                      : null,
                );
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

// ── Tab 1: Info ──────────────────────────────────────────────────────────────

class _InfoTab extends StatelessWidget {
  final dynamic trailer;
  final List<ProductionStepSummary> steps;
  const _InfoTab({required this.trailer, required this.steps});

  ProductionStepSummary? get _activeStep {
    for (final s in steps) {
      if (s.status == 'active') return s;
    }
    return null;
  }

  String _locationLine() {
    final loc = trailer.currentLocation;
    if (loc == null) return '—';
    final city = loc.code != null && (loc.code as String).isNotEmpty
        ? loc.code as String
        : null;
    return city != null ? '${loc.name}  ·  $city' : loc.name as String;
  }

  @override
  Widget build(BuildContext context) {
    final t = trailer;
    final active = _activeStep;
    final hasNotes = t.optionsNotes != null && t.optionsNotes!.isNotEmpty;
    final hasSpecial = t.specialNote != null && t.specialNote!.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status header
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.trailerModel?.displayName ?? 'Unknown Model',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      if (t.trailerModel?.series != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: SeriesBadge(series: t.trailerModel!.series),
                        ),
                    ],
                  ),
                ),
                StatusBadge(status: t.status),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Currently in: department (active step) + physical location.
        // Highest-signal info on the screen, so it sits above everything else.
        _CurrentlyInCard(
          activeStepDeptName: active?.departmentName ?? active?.departmentCode,
          trailerStatus: t.status as String,
          locationLine: _locationLine(),
        ),
        const SizedBox(height: 8),

        // Compact key/value details (short fields only — long-form notes are
        // rendered separately below so they get full width).
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _DetailRow('Customer', t.customer?.name ?? (t.isStockBuild ? 'Stock Build' : 'None')),
                _DetailRow('Color', t.color ?? '-'),
                _DetailRow('Size', t.size ?? '-'),
                _DetailRow('Priority', t.globalPriority < 9999 ? '#${t.globalPriority}' : 'Default'),
                if (t.qbSoPdfStorageKey != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: () => context.pushNamed(
                        RouteNames.pdfViewer,
                        extra: PdfViewerArgs(
                          storageKey: t.qbSoPdfStorageKey!,
                          title: t.soNumber,
                        ),
                      ),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Open QB PDF'),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Long-form notes — each in its own card so the layout grows with
        // arbitrary text length and the user can long-press to copy.
        if (hasNotes) ...[
          const SizedBox(height: 8),
          _NoteCard(
            label: 'Options / Notes',
            icon: Icons.notes_outlined,
            value: t.optionsNotes as String,
          ),
        ],
        if (hasSpecial) ...[
          const SizedBox(height: 8),
          _NoteCard(
            label: 'Special Note',
            icon: Icons.sticky_note_2_outlined,
            value: t.specialNote as String,
            accent: AppColors.amber,
          ),
        ],

        // Addons
        if (t.addons != null && (t.addons as List).isNotEmpty) ...[
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Addons',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.navy)),
                  const SizedBox(height: 8),
                  ...(t.addons as List).map<Widget>((a) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading:
                            const Icon(Icons.extension, size: 20, color: AppColors.navy),
                        title: Text(a.addonName),
                        subtitle: a.notes != null ? Text(a.notes!) : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 18, color: AppColors.error),
                          onPressed: () => context
                              .read<TrailerDetailViewModel>()
                              .removeAddon(a.id),
                        ),
                      )),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// "Currently in" highlight card — department of the active production step
/// + the trailer's physical yard. Falls back to the trailer's status when
/// there's no active step (e.g. ready_for_delivery, delivered).
class _CurrentlyInCard extends StatelessWidget {
  final String? activeStepDeptName;
  final String trailerStatus;
  final String locationLine;

  const _CurrentlyInCard({
    required this.activeStepDeptName,
    required this.trailerStatus,
    required this.locationLine,
  });

  String _fallbackFromStatus() {
    switch (trailerStatus) {
      case 'ready_for_delivery':
        return 'Ready for delivery';
      case 'in_transit':
        return 'In transit';
      case 'delivered':
        return 'Delivered';
      case 'on_hold':
        return 'On hold';
      case 'pending_production':
        return 'Pending production';
      default:
        return 'Workflow complete';
    }
  }

  @override
  Widget build(BuildContext context) {
    final deptText = activeStepDeptName ?? _fallbackFromStatus();
    return Card(
      elevation: 0,
      color: AppColors.navy.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.navy.withValues(alpha: 0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IconRow(
              icon: Icons.precision_manufacturing_outlined,
              label: 'Department',
              value: deptText,
              valueWeight: FontWeight.w700,
            ),
            const SizedBox(height: 12),
            _IconRow(
              icon: Icons.location_on_outlined,
              label: 'Location',
              value: locationLine,
            ),
          ],
        ),
      ),
    );
  }
}

class _IconRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final FontWeight valueWeight;
  const _IconRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueWeight = FontWeight.w500,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.navy),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.5,
                  color: AppColors.disabled,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                softWrap: true,
                style: TextStyle(fontSize: 15, fontWeight: valueWeight),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Full-width note card. Header above, body text below — the body uses
/// [SelectableText] with no maxLines so it wraps and grows freely with the
/// content (works for one short line or a long multi-paragraph instruction).
class _NoteCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final Color? accent;

  const _NoteCard({
    required this.label,
    required this.icon,
    required this.value,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.navy;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 0.5,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(
              value,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.disabled,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

// ── Tab 2: Workflow Stepper ──────────────────────────────────────────────────

class _WorkflowTab extends StatelessWidget {
  final List steps;
  const _WorkflowTab({required this.steps});

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return const Center(child: Text('No workflow steps'));
    }

    final canManage = _canManageWorkflow(context);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      itemCount: steps.length,
      itemBuilder: (context, i) {
        final step = steps[i];
        return _StepTile(
          step: step,
          isLast: i == steps.length - 1,
          canManage: canManage,
        );
      },
    );
  }

  /// Manual workflow override matches the backend RBAC on
  /// POST /production/trailers/:id/jump-to-step (owner + production_manager).
  static bool _canManageWorkflow(BuildContext context) {
    final auth = context.read<AuthViewModel>().state;
    if (auth is! Authenticated) return false;
    return auth.user.role == UserRole.owner ||
        auth.user.role == UserRole.productionManager;
  }
}

class _StepTile extends StatelessWidget {
  final dynamic step;
  final bool isLast;
  final bool canManage;
  const _StepTile({
    required this.step,
    required this.isLast,
    required this.canManage,
  });

  Future<void> _confirmAndJump(BuildContext context) async {
    final s = step;
    final deptName =
        s.departmentName ?? s.departmentCode ?? 'Step ${s.stepOrder}';
    final cubit = context.read<TrailerDetailViewModel>();
    final messenger = ScaffoldMessenger.of(context);

    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Move trailer to step ${s.stepOrder}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This places the trailer at "$deptName" as the current active '
              'step.\n\n'
              '• Earlier steps will be marked complete (no points awarded for '
              'any that weren\'t already done).\n'
              '• Later steps will be reset to waiting.\n'
              '• Each rolled-back step is recorded in the history tab.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g. wrong step tapped earlier',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Move Here'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await cubit.jumpToStep(
        (s.id is int) ? s.id as int : (s.id as num).toInt(),
        reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text('Trailer moved to "$deptName"'),
          backgroundColor: AppColors.success,
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Move failed: ${e.displayMessage}'),
          backgroundColor: AppColors.error,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Move failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = step;
    final isActive = s.status == 'active';
    final isComplete = s.status == 'complete';
    final isRework = s.isRework == true;
    final deptName = s.departmentName ?? s.departmentCode ?? 'Step ${s.stepOrder}';

    final (icon, iconColor, bgColor) = isComplete
        ? (Icons.check_circle, AppColors.success, AppColors.success.withValues(alpha: 0.1))
        : isActive
            ? (Icons.play_circle_filled, AppColors.statusInProduction,
                AppColors.statusInProduction.withValues(alpha: 0.08))
            : (Icons.circle_outlined, AppColors.disabled, Colors.transparent);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline line + icon
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: bgColor,
                    shape: BoxShape.circle,
                    border: isActive
                        ? Border.all(color: AppColors.statusInProduction, width: 2)
                        : null,
                  ),
                  child: Icon(icon, size: 16, color: iconColor),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: isComplete
                          ? AppColors.success.withValues(alpha: 0.3)
                          : AppColors.divider,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Content
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.statusInProduction.withValues(alpha: 0.05)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: isActive
                    ? Border.all(color: AppColors.statusInProduction.withValues(alpha: 0.2))
                    : Border.all(color: AppColors.divider.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${s.stepOrder}. $deptName',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                          color: isActive ? AppColors.statusInProduction : null,
                        ),
                      ),
                      const Spacer(),
                      if (isRework)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'REWORK x${s.reworkCount}',
                            style: const TextStyle(
                              color: AppColors.warning,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      StatusBadge(status: s.status),
                    ],
                  ),
                  if (isComplete && s.completedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Completed ${DateFormat.yMMMd().add_jm().format(s.completedAt!)}',
                      style: const TextStyle(fontSize: 11, color: AppColors.disabled),
                    ),
                  ],
                  if (isComplete && s.pointsAwarded != null && s.pointsAwarded! > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '+${s.pointsAwarded!.toStringAsFixed(1)} pts',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.amber,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (isActive) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.statusInProduction,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Currently active',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.statusInProduction,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (canManage && !isActive) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmAndJump(context),
                        icon: Icon(
                          isComplete
                              ? Icons.undo
                              : Icons.skip_next,
                          size: 16,
                        ),
                        label: Text(
                          isComplete ? 'Move trailer back here' : 'Move trailer here',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: AppColors.navy,
                          side: BorderSide(
                              color: AppColors.navy.withValues(alpha: 0.4)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab 3: History ───────────────────────────────────────────────────────────

class _HistoryTab extends StatelessWidget {
  final List<HistoryEntry> history;
  const _HistoryTab({required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const Center(child: Text('No history yet'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final entry = history[i];
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.navy.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.history, size: 16, color: AppColors.navy),
          ),
          title: Text(entry.action,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.userName != null)
                Text(entry.userName!,
                    style: const TextStyle(fontSize: 11, color: AppColors.disabled)),
              if (entry.timestamp != null)
                Text(
                  DateFormat.yMMMd().add_jm().format(entry.timestamp!),
                  style: const TextStyle(fontSize: 11, color: AppColors.disabled),
                ),
              if (entry.details != null && entry.details!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(entry.details!,
                      style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StagePhotosTab extends StatelessWidget {
  final List<StagePhotoGroup> stagePhotos;
  const _StagePhotosTab({required this.stagePhotos});

  @override
  Widget build(BuildContext context) {
    if (stagePhotos.isEmpty) {
      return const Center(child: Text('No stage photos available'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: stagePhotos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final group = stagePhotos[index];

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.stageLabel,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: group.photos.map((photo) {
                    return GestureDetector(
                      onTap: photo.downloadUrl == null
                          ? null
                          : () => _showPhotoDialog(context, photo),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          children: [
                            Container(
                              width: 110,
                              height: 110,
                              color: AppColors.divider.withValues(alpha: 0.35),
                              child: photo.downloadUrl != null
                                  ? Image.network(
                                      photo.downloadUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.broken_image_outlined),
                                    )
                                  : const Icon(Icons.photo_outlined),
                            ),
                            if (photo.note != null && photo.note!.isNotEmpty)
                              Positioned(
                                left: 4,
                                right: 4,
                                bottom: 4,
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  color: Colors.black54,
                                  child: Text(
                                    photo.note!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPhotoDialog(BuildContext context, TrailerStagePhoto photo) {
    if (photo.downloadUrl == null) return;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Text(
                photo.stageLabel,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: InteractiveViewer(child: Image.network(photo.downloadUrl!)),
            ),
          ],
        ),
      ),
    );
  }
}
