#!/usr/bin/env python3
"""Урезает шрифты Inter до символов, которые нужны приложению, и проверяет покрытие.

Полный Inter — около 2 900 знаков (греческий, вьетнамский, математика…), приложению
нужны латиница, кириллица с буквами таджикского, казахского и кыргызского (ғ ӣ қ ӯ ҳ ҷ ү ө ң ә і),
узбекский ʻ и типографика. Урезанные файлы в 3–4 раза меньше. Лицензия OFL 1.1 без
Reserved Font Name такие изменения разрешает (assets/fonts/LICENSE-Inter.txt).

  python3 tool/subset_fonts.py subset ПАПКА_С_ПОЛНЫМИ_OTF   # пересобрать assets/fonts/*.otf
  python3 tool/subset_fonts.py check                         # все символы текстов есть в шрифтах?

Тексты для проверки: assets/i18n/*.json (тексты интерфейса), ../content/**/*.json
(документы, учреждения, советы — их показывает приложение) и строки в lib/**/*.dart.
Знаки вне шрифта (эмодзи и т. п.) Flutter всё равно берёт из системного шрифта — они
в проверке не участвуют, см. FALLBACK_OK.

Нужен fontTools: pip install fonttools
"""
import json
import pathlib
import sys
import unicodedata

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = pathlib.Path(__file__).resolve().parent.parent  # mobile/
FONTS = ROOT / "assets" / "fonts"
FILES = [
    "Inter-Regular.otf", "Inter-Italic.otf", "Inter-Medium.otf", "Inter-SemiBold.otf",
    "Inter-Bold.otf", "Inter-ExtraBold.otf", "InterDisplay-ExtraBold.otf",
]

# Блоки Юникода, которые оставляем целиком (с запасом на новые тексты).
RANGES = [
    (0x0020, 0x007E),  # ASCII
    (0x00A0, 0x024F),  # Latin-1, Latin Extended-A/B: «», №-соседи, ё-подобные латинские
    (0x02B0, 0x02FF),  # модификаторы: узбекский ʻ (U+02BB), ʼ
    (0x0300, 0x036F),  # комбинируемые диакритики
    (0x0400, 0x052F),  # кириллица + дополнение: ғ ӣ қ ӯ ҳ ҷ ү ұ ө ң ә һ і
    (0x2000, 0x206F),  # пунктуация: — – … ‘ ’ “ ” „ • ‹ ›
    (0x20A0, 0x20CF),  # валюты: ₽ ₸ ₼ €
    (0x2100, 0x214F),  # № ℃ ™
    (0x2190, 0x21FF),  # стрелки
    (0x2200, 0x22FF),  # − × ≈ ≠ ≤ ≥ ∞
    (0x25A0, 0x25FF),  # ● ▪ ◦
]

# Категории знаков, для которых допустим системный шрифт (эмодзи, служебные символы).
FALLBACK_OK = {"So", "Cn", "Co", "Cs", "Cc", "Cf", "Zl", "Zp"}


def used_text() -> str:
    parts = []
    for p in sorted((ROOT / "assets" / "i18n").glob("*.json")):
        parts.append(p.read_text(encoding="utf-8"))
    for p in sorted((ROOT.parent / "content").rglob("*.json")):
        parts.append(json.dumps(json.loads(p.read_text(encoding="utf-8")), ensure_ascii=False))
    for p in sorted((ROOT / "lib").rglob("*.dart")):
        parts.append(p.read_text(encoding="utf-8"))
    return "".join(parts)


def needed_chars(text: str) -> set[int]:
    return {ord(c) for c in set(text) if unicodedata.category(c) not in FALLBACK_OK and not c.isspace()}


def keep_codepoints(text: str) -> set[int]:
    keep = set()
    for a, b in RANGES:
        keep.update(range(a, b + 1))
    return keep | needed_chars(text)


def do_subset(src_dir: pathlib.Path) -> None:
    text = used_text()
    unicodes = sorted(keep_codepoints(text))
    for name in FILES:
        src = src_dir / name
        opts = subset.Options()
        # Только то, что Flutter (HarfBuzz) включает сам: kern, liga, calt, ccmp, locl, mark…
        # Стилистические наборы Inter (ss01–ss08, cv01–cv13, case, tnum, zero) — ~850 запасных
        # глифов, а приложение FontFeature не запрашивает. Понадобятся — допишите сюда.
        opts.layout_features = subset.Options().layout_features
        opts.name_IDs = ["*"]
        opts.name_languages = ["*"]
        opts.notdef_outline = True
        opts.glyph_names = False
        font = subset.load_font(str(src), opts)
        sub = subset.Subsetter(opts)
        sub.populate(unicodes=unicodes)
        sub.subset(font)
        out = FONTS / name
        subset.save_font(font, str(out), opts)
        print(f"{name}: {src.stat().st_size // 1024} КБ → {out.stat().st_size // 1024} КБ")


def do_check() -> int:
    need = needed_chars(used_text())
    bad = 0
    for name in FILES:
        cmap = TTFont(str(FONTS / name)).getBestCmap()
        missing = sorted(cp for cp in need if cp not in cmap)
        if missing:
            bad += 1
            shown = " ".join(f"{chr(cp)} U+{cp:04X}" for cp in missing[:30])
            print(f"{name}: нет {len(missing)} знаков: {shown}")
    if bad:
        print("Добавьте нужный блок в RANGES и пересоберите шрифты: tool/subset_fonts.py subset <полные OTF>")
        return 1
    print(f"OK: все {len(need)} знаков текстов есть во всех {len(FILES)} шрифтах.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "check":
        sys.exit(do_check())
    if len(sys.argv) == 3 and sys.argv[1] == "subset":
        do_subset(pathlib.Path(sys.argv[2]))
        sys.exit(do_check())
    print(__doc__)
    sys.exit(2)
