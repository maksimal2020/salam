import 'package:flutter/material.dart';

import 'state/app_scope.dart';
import 'state/app_state.dart';
import 'ui/city_picker_screen.dart';
import 'ui/home_shell.dart';
import 'ui/language_screen.dart';
import 'ui/theme.dart';

class MigrantGuideApp extends StatelessWidget {
  const MigrantGuideApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    // AppScope стоит выше MaterialApp, поэтому состояние доступно и на всех открытых поверх экранах.
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Salam!',
        debugShowCheckedModeBanner: false,
        // Утверждённый дизайн только светлый. Тёмной темы нет: для неё нужны отдельные палитры четырёх разделов.
        theme: themeFor(Section.docs),
        themeMode: ThemeMode.light,
        home: const RootGate(),
      ),
    );
  }
}

/// Порядок первого запуска: язык → город (можно отложить) → основной экран.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.langChosen) return const LanguageScreen();
    if (!app.ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!app.cityAsked) return const CityPickerScreen(onboarding: true);
    return const HomeShell();
  }
}
