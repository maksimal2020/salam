// Модели ответов сервера. Поля повторяют web/src/api.ts и маршруты server/src/routes/*.ts.
import '../util/json_util.dart';

class SourceLink {
  const SourceLink({required this.title, required this.url});
  final String title;
  final String url;

  factory SourceLink.fromJson(dynamic j) {
    final m = asMap(j);
    return SourceLink(title: strOr(m['title']), url: strOr(m['url']));
  }
}

List<SourceLink> _sources(dynamic v) => asList(v).map(SourceLink.fromJson).toList();

class District {
  const District(this.id, this.name);
  final String id;
  final String name;
}

class City {
  const City({required this.id, required this.name, required this.region, this.districts = const []});
  final String id;
  final String name;
  final String region;
  final List<District> districts;

  String get label => '$name, $region';

  factory City.fromJson(dynamic j) {
    final m = asMap(j);
    return City(
      id: strOr(m['id']),
      name: strOr(m['name']),
      region: strOr(m['region']),
      districts: asList(m['districts']).map((d) {
        final dm = asMap(d);
        return District(strOr(dm['id']), strOr(dm['name']));
      }).toList(),
    );
  }

  /// Сохраняется только подтверждённый город и регион — без координат.
  Map<String, dynamic> toSaved() => {'id': id, 'name': name, 'region': region};
}

class LangInfo {
  const LangInfo(this.code, this.native);
  final String code;
  final String native;
}

/// Названия языков на самих языках: первый экран и список языков объявлений.
const List<LangInfo> kLangs = [
  LangInfo('ru', 'Русский'),
  LangInfo('tg', 'Тоҷикӣ'),
  LangInfo('uz', 'Oʻzbekcha'),
  LangInfo('ky', 'Кыргызча'),
  LangInfo('kk', 'Қазақша'),
];

String langNative(String code) {
  for (final l in kLangs) {
    if (l.code == code) return l.native;
  }
  return code;
}

class Citizenship {
  const Citizenship(this.id, this.group, this.name);
  final String id;
  final String group;
  final String name;
}

class IdName {
  const IdName(this.id, this.name);
  final String id;
  final String name;
}

class Meta {
  const Meta({
    required this.citizenships,
    required this.situations,
    required this.purposes,
    required this.stages,
    required this.flags,
    required this.includeDemo,
  });
  final List<Citizenship> citizenships;
  final List<IdName> situations;
  final List<String> purposes;
  final List<String> stages;
  final List<String> flags;
  final bool includeDemo;

  factory Meta.fromJson(dynamic j) {
    final m = asMap(j);
    final ref = asMap(m['reference']);
    return Meta(
      citizenships: asList(m['citizenships']).map((c) {
        final cm = asMap(c);
        return Citizenship(strOr(cm['id']), strOr(cm['group']), strOr(cm['name']));
      }).toList(),
      situations: asList(m['situations']).map((s) {
        final sm = asMap(s);
        return IdName(strOr(sm['id']), strOr(sm['name']));
      }).toList(),
      purposes: strList(ref['purposes']),
      stages: strList(ref['stages']),
      flags: strList(ref['flags']),
      includeDemo: asBool(m['includeDemo']),
    );
  }
}

class DocBrief {
  const DocBrief({
    required this.id,
    required this.necessity,
    required this.status,
    required this.checkedAt,
    required this.situations,
    required this.title,
    required this.summary,
  });
  final String id;
  final String necessity; // mandatory | conditional | service
  final String status; // verified | demo
  final String? checkedAt;
  final List<String> situations;
  final String title;
  final String summary;

  factory DocBrief.fromJson(dynamic j) {
    final m = asMap(j);
    return DocBrief(
      id: strOr(m['id']),
      necessity: strOr(m['necessity'], 'conditional'),
      status: strOr(m['status'], 'demo'),
      checkedAt: asStr(m['checked_at']),
      situations: strList(m['situations']),
      title: strOr(m['title']),
      summary: strOr(m['summary']),
    );
  }
}

class DocDetails {
  const DocDetails({this.who, this.prepare = const [], this.how = const [], this.renewal});
  final String? who;
  final List<String> prepare;
  final List<String> how;
  final String? renewal;

