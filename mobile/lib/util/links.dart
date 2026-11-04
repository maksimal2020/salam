import 'package:url_launcher/url_launcher.dart';

import '../api/models.dart';

/// Открывает ссылку во внешнем приложении (браузер, карты, телефон). Возвращает false, если не вышло.
Future<bool> openExternal(String url) async {
  try {
    final uri = Uri.parse(url);
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Ссылка «Открыть на карте». Подтверждённый адрес важнее названия; без адреса ищем по названию.
String? mapUrl(MapRef map, String? address, String cityName) {
  if (map.lat != null && map.lon != null && address != null) {
    return 'https://yandex.ru/maps/?pt=${map.lon},${map.lat}&z=16&l=map';
  }
  final q = address ?? map.query;
  if (q == null || q.isEmpty) return null;
  final text = address != null && !address.contains(cityName) ? '$cityName, $q' : q;
  return 'https://yandex.ru/maps/?text=${Uri.encodeQueryComponent(text)}';
}

String telUri(String phone) => 'tel:${phone.replaceAll(RegExp(r'[^+\d]'), '')}';
