// Главный экран: логотип ведёт к первому запуску, подписи нижней панели не рвутся посередине слова.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migrant_guide/app.dart';
import 'package:migrant_guide/state/app_state.dart';
import 'package:migrant_guide/ui/home_shell.dart';

import 'support.dart';

Future<void> _settle(WidgetTester tester) =>
    tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));

Future<void> _start(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(1080, 2340); // 360×780 dp
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MigrantGuideApp(state: state));
  await _settle(tester);
}

Future<void> _stop(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 400));
  tester.view.reset();
  tester.platformDispatcher.clearTextScaleFactorTestValue();
}

Future<AppState> _returning([String lang = 'ru']) => makeState(prefsInit: {
      'lang': lang,
      'cityAsked': true,
      'city': '{"id":"moscow","name":"Москва","region":"г. Москва"}',
      'strings:$lang': File('assets/i18n/$lang.json').readAsStringSync(),
    });

void main() {
  testWidgets('логотип ведёт к выбору языка; «Назад» возвращает как было — кнопкой и жестом', (tester) async {
    final state = await _returning();
    await _start(tester, state);
    expect(find.byKey(const ValueKey('tab-docs')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('logo-button')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('lang-ru')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lang-back')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('tab-docs')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('logo-button')));
    await _settle(tester);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byKey(const ValueKey('tab-docs')), findsOneWidget);

    expect(state.city?.id, 'moscow');
    expect(state.lang, 'ru');
    expect(state.restarting, isFalse);
    expect(state.prefs.getString('lang'), 'ru');
    await _stop(tester);
  }, timeout: const Timeout(Duration(seconds: 25)));

  testWidgets('по логотипу: новый язык → экран города → «Выбрать позже» — прежний город остаётся', (tester) async {
    final state = await _returning();
    await _start(tester, state);
    await tester.tap(find.byKey(const ValueKey('logo-button')));
    await _settle(tester);

    // С экрана города «Назад» снова ведёт к языкам, и оттуда всё ещё можно вернуться домой.
    await tester.tap(find.byKey(const ValueKey('lang-tg')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('city-detect')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hero-back')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('lang-back')), findsOneWidget);
    expect(state.prefs.getString('lang'), 'tg', reason: 'при повторном проходе язык не стирается');

    await tester.tap(find.byKey(const ValueKey('lang-tg')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('city-skip')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('tab-docs')), findsOneWidget);
    expect(state.lang, 'tg');
    expect(state.city?.id, 'moscow');
    expect(state.restarting, isFalse);
    await _stop(tester);
  }, timeout: const Timeout(Duration(seconds: 25)));

  group('подписи нижней панели', () {
    setUpAll(() async {
      // С тестовым шрифтом Ahem все буквы одной ширины — проверка была бы бессмысленной.
      final inter = FontLoader('Inter');
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
        inter.addFont(Future.value(ByteData.view(File('assets/fonts/Inter-$w.otf').readAsBytesSync().buffer)));
      }
      await inter.load();
    });

    for (final lang in ['ru', 'tg', 'uz', 'ky', 'kk']) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('$lang, системный шрифт ×$scale, экран 360 dp: слова целиком', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await _start(tester, await _returning(lang));
          for (final tab in ['tab-docs', 'tab-where', 'tab-tips', 'tab-ads']) {
            final paragraphs = tester
                .renderObjectList<RenderParagraph>(find.descendant(of: find.byKey(ValueKey(tab)), matching: find.byType(RichText)))
                .where((p) => RegExp(r'\p{L}', unicode: true).hasMatch(p.text.toPlainText()))
                .toList();
            expect(paragraphs, isNotEmpty, reason: tab);
            for (final p in paragraphs) {
              final text = p.text.toPlainText();
              double? lastDy;
              for (var i = 0; i < text.length; i++) {
                final dy = p.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dy;
                if (lastDy != null && dy > lastDy + 0.5) {
                  expect(' -'.contains(text[i - 1]), isTrue, reason: '$tab: «$text» разорвано перед «${text.substring(i)}»');
                }
                lastDy = dy;
              }
              expect(p.size.width, lessThanOrEqualTo(90), reason: '$tab: «$text» шире колонки');
            }
          }
          await _stop(tester);
        }, timeout: const Timeout(Duration(seconds: 25)));
      }
    }
  });

  test('перенос длинного слова: после гласной, куски не короче трёх букв', () {
    bool fits(String s) => s.length <= 11;
    expect(hyphenateNavWord('Хабарландырулар', fits), 'Хабарланды-рулар');
    expect(hyphenateNavWord('Документы', fits), 'Документы');
  });
}
