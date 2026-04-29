import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/worker_message.dart';
import '../viewmodel/messages_viewmodel.dart';

class MessageScreen extends StatefulWidget {
  final int trailerId;

  const MessageScreen({super.key, required this.trailerId});

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  final TextEditingController _text = TextEditingController();
  final TextEditingController _recipient = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  List<WorkerMessage> _thread = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    _recipient.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final messages = await context.read<MessagesViewModel>().getThread(widget.trailerId);
      if (!mounted) return;
      setState(() => _thread = messages);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Trailer #${widget.trailerId} Messages'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _recipient,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Recipient User ID',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _thread.length,
                    itemBuilder: (_, i) {
                      final m = _thread[i];
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.navy.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.senderName ?? 'User ${m.senderUserId}',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(m.body),
                              const SizedBox(height: 4),
                              Text(
                                m.sentAt.toLocal().toString(),
                                style: const TextStyle(fontSize: 11, color: AppColors.disabled),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Message...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : _send,
                    child: const Text('Send'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    final recipient = int.tryParse(_recipient.text.trim());
    if (body.isEmpty || recipient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recipient user id and message are required')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final sent = await context.read<MessagesViewModel>().sendMessage(
            trailerId: widget.trailerId,
            recipientUserId: recipient,
            body: body,
          );
      if (!mounted) return;
      setState(() {
        _thread = [..._thread, sent];
        _text.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }
}
