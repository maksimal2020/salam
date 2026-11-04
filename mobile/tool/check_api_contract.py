#!/usr/bin/env python3
"""Сверка приложения с настоящим сервером.

Запускает те же запросы, что делает приложение, собирает все ключи JSON из ответов
и проверяет, что каждый ключ, который читает Dart-код (m['ключ']), реально приходит от сервера.
Опечатка в имени поля иначе проявилась бы только на устройстве как пустой экран.

Использование:
  python3 tool/check_api_contract.py http://localhost:3000 moderator@example.local change-me-please
Нужен запущенный сервер с загруженным контентом и (для проверки учреждений) тестовыми данными из e2e/fixtures/content.
"""
import glob
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

base = sys.argv[1].rstrip('/') if len(sys.argv) > 1 else 'http://localhost:3000'
mod_email = sys.argv[2] if len(sys.argv) > 2 else 'moderator@example.local'
mod_pass = sys.argv[3] if len(sys.argv) > 3 else 'change-me-please'


def call(method, path, body=None, token=None, query=None, expect=(200, 201)):
    url = base + '/api' + path + ('?' + urllib.parse.urlencode(query) if query else '')
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header('accept', 'application/json')
    if data is not None:
        req.add_header('content-type', 'application/json')
    if token:
        req.add_header('authorization', 'Bearer ' + token)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            status, text = r.status, r.read().decode('utf-8')
    except urllib.error.HTTPError as e:
        status, text = e.code, e.read().decode('utf-8')
    if status not in expect:
        raise SystemExit(f'{method} {path}: неожиданный статус {status}: {text[:200]}')
    return json.loads(text) if text else None


responses = []  # (label, json)


def rec(label, value):
    responses.append((label, value))
    return value


meta = rec('meta', call('GET', '/meta', query={'lang': 'ru'}))
rec('i18n', call('GET', '/i18n/tg'))
rec('cities', call('GET', '/cities', query={'q': 'моск'}))
rec('locate-ok', call('POST', '/cities/locate', {'lat': 55.75, 'lon': 37.62}))
rec('locate-outside', call('POST', '/cities/locate', {'lat': 52.52, 'lon': 13.4}))
docs = rec('documents', call('GET', '/documents', query={'lang': 'ru'}))
rec('document', call('GET', '/documents/' + docs['documents'][0]['id'], query={'lang': 'tg'}))
for city in ('moscow', 'khimki', 'kazan'):
    for d in docs['documents']:
        rec(f'places-{city}-{d["id"]}', call('GET', f'/documents/{d["id"]}/places', query={'lang': 'ru', 'city': city, 'citizenship': 'KG'}))
rec('institutions', call('GET', '/institutions', query={'lang': 'ru', 'city': 'moscow'}))
rec('institutions-khimki', call('GET', '/institutions', query={'lang': 'ru', 'city': 'khimki', 'mode': 'online'}))
rec('tips', call('GET', '/tips', query={'lang': 'ru', 'city': 'moscow'}))
rec('coverage', call('GET', '/coverage'))
cit = meta['citizenships'][0]['id']
for profile in (
    {'citizenship': cit, 'purpose': 'work', 'stage': 'in_russia', 'flags': {'has_contract': True}, 'lang': 'ru'},
    {'purpose': 'work', 'lang': 'ru'},
):
    rec('checklist', call('POST', '/checklist', profile))
other = next((c for c in meta['citizenships'] if c['group'] == 'other'), None)
if other:
    rec('checklist-other', call('POST', '/checklist', {'citizenship': other['id'], 'purpose': 'work', 'stage': 'in_russia', 'lang': 'ru'}))

