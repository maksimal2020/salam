// Небольшие помощники для разбора JSON от сервера: ответ может содержать null там, где поле необязательное.

Map<String, dynamic> asMap(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

List<dynamic> asList(dynamic v) => v is List ? v : const <dynamic>[];

String? asStr(dynamic v) => v?.toString();

String strOr(dynamic v, [String fallback = '']) => v == null ? fallback : v.toString();

int asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? fallback;
}

double? asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v == null) return null;
  return double.tryParse('$v');
}

bool asBool(dynamic v) => v == true;

List<String> strList(dynamic v) => asList(v).map((e) => e.toString()).toList();
