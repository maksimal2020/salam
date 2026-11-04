/// Адрес сервера. Задаётся при сборке:
///   flutter run --dart-define=API_BASE_URL=https://example.org
/// По умолчанию — адрес компьютера разработчика из эмулятора Android.
/// (В симуляторе iOS используйте http://localhost:3000.)
const String kApiBase = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:3000');
