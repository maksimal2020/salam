import 'package:flutter/material.dart';

import '../api/models.dart';
import '../state/app_scope.dart';
import 'account_screens.dart';
import 'ad_form_screen.dart';
import 'ad_screen.dart';
import 'widgets.dart';

const List<String> kCategories = ['work', 'housing', 'market', 'services', 'free'];

/// Карточка объявления: язык оригинала показан меткой, текст не переводится.
class ListingCard extends StatelessWidget {
  const ListingCard({super.key, required this.listing, this.onTap});
  final Listing listing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l = listing;
    final meta = <String>[
      l.city.label,
      if (l.price != null && l.price!.isNotEmpty) l.price!,
      if (l.extra['pay'] != null) l.extra['pay']!,
    ].join(' · ');
    return AppCard(
      key: ValueKey('listing-${l.id}'),
      onTap: onTap ?? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdScreen(id: l.id))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconTile(Icons.campaign_outlined),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SourceLabel(app.t('badge.user'), Icons.person_outline),
                    Text(l.title, style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Badges([
            Tag(app.tk('ads.cat', l.category)),
            Tag(langNative(l.lang)),
          ]),
          const SizedBox(height: 10),
          Text(meta, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          if (l.publishedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${app.t('ads.published', {'date': app.fmtDate(l.publishedAt)})}${l.expiresAt != null ? ' · ${app.t('ads.until', {'date': app.fmtDate(l.expiresAt)})}' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// Раздел «Объявления»: смотреть можно без входа, подавать и откликаться — после входа.
class AdsTab extends StatefulWidget {
  const AdsTab({super.key});

  @override
  State<AdsTab> createState() => _AdsTabState();
}

class _AdsTabState extends State<AdsTab> {
  String _category = '';
  String _q = '';
  bool _allCities = false;
  int _bump = 0;
  final _debounce = Debouncer(300);

  @override
  void dispose() {
    _debounce.dispose();
    super.dispose();
  }

  Future<void> _newAd() async {
    final app = context.app;
    if (app.user == null) {
      final ok = await openAuth(context);
      if (ok != true || !mounted) return;
    }
    final id = await Navigator.of(context).push<int>(MaterialPageRoute<int>(builder: (_) => const AdFormScreen()));
    if (!mounted) return;
    setState(() => _bump++);
    if (id != null) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdScreen(id: id)));
      if (mounted) setState(() => _bump++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final city = app.city;
    final cityId = _allCities ? null : city?.id;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(
            key: const ValueKey('ads-new'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _newAd,
            child: Text(app.t('ads.new')),
          ),
          if (app.user != null)
            OutlinedButton(
              key: const ValueKey('ads-mine'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MyAdsScreen()));
                if (mounted) setState(() => _bump++);
              },
              child: Text(app.t('ads.mine')),
            ),
          if (app.user?.isModerator == true)
            OutlinedButton(
              key: const ValueKey('ads-mod'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ModScreen())),
              child: Text(app.t('mod.title')),
            ),
        ]),
        const SizedBox(height: 16),
        ChipChoice(
          value: _category,
          onChanged: (v) => setState(() => _category = v),
          options: [Opt<String>('', app.t('common.all')), for (final c in kCategories) Opt<String>(c, app.tk('ads.cat', c))],
        ),
        const SizedBox(height: 12),
        SearchField(
          hint: app.t('ads.search'),
          onChanged: (v) => _debounce.run(() {
            if (mounted) setState(() => _q = v);
          }),
        ),
        CheckboxListTile(
          key: const ValueKey('ads-all-cities'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _allCities,
          title: Text(app.t('ads.allCities')),
          onChanged: (v) => setState(() => _allCities = v ?? false),
        ),
        const SizedBox(height: 8),
        Async<List<Listing>>(
          cacheKey: '$_category|$_q|${cityId ?? ''}|$_bump',
          load: () async {
            final j = await app.api.get('/listings', query: {'category': _category, 'q': _q, 'city': cityId});
            return ((j as Map)['listings'] as List).map(Listing.fromJson).toList();
          },
          builder: (context, list, reload) {
            if (list.isEmpty) return EmptyNote(app.t('ads.empty'));
            return Column(children: [for (final l in list) ListingCard(listing: l)]);
          },
        ),
      ],
    );
  }
}