  factory DocDetails.fromJson(dynamic j) {
    final m = asMap(j);
    return DocDetails(
      who: asStr(m['who']),
      prepare: strList(m['prepare']),
      how: strList(m['how']),
      renewal: asStr(m['renewal']),
    );
  }
}

class DocFull {
  const DocFull({
    required this.brief,
    required this.details,
    required this.detailsFallback,
    required this.deadline,
    required this.cost,
    required this.sources,
    required this.whereKind,
    required this.whereNote,
  });
  final DocBrief brief;
  final DocDetails details;
  final bool detailsFallback;
  final Map<String, String>? deadline; // язык → текст; только у проверенных записей
  final Map<String, String>? cost;
  final List<SourceLink> sources;
  final String whereKind;
  final String? whereNote;

  static Map<String, String>? _byLang(dynamic v) {
    if (v == null) return null;
    final m = asMap(v);
    if (m.isEmpty) return null;
    return m.map((k, val) => MapEntry(k, strOr(val)));
  }

  factory DocFull.fromJson(dynamic j) {
    final m = asMap(j);
    return DocFull(
      brief: DocBrief.fromJson(m),
      details: DocDetails.fromJson(m['details']),
      detailsFallback: asBool(m['details_fallback']),
      deadline: _byLang(m['deadline']),
      cost: _byLang(m['cost']),
      sources: _sources(m['sources']),
      whereKind: strOr(m['where_kind'], 'institutions'),
      whereNote: asStr(m['where_note']),
    );
  }
}

class Serve {
  const Serve({this.country = false, this.city, this.districts});
  final bool country;
  final String? city;
  final List<String>? districts;

  factory Serve.fromJson(dynamic j) {
    final m = asMap(j);
    if (m['scope'] != null) return const Serve(country: true);
    return Serve(city: asStr(m['city']), districts: m['districts'] == null ? null : strList(m['districts']));
  }
}

class MapRef {
  const MapRef({this.query, this.lat, this.lon});
  final String? query;
  final double? lat;
  final double? lon;
}

class Institution {
  const Institution({
    required this.id,
    required this.name,
    required this.status,
    required this.checkedAt,
    required this.mode,
    required this.city,
    required this.otherCity,
    required this.address,
    required this.map,
    required this.hours,
    required this.phone,
    required this.site,
    required this.bookingUrl,
    required this.services,
    required this.serves,
    required this.citizenships,
    required this.sources,
    required this.note,
  });
  final String id;
  final String name;
  final String status;
  final String? checkedAt;
  final String mode;
  final City city;
  final bool otherCity;
  final String? address;
  final MapRef map;
  final String? hours;
  final String? phone;
  final String? site;
  final String? bookingUrl;
  final List<IdName> services;
  final List<Serve> serves;
  final List<String>? citizenships;
  final List<SourceLink> sources;
  final String? note;

  factory Institution.fromJson(dynamic j) {
    final m = asMap(j);
    final mp = asMap(m['map']);
    return Institution(
      id: strOr(m['id']),
      name: strOr(m['name']),
      status: strOr(m['status'], 'demo'),
      checkedAt: asStr(m['checked_at']),
      mode: strOr(m['mode'], 'in_person'),
      city: City.fromJson(m['city']),
      otherCity: asBool(m['other_city']),
      address: asStr(m['address']),
      map: MapRef(query: asStr(mp['query']), lat: asDouble(mp['lat']), lon: asDouble(mp['lon'])),
      hours: asStr(m['hours']),
      phone: asStr(m['phone']),
      site: asStr(m['site']),
      bookingUrl: asStr(m['booking_url']),
      services: asList(m['services']).map((s) {
        final sm = asMap(s);
        return IdName(strOr(sm['id']), strOr(sm['title']));
      }).toList(),
      serves: asList(m['serves']).map(Serve.fromJson).toList(),
      citizenships: m['citizenships'] == null ? null : strList(m['citizenships']),
      sources: _sources(m['sources']),
      note: asStr(m['note']),
    );
  }
}

