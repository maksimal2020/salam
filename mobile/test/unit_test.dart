import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:migrant_guide/api/api_client.dart';
import 'package:migrant_guide/api/models.dart';
import 'package:migrant_guide/state/location_provider.dart';
import 'package:migrant_guide/util/links.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiClient', () {
    test('собирает адрес и пропускает пустые параметры', () async {
      SharedPreferences.setMockInitialValues({});
      final api = ApiClient(baseUrl: 'http://host:3000/', tokens: MemoryTokenStore(), prefs: await SharedPreferences.getInstance());
      final u = api.uri('/documents', {'lang': 'ru', 'q': '', 'situation': null, 'x': false, 'city': 'moscow'});
      expect(u.toString(), 'http://host:3000/api/documents?lang=ru&city=moscow');
    });

    test('передаёт токен и разбирает код ошибки', () async {
      SharedPreferences.setMockInitialValues({});
      String? seen;
      final tokens = MemoryTokenStore();
      await tokens.write('abc');
      final api = ApiClient(
        baseUrl: 'http://t',
        tokens: tokens,
        prefs: await SharedPreferences.getInstance(),
        client: MockClient((r) async {
          seen = r.headers['authorization'];
          return http.Response(jsonEncode({'code': 'invalid_credentials'}), 401, headers: {'content-type': 'application/json'});
        }),
      );
      await expectLater(api.post('/auth/login', {'email': 'a'}), throwsA(isA<ApiError>().having((e) => e.code, 'code', 'invalid_credentials').having((e) => e.status, 'status', 401)));
      expect(seen, 'Bearer abc');
    });

    test('без связи отдаёт сохранённую копию только для справочных запросов', () async {
      SharedPreferences.setMockInitialValues({});
      var online = true;
      var servedFromCache = 0;
      final api = ApiClient(
        baseUrl: 'http://t',
        tokens: MemoryTokenStore(),
        prefs: await SharedPreferences.getInstance(),
        onServedFromCache: () => servedFromCache++,
        client: MockClient((r) async {
          if (!online) throw http.ClientException('offline');
          return http.Response(jsonEncode({'ok': r.url.path}), 200, headers: {'content-type': 'application/json'});
        }),
      );
      await api.get('/documents', cache: true);
      await api.get('/my/listings');
      online = false;
      final cached = await api.get('/documents', cache: true) as Map;
      expect(cached['ok'], '/api/documents');
      expect(servedFromCache, 1);
      await expectLater(api.get('/my/listings'), throwsA(isA<ApiError>().having((e) => e.isNetwork, 'isNetwork', true)));
    });

    test('кириллица в ответе читается как UTF-8 даже без charset', () async {
      SharedPreferences.setMockInitialValues({});
      final api = ApiClient(
        baseUrl: 'http://t',
        tokens: MemoryTokenStore(),
        prefs: await SharedPreferences.getInstance(),
        client: MockClient((r) async => http.Response.bytes(utf8.encode(jsonEncode({'name': 'Москва'})), 200, headers: {'content-type': 'application/json'})),
      );
      expect((await api.get('/x') as Map)['name'], 'Москва');
    });
  });

  group('mapUrl', () {
    test('адрес без города дополняется городом', () {
      final u = mapUrl(const MapRef(), 'ул. Тестовая, 1', 'Химки');
      expect(Uri.parse(u!).queryParameters['text'], 'Химки, ул. Тестовая, 1');
    });
    test('без адреса ищем по названию', () {
      final u = mapUrl(const MapRef(query: 'Центр'), null, 'Химки');
      expect(Uri.parse(u!).queryParameters['text'], 'Центр');
    });
    test('нет ни адреса, ни названия — ссылки нет', () {
      expect(mapUrl(const MapRef(), null, 'Химки'), isNull);
    });
  });

  group('AppState', () {
    test('подстановка параметров и запасной вариант — сам ключ', () async {
      final s = await makeState();
      s.strings = {'city.found': 'Мы нашли: {city}. Это ваш город?'};
      expect(s.t('city.found', {'city': 'Казань'}), 'Мы нашли: Казань. Это ваш город?');
      expect(s.t('нет.такого'), 'нет.такого');
    });

    test('дата выводится как ДД.ММ.ГГГГ', () async {
      final s = await makeState();
      expect(s.fmtDate('2026-10-01'), '01.10.2026');
      expect(s.fmtDate(null), '');
    });

    test('сохраняются только город и регион, координаты не сохраняются', () async {
      final loc = FakeLocation(const LocationOutcome(LocationStatus.ok, lat: 55.7512, lon: 37.6184));
      final s = await makeState(location: loc);
      final r = await s.detectCity();
      expect(r.candidate?.id, 'moscow');
      s.setCity(r.candidate);
      final stored = s.prefs.getKeys().map((k) => '$k=${s.prefs.get(k)}').join('\n');
      expect(stored, contains('moscow'));
      expect(stored, isNot(contains('55.75')));
      expect(stored, isNot(contains('37.61')));
    });

    test('отказ в геолокации и недоступность ведут к ручному выбору', () async {
      var s = await makeState(location: FakeLocation(const LocationOutcome(LocationStatus.denied)));
      expect((await s.detectCity()).messageKey, 'city.denied');
      s = await makeState(location: FakeLocation(const LocationOutcome(LocationStatus.unavailable)));
      expect((await s.detectCity()).messageKey, 'city.unavailable');
    });

    test('при смене города район сбрасывается', () async {
      final s = await makeState();
      s.setCity(const City(id: 'moscow', name: 'Москва', region: 'г. Москва'));
      s.setDistrict('cao');
      expect(s.district, 'cao');
      s.setCity(const City(id: 'kazan', name: 'Казань', region: 'Республика Татарстан'));
      expect(s.district, isNull);
      expect(s.prefs.getString('district'), isNull);
    });

    test('«Выбрать позже» не задаёт город, но больше не спрашивает', () async {
      final s = await makeState();
      expect(s.cityAsked, false);
      s.skipCity();
      expect(s.cityAsked, true);
      expect(s.city, isNull);
    });
  });

  group('модели', () {
    test('учреждение из другого города', () {
      final i = Institution.fromJson(institution(id: 'i', name: 'Центр', city: moscow, otherCity: true));
      expect(i.otherCity, true);
      expect(i.city.name, 'Москва');
      expect(i.serves.first.districts, isNull);
    });

    test('объявление: поля автора есть только у автора', () {
      final base = {'id': 1, 'category': 'housing', 'title': 'a', 'body': 'b', 'lang': 'tg', 'city': kazan, 'extra': {}, 'status': 'published'};
      expect(Listing.fromJson(base).hasOwnerFields, false);
      expect(Listing.fromJson({...base, 'moderation_note': null}).hasOwnerFields, true);
      expect(Listing.fromJson(base).lang, 'tg');
    });
  });
}
