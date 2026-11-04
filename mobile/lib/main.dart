import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'api/secure_token_store.dart';
import 'app.dart';
import 'config.dart';
import 'state/app_state.dart';
import 'state/location_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final tokens = SecureTokenStore();
  late final AppState state;
  final api = ApiClient(
    baseUrl: kApiBase,
    tokens: tokens,
    prefs: prefs,
    onServedFromCache: () => state.markOffline(),
    onOnline: () => state.markOnline(),
  );
  state = AppState(prefs: prefs, api: api, tokens: tokens, location: GeolocatorLocationProvider());
  await state.init();
  runApp(MigrantGuideApp(state: state));
}
