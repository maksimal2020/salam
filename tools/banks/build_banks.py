#!/usr/bin/env python3
"""Собирает content/banks.json — отделения банков в 44 городах приложения.

Откуда что берётся:
- список подразделений банка и их адреса — веб-сервис Банка России
  (https://www.cbr.ru/CreditInfoWebServ/CreditOrgInfo.asmx, метод GetOfficesXML);
- название, лицензия, статус и телефон банка — там же (CreditInfoByIntCodeXML);
- координаты — геокодирование адреса через OpenStreetMap Nominatim (не чаще 1 запроса
  в секунду, с кэшем); если дом не найден точно, координаты не ставятся;
- что банк обслуживает иностранных граждан — официальная страница банка (BANKS[*].foreign).

В каждом городе берутся до трёх отделений, ближайших к центру города (центр — lat/lon из
content/cities.json). Кандидаты: офисы с названием из реестра, без автосалонов, передвижных
пунктов, кассово-инкассаторских центров, ипотечных и премиальных офисов. Полный список
отделений человек видит по ссылке на карту банка.

  python3 tools/banks/build_banks.py --cache ПАПКА_КЭША [--banks vtb,psb,tbank]

Кэш (ответы ЦБ и геокодера) лежит вне репозитория: повторный запуск ничего не скачивает заново.
"""
import argparse
import html
import json
import math
import pathlib
import re
import subprocess
import sys
import time
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[2]
CBR_WS = 'https://www.cbr.ru/CreditInfoWebServ/CreditOrgInfo.asmx'
UA = 'SalamContentBuilder/1.0 (+https://salam-app.ru)'

# Банки, у которых на официальном сайте есть раздел для иностранных граждан.
# status: verified — показывается в приложении; draft — собран, но не показывается.
BANKS = {
    'vtb': {
        'regnum': 1000,
        'name': 'ВТБ',
        'status': 'verified',
        'map': 'https://vtb.ru/about/offices',
        'foreign': {
            'title': 'vtb.ru — Банк ВТБ: дебетовая карта для иностранных граждан',
            'url': 'https://www.vtb.ru/personal/karty/debetovye/foreign/',
        },
        'verified_how': 'страница для иностранных граждан на vtb.ru найдена поиском; сайт закрыт для автоматического чтения (robots.txt), текст условий не прочитан',
    },
    'psb': {
        'regnum': 3251,
        'name': 'ПСБ',
        'status': 'verified',
        'map': 'https://www.psbank.ru/',
        'foreign': {
            'title': 'psbank.ru — Банк ПСБ: продукты и услуги для иностранных граждан',
            'url': 'https://www.psbank.ru/personal/kompleksnye-finansovye-resheniya',
        },
        'verified_how': 'раздел «Продукты и услуги для иностранных граждан» на psbank.ru найден поиском; сайт закрыт для автоматического чтения (robots.txt), текст условий не прочитан',
    },
    'sber': {
        'regnum': 1481,
        'name': 'СберБанк',
        'status': 'draft',
        'map': 'https://www.sberbank.ru/',
        'foreign': None,
        'verified_how': 'официальная страница для иностранных граждан не найдена (в поиске только агрегаторы); сайт закрыт для автоматического чтения',
    },
    'alfa': {
        'regnum': 1326,
        'name': 'Альфа-Банк',
        'status': 'draft',
        'map': 'https://alfabank.ru/',
        'foreign': None,
        'verified_how': 'официальная страница для иностранных граждан не найдена (в поиске только агрегаторы)',
    },
}

