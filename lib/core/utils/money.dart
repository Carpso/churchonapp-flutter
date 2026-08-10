import 'package:intl/intl.dart';

final _kwachaFormat = NumberFormat('#,##0.00', 'en_US');
final _kwachaWholeFormat = NumberFormat('#,##0', 'en_US');

String formatKwacha(double amount) => 'K${_kwachaFormat.format(amount)}';

String formatKwachaPlain(double amount) => _kwachaFormat.format(amount);

String formatKwachaWhole(double amount) => 'K${_kwachaWholeFormat.format(amount)}';

String formatPct(double pct) {
  if (!pct.isFinite) return '0%';
  final rounded = pct.round();
  final t = (pct - rounded).abs() < 0.05 ? rounded.toString() : pct.toStringAsFixed(1);
  return '$t%';
}