class ServiceRef {
  const ServiceRef({required this.id, required this.title, required this.officialSearch});
  final String id;
  final String title;
  final SourceLink? officialSearch;
}

class Places {
  const Places({
    required this.needsCity,
    required this.city,
    required this.institutions,
    required this.needsDistrict,
    required this.districts,
    required this.whereKind,
    required this.whereNote,
    required this.officialSearch,
    required this.sources,
    required this.document,
    required this.services,
  });
  final bool needsCity;
  final City? city;
  final List<Institution> institutions;
  final bool needsDistrict;
  final List<District> districts;
  final String? whereKind; // есть только в ответе «где оформить документ»
  final String? whereNote;
  final SourceLink? officialSearch;
  final List<SourceLink> sources;
  final DocBrief? document;
  final List<ServiceRef> services; // есть только в общем поиске учреждений

  factory Places.fromJson(dynamic j) {
    final m = asMap(j);
    final os = m['official_search'];
    return Places(
      needsCity: asBool(m['needs_city']),
      city: m['city'] == null ? null : City.fromJson(m['city']),
      institutions: asList(m['institutions']).map(Institution.fromJson).toList(),
      needsDistrict: asBool(m['needs_district']),
      districts: asList(m['districts']).map((d) {
        final dm = asMap(d);
        return District(strOr(dm['id']), strOr(dm['name']));
      }).toList(),
      whereKind: asStr(m['where_kind']),
      whereNote: asStr(m['where_note']),
      officialSearch: os == null ? null : SourceLink.fromJson(os),
      sources: _sources(m['sources']),
      document: m['document'] == null ? null : DocBrief.fromJson(m['document']),
      services: asList(m['services']).map((s) {
        final sm = asMap(s);
        final so = sm['official_search'];
        return ServiceRef(id: strOr(sm['id']), title: strOr(sm['title']), officialSearch: so == null ? null : SourceLink.fromJson(so));
      }).toList(),
    );
  }
}

class ClarifyItem {
  const ClarifyItem({required this.type, this.field, this.docId, this.title});
  final String type; // missing | other_country | depends_on_citizenship
  final String? field;
  final String? docId;
  final String? title;
}

class ChecklistResult {
  const ChecklistResult({required this.items, required this.clarify, required this.whereToCheck, required this.includesDemo});
  final List<DocBrief> items;
  final List<ClarifyItem> clarify;
  final List<SourceLink> whereToCheck;
  final bool includesDemo;

  factory ChecklistResult.fromJson(dynamic j) {
    final m = asMap(j);
    return ChecklistResult(
      items: asList(m['items']).map(DocBrief.fromJson).toList(),
      clarify: asList(m['clarify']).map((c) {
        final cm = asMap(c);
        return ClarifyItem(type: strOr(cm['type']), field: asStr(cm['field']), docId: asStr(cm['docId']), title: asStr(cm['title']));
      }).toList(),
      whereToCheck: _sources(m['where_to_check']),
      includesDemo: asBool(m['includes_demo']),
    );
  }
}

class Tip {
  const Tip({required this.id, required this.topic, required this.updatedAt, required this.title, required this.body, required this.city});
  final String id;
  final String topic;
  final String? updatedAt;
  final String title;
  final String body;
  final City? city;

  factory Tip.fromJson(dynamic j) {
    final m = asMap(j);
    return Tip(
      id: strOr(m['id']),
      topic: strOr(m['topic']),
      updatedAt: asStr(m['updated_at']),
      title: strOr(m['title']),
      body: strOr(m['body']),
      city: m['city'] == null ? null : City.fromJson(m['city']),
    );
  }
}

class ModReport {
  const ModReport(this.id, this.reason);
  final int id;
  final String reason;
}

class Listing {
  const Listing({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.lang,
    required this.city,
    required this.price,
    required this.extra,
    required this.durationDays,
    required this.status,
    required this.createdAt,
    required this.publishedAt,
    required this.expiresAt,
    required this.hasOwnerFields,
    required this.moderationNote,
    required this.responseCount,
    required this.authorEmail,
    required this.reportCount,
    required this.reports,
  });
  final int id;
  final String category;
  final String title;
  final String body;
  final String lang;
  final City city;
  final String? price;
  final Map<String, String> extra; // employer, pay, schedule, terms
  final int durationDays;
  final String status;
  final String? createdAt;
  final String? publishedAt;
  final String? expiresAt;

