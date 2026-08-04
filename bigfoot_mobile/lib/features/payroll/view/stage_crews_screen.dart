import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/dio_client.dart';

/// Admin editor for the fixed crew roster on split-pay stages (gooseneck jig
/// weld, yeti finish weld). Slot 1 earns the model's top split rate, slot 2 the
/// next, etc. Owner / office / production_manager only.
class StageCrewsScreen extends StatefulWidget {
  const StageCrewsScreen({super.key});

  @override
  State<StageCrewsScreen> createState() => _StageCrewsScreenState();
}

class _StageCrewsScreenState extends State<StageCrewsScreen> {
  bool _loading = true;
  String? _error;
  List<_Crew> _crews = [];
  List<_Worker> _workers = [];
  final Set<int> _saving = {};

  DioClient get _api => context.read<DioClient>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final crewsResp = await _api.get<List<dynamic>>(
        ApiEndpoints.payrollStageCrews,
        fromJson: (d) => d as List<dynamic>,
      );
      final usersResp = await _api.get<List<dynamic>>(
        ApiEndpoints.users,
        fromJson: (d) => d as List<dynamic>,
      );
      final crews = (crewsResp.data ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_Crew.fromJson)
          .toList();
      final workers = (usersResp.data ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_Worker.fromJson)
          .where((w) => w.isActive)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) {
        setState(() {
          _crews = crews;
          _workers = workers;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _save(_Crew crew) async {
    final ids = crew.slots.where((s) => s != null).map((s) => s!).toList();
    setState(() => _saving.add(crew.departmentId));
    try {
      await _api.patch<Map<String, dynamic>>(
        ApiEndpoints.payrollStageCrew(crew.departmentId),
        data: {'userIds': ids},
        fromJson: (d) => d as Map<String, dynamic>,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${crew.departmentName} crew saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(crew.departmentId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stage crews')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : _crews.isEmpty
                  ? const Center(child: Text('No split-pay stages configured.'))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          'These stages split pay across a crew. Assign who\'s on each '
                          'crew; slot 1 earns the top rate, slot 2 the next, and so on.',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 12),
                        ..._crews.map(_buildCrewCard),
                      ],
                    ),
    );
  }

  Widget _buildCrewCard(_Crew crew) {
    final saving = _saving.contains(crew.departmentId);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(crew.departmentName,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.navy)),
            const SizedBox(height: 12),
            ...List.generate(crew.maxSlots, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: Text('Slot ${i + 1}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        value: crew.slots[i],
                        isExpanded: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('— unassigned —'),
                          ),
                          ..._workers.map((w) => DropdownMenuItem<int?>(
                                value: w.id,
                                child: Text(w.name, overflow: TextOverflow.ellipsis),
                              )),
                        ],
                        onChanged: (v) => setState(() => crew.slots[i] = v),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: saving ? null : () => _save(crew),
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save, size: 18),
                label: const Text('Save crew'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.amber),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Crew {
  final int departmentId;
  final String departmentName;
  final int maxSlots;
  final List<int?> slots; // slot index -> userId (mutable)

  _Crew({
    required this.departmentId,
    required this.departmentName,
    required this.maxSlots,
    required this.slots,
  });

  factory _Crew.fromJson(Map<String, dynamic> j) {
    final maxSlots = (j['maxSlots'] as num?)?.toInt() ?? 3;
    final slots = List<int?>.filled(maxSlots, null);
    for (final m in (j['members'] as List<dynamic>? ?? const [])) {
      if (m is Map<String, dynamic>) {
        final slot = (m['slot'] as num?)?.toInt();
        final userId = int.tryParse('${m['userId']}');
        if (slot != null && slot < maxSlots && userId != null) slots[slot] = userId;
      }
    }
    return _Crew(
      departmentId: (j['departmentId'] as num?)?.toInt() ?? 0,
      departmentName: j['departmentName'] as String? ?? '',
      maxSlots: maxSlots,
      slots: slots,
    );
  }
}

class _Worker {
  final int id;
  final String name;
  final bool isActive;
  _Worker({required this.id, required this.name, required this.isActive});

  factory _Worker.fromJson(Map<String, dynamic> j) => _Worker(
        id: int.tryParse('${j['id']}') ?? 0,
        name: (j['fullName'] ?? j['name'] ?? j['email'] ?? 'User') as String,
        isActive: (j['isActive'] as bool?) ?? true,
      );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 40),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
