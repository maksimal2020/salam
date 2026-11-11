import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'location_provider.dart';

/// Ответы пользователя для «Моего списка».
class Profile {
  const Profile({this.citizenship, this.purpose, this.stage, this.flags = const {}});
  final String? citizenship;
  final String? purpose;
  final String? stage;
  final Map<String, bool> flags;

  bool get complete => citizenship != null && purpose != null && stage != null;

  Profile copyWith({String? citizenship, String? purpose, String? stage, Map<String, bool>? flags}) => Profile(
        citizenship: citizenship ?? this.citizenship,
        purpose: purpose ?? this.purpose,
        stage: stage ?? this.stage,
        flags: flags ?? this.flags,
      );

  Map<String, dynamic> toJson() => {'citizenship': citizenship, 'purpose': purpose, 'stage': stage, 'flags': flags};

  /// Тело запроса POST /checklist.
  Map<String, dynamic> toRequest(String lang) => {
        if (citizenship != null) 'citizenship': citizenship,
        if (purpose != null) 'purpose': purpose,
        if (stage != null) 'stage': stage,
        'flags': flags,
        'lang': lang,
      };

  factory Profile.fromJson(dynamic j) {
    if (j is! Map) return const Profile();
    final flags = <String, bool>{};
    final f = j['flags'];
    if (f is Map) f.forEach((k, v) => flags[k.toString()] = v == true);
    String? s(dynamic v) => v is String && v.isNotEmpty ? v : null;
    return Profile(citizenship: s(j['citizenship']), purpose: s(j['purpose']), stage: s(j['stage']), flags: flags);
  }
}

/// Всё состояние приложения: язык, тексты, город, ответы для списка, отметки, вход.
/// Язык, город и гражданство выбираются независимо друг от друга.
class AppState extends ChangeNotifier {
  AppState({required this.prefs, required this.api, required this.tokens, required this.location});

  final SharedPreferences prefs;
  final ApiClient api;
  final TokenStore tokens;
  final LocationProvider location;

  String lang = 'ru';
  bool langChosen = false;
  Map<String, String> strings = {};
  bool ready = false;
  bool offline = false;
  Meta? meta;

  City? city;
  bool cityAsked = false;
  String? district;

  Profile profile = const Profile();
  Map<String, bool> marks = {};

  AppUser? user;

  int _stringsRequest = 0;
  int _metaRequest = 0;

  // ---------------------------------------------------------------- запуск

  Future<void> init() async {
    final savedLang = prefs.getString('lang');
    if (savedLang != null && kLangs.any((l) => l.code == savedLang)) {
      lang = savedLang;
      langChosen = true;
    }
    city = _readCity();
    cityAsked = prefs.getBool('cityAsked') ?? false;
    district = prefs.getString('district');
    profile = Profile.fromJson(_readJson('profile'));
    final m = _readJson('marks');
    if (m is Map) marks = m.map((k, v) => MapEntry(k.toString(), v == true));
    final u = _readJson('user');
    if (u is Map) user = AppUser.fromJson(u);

    await _loadStrings();
    unawaited(_loadMeta());
    unawaited(_verifyUser());
  }

