import 'package:flutter/material.dart';

import '../api/models.dart';
import '../state/app_scope.dart';
import 'widgets.dart';

const List<String> kTopics = ['housing', 'groceries', 'clothes', 'secondhand', 'transport', 'mobile', 'sim', 'banking', 'jobsearch', 'scams', 'legal'];

/// Раздел «Полезные советы»: редакционные материалы, которые не выдаются за официальную инструкцию.
class TipsTab extends StatefulWidget {
  const TipsTab({super.key});

  @override
  State<TipsTab> createState() => _TipsTabState();
}

class _TipsTabState extends State<TipsTab> {
  String _q = '';
  String _topic = '';
  bool _local = false;
  final _debounce = Debouncer(250);

  @override
  void dispose() {
    _debounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final city = app.city;
    final onlyLocal = _local && city != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        SearchField(
          hint: app.t('tips.search'),
          onChanged: (v) => _debounce.run(() {
            if (mounted) setState(() => _q = v);
          }),
        ),
        CheckboxListTile(
          key: const ValueKey('tips-local'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: onlyLocal,
          title: Text(app.t('tips.thisCity')),
          onChanged: city == null ? null : (v) => setState(() => _local = v ?? false),
        ),
        const SizedBox(height: 4),
        ChipChoice(
          value: _topic,
          onChanged: (v) => setState(() => _topic = v),
          options: [Opt<String>('', app.t('tips.allTopics')), for (final x in kTopics) Opt<String>(x, app.tk('topic', x))],
        ),
        const SizedBox(height: 16),
        Async<List<Tip>>(
          cacheKey: '${app.lang}|${city?.id ?? ''}|$_q|$_topic|$onlyLocal',
          load: () async {
            final j = await app.api.get('/tips', cache: true, query: {
              'lang': app.lang,
              'city': city?.id,
              'q': _q,
              'topic': _topic,
              'local': onlyLocal ? '1' : null,
            });
            return ((j as Map)['tips'] as List).map(Tip.fromJson).toList();
          },
          builder: (context, tips, reload) {
            if (tips.isEmpty) return EmptyNote(app.t('tips.empty'));
            return Column(
              children: [
                for (final tip in tips)
                  AppCard(
                    key: ValueKey('tip-${tip.id}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const IconTile(Icons.lightbulb_outline),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SourceLabel(app.t('badge.editorial'), Icons.edit_note),
                                  Text(tip.title, style: Theme.of(context).textTheme.titleMedium),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Badges([
                          Tag(app.tk('topic', tip.topic)),
                          Tag(tip.city != null ? app.t('tips.cityOnly', {'city': tip.city!.label}) : app.t('tips.general')),
                        ]),
                        const SizedBox(height: 10),
                        Text(tip.body),
                        const SizedBox(height: 10),
                        Text(app.t('common.updated', {'date': app.fmtDate(tip.updatedAt)}), style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