  /// Поля автора есть в ответе только для самого автора (так же определяет web-версия).
  final bool hasOwnerFields;
  final String? moderationNote;
  final int responseCount;
  final String? authorEmail;
  final int reportCount;
  final List<ModReport> reports;

  factory Listing.fromJson(dynamic j) {
    final m = asMap(j);
    final extra = <String, String>{};
    asMap(m['extra']).forEach((k, v) {
      if (v != null && v.toString().isNotEmpty) extra[k] = v.toString();
    });
    return Listing(
      id: asInt(m['id']),
      category: strOr(m['category']),
      title: strOr(m['title']),
      body: strOr(m['body']),
      lang: strOr(m['lang'], 'ru'),
      city: City.fromJson(m['city']),
      price: asStr(m['price']),
      extra: extra,
      durationDays: asInt(m['duration_days'], 14),
      status: strOr(m['status']),
      createdAt: asStr(m['created_at']),
      publishedAt: asStr(m['published_at']),
      expiresAt: asStr(m['expires_at']),
      hasOwnerFields: m.containsKey('moderation_note'),
      moderationNote: asStr(m['moderation_note']),
      responseCount: asInt(m['response_count']),
      authorEmail: asStr(m['author_email']),
      reportCount: asInt(m['report_count']),
      reports: asList(m['reports']).map((r) {
        final rm = asMap(r);
        return ModReport(asInt(rm['id']), strOr(rm['reason']));
      }).toList(),
    );
  }
}

class AdResponse {
  const AdResponse({required this.id, required this.message, required this.contact, required this.createdAt});
  final int id;
  final String message;
  final String? contact;
  final String? createdAt;

  factory AdResponse.fromJson(dynamic j) {
    final m = asMap(j);
    return AdResponse(id: asInt(m['id']), message: strOr(m['message']), contact: asStr(m['contact']), createdAt: asStr(m['created_at']));
  }
}

class SentResponse {
  const SentResponse({required this.id, required this.listingId, required this.title, required this.message});
  final int id;
  final int listingId;
  final String title;
  final String message;

  factory SentResponse.fromJson(dynamic j) {
    final m = asMap(j);
    return SentResponse(id: asInt(m['id']), listingId: asInt(m['listing_id']), title: strOr(m['title']), message: strOr(m['message']));
  }
}

class AppUser {
  const AppUser({required this.id, required this.email, required this.role, required this.displayName});
  final int id;
  final String email;
  final String role; // user | moderator
  final String? displayName;

  bool get isModerator => role == 'moderator';

  factory AppUser.fromJson(dynamic j) {
    final m = asMap(j);
    return AppUser(id: asInt(m['id']), email: strOr(m['email']), role: strOr(m['role'], 'user'), displayName: asStr(m['displayName']));
  }

  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'role': role, 'displayName': displayName};
}

class ModQueue {
  const ModQueue({required this.listings, required this.pending, required this.reported, required this.recent});
  final List<Listing> listings;
  final int pending;
  final int reported;
  final int recent;

  int count(String kind) => kind == 'pending' ? pending : kind == 'reported' ? reported : recent;

  factory ModQueue.fromJson(dynamic j) {
    final m = asMap(j);
    final c = asMap(m['counts']);
    return ModQueue(
      listings: asList(m['listings']).map(Listing.fromJson).toList(),
      pending: asInt(c['pending']),
      reported: asInt(c['reported']),
      recent: asInt(c['recent']),
    );
  }
}

/// Результат определения города по положению.
class LocateResult {
  const LocateResult(this.status, this.city);
  final String status; // candidate | no_match | outside
  final City? city;

  factory LocateResult.fromJson(dynamic j) {
    final m = asMap(j);
    return LocateResult(strOr(m['status']), m['city'] == null ? null : City.fromJson(m['city']));
  }
}