  dynamic _readJson(String key) {
    try {
      final s = prefs.getString(key);
      return s == null ? null : jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  City? _readCity() {
    final j = _readJson('city');
    if (j is! Map) return null;
    final c = City.fromJson(j);
    return c.id.isEmpty ? null : c;
  }

  void _write(String key, Object? value) {
    prefs.setString(key, jsonEncode(value));
  }

  // ---------------------------------------------------------------- тексты

  Future<Map<String, String>?> _bundled(String code) async {
    try {
      final raw = await rootBundle.loadString('assets/i18n/$code.json');
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return null;
    }
  }

  /// Сначала показываем сохранённые или встроенные тексты, затем обновляем с сервера.
  Future<void> _loadStrings() async {
    final request = ++_stringsRequest;
    Map<String, String>? local;
    try {
      final saved = prefs.getString('strings:$lang');
      if (saved != null) local = (jsonDecode(saved) as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {}
    local ??= await _bundled(lang);
    if (request != _stringsRequest) return;
    if (local != null) {
      strings = local;
      ready = true;
      notifyListeners();
    }
    try {
      final r = asMapSafe(await api.get('/i18n/$lang'));
      final fresh = asMapSafe(r['strings']).map((k, v) => MapEntry(k, v.toString()));
      if (request != _stringsRequest) return;
      if (fresh.isNotEmpty) {
        strings = fresh;
        prefs.setString('strings:$lang', jsonEncode(fresh));
      }
      offline = false;
    } catch (_) {
      if (request != _stringsRequest) return;
      offline = true;
    }
    ready = true;
    notifyListeners();
  }

  static Map<String, dynamic> asMapSafe(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

  Future<void> _loadMeta() async {
    final request = ++_metaRequest;
    try {
      final j = await api.get('/meta', query: {'lang': lang}, cache: true);
      if (request != _metaRequest) return;
      meta = Meta.fromJson(j);
      notifyListeners();
    } catch (_) {
      // Без связи справочник берётся из сохранённой копии; если её нет — списки выбора останутся пустыми.
    }
  }

  Future<void> reloadTexts() async {
    await _loadStrings();
    unawaited(_loadMeta());
  }

  /// Подстановка {имя} в текст интерфейса. Нет ключа — показываем сам ключ, а не пустоту.
  String t(String key, [Map<String, Object>? params]) {
    var s = strings[key] ?? key;
    if (params != null) {
      params.forEach((k, v) {
        s = s.replaceAll('{$k}', v.toString());
      });
    }
    return s;
  }

  /// Для ключей, составленных из данных: tk('topic', 'housing') → topic.housing.
  String tk(String group, String id, [Map<String, Object>? params]) => t('$group.$id', params);

  /// Дата в виде ДД.ММ.ГГГГ — одинаково читается на всех пяти языках.
  String fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final d = DateTime.tryParse(iso.length == 10 ? '${iso}T12:00:00' : iso);
    if (d == null) return iso.length >= 10 ? iso.substring(0, 10) : iso;
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year}';
  }

  Future<void> setLang(String code) async {
    if (!kLangs.any((l) => l.code == code)) return;
    lang = code;
    langChosen = true;
    await prefs.setString('lang', code);
    notifyListeners();
    await reloadTexts();
  }

  /// Первый запуск: вернуться с экрана города к выбору языка (кнопка «Назад» и системный жест).
  /// Сохранённый выбор стирается, чтобы после перезапуска приложение тоже начиналось с языка.
  Future<void> backToLanguage() async {
    langChosen = false;
    await prefs.remove('lang');
    notifyListeners();
  }

  // ---------------------------------------------------------------- город

  /// Запоминаются только id, название и регион подтверждённого города — не координаты.
  void setCity(City? c) {
    city = c;
    cityAsked = true;
    if (c == null) {
      prefs.remove('city');
    } else {
      _write('city', c.toSaved());
    }
    prefs.setBool('cityAsked', true);
    // Район принадлежит городу, поэтому при смене города он сбрасывается.
    district = null;
    prefs.remove('district');
    notifyListeners();
  }

  void skipCity() {
    cityAsked = true;
    prefs.setBool('cityAsked', true);
    notifyListeners();
  }

  void setDistrict(String? id) {
    district = id;
    if (id == null) {
      prefs.remove('district');
    } else {
      prefs.setString('district', id);
    }
    notifyListeners();
  }

  /// Определение города по положению: координаты уходят на сервер один раз и тут же забываются.
  /// Возвращает сообщение-ключ (если пришлось перейти к ручному выбору) или кандидата.
  Future<CityDetection> detectCity() async {
    final pos = await location.current();
    if (pos.status == LocationStatus.denied) return const CityDetection(messageKey: 'city.denied');
    if (pos.status != LocationStatus.ok || pos.lat == null || pos.lon == null) {
      return const CityDetection(messageKey: 'city.unavailable');
    }
    try {
      final j = await api.post('/cities/locate', {'lat': pos.lat, 'lon': pos.lon});
      final r = LocateResult.fromJson(j);
      if (r.status == 'candidate' && r.city != null) return CityDetection(candidate: r.city);
      return CityDetection(messageKey: r.status == 'outside' ? 'city.outside' : 'city.notFoundNear');
    } catch (_) {
      return const CityDetection(messageKey: 'city.unavailable');
    }
  }

  // ---------------------------------------------------------------- «Мой список»

  void setProfile(Profile p) {
    profile = p;
    _write('profile', p.toJson());
    notifyListeners();
  }

  void toggleMark(String id) {
    marks = {...marks, id: !(marks[id] ?? false)};
    _write('marks', marks);
    notifyListeners();
  }

  // ---------------------------------------------------------------- аккаунт

  Future<void> _verifyUser() async {
    final token = await tokens.read();
    if (token == null || token.isEmpty) {
      if (user != null) {
        user = null;
        prefs.remove('user');
        notifyListeners();
      }
      return;
    }
    try {
      final j = await api.get('/me');
      user = AppUser.fromJson(asMapSafe(j)['user']);
      _write('user', user!.toJson());
      notifyListeners();
    } on ApiError catch (e) {
      if (e.status == 401) {
        await tokens.write(null);
        user = null;
        prefs.remove('user');
        notifyListeners();
      }
      // Нет связи: остаёмся с сохранённым пользователем, сервер всё равно проверит токен.
    }
  }

  Future<void> login(String token, AppUser u) async {
    await tokens.write(token);
    user = u;
    _write('user', u.toJson());
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/logout', <String, dynamic>{});
    } catch (_) {}
    await tokens.write(null);
    user = null;
    prefs.remove('user');
    notifyListeners();
  }

  void markOnline() {
    if (offline) {
      offline = false;
      notifyListeners();
    }
  }

  void markOffline() {
    if (!offline) {
      offline = true;
      notifyListeners();
    }
  }
}

/// Итог попытки определить город: либо кандидат на подтверждение, либо причина перейти к ручному выбору.
class CityDetection {
  const CityDetection({this.candidate, this.messageKey});
  final City? candidate;
  final String? messageKey;
}