# Банки без сети отделений для частных клиентов: одна запись «онлайн» на всю страну.
ONLINE = {
    'tbank': {
        'regnum': 2673,
        'name': 'Т-Банк — заявка на карту онлайн',
        'status': 'verified',
        'site': 'https://www.tbank.ru/',
        'foreign': {
            'title': 'tbank.ru — Т-Банк: новость от 11.06.2025 «Т-Банк начал выдавать кредитные карты иностранным гражданам»',
            'url': 'https://www.tbank.ru/about/news/11062025-t-bank-has-started-issuing-credit-cards-to-foreign-citizens',
        },
        'note': ('Отделений для частных клиентов у банка почти нет: заявку на карту подают на сайте или в приложении банка. '
                 'По сообщению банка (11.06.2025), иностранным гражданам доступны дебетовая карта Black и кредитная карта. '
                 'Для кредитной карты нужны зарубежный паспорт, документ, подтверждающий право находиться в России, '
                 'и российская SIM-карта. Остальные условия уточните на сайте банка.'),
        'verified_how': ('Новость на tbank.ru прочитана 2026-11-18: дебетовая карта Black и кредитная карта для нерезидентов; '
                         'документы для кредитной карты — зарубежный паспорт, документ о праве находиться в РФ, российская SIM-карта; '
                         'заявка на сайте. Как получить карту (доставка/офис) в новости не сказано.'),
    },
}

# Точки, где частному клиенту счёт не откроют или откроют не всем.
EXCLUDE = re.compile(
    r'МОТОРС|АВТО|SOLLERS|ДИЛЕР|РОЛЬФ|АВИЛОН|ТТС|БМВ|BMW|MERCEDES|TOYOTA|ЛАДА|KIA|HYUNDAI|'
    r'ИПОТЕК|ПРЕМИУМ|PREMIUM|PRIVATE|ПРИВИЛЕГ|PRIME|ПРАЙМ|'
    r'КАССОВО-ИНКАССАТОР|КАССОВЫЙ ЦЕНТР|ИНКАССАЦ|ПЕРЕДВИЖН|МОБИЛЬН|АВТОМОБИЛЬ|'
    r'КОРПОРАТИВ|БИЗНЕС|МСБ|ЛИЗИНГ|ЦИФРОВОЙ',
    re.I)


def soap(op, cache, **args):
    key = cache / ('cbr_' + op + ''.join(f'_{k}{v}' for k, v in args.items()) + '.xml')
    if key.exists():
        return key.read_text(encoding='utf-8')
    body = ''.join(f'<{k}>{v}</{k}>' for k, v in args.items())
    env = ('<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">'
           f'<soap:Body><{op} xmlns="http://web.cbr.ru/">{body}</{op}></soap:Body></soap:Envelope>')
    out = subprocess.run(['curl', '-sS', '-m', '180', '-X', 'POST', CBR_WS, '-H', 'Content-Type: text/xml; charset=utf-8',
                          '-H', f'SOAPAction: "http://web.cbr.ru/{op}"', '--data-binary', env],
                         capture_output=True, text=True, check=True).stdout
    if '<soap:Fault>' in out or not out.strip():
        sys.exit(f'ЦБ: ошибка {op} {args}: {out[:300]}')
    key.write_text(out, encoding='utf-8')
    return out


def tag(s, t):
    m = re.search(f'<{t}>(.*?)</{t}>', s, re.S)
    return html.unescape(m.group(1)).strip() if m else None


def bank_info(b, cache):
    code = tag(soap('RegNumToIntCode', cache, RegNumber=b['regnum']), 'RegNumToIntCodeResult')
    info = soap('CreditInfoByIntCodeXML', cache, InternalCode=code)
    offices = soap('GetOfficesXML', cache, IntCode=code)
    recs = []
    for rec in re.findall(r'<Offices>(.*?)</Offices>', offices, re.S):
        recs.append({'name': (tag(rec, 'cname') or '').strip(), 'addr': tag(rec, 'straddrmn') or '', 'reg': tag(rec, 'RegId')})
    return {
        'intcode': code, 'full': tag(info, 'OrgFullName'), 'short': tag(info, 'csname'),
        'status': tag(info, 'OrgStatus'), 'phones': tag(info, 'phones'), 'offices': recs,
    }


def regions(cache):
    s = html.unescape(soap('EnumRegionsXML', cache))
    return {n.strip(): r for n, r in re.findall(r'<ER><Name>(.*?)</Name><rgn>(\d+)</rgn></ER>', s, re.S)}


