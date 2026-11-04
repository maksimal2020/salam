import 'package:flutter/widgets.dart';

import 'app_state.dart';

/// Делает состояние доступным любому экрану: context.app, context.t('ключ').
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope не найден в дереве виджетов');
    return scope!.notifier!;
  }
}

extension AppContext on BuildContext {
  AppState get app => AppScope.of(this);
  String t(String key, [Map<String, Object>? params]) => app.t(key, params);
  String tk(String group, String id, [Map<String, Object>? params]) => app.tk(group, id, params);
}
