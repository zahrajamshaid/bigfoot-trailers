/// A manual payroll line-item (bonus / correction / deduction) added to a
/// worker's pay for a given week. Dollars may be negative.
class PayrollAdjustment {
  final int id;
  final int userId;
  final String fullName;
  final String effectiveDate; // YYYY-MM-DD
  final double dollars;
  final String note;

  const PayrollAdjustment({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.effectiveDate,
    required this.dollars,
    required this.note,
  });

  factory PayrollAdjustment.fromJson(Map<String, dynamic> json) =>
      PayrollAdjustment(
        id: int.parse(json['id'].toString()),
        userId: int.parse(json['userId'].toString()),
        fullName: (json['fullName'] as String?) ?? 'Unknown',
        effectiveDate: (json['effectiveDate'] as String?) ?? '',
        dollars: (json['dollars'] as num?)?.toDouble() ?? 0,
        note: (json['note'] as String?) ?? '',
      );
}