def norm(s):
    return s.upper().replace('Ё', 'Е')


def city_pattern(name):
    """«Ростов-на-Дону» → шаблон для адресов ЦБ («Г. РОСТОВ-НА-ДОНУ», «ГОРОД РОСТОВ-НА-ДОНУ»)."""
    n = re.escape(norm(name)).replace(r'\ ', r'[\s.]*').replace(r'\-', r'[\s-]*')
    if norm(name) == 'НИЖНИЙ НОВГОРОД':
        n = r'(?:НИЖНИЙ|Н\.)[\s.]*НОВГОРОД'
    if norm(name) == 'САНКТ-ПЕТЕРБУРГ':
        n = r'(?:САНКТ|С\.)[\s-]*ПЕТЕРБУРГ'
    return re.compile(r'(?:^|[\s,])(?:Г\.|Г\s|ГОР\.|ГОРОД)\s*' + n + r'(?=$|[\s,])')


def office_city(rec, city, reg_code):
    a = norm(rec['addr'])
    if '#' in a:  # передвижной офис: список сёл через «#»
        return False
    if rec['reg'] and reg_code and rec['reg'] != reg_code:
        return False
    if not city['_pat'].search(a):
        return False
    # Москва и Московская область у ЦБ — один код региона: отделяем по адресу.
    if city['id'] == 'moscow' and re.search(r'МОСКОВСКАЯ\s+ОБЛ', a):
        return False
    return True


ABBR = {
    'ПР.': 'пр.', 'Г.': 'г.', 'УЛ.': 'ул.', 'Д.': 'д.', 'ДОМ': 'дом', 'ПР-Т': 'пр-т', 'ПР-КТ': 'пр-кт', 'ПРОСП.': 'просп.', 'Ш.': 'ш.',
    'ПЕР.': 'пер.', 'ПЛ.': 'пл.', 'Б-Р': 'б-р', 'НАБ.': 'наб.', 'СТР.': 'стр.', 'КОРП.': 'корп.', 'К.': 'к.',
    'ПОМ.': 'пом.', 'ПОМЕЩ.': 'помещ.', 'ЛИТ.': 'лит.', 'ЛИТЕР': 'литер', 'ЛИТЕРА': 'литера', 'ОФ.': 'оф.',
    'ЭТ.': 'эт.', 'ЭТАЖ': 'этаж', 'ЗД.': 'зд.', 'ВЛ.': 'вл.', 'МКР.': 'мкр.', 'МКР': 'мкр', 'ПР-Д': 'пр-д',
    'ПРОЕЗД': 'проезд', 'УЛИЦА': 'улица', 'ПРОСПЕКТ': 'проспект', 'ШОССЕ': 'шоссе', 'ПЕРЕУЛОК': 'переулок',
    'ПЛОЩАДЬ': 'площадь', 'БУЛЬВАР': 'бульвар', 'НАБЕРЕЖНАЯ': 'набережная', 'ГОРОД': 'город', 'ОБЛАСТЬ': 'область',
    'ОБЛ.': 'обл.', 'КРАЙ': 'край', 'РЕСПУБЛИКА': 'Республика', 'Р-Н': 'р-н', 'РАЙОН': 'район', 'ВН.': 'вн.',
    'ТЕР.': 'тер.', 'МУНИЦИПАЛЬНЫЙ': 'муниципальный', 'ОКРУГ': 'округ', 'ГОРОДСКОЙ': 'городской', 'ПОС.': 'пос.',
    'ПОСЕЛЕНИЕ': 'поселение', 'ПГТ.': 'пгт.', 'С.': 'с.', 'Д': 'д', 'ИМ.': 'им.', 'КВ-Л': 'кв-л', 'ЛИН.': 'лин.',
    'ТЦ': 'ТЦ', 'ТРЦ': 'ТРЦ', 'ТРК': 'ТРК', 'ТК': 'ТК', 'БЦ': 'БЦ', 'Н': 'н', 'ЧАСТЬ': 'часть', 'ЗДАНИЕ': 'здание',
    'СТРОЕНИЕ': 'строение', 'КОРПУС': 'корпус', 'ПОМЕЩЕНИЕ': 'помещение', 'ВЛАДЕНИЕ': 'владение', 'РОССИЙСКАЯ': 'Российская',
    'ФЕДЕРАЦИЯ': 'Федерация', 'НА': 'на', 'И': 'и', 'ЛЕТ': 'лет', 'ЛЕТИЯ': 'летия', 'Я': 'я', 'ГО': 'го', 'Й': 'й',
}


