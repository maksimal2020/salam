import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:migrant_guide/api/api_client.dart';
import 'package:migrant_guide/state/app_state.dart';
import 'package:migrant_guide/state/location_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeLocation implements LocationProvider {
  FakeLocation(this.outcome);
  final LocationOutcome outcome;
  int calls = 0;
  @override
  Future<LocationOutcome> current() async {
    calls++;
    return outcome;
  }
}

const moscow = {
  'id': 'moscow',
  'name': 'Москва',
  'region': 'г. Москва',
  'districts': [
    {'id': 'cao', 'name': 'ЦАО (Центральный)'},
    {'id': 'sao', 'name': 'САО (Северный)'},
  ],
};
const khimki = {'id': 'khimki', 'name': 'Химки', 'region': 'Московская область', 'districts': []};
const kazan = {'id': 'kazan', 'name': 'Казань', 'region': 'Республика Татарстан', 'districts': []};

Map<String, dynamic> institution({required String id, required String name, required Map<String, dynamic> city, required bool otherCity}) => {
      'id': id,
      'name': name,
      'status': 'verified',
      'checked_at': '2026-10-01',
      'mode': 'in_person',
      'city': {'id': city['id'], 'name': city['name'], 'region': city['region']},
      'other_city': otherCity,
      'address': 'ул. Тестовая, 1',
      'map': {'query': null, 'lat': null, 'lon': null},
      'hours': 'пн–пт 9:00–18:00',
      'phone': null,
      'site': null,
      'booking_url': null,
      'services': [
        {'id': 'passport_valid', 'title': 'Паспорт'}
      ],
      'serves': [
        {'city': 'Химки', 'districts': null}
      ],
      'citizenships': null,
      'sources': [
        {'title': 'Официальная страница', 'url': 'https://example.org/'}
      ],
      'note': null,
    };

/// Ответ вымышленного сервера. Данные тестовые, к реальным учреждениям отношения не имеют.
http.Response fakeServer(http.Request r) {
  Map<String, dynamic> places(Map<String, dynamic> city, List<Map<String, dynamic>> inst, {bool needsDistrict = false}) => {
        'document': {'id': 'passport_valid', 'necessity': 'mandatory', 'status': 'demo', 'checked_at': null, 'situations': <String>[], 'title': 'Паспорт', 'summary': 'Документ'},
        'where_kind': 'institutions',
        'where_note': null,
        'official_search': null,
        'sources': <Map<String, String>>[],
        'needs_city': false,
        'city': city,
        'institutions': inst,
        'needs_district': needsDistrict,
        'districts': city['districts'],
      };

  Object? body;
  final path = r.url.path;
  final q = r.url.queryParameters;
  if (path == '/api/i18n/ru') {
    final strings = jsonDecode(File('assets/i18n/ru.json').readAsStringSync());
    body = {'lang': 'ru', 'strings': strings, 'missing': <String>[]};
  } else if (path == '/api/meta') {
    body = {
      'languages': <Object>[],
      'citizenships': [
        {'id': 'KG', 'group': 'eaeu', 'name': 'Кыргызстан'}
      ],
      'situations': [
        {'id': 'before_arrival', 'name': 'До приезда'}
      ],
      'reference': {'purposes': ['work', 'study'], 'stages': ['before', 'in_russia'], 'flags': ['has_contract']},
      'includeDemo': true,
    };
  } else if (path == '/api/cities') {
    final text = (q['q'] ?? '').toLowerCase();
    body = {'cities': [if ('казань'.contains(text) && text.isNotEmpty) kazan, if ('химки'.contains(text) && text.isNotEmpty) khimki]};
  } else if (path == '/api/cities/locate') {
    body = {'status': 'candidate', 'city': moscow};
  } else if (path == '/api/documents') {
    body = {
      'documents': [
        {'id': 'passport_valid', 'necessity': 'mandatory', 'status': 'demo', 'checked_at': null, 'situations': ['before_arrival'], 'title': 'Паспорт', 'summary': 'Документ'}
      ]
    };
  } else if (path == '/api/documents/passport_valid') {
    body = {
      'id': 'passport_valid', 'necessity': 'mandatory', 'status': 'demo', 'checked_at': null, 'situations': ['before_arrival'], 'title': 'Паспорт', 'summary': 'Документ',
      'details': {'who': 'Все', 'prepare': ['Паспорт'], 'how': ['Проверьте срок']},
      'details_fallback': false, 'deadline': null, 'cost': null, 'sources': <Object>[], 'where_kind': 'institutions', 'where_note': null,
    };
  } else if (path == '/api/documents/passport_valid/places') {
    switch (q['city']) {
      case 'moscow':
        body = q['district'] == 'cao'
            ? places(moscow, [institution(id: 'i_cao', name: 'Подразделение ЦАО', city: moscow, otherCity: false)])
            : places(moscow, [], needsDistrict: true);
        break;
      case 'khimki':
        // Учреждение находится в другом городе, но обслуживает выбранный.
        body = places(khimki, [institution(id: 'i_far', name: 'Центр в Москве', city: moscow, otherCity: true)]);
        break;
      default:
        body = places(kazan, []);
    }
  } else if (path == '/api/tips') {
    body = {'tips': <Object>[]};
  } else if (path == '/api/listings') {
    body = {'listings': <Object>[]};
  }
  if (body == null) return http.Response(jsonEncode({'code': 'not_found'}), 404, headers: {'content-type': 'application/json; charset=utf-8'});
  return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
}

Future<AppState> makeState({
  LocationProvider? location,
  Map<String, Object> prefsInit = const {},
  http.Client? client,
}) async {
  // ignore: avoid_print
  print('[trace] makeState: setMockInitialValues begin');
  SharedPreferences.setMockInitialValues(prefsInit);
  // ignore: avoid_print
  print('[trace] makeState: getInstance begin');
  final prefs = await SharedPreferences.getInstance();
  // ignore: avoid_print
  print('[trace] makeState: getInstance done');
  final tokens = MemoryTokenStore();
  final api = ApiClient(
    baseUrl: 'http://test',
    tokens: tokens,
    prefs: prefs,
    client: client ?? MockClient((r) async => fakeServer(r)),
  );
  final state = AppState(prefs: prefs, api: api, tokens: tokens, location: location ?? FakeLocation(const LocationOutcome(LocationStatus.denied)));
  // ignore: avoid_print
  print('[trace] makeState: state.init begin');
  await state.init();
  // ignore: avoid_print
  print('[trace] makeState: state.init done');
  return state;
}
