import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/repositories/activity_repository.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';

/// Wraps the app shell and sends a lightweight usage heartbeat every 60s while
/// the app is foregrounded and the user is signed in. Powers the admin
/// "User Activity" screen (daily active users + time-on-app). Fire-and-forget:
/// the repository swallows all errors, so a flaky network never disrupts use.
class ActivityHeartbeat extends StatefulWidget {
  final Widget child;

  const ActivityHeartbeat({super.key, required this.child});

  @override
  State<ActivityHeartbeat> createState() => _ActivityHeartbeatState();
}

class _ActivityHeartbeatState extends State<ActivityHeartbeat>
    with WidgetsBindingObserver {
  static const Duration _interval = Duration(seconds: 60);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _start() {
    _beat(); // immediate ping on launch / foreground
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _beat());
  }

  void _beat() {
    if (!mounted) return;
    final auth = context.read<AuthViewModel>().state;
    if (auth is! Authenticated) return;
    // Fire-and-forget — errors are swallowed inside the repository.
    context.read<ActivityRepository>().heartbeat();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