def pretty_word(w):
    if not w:
        return w
    if w in ABBR:
        return ABBR[w]
    if re.fullmatch(r'[IVXLCDM]+', w) or re.fullmatch(r'[A-Z0-9]+', w):
        return w
    if re.fullmatch(r'\d+[А-ЯA-Z]?', w):
        return w
    return w[0] + w[1:].lower()


def spaced(a):
    """«Г.НОВОСИБИРСК, УЛ.ДУСИ КОВАЛЬЧУК, Д.266» → «Г. НОВОСИБИРСК, УЛ. ДУСИ КОВАЛЬЧУК, Д. 266»."""
    return re.sub(r'(?<![А-ЯЁA-Z])(Г|УЛ|Д|ПР|ПЕР|ПЛ|НАБ|СТР|КОРП|ПОМ|ПОМЕЩ|ЛИТ|ОФ|ЭТ|ЗД|ВЛ|МКР|ПОС|ИМ|ОБЛ|Ш|ПРОСП|К)\.(?=[А-ЯЁA-Z0-9])', r'\1. ', a.upper())


def pretty(addr):
    """«390000, Г. РЯЗАНЬ, УЛ. ПОЖАЛОСТИНА, Д. 19» → «г. Рязань, ул. Пожалостина, д. 19»."""
    a = re.sub(r'^\s*\d{6},\s*', '', spaced(addr.strip()))
    a = re.sub(r'^РОССИЙСКАЯ ФЕДЕРАЦИЯ,\s*', '', a)
    a = re.sub(r'\s+', ' ', a)
    # Регион перед городом («Свердловская область, г. Екатеринбург, …») лишний: город и так указан.
    segs = [x.strip() for x in a.split(',')]
    for i, seg in enumerate(segs):
        if re.match(r'^(Г\.|ГОРОД\s)', seg):
            segs = segs[i:]
            segs[0] = re.sub(r'^ГОРОД\s+', 'Г. ', segs[0])
            break
    a = ', '.join(segs)
    out = []
    for token in re.split(r'(\s+|,|"|«|»|\(|\))', a):
        if not token or not token.strip() or token in ',"«»()':
            out.append(token)
            continue
        if token in ABBR or token in HYPHEN_ABBR:
            out.append(ABBR.get(token) or HYPHEN_ABBR[token])
            continue
        if re.fullmatch(r'[БВГДЖЗЙКЛМНПРСТФХЦЧШЩ]{2,}', token):  # ВЛКСМ, СНТ
            out.append(token)
            continue
        parts = token.split('-')
        conv = []
        for i, p in enumerate(parts):
            if i > 0 and p in ('НА', 'ЛЕТИЯ', 'ЛЕТ', 'Я', 'ГО', 'Й', 'ОЙ', 'ЫЙ', 'ИЙ', 'АЯ', 'ЕЙ', 'ОГО'):
                conv.append(p.lower())
            else:
                conv.append(pretty_word(p))
        out.append('-'.join(conv))
    s = ''.join(out)
    return re.sub(r'\s+,', ',', s).strip()


HYPHEN_ABBR = {'ПР-Т': 'пр-т', 'ПР-КТ': 'пр-кт', 'Б-Р': 'б-р', 'Р-Н': 'р-н', 'ПР-Д': 'пр-д', 'КВ-Л': 'кв-л', 'Р-НА': 'р-на'}

