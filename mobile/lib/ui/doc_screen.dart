import 'package:flutter/material.dart';

import '../api/models.dart';
import '../state/app_scope.dart';
import 'brand.dart';
import 'city_picker_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Карточка документа и кнопка «Где оформить в моём городе».
class DocScreen extends StatelessWidget {
  const DocScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return SectionScaffold(
      section: Section.docs,
      title: app.t('nav.docs'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Async<DocFull>(
              cacheKey: '$id|${app.lang}',
              load: () async => DocFull.fromJson(await app.api.get('/documents/$id', query: {'lang': app.lang}, cache: true)),
              builder: (context, d, reload) => _Body(doc: d),
            ),
          ],
        ),
      ),
      bottom: DecoratedBox(
        decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x141B1B2B), offset: Offset(0, -8), blurRadius: 24)]),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            child: FilledButton.icon(
              key: const ValueKey('where-button'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DocWhereScreen(id: id))),
              icon: const Icon(Icons.place_outlined),
              label: Text(app.t('docs.whereButton')),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.doc});
  final DocFull doc;

  Widget _h(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final d = doc;
    final b = d.brief;
    final unconfirmed = Text(app.t('docs.notConfirmed'), style: const TextStyle(fontStyle: FontStyle.italic));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(b.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Badges([Necessity(b.necessity), Stamp(status: b.status)]),
        if (b.status == 'demo') Notice(demo: true, child: Text(app.t('docs.demoWarning'), key: const ValueKey('demo-warning'))),
        if (d.detailsFallback) Notice(child: Text(app.t('docs.fallbackNote'))),
        _h(context, app.t('docs.purpose')),
        Text(b.summary),
        if (d.details.who != null) ...[_h(context, app.t('docs.who')), Text(d.details.who!)],
        if (d.details.prepare.isNotEmpty) ...[
          _h(context, app.t('docs.prepare')),
          for (final x in d.details.prepare)
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  '), Expanded(child: Text(x))])),
        ],
        if (d.details.how.isNotEmpty) ...[
          _h(context, app.t('docs.how')),
          for (var i = 0; i < d.details.how.length; i++)
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${i + 1}.  '), Expanded(child: Text(d.details.how[i]))])),
        ],
        if (d.details.renewal != null) ...[_h(context, app.t('docs.renewal')), Text(d.details.renewal!)],
        _h(context, app.t('docs.deadline')),
        d.deadline != null ? Text(d.deadline![app.lang] ?? d.deadline!['ru'] ?? '') : unconfirmed,
        _h(context, app.t('docs.cost')),
        d.cost != null ? Text(d.cost![app.lang] ?? d.cost!['ru'] ?? '') : unconfirmed,
        _h(context, app.t('docs.sources')),
        SourceList(sources: d.sources, checkedAt: b.checkedAt),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// «Где оформить в моём городе»: подтверждённые учреждения с адресом, территорией обслуживания и ссылкой на карту.
class DocWhereScreen extends StatelessWidget {
  const DocWhereScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final city = app.city;
    return SectionScaffold(
      section: Section.where,
      title: app.t('where.title'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: CityButton(onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CityPickerScreen()))),
            ),
            const SizedBox(height: 8),
            if (city == null)
              Notice(
                key: const ValueKey('need-city'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(app.t('city.needed')),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CityPickerScreen())),
                    child: Text(app.t('city.manual')),
                  ),
                ]),
              )
            else
              Async<Places>(
                cacheKey: '$id|${app.lang}|${city.id}|${app.district ?? ''}|${app.profile.citizenship ?? ''}',
                load: () async => Places.fromJson(await app.api.get('/documents/$id/places', cache: true, query: {
                      'lang': app.lang,
                      'city': city.id,
                      'district': app.district,
                      'citizenship': app.profile.citizenship,
                    })),
                builder: (context, d, reload) => _WhereBody(places: d, cityName: city.name),
              ),
          ],
        ),
      ),
    );
  }
}

class _WhereBody extends StatelessWidget {
  const _WhereBody({required this.places, required this.cityName});
  final Places places;
  final String cityName;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final d = places;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (d.document != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(app.t('where.forDocument', {'doc': d.document!.title}), key: const ValueKey('where-doc'))),
        if (d.whereKind != 'institutions')
          Notice(
            key: const ValueKey('no-institution'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(app.t('where.noInstitution')),
              if (d.whereNote != null) Text(d.whereNote!, style: Theme.of(context).textTheme.bodySmall),
            ]),
          )
        else ...[
          if ((d.needsDistrict || app.district != null) && d.districts.isNotEmpty)
            DistrictSelect(districts: d.districts, value: app.district, onChanged: app.setDistrict),
          if (d.institutions.isEmpty && !(d.needsDistrict && app.district == null))
            NoPlaces(cityName: cityName, officialSearch: d.officialSearch, sources: d.sources),
          if (d.institutions.isEmpty && d.needsDistrict && app.district == null) EmptyNote(app.t('where.none', {'city': cityName})),
          for (final i in d.institutions) InstitutionCard(key: ValueKey('inst-${i.id}'), inst: i),
        ],
      ],
    );
  }
}
