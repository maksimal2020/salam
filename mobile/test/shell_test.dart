// Главный экран: логотип ведёт к первому запуску, подписи нижней панели не рвутся посередине слова.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migrant_guide/app.dart';
import 'package:migrant_guide/state/app_state.dart';
import 'package:migrant_guide/ui/app_nav.dart';
import 'package:migrant_guide/ui/docs_screen.dart';

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

  testWidgets('нижняя панель: значки на одной линии, подписи по центру под ними и выровнены по верху', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    await _start(tester, await _returning());
    const tabs = ['tab-docs', 'tab-where', 'tab-tips', 'tab-ads'];
    final icons = [for (final t in tabs) tester.getCenter(find.descendant(of: find.byKey(ValueKey(t)), matching: find.byType(Icon)))];
    final labels = [for (final t in tabs) find.descendant(of: find.byKey(ValueKey(t)), matching: find.byType(Text))];
    for (var i = 0; i < tabs.length; i++) {
      expect(icons[i].dy, moreOrLessEquals(icons[0].dy, epsilon: 0.5), reason: '${tabs[i]}: значок не на одной линии');
      expect(tester.getTopLeft(labels[i]).dy, moreOrLessEquals(tester.getTopLeft(labels[0]).dy, epsilon: 0.5), reason: '${tabs[i]}: подпись не по верху');
      // Каждая строка подписи центрирована под значком.
      final p = tester.renderObject<RenderParagraph>(find.descendant(of: labels[i], matching: find.byType(RichText)));
      final text = p.text.toPlainText();
      final boxes = p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: text.length));
      final origin = p.localToGlobal(Offset.zero);
      final lines = <double, List<double>>{};
      for (final b in boxes) {
        (lines[b.top.roundToDouble()] ??= [double.infinity, double.negativeInfinity])
          ..[0] = b.left < lines[b.top.roundToDouble()]![0] ? b.left : lines[b.top.roundToDouble()]![0]
          ..[1] = b.right > lines[b.top.roundToDouble()]![1] ? b.right : lines[b.top.roundToDouble()]![1];
      }
      for (final l in lines.values) {
        expect(origin.dx + (l[0] + l[1]) / 2, moreOrLessEquals(icons[i].dx, epsilon: 2), reason: '${tabs[i]}: «$text» не по центру');
      }
    }
    expect(find.byType(AppBottomNav), findsOneWidget);
    expect(find.byType(AppNavRail), findsNothing);
    await _stop(tester);
  }, timeout: const Timeout(Duration(seconds: 25)));

  for (final c in [('планшет', const Size(2048, 1536), 2.0), ('телефон в альбомной ориентации', const Size(2340, 1080), 3.0)]) {
    testWidgets('${c.$1}: боковая колонка вместо нижней панели, содержимое не шире 720', (tester) async {
      tester.view.physicalSize = c.$2;
      tester.view.devicePixelRatio = c.$3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MigrantGuideApp(state: await _returning()));
      await _settle(tester);
      expect(find.byType(AppNavRail), findsOneWidget);
      expect(find.byType(AppBottomNav), findsNothing);
      expect(tester.getSize(find.byType(DocsTab)).width, lessThanOrEqualTo(720));
      // Разделы переключаются и из колонки.
      await tester.tap(find.byKey(const ValueKey('tab-tips')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('tab-tips')), findsOneWidget);
      await _stop(tester);
    }, timeout: const Timeout(Duration(seconds: 25)));
  }

  test('перенос длинного слова: после гласной, куски не короче трёх букв', () {
    bool fits(String s) => s.length <= 11;
    expect(hyphenateNavWord('Хабарландырулар', fits), 'Хабарланды-рулар');
    expect(hyphenateNavWord('Документы', fits), 'Документы');
  });
}