STREET = re.compile(r'(?<![А-ЯЁ])(УЛ\.|УЛИЦА|ПР-КТ|ПР-Т|ПРОСП\.|ПР\.|ПРОСПЕКТ|Ш\.|ШОССЕ|ПЕР\.|ПЕРЕУЛОК|ПЛ\.|ПЛОЩАДЬ|Б-Р|БУЛЬВАР|НАБ\.|НАБЕРЕЖНАЯ|ПР-Д|ПРОЕЗД|МКР\.?|МИКРОРАЙОН|КВ-Л)')
FULL = {'УЛ.': 'улица', 'ПР-КТ': 'проспект', 'ПР-Т': 'проспект', 'ПРОСП.': 'проспект', 'ПР.': 'проспект', 'Ш.': 'шоссе', 'ПЕР.': 'переулок',
        'ПЛ.': 'площадь', 'Б-Р': 'бульвар', 'НАБ.': 'набережная', 'ПР-Д': 'проезд', 'МКР.': 'микрорайон', 'МКР': 'микрорайон',
        'КВ-Л': 'квартал'}


def geo_query(addr, city_name, region=None):
    """Строка для геокодера: город, улица, дом — без индекса, округов, помещений и литер."""
    parts = [p.strip() for p in spaced(norm(addr)).split(',')]
    street = house = None
    for i, p in enumerate(parts):
        if street is None and STREET.search(p):
            m = STREET.search(p)
            name = (p[:m.start()] + p[m.end():]).strip(' .')
            street = f"{FULL.get(m.group(1), m.group(1).lower())} {pretty(name)}".strip()
            for q in parts[i + 1:i + 3]:
                hm = re.match(r'^(?:Д\.|ДОМ|ЗД\.|ЗДАНИЕ|ВЛ\.|ВЛАДЕНИЕ|СТР\.|СТРОЕНИЕ)?\s*(\d+[А-Я]?(?:\s*/\s*\d+)?)', q)
                if hm:
                    house = hm.group(1).replace(' ', '').lower()
                    break
            if house is None:  # «УЛ. ЛЕНИНА 5», «ПРОСПЕКТ МИРА, 12» без «Д.»
                hm = re.search(r'\s(\d+[А-Я]?)$', p)
                if hm:
                    house = hm.group(1).lower()
                    street = street[: -len(hm.group(1))].strip()
            break
    if not street:
        return None
    where = f'{city_name}, {region}' if region else city_name
    return f'{where}, {street}' + (f', {house}' if house else '')


def office_label(name):
    """«№ 1234 "Московский, 1" в г. Санкт-Петербурге» → «Московский, 1»; «8606/001» → «№ 8606/001»."""
    n = re.sub(r'\s+', ' ', name).strip()
    n = re.sub(r'\s+в\s+(?:г\.|городе|г\s)\s*.*$', '', n, flags=re.I).strip()
    q = re.search(r'["«](.+?)["»]', n)
    if q:
        return f'«{q.group(1).strip()}»'
    n = n.strip(' "«»')
    if re.match(r'^№?\s*\d', n):
        return '№ ' + n.lstrip('№ ').strip()
    return f'«{n}»'


def geocode(q, cache_file, cache):
    if q in cache:
        return cache[q]
    time.sleep(1.1)  # правила Nominatim: не чаще 1 запроса в секунду
    url = 'https://nominatim.openstreetmap.org/search?' + urllib.parse.urlencode(
        {'format': 'jsonv2', 'addressdetails': 1, 'limit': 3, 'countrycodes': 'ru', 'q': q})
    out = subprocess.run(['curl', '-sS', '-m', '30', '-A', UA, url], capture_output=True, text=True).stdout
    try:
        res = json.loads(out)
    except json.JSONDecodeError:
        res = None
    if res is None:
        return None  # сбой сети — не кэшируем
    cache[q] = res
    cache_file.write_text(json.dumps(cache, ensure_ascii=False), encoding='utf-8')
    return res


