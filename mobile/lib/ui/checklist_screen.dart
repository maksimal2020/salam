import 'package:flutter/material.dart';

import '../api/models.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import 'brand.dart';
import 'city_picker_screen.dart';
import 'doc_screen.dart';
import 'docs_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// «Мой список»: несколько вопросов — и шаги именно для этой ситуации, с отметками о выполнении.
/// Работает без регистрации; ответы и отметки хранятся на телефоне.
class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key});

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  late Profile _draft;
  late bool _editing;

  @override
  void initState() {
    super.initState();
    // Ответы читаются один раз; контекст в initState недоступен для InheritedWidget, поэтому позже, в didChangeDependencies.
    _draft = const Profile();
    _editing = true;
  }

  bool _inited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_inited) {
      _inited = true;
      final p = context.app.profile;
      _draft = p;
      _editing = !p.complete;
    }
  }

  void _submit() {
    final app = context.app;
    app.setProfile(_draft);
    setState(() => _editing = !_draft.complete);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return SectionScaffold(
      section: Section.docs,
      title: app.t('list.title'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: _editing ? _form(app) : _result(app),
        ),
      ),
    );
  }

  List<Widget> _form(AppState app) {
    final meta = app.meta;
    return [
      Text(app.t('list.intro')),
      const SizedBox(height: 16),
      PickerField<String>(
        key: const ValueKey('citizenship-select'),
        label: app.t('list.citizenship'),
        value: _draft.citizenship,
        options: [
          Opt<String>(null, app.t('list.chooseCitizenship')),
          for (final c in meta?.citizenships ?? const <Citizenship>[]) Opt<String>(c.id, c.name),
        ],
        onChanged: (v) => setState(() => _draft = Profile(citizenship: v, purpose: _draft.purpose, stage: _draft.stage, flags: _draft.flags)),
      ),
      const SizedBox(height: 16),
      Text(app.t('list.purpose'), style: Theme.of(context).textTheme.titleSmall),
      for (final p in meta?.purposes ?? const <String>[])
        _Choice(
          key: ValueKey('purpose-$p'),
          selected: _draft.purpose == p,
          label: app.t('purpose.$p'),
          onTap: () => setState(() => _draft = Profile(citizenship: _draft.citizenship, purpose: p, stage: _draft.stage, flags: _draft.flags)),
        ),
      const SizedBox(height: 12),
      Text(app.t('list.stage'), style: Theme.of(context).textTheme.titleSmall),
      for (final s in meta?.stages ?? const <String>[])
        _Choice(
          key: ValueKey('stage-$s'),
          selected: _draft.stage == s,
          label: app.t(s == 'before' ? 'list.stage.before' : 'list.stage.in_russia'),
          onTap: () => setState(() => _draft = Profile(citizenship: _draft.citizenship, purpose: _draft.purpose, stage: s, flags: _draft.flags)),
        ),
      const SizedBox(height: 12),
      Text(app.t('list.city'), style: Theme.of(context).textTheme.titleSmall),
      Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          avatar: const Icon(Icons.place_outlined, size: 18),
          label: Text(app.city?.label ?? app.t('list.noCityYet'), overflow: TextOverflow.ellipsis),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CityPickerScreen())),
        ),
      ),
      const SizedBox(height: 12),
      Text(app.t('list.status'), style: Theme.of(context).textTheme.titleSmall),
      for (final f in meta?.flags ?? const <String>[])
        CheckboxListTile(
          key: ValueKey('flag-$f'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _draft.flags[f] ?? false,
          title: Text(app.t('flag.$f')),
          onChanged: (v) => setState(() => _draft = Profile(
                citizenship: _draft.citizenship,
                purpose: _draft.purpose,
                stage: _draft.stage,
                flags: {..._draft.flags, f: v ?? false},
              )),
        ),
      const SizedBox(height: 16),
      FilledButton(key: const ValueKey('list-build'), onPressed: _submit, child: Text(app.t('list.build'))),
    ];
  }

  List<Widget> _result(AppState app) {
    final profile = app.profile;
    return [
      Row(children: [
        OutlinedButton(
          key: const ValueKey('list-edit'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: () => setState(() => _editing = true),
          child: Text(app.t('list.edit')),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () {
            app.setProfile(const Profile());
            setState(() {
              _draft = const Profile();
              _editing = true;
            });
          },
          child: Text(app.t('list.reset')),
        ),
      ]),
      const SizedBox(height: 8),
      Async<ChecklistResult>(
        cacheKey: '${app.lang}|${profile.citizenship}|${profile.purpose}|${profile.stage}|${profile.flags}',
        load: () async => ChecklistResult.fromJson(await app.api.post('/checklist', profile.toRequest(app.lang), cache: true)),
        builder: (context, r, reload) {
          final done = r.items.where((i) => app.marks[i.id] == true).length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (r.includesDemo) Notice(demo: true, child: Text(app.t('list.demoBanner'))),
              if (r.items.isNotEmpty) _RingCard(done: done, total: r.items.length),
              if (r.items.isEmpty && r.clarify.isEmpty) EmptyNote(app.t('list.empty')),
              for (final i in r.items) _Step(item: i),
              if (r.clarify.isNotEmpty) _Clarify(result: r),
            ],
          );
        },
      ),
    ];
  }
}

