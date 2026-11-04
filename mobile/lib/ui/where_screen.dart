import 'package:flutter/material.dart';

import '../api/models.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import '../state/location_provider.dart';
import 'home_shell.dart';
import 'widgets.dart';

/// Раздел «Где оформить»: все учреждения выбранного города с фильтрами по услуге и формату,
/// либо (при включённом тумблере «Рядом со мной») ближайшие физические учреждения по
/// текущей геопозиции, независимо от выбранного города.
class WhereTab extends StatefulWidget {
  const WhereTab({super.key});

  @override
  State<WhereTab> createState() => _WhereTabState();
}

class _WhereTabState extends State<WhereTab> {
  String _service = '';
  String _mode = '';
  bool _nearMe = false;
  bool _locating = false;
  LocationOutcome? _loc;

  Future<void> _toggleNearMe(bool value) async {
    if (!value) {
      setState(() {
        _nearMe = false;
        _loc = null;
      });
      return;
    }
    setState(() {
      _nearMe = true;
      _locating = true;
      _loc = null;
    });
    // Координаты уходят только в этот запрос и не сохраняются — тот же принцип, что у
    // определения города (см. LocationProvider).
    final loc = await context.app.location.current();
    if (!mounted) return;
    setState(() {
      _loc = loc;
      _locating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final city = app.city;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: ToggleChip(
              key: const ValueKey('near-me-toggle'),
              icon: Icons.my_location,
              label: app.t('where.nearMe'),
              selected: _nearMe,
              onChanged: _toggleNearMe,
            ),
          ),
        ),
        if (_nearMe) ..._nearMeSection(app) else ..._byCitySection(app, city),
      ],
    );
  }

  List<Widget> _byCitySection(AppState app, City? city) {
    if (city == null) {
      return [
        Notice(
          key: const ValueKey('need-city'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(app.t('where.noCity')),
            const SizedBox(height: 8),
            FilledButton(onPressed: () => openCityPicker(context), child: Text(app.t('city.manual'))),
          ]),
        ),
      ];
    }
    return [
      Async<Places>(
        cacheKey: '${app.lang}|${city.id}|${app.district ?? ''}|$_service|$_mode|${app.profile.citizenship ?? ''}',
        load: () async => Places.fromJson(await app.api.get('/institutions', cache: true, query: {
              'lang': app.lang,
              'city': city.id,
              'district': app.district,
              'service': _service,
              'mode': _mode,
              'citizenship': app.profile.citizenship,
            })),
        builder: (context, d, reload) {
          ServiceRef? selected;
          for (final s in d.services) {
            if (s.id == _service) selected = s;
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _serviceFilter(app, d.services),
              const SizedBox(height: 12),
              ChipChoice(
                value: _mode,
                onChanged: (v) => setState(() => _mode = v),
                options: [
                  Opt<String>('', app.t('common.all')),
                  Opt<String>('in_person', app.t('mode.in_person')),
                  Opt<String>('online', app.t('mode.online')),
                ],
              ),
              const SizedBox(height: 12),
              if ((d.needsDistrict || app.district != null) && d.districts.isNotEmpty)
                DistrictSelect(districts: d.districts, value: app.district, onChanged: app.setDistrict),
              if (d.institutions.isEmpty && !(d.needsDistrict && app.district == null))
                NoPlaces(cityName: city.name, officialSearch: selected?.officialSearch, sources: const []),
              for (final i in d.institutions) InstitutionCard(key: ValueKey('inst-${i.id}'), inst: i),
            ],
          );
        },
      ),
    ];
  }

  List<Widget> _nearMeSection(AppState app) {
    if (_locating) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(app.t('where.locating')),
            ]),
          ),
        ),
      ];
    }
    final loc = _loc;
    final deniedOrUnavailable = loc != null && loc.status != LocationStatus.ok;
    final widgets = <Widget>[];
    if (deniedOrUnavailable) {
      widgets.add(Notice(
        key: const ValueKey('near-me-denied'),
        child: Text(app.t(loc.status == LocationStatus.denied ? 'where.nearMeDenied' : 'where.nearMeUnavailable')),
      ));
      // Без геопозиции тумблер бесполезен — честно откатываемся на обычный список по городу,
      // а не оставляем пользователя с пустым экраном.
      widgets.addAll(_byCitySection(app, app.city));
      return widgets;
    }
    if (loc == null || loc.lat == null || loc.lon == null) return widgets;
    // В этом режиме нет загруженного по городу списка услуг для выпадающего списка —
    // показываем все учреждения без фильтра по услуге, а не пустой на вид список.
    widgets.add(
      Async<NearbyInstitutions>(
        cacheKey: 'nearby|${app.lang}|${loc.lat}|${loc.lon}|$_service|${app.profile.citizenship ?? ''}',
        load: () async => NearbyInstitutions.fromJson(await app.api.get('/institutions/nearby', query: {
              'lang': app.lang,
              'lat': loc.lat,
              'lon': loc.lon,
              'service': _service,
              'citizenship': app.profile.citizenship,
            })),
        builder: (context, d, reload) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (d.institutions.isEmpty) EmptyNote(app.t('where.nearMeEmpty')),
            for (final i in d.institutions) InstitutionCard(key: ValueKey('inst-${i.id}'), inst: i),
          ],
        ),
      ),
    );
    return widgets;
  }

  Widget _serviceFilter(AppState app, List<ServiceRef> services) => PickerField<String>(
        key: const ValueKey('service-filter'),
        label: app.t('where.service'),
        value: _service,
        options: [Opt<String>('', app.t('common.all')), for (final s in services) Opt<String>(s.id, s.title)],
        onChanged: (v) => setState(() => _service = v ?? ''),
      );
}
