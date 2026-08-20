/// The fixed crew for a production step's department, used by the completion
/// screen to let the completer uncheck absent members (crew stages only).
class StepCrewMember {
  final int userId;
  final String fullName;
  final int slot;

  const StepCrewMember({
    required this.userId,
    required this.fullName,
    required this.slot,
  });

  factory StepCrewMember.fromJson(Map<String, dynamic> json) => StepCrewMember(
        userId: int.parse(json['userId'].toString()),
        fullName: (json['fullName'] as String?) ?? 'Worker',
        slot: (json['slot'] as num?)?.toInt() ?? 0,
      );
}

class StepCrew {
  final String departmentName;
  final bool isCrewStage;
  final List<StepCrewMember> crew;

  const StepCrew({
    required this.departmentName,
    required this.isCrewStage,
    required this.crew,
  });

  factory StepCrew.fromJson(Map<String, dynamic> json) => StepCrew(
        departmentName: (json['departmentName'] as String?) ?? '',
        isCrewStage: json['isCrewStage'] as bool? ?? false,
        crew: ((json['crew'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(StepCrewMember.fromJson)
            .toList(),
      );
}
