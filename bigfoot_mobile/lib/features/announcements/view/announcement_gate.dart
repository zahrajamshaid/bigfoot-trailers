import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/announcement.dart';
import '../../../domain/repositories/announcement_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';

/// Wraps the routed app shell content and intercepts the user with a
/// non-dismissible AlertDialog whenever the backend has unread floor-wide
/// messages for them. One dialog at a time, oldest first — tapping OK acks
/// that message and either shows the next one or releases the user back to
/// the app.
///
/// Fetch points: the first time the user is authenticated (on login or
/// app launch) and every time the app returns to foreground.
class AnnouncementGate extends StatefulWidget {
  final Widget child;

  const AnnouncementGate({super.key, required this.child});

  @override
  State<AnnouncementGate> createState() => _AnnouncementGateState();
}

class _AnnouncementGateState extends State<AnnouncementGate>
    with WidgetsBindingObserver {
  final List<Announcement> _queue = [];
  bool _dialogShowing = false;
  bool _fetchInFlight = false;
  bool _hasFetchedSinceAuth = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from background → re-poll. The server may have new
    // announcements since the user backgrounded the app.
    if (state == AppLifecycleState.resumed) {
      _maybeFetch(force: true);
    }
  }

  Future<void> _maybeFetch({bool force = false}) async {
    if (_fetchInFlight) return;
    final auth = context.read<AuthViewModel>().state;
    if (auth is! Authenticated) {
      _hasFetchedSinceAuth = false;
      return;
    }
    if (!force && _hasFetchedSinceAuth) return;

    _fetchInFlight = true;
    try {
      final pending = await context.read<AnnouncementRepository>().getPending();
      if (!mounted) return;
      // De-dup against anything still queued so a re-poll while the user is
      // still on the modal doesn't add duplicates.
      final existingIds = _queue.map((a) => a.id).toSet();
      _queue.addAll(pending.where((a) => !existingIds.contains(a.id)));
      _hasFetchedSinceAuth = true;
      _showNextIfNeeded();
    } catch (_) {
      // Network failure isn't fatal — we'll try again on next lifecycle change.
    } finally {
      _fetchInFlight = false;
    }
  }

  void _showNextIfNeeded() {
    if (_dialogShowing || _queue.isEmpty || !mounted) return;
    _dialogShowing = true;
    final announcement = _queue.first;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      // The route-level barrier is the same as the modal — we also block
      // the system back button below via PopScope so a hardware Back
      // can't sneak past the ack.
      builder: (dialogCtx) {
        return _AnnouncementDialog(
          announcement: announcement,
          onAck: () async {
            try {
              await context
                  .read<AnnouncementRepository>()
                  .ack(announcement.id);
            } catch (_) {
              // Even if the ack fails on the network we remove it locally;
              // the next poll will resurface it if the server still has it
              // open. Beats locking the user out on a flaky connection.
            }
            if (!dialogCtx.mounted) return;
            Navigator.of(dialogCtx).pop();
            // Pop the just-acked one and chain to the next, if any.
            if (mounted) {
              setState(() {
                _queue.removeAt(0);
                _dialogShowing = false;
              });
              _showNextIfNeeded();
            }
          },
        );
      },
    ).whenComplete(() {
      if (mounted && _dialogShowing) {
        // Safety net — if the dialog was popped by another route push, flush
        // the showing flag so a re-fetch can reopen us.
        _dialogShowing = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthViewModel, AuthState>(
      // Fetch as soon as the user becomes authenticated (login, refresh,
      // cold boot with a saved token). The listener also fires on logout
      // but `_maybeFetch` early-returns in that case.
      listener: (_, state) {
        if (state is Authenticated) {
          _hasFetchedSinceAuth = false;
          _maybeFetch();
        } else {
          // Drop anything queued so a re-login as a different user doesn't
          // see the previous user's pending list.
          setState(() {
            _queue.clear();
            _hasFetchedSinceAuth = false;
          });
        }
      },
      child: Builder(builder: (ctx) {
        // First-pass fetch on mount if the user is already authenticated
        // (cold boot with saved token).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _maybeFetch();
        });
        return widget.child;
      }),
    );
  }
}

class _AnnouncementDialog extends StatefulWidget {
  final Announcement announcement;
  final Future<void> Function() onAck;

  const _AnnouncementDialog({
    required this.announcement,
    required this.onAck,
  });

  @override
  State<_AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<_AnnouncementDialog> {
  bool _acking = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final a = widget.announcement;
    return PopScope(
      // Hardware back button can't escape until OK is tapped.
      canPop: false,
      child: AlertDialog(
        icon: const Icon(Icons.campaign, color: AppColors.navy, size: 32),
        title: Text(a.title?.trim().isNotEmpty == true
            ? a.title!.trim()
            : l.announcementDefaultTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.body, style: const TextStyle(fontSize: 15, height: 1.35)),
              if (a.postedByName != null && a.postedByName!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  l.announcementPostedBy(a.postedByName!),
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: _acking
                ? null
                : () async {
                    setState(() => _acking = true);
                    await widget.onAck();
                  },
            child: _acking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l.commonOk),
          ),
        ],
      ),
    );
  }
}
