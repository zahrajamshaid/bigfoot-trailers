import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/constants/app_colors.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/location.dart';
import '../../domain/repositories/location_repository.dart';

/// Chip-style picker for trailer yards (Mul, Jax, VA, GA, TAL).
///
/// Loads locations from [LocationRepository] (cached for the session) so a
/// rename or new yard on the backend propagates with no app build. The
/// selected chip is highlighted and the city/state shows below as confirmation.
class StockLocationChips extends StatefulWidget {
  final int? selectedLocationId;
  final ValueChanged<Location> onChanged;
  final bool enabled;
  final String? labelText;
  final String? helperText;
  final String? errorText;

  const StockLocationChips({
    super.key,
    required this.selectedLocationId,
    required this.onChanged,
    this.enabled = true,
    this.labelText,
    this.helperText,
    this.errorText,
  });

  @override
  State<StockLocationChips> createState() => _StockLocationChipsState();
}

class _StockLocationChipsState extends State<StockLocationChips> {
  bool _loading = true;
  String? _error;
  List<Location> _locations = const [];

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
      final repo = context.read<LocationRepository>();
      // getAllLocations (not getStockLocations) so the Mulberry factory yard
      // is offered as a stock destination too — a stock build can be held at
      // the factory, not just the satellite yards.
      final items = await repo.getAllLocations();
      if (!mounted) return;
      setState(() {
        _locations = items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.displayMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load locations.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _locations.firstWhere(
      (l) => l.id == widget.selectedLocationId,
      orElse: () => const Location(id: -1, code: '', name: ''),
    );
    final hasSelection = selected.id != -1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.labelText != null) ...[
          Text(
            widget.labelText!,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.disabled,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: AppColors.amber),
            ),
          )
        else if (_error != null)
          Row(
            children: [
              const Icon(Icons.error_outline,
                  size: 18, color: AppColors.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _error!,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.error),
                ),
              ),
              TextButton(
                onPressed: widget.enabled ? _load : null,
                child: const Text('Retry'),
              ),
            ],
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _locations.map((l) {
              final isSelected = l.id == widget.selectedLocationId;
              return ChoiceChip(
                label: Text(l.chipLabel),
                selected: isSelected,
                onSelected: widget.enabled
                    ? (_) => widget.onChanged(l)
                    : null,
                selectedColor: AppColors.amber.withValues(alpha: 0.85),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isSelected ? AppColors.navy : null,
                ),
                tooltip: l.cityState.isEmpty ? l.name : l.cityState,
              );
            }).toList(),
          ),
        if (hasSelection) ...[
          const SizedBox(height: 6),
          Text(
            selected.cityState.isEmpty ? selected.name : selected.cityState,
            style: const TextStyle(fontSize: 12, color: AppColors.disabled),
          ),
        ],
        if (widget.errorText != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.errorText!,
            style: const TextStyle(fontSize: 12, color: AppColors.error),
          ),
        ] else if (widget.helperText != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.helperText!,
            style: const TextStyle(fontSize: 12, color: AppColors.disabled),
          ),
        ],
      ],
    );
  }
}
