import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/dio_client.dart';
import '../../../data/models/user.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../data/support_api.dart';
import '../model/support_ticket.dart';
import '../viewmodel/support_thread_cubit.dart';

/// One support ticket thread: the conversation between the reporter and the
/// admins, with a reply box. Admins get a Resolve / Reopen action.
class SupportThreadScreen extends StatelessWidget {
  final int ticketId;
  const SupportThreadScreen({super.key, required this.ticketId});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthViewModel>().state;
    final me = auth is Authenticated ? auth.user : null;
    final isAdmin = me != null &&
        (me.role == UserRole.owner ||
            me.role == UserRole.office ||
            me.role == UserRole.productionManager);

    return BlocProvider<SupportThreadCubit>(
      create: (ctx) =>
          SupportThreadCubit(SupportApi(ctx.read<DioClient>()), ticketId)..load(),
      child: _ThreadView(myId: me?.id, isAdmin: isAdmin),
    );
  }
}

class _ThreadView extends StatefulWidget {
  final int? myId;
  final bool isAdmin;
  const _ThreadView({required this.myId, required this.isAdmin});

  @override
  State<_ThreadView> createState() => _ThreadViewState();
}

class _ThreadViewState extends State<_ThreadView> {
  final _replyController = TextEditingController();

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    final ok = await context.read<SupportThreadCubit>().reply(text);
    if (ok) _replyController.clear();
  }

  Future<void> _confirmDelete(BuildContext context, int ticketId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this report?'),
        content: const Text('This removes the whole conversation. It can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await SupportApi(context.read<DioClient>()).deleteTicket(ticketId);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SupportThreadCubit, SupportThreadState>(
      builder: (context, state) {
        final detail = state.detail;
        return Scaffold(
          appBar: AppBar(
            title: Text(detail?.subject ?? 'Report'),
            actions: [
              if (widget.isAdmin && detail != null)
                TextButton(
                  onPressed: () => context
                      .read<SupportThreadCubit>()
                      .setResolved(detail.isOpen),
                  child: Text(
                    detail.isOpen ? 'Resolve' : 'Reopen',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (widget.isAdmin && detail != null)
                IconButton(
                  tooltip: 'Delete report',
                  icon: const Icon(Icons.delete_outline, color: AppColors.white),
                  onPressed: () => _confirmDelete(context, detail.id),
                ),
            ],
          ),
          body: Column(
            children: [
              if (detail != null && !detail.isOpen)
                Container(
                  width: double.infinity,
                  color: AppColors.success.withValues(alpha: 0.12),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: const Center(
                    child: Text('Resolved',
                        style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                  ),
                ),
              Expanded(
                child: detail == null
                    ? Center(
                        child: state.loading
                            ? const CircularProgressIndicator(
                                color: AppColors.amber)
                            : const Text('Could not load this report'),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          for (final m in detail.messages)
                            _Bubble(
                              message: m,
                              mine: widget.myId != null &&
                                  m.senderId == widget.myId,
                            ),
                        ],
                      ),
              ),
              _Composer(
                controller: _replyController,
                sending: state.sending,
                onSend: _send,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  final SupportMessage message;
  final bool mine;
  const _Bubble({required this.message, required this.mine});

  @override
  Widget build(BuildContext context) {
    final bg = mine ? AppColors.navy : AppColors.background;
    final fg = mine ? AppColors.white : AppColors.navy;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: mine ? null : Border.all(color: AppColors.disabled.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.senderName + (message.fromReporter ? ' (reporter)' : ''),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: fg.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 2),
            Text(message.body, style: TextStyle(color: fg)),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Write a reply…',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            sending
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: AppColors.amber),
                    onPressed: onSend,
                    icon: const Icon(Icons.send),
                  ),
          ],
        ),
      ),
    );
  }
}
