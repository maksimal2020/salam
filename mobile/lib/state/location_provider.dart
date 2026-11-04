import 'package:geolocator/geolocator.dart';

enum LocationStatus { ok, denied, unavailable }

/// Результат запроса положения. Координаты живут только в этом объекте:
/// они один раз уходят на сервер для подбора города и нигде не сохраняются.
class LocationOutcome {
  const LocationOutcome(this.status, {this.lat, this.lon});
  final LocationStatus status;
  final double? lat;
  final double? lon;
}

abstract class LocationProvider {
  Future<LocationOutcome> current();
}

class GeolocatorLocationProvider implements LocationProvider {
  @override
  Future<LocationOutcome> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationOutcome(LocationStatus.unavailable);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return const LocationOutcome(LocationStatus.denied);
      }
      // Для города достаточно грубого положения.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 12)),
      );
      return LocationOutcome(LocationStatus.ok, lat: pos.latitude, lon: pos.longitude);
    } catch (_) {
      return const LocationOutcome(LocationStatus.unavailable);
    }
  }
}