/// Кольцо выполнения над списком шагов. Подпись «Выполнено N из M» остаётся текстом: по ней читают и тестируют.
class _RingCard extends StatelessWidget {
  const _RingCard({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final percent = total == 0 ? 0 : (done * 100 / total).round();
    return AppCard(
      child: Row(
        children: [
          ExcludeSemantics(
            child: ProgressRing(
              value: total == 0 ? 0 : done / total,
              color: context.tone.accent,
              track: const Color(0xFFE9E6F4),
              child: Text('$percent%', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Palette.ink)),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              app.t('list.progress', {'done': done, 'total': total}),
              key: const ValueKey('progress'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.selected, required this.label, required this.onTap});
  final bool selected;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        minVerticalPadding: 10,
        leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: selected ? context.tone.accent : Palette.control),
        title: Text(label, style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
        onTap: onTap,
      );
}

class _Step extends StatelessWidget {
  const _Step({required this.item});
  final DocBrief item;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final done = app.marks[item.id] == true;
    return AppCard(
      key: ValueKey('step-${item.id}'),
      outlined: done,
      dashed: item.status != 'verified',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            key: ValueKey('mark-${item.id}'),
            value: done,
            onChanged: (_) => app.toggleMark(item.id),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DocScreen(id: item.id))),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(item.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(decoration: done ? TextDecoration.lineThrough : null)),
                  ),
                ),
                const SizedBox(height: 6),
                Badges([Necessity(item.necessity), Stamp(status: item.status)]),
                const SizedBox(height: 6),
                Text(item.summary, style: Theme.of(context).textTheme.bodySmall),
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DocWhereScreen(id: item.id))),
                  child: Text(app.t('list.showWhere')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Clarify extends StatelessWidget {
  const _Clarify({required this.result});
  final ChecklistResult result;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    String label(ClarifyItem c) {
      if (c.type == 'missing') {
        return app.t(c.field == 'citizenship' ? 'list.citizenship' : c.field == 'purpose' ? 'list.purpose' : 'list.stage');
      }
      if (c.type == 'other_country') return app.t('list.otherCountry');
      return c.title ?? c.docId ?? '';
    }

    return Notice(
      key: const ValueKey('clarify'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(app.t('list.clarify'), style: Theme.of(context).textTheme.titleMedium),
          Text(app.t('list.clarifyHint'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final c in result.clarify) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• ${label(c)}')),
          const SizedBox(height: 8),
          LinkList(result.whereToCheck),
        ],
      ),
    );
  }
}