# аккаунты, объявления, отклики, жалобы, модерация
suffix = uuid.uuid4().hex[:8]
author = rec('register', call('POST', '/auth/register', {'email': f'a{suffix}@example.com', 'password': 'password-123', 'displayName': 'Автор'}))
reader = call('POST', '/auth/register', {'email': f'b{suffix}@example.com', 'password': 'password-123'})
rec('me', call('GET', '/me', token=author['token']))
work = call('POST', '/listings', {
    'category': 'work', 'title': 'Требуется грузчик на склад', 'body': 'Склад в Москве, график сменный, оформление по договору.',
    'lang': 'ru', 'city_id': 'moscow', 'duration_days': 14,
    'extra': {'employer': 'ООО Пример', 'pay': '90 000 руб.', 'schedule': '2/2', 'terms': 'трудовой договор'}}, token=author['token'])
rec('create-work', work)
house = rec('create-housing', call('POST', '/listings', {
    'category': 'housing', 'title': 'Сдаётся комната в центре', 'body': 'Комната для одного человека, рядом метро, без посредников.',
    'lang': 'ru', 'city_id': 'moscow', 'price': '25 000 руб./мес.', 'duration_days': 14}, token=author['token']))
rec('listings', call('GET', '/listings', query={'category': 'housing', 'city': 'moscow'}))
rec('listing-public', call('GET', f'/listings/{house["id"]}'))
rec('listing-owner', call('GET', f'/listings/{house["id"]}', token=author['token']))
call('POST', f'/listings/{house["id"]}/respond', {'message': 'Здравствуйте, комната ещё свободна?', 'contact': 'tg @example'}, token=reader['token'])
rec('responses', call('GET', f'/my/listings/{house["id"]}/responses', token=author['token']))
rec('my-listings', call('GET', '/my/listings', token=author['token']))
rec('my-responses', call('GET', '/my/responses', token=reader['token']))
call('POST', f'/listings/{house["id"]}/report', {'reason': 'Проверка жалобы'}, token=reader['token'])
mod = call('POST', '/auth/login', {'email': mod_email, 'password': mod_pass})
for kind in ('pending', 'reported', 'recent'):
    rec('mod-' + kind, call('GET', '/mod/queue', query={'kind': kind}, token=mod['token']))
call('POST', f'/mod/listings/{work["id"]}/approve', {}, token=mod['token'])
call('POST', f'/mod/listings/{house["id"]}/hide', {'reason': 'Проверка скрытия'}, token=mod['token'])
call('POST', f'/mod/listings/{house["id"]}/restore', {}, token=mod['token'])
call('POST', f'/listings/{house["id"]}/withdraw', {}, token=author['token'])

# --- ключи из ответов
seen = set()


def walk(v):
    if isinstance(v, dict):
        for k, x in v.items():
            seen.add(k)
            walk(x)
    elif isinstance(v, list):
        for x in v:
            walk(x)


for _, v in responses:
    walk(v)
# ключи словарей «язык → текст» и «id → значение» — это данные, а не поля
dynamic = {'ru', 'tg', 'uz', 'ky', 'kk'}
# Ключи, которые приложение читает из собственного хранилища на телефоне (а не из ответа сервера).
local_only = {'citizenship'}

# --- ключи, которые читает Dart
missing = {}
for f in sorted(glob.glob('lib/**/*.dart', recursive=True)):
    if f.endswith('json_util.dart'):
        continue
    src = open(f, encoding='utf-8').read()
    for m in re.finditer(r"\b(?:m|j|cm|sm|dm|rm|mp|ref|c|s|d|x|r)\['([A-Za-z_][A-Za-z0-9_]*)'\]", src):
        key = m.group(1)
        if key not in seen and key not in dynamic and key not in local_only and not key.startswith('_'):
            missing.setdefault(key, set()).add(f)

print(f'Запросов проверено: {len(responses)}; уникальных ключей в ответах: {len(seen)}')
# Эти ключи читаются из ответов, которые тут не воспроизвести (редкие ветки) — проверяем по коду сервера вручную.
if missing:
    print('НЕ найдены в ответах сервера:')
    for k, fs in sorted(missing.items()):
        print(f'  {k}  ← {", ".join(sorted(fs))}')
    sys.exit(1)
print('Все ключи, которые читает приложение, есть в ответах сервера.')
