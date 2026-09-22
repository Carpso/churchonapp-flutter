/// Defensive JSON/number coercion helpers.
///
/// Supabase/PostgREST RPCs can return a numeric value as a JSON number, a
/// numeric string (e.g. `numeric`/`bigint` rendered as text), or `null`
/// depending on the function. A bare `value as num?` cast throws a `TypeError`
/// on a `String`/`null` and, when it happens inside `build()`, kills the whole
/// screen. Always go through these helpers for RPC/row values.
library;

/// Best-effort numeric coercion. Returns `null` for null/unparseable values.
num? asNum(dynamic value) {
  if (value == null) return null;
  if (value is num) return value;
  if (value is bool) return value ? 1 : 0;
  final parsed = num.tryParse(value.toString().replaceAll(',', '').trim());
  return parsed;
}

/// Coerces to `int`, tolerating strings, doubles, null and non-finite values.
int asInt(dynamic value, {int fallback = 0}) {
  final n = asNum(value);
  if (n == null || !n.isFinite) return fallback;
  return n.toInt();
}

/// Coerces to `double`, tolerating strings, ints, null and non-finite values.
double asDouble(dynamic value, {double fallback = 0}) {
  final n = asNum(value);
  if (n == null || !n.isFinite) return fallback;
  return n.toDouble();
}

/// Coerces to `bool`, tolerating strings such as `"true"`/`"1"`.
bool asBool(dynamic value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final s = value.toString().toLowerCase().trim();
  if (s == 'true' || s == 't' || s == '1' || s == 'yes') return true;
  if (s == 'false' || s == 'f' || s == '0' || s == 'no') return false;
  return fallback;
}