def dist_km(a_lat, a_lon, b_lat, b_lon):
    r = 6371.0
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    dp, dl = p2 - p1, math.radians(b_lon - a_lon)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def best_hit(results, city):
    """Точное попадание в дом в нужном городе: координаты и описание того, что нашлось."""
    for r in results or []:
        ad = r.get('address', {})
        # Одноимённые города (два Железногорска, два Советска, два Заречных): только расстояние
        # до центра нужного города отличает правильный дом от однофамильца за тысячи километров.
        if dist_km(float(r['lat']), float(r['lon']), city['lat'], city['lon']) > city['_radius']:
            continue
        if not ad.get('house_number'):
            continue
        what = f"{r.get('category', r.get('class'))}/{r.get('type')}"
        return float(r['lat']), float(r['lon']), what, r.get('display_name', '')
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--cache', required=True)
    ap.add_argument('--banks', default=','.join(BANKS))
    ap.add_argument('--checked', default=time.strftime('%Y-%m-%d'))
    ap.add_argument('--candidates', type=int, default=6, help='сколько офисов на город геокодировать')
    ap.add_argument('--dry', action='store_true', help='только посчитать кандидатов, без геокодирования')
    args = ap.parse_args()
    cache = pathlib.Path(args.cache)
    cache.mkdir(parents=True, exist_ok=True)
    geo_file = cache / 'nominatim.json'
    geo_cache = json.loads(geo_file.read_text(encoding='utf-8')) if geo_file.exists() else {}

    regs = regions(cache)
    cities = json.loads((ROOT / 'content' / 'cities.json').read_text(encoding='utf-8'))
    for c in cities:
        name = c['name']['ru'] if isinstance(c['name'], dict) else c['name']
        region = c['region']['ru'] if isinstance(c['region'], dict) else c['region']
        c['_name'] = name
        c['_reg'] = regs.get('Московская область') if region == 'г. Москва' else regs.get(region)
        c['_pat'] = city_pattern(name)
        c['_pat_plain'] = re.compile(re.escape(norm(name)).replace(r'\-', r'[\s-]*').replace(r'\ ', r'\s*'))
        c['_region'] = region
        c['_radius'] = 40 if c['id'] in ('moscow', 'spb') else 25
    names = [c['_name'] for c in cities]
    for c in cities:
        c['_homonym'] = names.count(c['_name']) > 1
        if c['_homonym'] or c['id'] in ('dubna', 'kotelniki', 'korolev', 'lyubertsy', 'krasnogorsk', 'odintsovo', 'mytishchi',
                                        'khimki', 'balashikha', 'podolsk'):
            c['_radius'] = 12
        if c['_reg'] is None:
            sys.exit(f'нет кода региона ЦБ для {name} ({region})')

    records, report = [], []
    for bid in args.banks.split(','):
        if bid not in BANKS:  # онлайн-банки — ниже, отдельной записью
            continue
        b = BANKS[bid]
        info = bank_info(b, cache)
        if info['status'] and 'норм' not in info['status']:
            report.append(f'{bid}: статус в реестре ЦБ «{info["status"]}» — пропущен')
            continue
        offices = [o for o in info['offices'] if o['name'] and not EXCLUDE.search(o['name']) and not EXCLUDE.search(o['addr'])]
        cbr_src = {'title': f'cbr.ru — Банк России, справочник по кредитным организациям: {info["full"]}, рег. № {b["regnum"]} (подразделения и адреса)',
                   'url': 'https://www.cbr.ru/banking_sector/credit/'}
        for city in cities:
            cand = [o for o in offices if office_city(o, city, city['_reg'])]
            # Ближе к центру обычно меньший почтовый индекс: с них и начинаем геокодирование.
            cand.sort(key=lambda o: (re.match(r'\s*(\d{6})', o['addr']) or [None, '999999'])[1])
            if args.dry:
                report.append(f'{bid} {city["id"]}: кандидатов {len(cand)}' + (f' — {pretty(cand[0]["addr"])} | {geo_query(cand[0]["addr"], city["_name"])}' if cand else ''))
                continue
            picked = []
            tried = 0
            for o in cand:
                if tried >= args.candidates:
                    break
                q = geo_query(o['addr'], city['_name'], city['_region'] if city['_homonym'] else None)
                if not q:
                    continue
                tried += 1
                hit = best_hit(geocode(q, geo_file, geo_cache), city)
                if hit:
                    picked.append((dist_km(hit[0], hit[1], city['lat'], city['lon']), o, hit, q))
            picked.sort(key=lambda x: x[0])
            seen = set()
            chosen = []
            for d, o, hit, q in picked:
                key = (round(hit[0], 4), round(hit[1], 4))
                if key in seen:
                    continue
                seen.add(key)
                chosen.append((d, o, hit, q))
                if len(chosen) == 3:
                    break
            report.append(f'{bid} {city["id"]}: кандидатов {len(cand)}, геокодировано {tried}, найдено точно {len(picked)}, взято {len(chosen)}')
            for n, (d, o, hit, q) in enumerate(chosen, 1):
                src = [cbr_src] + ([b['foreign']] if b['foreign'] else [])
                records.append({
                    'id': f'bank_{bid}_{city["id"]}_{n}',
                    'name': {'ru': f'{b["name"]}, офис {office_label(o["name"])}'},
                    'city_id': city['id'],
                    'services': ['bank_account'],
                    'mode': 'in_person',
                    'address': pretty(o['addr']),
                    'map_query': f'{b["name"]} {pretty(o["addr"])}',
                    'lat': round(hit[0], 6),
                    'lon': round(hit[1], 6),
                    'hours': None,
                    'phone': info['phones'],
                    'site': b['map'],
                    'booking_url': None,
                    'serves': [{'city': city['id'], 'districts': None}],
                    'citizenships': None,
                    'status': b['status'],
                    'checked_at': args.checked,
                    'sources': src,
                    'note': (f'Отделение {b["name"]} из реестра Банка России. Банк оформляет карты иностранным гражданам — '
                             'условия и список документов на странице банка для иностранцев (ссылка в источниках). '
                             'Часы работы и полный список отделений — на карте банка: требования к документам '
                             'у разных банков свои, перед визитом уточните их по телефону.'),
                    'internal_note': (f'Сгенерировано tools/banks/build_banks.py {args.checked}. Запись ЦБ: «{o["name"]}», '
                                      f'адрес «{o["addr"]}» ({info["full"]}, рег. № {b["regnum"]}). Отобрано среди {len(cand)} '
                                      f'именованных офисов города как одно из трёх ближайших к центру ({d:.1f} км). '
                                      f'Координаты: OpenStreetMap Nominatim по запросу «{q}», найдено {hit[2]}: {hit[3][:160]}. '
                                      f'Обслуживание иностранцев: {b["verified_how"]}. Часы работы не указаны: в реестре ЦБ их нет.'),
                })
    for bid, o in ONLINE.items():
        if bid not in args.banks.split(','):
            continue
        info = bank_info(o, cache)
        records.append({
            'id': f'bank_{bid}_online', 'name': {'ru': o['name']}, 'city_id': 'moscow', 'services': ['bank_account'],
            'mode': 'online', 'address': None, 'map_query': None, 'lat': None, 'lon': None, 'hours': None,
            'phone': info['phones'], 'site': o['site'], 'booking_url': None, 'serves': [{'scope': 'country'}],
            'citizenships': None, 'status': o['status'], 'checked_at': args.checked,
            'sources': [{'title': f'cbr.ru — Банк России, справочник по кредитным организациям: {info["full"]}, рег. № {o["regnum"]}',
                         'url': 'https://www.cbr.ru/banking_sector/credit/'}, o['foreign']],
            'note': o['note'],
            'internal_note': f'Сгенерировано tools/banks/build_banks.py {args.checked}. Статус в реестре ЦБ: {info["status"]}. {o["verified_how"]}',
        })
    out = ROOT / 'content' / 'banks.json'
    out.write_text(json.dumps(records, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (cache / 'report.txt').write_text('\n'.join(report) + '\n', encoding='utf-8')
    print(f'{len(records)} записей → {out.relative_to(ROOT)}; отчёт: {cache / "report.txt"}')


if __name__ == '__main__':
    main()
