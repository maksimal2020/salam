// Сценарии из задания: выбор языка, ручной выбор города, отказ в геолокации, смена города, нет подтверждённых адресов.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migrant_guide/api/models.dart';
import 'package:migrant_guide/app.dart';
import 'package:migrant_guide/state/app_state.dart';
import 'package:migrant_guide/state/location_provider.dart';

import 'support.dart';

Future<void> start(WidgetTester tester, AppState state) async {
  // Размер обычного телефона (360×780 dp): на стандартном окне 800×600 цветная шапка и нижнее меню оставляют списку слишком мало места.
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MigrantGuideApp(state: state));
  await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));
}

Future<void> stop(WidgetTester tester) async {
  // Убираем дерево, чтобы не осталось таймеров поиска.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> typeCity(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('city-search')), text);
  await tester.pump(const Duration(milliseconds: 400)); // ждём задержку поиска
  await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));
}

/// Первый запуск до главного экрана: язык, затем ручной выбор города.
Future<void> onboardManual(WidgetTester tester, AppState state, String query, String cityKey) async {
  await start(tester, state);
  await tester.tap(find.byKey(const ValueKey('lang-ru')));
  await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));
  await tester.tap(find.byKey(const ValueKey('city-manual')));
  await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));
  await typeCity(tester, query);
  await tester.tap(find.byKey(ValueKey(cityKey)));
  await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));
}

Future<void> openWhere(WidgetTester tester) async {
  final doc = find.byKey(const ValueKey('doc-passport_valid'));
  await tester.ensureVisible(doc);
  await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));
  await tester.tap(doc);
  await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));
  await tester.tap(find.byKey(const ValueKey('where-button')));
  await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));
}

void main() {
  testWidgets('первый экран показывает языки на самих языках', (tester) async {
    final state = await makeState();
    await start(tester, state);
    for (final name in ['Русский', 'Тоҷикӣ', 'Oʻzbekcha', 'Кыргызча', 'Қазақша']) {
      expect(find.text(name), findsOneWidget);
    }
    await stop(tester);
  });

  testWidgets('после выбора языка предлагают определить город или выбрать вручную', (tester) async {
    final state = await makeState();
    await start(tester, state);
    await tester.tap(find.byKey(const ValueKey('lang-ru')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));
    expect(find.byKey(const ValueKey('city-detect')), findsOneWidget);
    expect(find.byKey(const ValueKey('city-manual')), findsOneWidget);
    expect(find.byKey(const ValueKey('city-skip')), findsOneWidget);
    await stop(tester);
  });

  testWidgets('отказ в геолокации ведёт к ручному выбору с пояснением', (tester) async {
    final loc = FakeLocation(const LocationOutcome(LocationStatus.denied));
    final state = await makeState(location: loc);
    await start(tester, state);
    await tester.tap(find.byKey(const ValueKey('lang-ru')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));
    await tester.tap(find.byKey(const ValueKey('city-detect')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));
    expect(loc.calls, 1);
    expect(find.text(state.t('city.denied')), findsOneWidget);
    expect(find.byKey(const ValueKey('city-search')), findsOneWidget);
    expect(state.city, isNull);
    await stop(tester);
  });

  testWidgets('найденный город нужно подтвердить; координаты не сохраняются', (tester) async {
    final loc = FakeLocation(const LocationOutcome(LocationStatus.ok, lat: 55.7512, lon: 37.6184));
    final state = await makeState(location: loc);
    await start(tester, state);
    await tester.tap(find.byKey(const ValueKey('lang-ru')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));
    await tester.tap(find.byKey(const ValueKey('city-detect')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));
    expect(find.text(state.t('city.found', {'city': 'Москва, г. Москва'})), findsOneWidget);
    expect(state.city, isNull, reason: 'до подтверждения город не сохраняется');
    await tester.tap(find.byKey(const ValueKey('city-confirm')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));
    expect(state.city?.id, 'moscow');
    expect(find.text('Москва, г. Москва'), findsWidgets);
    final stored = state.prefs.getKeys().map((k) => '${state.prefs.get(k)}').join('\n');
    expect(stored, isNot(contains('55.75')));
    await stop(tester);
  });

  testWidgets('ручной выбор города и показ его в шапке', (tester) async {
    final state = await makeState();
    await onboardManual(tester, state, 'каз', 'city-kazan');
    expect(state.city?.id, 'kazan');
    expect(find.byKey(const ValueKey('city-chip')), findsOneWidget);
    expect(find.text('Казань, Республика Татарстан'), findsWidgets);
    await stop(tester);
  });

  testWidgets('нет подтверждённых адресов: честное сообщение, без выдумок', (tester) async {
    final state = await makeState();
    await onboardManual(tester, state, 'каз', 'city-kazan');
    await openWhere(tester);
    expect(find.text(state.t('where.none', {'city': 'Казань'})), findsOneWidget);
    expect(find.text(state.t('where.noOfficialSearch')), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('inst-')), findsNothing,
        reason: 'карточек учреждений быть не должно');
    await stop(tester);
  });

  testWidgets('смена города обновляет адреса; учреждение из другого города поясняется', (tester) async {
    final state = await makeState(prefsInit: {
      'lang': 'ru',
      'cityAsked': true,
      'city': '{"id":"kazan","name":"Казань","region":"Республика Татарстан"}',
    });
    await start(tester, state);
    await openWhere(tester);
    expect(find.text(state.t('where.none', {'city': 'Казань'})), findsOneWidget);

    // Тестовый сервер знает для Химок учреждение, которое находится в Москве.
    state.setCity(const City(id: 'khimki', name: 'Химки', region: 'Московская область'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));
    expect(find.text('Центр в Москве'), findsOneWidget);
    expect(find.textContaining('ул. Тестовая, 1, Москва'), findsWidgets, reason: 'фактический адрес и пояснение про обслуживание Химок');
    await stop(tester);
  });

  testWidgets('для Москвы просят выбрать район, затем показывают подразделение', (tester) async {
    final state = await makeState(prefsInit: {
      'lang': 'ru',
      'cityAsked': true,
      'city': '{"id":"moscow","name":"Москва","region":"г. Москва"}',
    });
    await start(tester, state);
    await openWhere(tester);
    expect(find.text(state.t('city.districtTitle')), findsWidgets);
    expect(find.text('Подразделение ЦАО'), findsNothing);
    state.setDistrict('cao');
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));
    expect(find.text('Подразделение ЦАО'), findsOneWidget);
    await stop(tester);
  });
}
