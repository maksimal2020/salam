import 'package:flutter/material.dart';

import '../api/models.dart';
import '../state/app_scope.dart';
import '../util/links.dart';
import 'brand.dart';
import 'checklist_screen.dart';
import 'doc_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Раздел «Документы»: каталог и вход в «Мой список».
class DocsTab extends StatefulWidget {
  const DocsTab({super.key});

  @override
  State<DocsTab> createState() => _DocsTabState();
}

class _DocsTabState extends State<DocsTab> {
  String _q = '';
  String _situation = '';
  final _debounce = Debouncer(250);

  @override
  void dispose() {
    _debounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final done = app.marks.values.where((v) => v).length;
    final situations = app.meta?.situations ?? const <IdName>[];
    final total = app.marks.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        _MyListCard(
          done: done,
          total: total,
          title: app.t('docs.myList'),
          subtitle: done > 0 ? app.t('list.progress', {'done': done, 'total': total}) : app.t('docs.myListHint'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ChecklistScreen())),
        ),
        SearchField(
          hint: app.t('docs.search'),
          onChanged: (v) => _debounce.run(() {
            if (mounted) setState(() => _q = v);
          }),
        ),
        const SizedBox(height: 12),
        ChipChoice(
          value: _situation,
          onChanged: (v) => setState(() => _situation = v),
          options: [Opt<String>('', app.t('common.all')), for (final s in situations) Opt<String>(s.id, s.name)],
        ),
        const SizedBox(height: 16),
        Async<List<DocBrief>>(
          cacheKey: '${app.lang}|$_q|$_situation',
          load: () async {
            final j = await app.api.get('/documents', query: {'lang': app.lang, 'q': _q, 'situation': _situation}, cache: true);
            return ((j as Map)['documents'] as List).map(DocBrief.fromJson).toList();
          },
          builder: (context, docs, reload) {
            if (docs.isEmpty) return EmptyNote(app.t('common.empty'));
            return Column(
              children: [
                for (final d in docs)
                  AppCard(
                    key: ValueKey('doc-${d.id}'),
                    dashed: d.status != 'verified',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DocScreen(id: d.id))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const IconTile(Icons.description_outlined),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SourceLabel(app.t('badge.official'), Icons.shield_outlined),
                                  Text(d.title, style: Theme.of(context).textTheme.titleMedium),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Badges([Necessity(d.necessity), Stamp(status: d.status)]),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(child: Text(d.summary)),
                            const SizedBox(width: 12),
                            const ArrowDot(),
                          ],
                        ),
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

/// Синяя карточка «Мой список» с кольцом выполнения. Кольцо считает отметки, сохранённые на телефоне.
class _MyListCard extends StatelessWidget {
  const _MyListCard({required this.done, required this.total, required this.title, required this.subtitle, required this.onTap});
  final int done;
  final int total;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(30);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(color: Palette.blue, borderRadius: radius, boxShadow: const [BoxShadow(color: Palette.blueDark, offset: Offset(0, 6))]),
        child: ClipRRect(
          borderRadius: radius,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const ValueKey('my-list-link'),
              onTap: onTap,
              child: Stack(
                children: [
                  const Positioned(right: -40, bottom: -60, width: 170, height: 170, child: ExcludeSemantics(child: DecoratedBox(decoration: BoxDecoration(color: Palette.violet, shape: BoxShape.circle)))),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: const TextStyle(fontSize: 22, height: 27 / 22, fontWeight: FontWeight.w800, color: Colors.white)),
                              const SizedBox(height: 3),
                              Text(subtitle, style: const TextStyle(fontSize: 15, height: 21 / 15, color: Color(0xFFEEF0FF))),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        ExcludeSemantics(
                          child: ProgressRing(
                            value: total == 0 ? 0 : done / total,
                            color: Palette.yellow,
                            track: const Color(0x45FFFFFF),
                            child: total == 0
                                ? const Icon(Icons.arrow_forward, color: Colors.white, size: 28)
                                : Text('$done/$total', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Список ссылок «где проверить» (используется и в карточке документа, и в списке).
class LinkList extends StatelessWidget {
  const LinkList(this.links, {super.key});
  final List<SourceLink> links;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final s in links) LinkText(s.title, () => openExternal(s.url))],
      );
}
