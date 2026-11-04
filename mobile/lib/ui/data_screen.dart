import 'package:flutter/material.dart';

import '../state/app_scope.dart';
import '../util/json_util.dart';
import 'brand.dart';
import 'theme.dart';
import 'widgets.dart';

/// «О данных»: какие случаи и города уже подтверждены, а какие ещё нужно заполнить.
class DataScreen extends StatelessWidget {
  const DataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    String stateLabel(String s) => s == 'verified'
        ? app.t('data.verified')
        : s == 'partial'
            ? app.t('data.partial')
            : s == 'demo'
                ? app.t('data.demo')
                : app.t('data.missing');
    return SectionScaffold(
      section: Section.docs,
      title: app.t('data.title'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Text(app.t('data.intro')),
            const SizedBox(height: 12),
            Async<Map<String, dynamic>>(
              cacheKey: 'coverage|${app.lang}',
              load: () async {
                final c = asMap(await app.api.get('/coverage', cache: true));
                // Названия документов — на языке интерфейса.
                final list = asMap(await app.api.get('/documents', query: {'lang': app.lang}, cache: true));
                final titles = <String, String>{};
                for (final d in asList(list['documents']).map(asMap)) {
                  titles[strOr(d['id'])] = strOr(d['title']);
                }
                return {...c, '_titles': titles};
              },
              builder: (context, c, reload) {
                final titles = c['_titles'] as Map<String, String>;
                final scenarios = asList(c['scenarios']).map(asMap).toList();
                final cities = asList(c['cities']).map(asMap).toList();
                final docs = asList(c['documents']).map(asMap).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.t('data.scenarios'), style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final s in scenarios)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          dense: true,
                          title: Text('${app.tk('group', strOr(s['group']))} · ${app.tk('purpose', strOr(s['purpose']))}${s['lostDocument'] == true ? ' · ${app.tk('flag', 'lost_document')}' : ''}'),
                          subtitle: Text('${app.t(strOr(s['stage']) == 'before' ? 'list.stage.before' : 'list.stage.in_russia')} · ${asInt(s['verified'])}/${asInt(s['total'])}'),
                          trailing: Tag(stateLabel(strOr(s['state']))),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(app.t('data.cities'), style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: [
                          DataColumn(label: Text(app.t('nav.docs'))),
                          for (final x in cities) DataColumn(label: Text(strOr(x['name']))),
                        ],
                        rows: [
                          for (final d in docs)
                            DataRow(cells: [
                              DataCell(Text(titles[strOr(d['id'])] ?? strOr(d['id']))),
                              for (final x in cities)
                                DataCell(Text(strOr(d['whereKind']) != 'institutions'
                                    ? 'n/a'
                                    : switch (strOr(asMap(d['cells'])[strOr(x['id'])])) {
                                        'verified' => app.t('data.verified'),
                                        'demo' => app.t('data.demo'),
                                        'district' => app.t('city.districtTitle'),
                                        _ => '—',
                                      })),
                            ]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('${app.t('data.missing')}: ${asInt(c['otherCities'])}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
