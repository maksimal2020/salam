import 'package:flutter/material.dart';

import '../api/models.dart';
import '../state/app_scope.dart';
import 'home_shell.dart';
import 'widgets.dart';

/// Раздел «Где оформить»: все учреждения выбранного города с фильтрами по услуге и формату.
class WhereTab extends StatefulWidget {
  const WhereTab({super.key});

  @override
  State<WhereTab> createState() => _WhereTabState();
}

class _WhereTabState extends State<WhereTab> {
  String _service = '';
  String _mode = '';

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final city = app.city;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        if (city == null)
          Notice(
            key: const ValueKey('need-city'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(app.t('where.noCity')),
              const SizedBox(height: 8),
              FilledButton(onPressed: () => openCityPicker(context), child: Text(app.t('city.manual'))),
            ]),
          )
        else
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
                  PickerField<String>(
                    key: const ValueKey('service-filter'),
                    label: app.t('where.service'),
                    value: _service,
                    options: [Opt<String>('', app.t('common.all')), for (final s in d.services) Opt<String>(s.id, s.title)],
                    onChanged: (v) => setState(() => _service = v ?? ''),
                  ),
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
      ],
    );
  }
}
