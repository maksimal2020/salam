#!/usr/bin/env python3
"""Дописывает в папки android/ и ios/, созданные командой `flutter create`, всё, что нужно приложению:
  • Android: доступ в интернет, грубое определение местоположения, разрешение http-адреса для разработки;
  • iOS: текст запроса геолокации, название приложения, исключение для http-адреса разработки.

Запускать после `flutter create --platforms=android,ios .` — см. README. Повторный запуск безопасен.
Исключение для http нужно только пока сервер работает без HTTPS (локальная разработка); перед выпуском
запустите скрипт с флагом --release-https, он уберёт его.
"""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
release = '--release-https' in sys.argv
APP_NAME = 'Salam!'
LOCATION_TEXT = ('Приложение использует ваше местоположение один раз, чтобы предложить город. '
                 'Координаты не сохраняются — запоминаются только город и регион.')


def patch_android():
    manifest = root / 'android/app/src/main/AndroidManifest.xml'
    if not manifest.exists():
        print('android/: не найдено — пропускаю (создайте: flutter create --platforms=android .)')
        return
    s = manifest.read_text(encoding='utf-8')
    perms = ['android.permission.INTERNET', 'android.permission.ACCESS_COARSE_LOCATION']
    for p in perms:
        if p not in s:
            s = re.sub(r'(<manifest[^>]*>)', r'\1\n    <uses-permission android:name="%s"/>' % p, s, count=1)
    s = re.sub(r'android:label="[^"]*"', 'android:label="%s"' % APP_NAME, s, count=1)
    has_clear = 'android:usesCleartextTraffic' in s
    if release:
        s = re.sub(r'\s*android:usesCleartextTraffic="[^"]*"', '', s)
    elif not has_clear:
        s = re.sub(r'(<application)', r'\1\n        android:usesCleartextTraffic="true"', s, count=1)
    manifest.write_text(s, encoding='utf-8')
    print('Android: разрешения и название обновлены' + (' (http отключён)' if release else ' (http для разработки разрешён)'))


def plist_set(s, key, value_xml):
    """Задаёт строковое значение ключа в Info.plist (заменяет или добавляет перед </dict>)."""
    pattern = re.compile(r'(<key>%s</key>\s*)<string>.*?</string>' % re.escape(key), re.S)
    if pattern.search(s):
        return pattern.sub(lambda m: m.group(1) + value_xml, s, count=1)
    idx = s.rfind('</dict>')
    return s[:idx] + '\t<key>%s</key>\n\t%s\n' % (key, value_xml) + s[idx:]


def patch_ios():
    plist = root / 'ios/Runner/Info.plist'
    if not plist.exists():
        print('ios/: не найдено — пропускаю (создайте: flutter create --platforms=ios .)')
        return
    s = plist.read_text(encoding='utf-8')
    s = plist_set(s, 'NSLocationWhenInUseUsageDescription', '<string>%s</string>' % LOCATION_TEXT)
    s = plist_set(s, 'CFBundleDisplayName', '<string>%s</string>' % APP_NAME)
    ats_present = 'NSAppTransportSecurity' in s
    if release:
        s = re.sub(r'\s*<key>NSAppTransportSecurity</key>\s*<dict>.*?</dict>', '', s, flags=re.S)
    elif not ats_present:
        idx = s.rfind('</dict>')
        s = s[:idx] + '\t<key>NSAppTransportSecurity</key>\n\t<dict>\n\t\t<key>NSAllowsLocalNetworking</key>\n\t\t<true/>\n\t</dict>\n' + s[idx:]
    plist.write_text(s, encoding='utf-8')
    print('iOS: текст запроса геолокации и название обновлены' + (' (исключение http убрано)' if release else ''))


patch_android()
patch_ios()
