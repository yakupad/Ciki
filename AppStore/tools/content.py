"""App Store içeriğinin tek kaynağı: ekran başlıkları, cihaz ölçüleri, yaratıcı görseller,
hedef kitleye özel ürün sayfaları (CPP) ve ürün sayfası optimizasyonu (PPO) testleri.

Kullanım:
    python3 content.py <ham-görüntü-klasörü>
Çıktı: tools/jobs.json (compose.swift için) ve AppStore/asset-library.json.
Ham görüntüler kurgusal örnek veriyle (Deniz ve Ece) alınır; gerçek kişisel veri kullanılmaz.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # AppStore/
LOCALES = {"tr": "tr", "en": "en-US"}

# Ekran -> (başlık, alt başlık); mağazadaki varsayılan sıra bu listenin sırasıdır.
SCREENS = {
    "ozet": {
        "tr": ("Ay sonunu bugünden gör", "Gelir, gider ve borç tek ekranda"),
        "en": ("See your month-end today", "Income, bills and debt on one screen"),
    },
    "aylar": {
        "tr": ("Ödendi mi? Kaydır, geç", "Kart, kredi ve kira bankaya göre düzenli"),
        "en": ("Paid? Just swipe", "Cards, loans and rent, grouped by bank"),
    },
    "tablo": {
        "tr": ("Excel tablon artık cebinde", "Aylar yan yana, kalemler alt alta"),
        "en": ("Your spreadsheet, in your pocket", "Months across, items down"),
    },
    "karsilama": {
        "tr": ("Hanece, birlikte", "Eş, aile ve ev arkadaşları aynı kayıtları görür"),
        "en": ("Shared with your household", "Partner, family and housemates see the same entries"),
    },
    "rapor": {
        "tr": ("Paran nereye gidiyor, gör", "Birikimli bakiye, kart ve kredi raporu"),
        "en": ("See where your money goes", "Running balance plus card and loan report"),
    },
    "kalemler": {
        "tr": ("TL, dolar, euro bir arada", "Düzenli ödemeler ve TCMB kurlarıyla çeviri"),
        "en": ("Lira, dollar and euro together", "Recurring payments at central bank rates"),
    },
}
DEFAULT_ORDER = ["ozet", "aylar", "tablo", "karsilama", "rapor", "kalemler"]

# App Store Connect ekran görüntüsü ölçüleri (developer.apple.com, screenshot specifications)
DEVICES = {
    "iPhone-6.9": {"size": (1320, 2868), "raw": "iphone69_{L}_{S}", "layout": "phone", "screens": DEFAULT_ORDER},
    "iPhone-6.3": {"size": (1206, 2622), "raw": "iphone63_{L}_{S}", "layout": "phone", "screens": DEFAULT_ORDER, "required": True},
    "iPad-13": {"size": (2064, 2752), "raw": "ipad_{L}_{S}", "layout": "tablet", "screens": ["ozet", "tablo", "rapor"], "required": True},
    "Mac": {"size": (2880, 1800), "raw": "mac_{L}_{S}", "layout": "mac", "screens": ["ozet", "aylar", "tablo"],
            "rawKey": {"ozet": "0", "aylar": "1", "tablo": "2"}, "required": True},
    "iPhone-Duo-Inner": {"size": (2853, 2007), "raw": "duoinner_{L}_{S}", "layout": "duoInner", "screens": ["ozet"],
                         "note": "App Store Connect'te bu cihaz için yükleme 'bu yıl içinde' açılacak."},
    "iPhone-Duo-Outer": {"size": (1398, 2034), "raw": "duoouter_{L}_{S}", "layout": "duoOuter", "screens": ["ozet"],
                         "note": "App Store Connect'te bu cihaz için yükleme 'bu yıl içinde' açılacak."},
}
WATCH = {"size": (422, 514), "raw": "watch_{L}_{S}", "screens": ["0", "1"], "names": {"0": "ozet", "1": "odemeler"}}

# Yaratıcı görseller (Asset Library): ölçüler Apple şablonlarından
CREATIVE = {
    "header-urun": {"size": (3840, 1646), "layout": "header", "type": "productPageHeader",
                    "shots": ["ozet", "aylar", "rapor"]},
    "header-marka": {"size": (3840, 1646), "layout": "headerBrand", "type": "productPageHeader",
                     "tr": ("Çıkı", "Hanenin ortak bütçesi: borç, ödeme ve kira takibi"),
                     "en": ("Çıkı", "Your household's shared budget for bills, debts and rent")},
    "search-varsayilan": {"size": (3840, 2560), "layout": "search", "type": "searchResults", "shots": ["ozet"],
                          "screen": "ozet"},
    "universal": {"size": (5244, 2950), "layout": "universal", "type": "universal", "shots": ["ozet", "aylar", "rapor"],
                  "tr": ("Hanenin bütçesi, tek bir çıkıda", None), "en": ("Your household budget, all tied together", None)},
}

# Hedef kitleye özel ürün sayfaları (Custom Product Pages)
CPPS = [
    {
        "id": "aile",
        "name": {"tr": "Aile bütçesi", "en": "Family budget"},
        "audience": "Bütçesini eşiyle ya da ailesiyle birlikte yöneten haneler",
        "keywords": {"tr": ["aile bütçesi", "ev bütçesi", "ortak bütçe", "eş"], "en": ["family budget", "household budget", "shared budget", "couples"]},
        "promotional_text": {
            "tr": "Ailenin bütün ödemeleri tek yerde. Eşinizle iCloud üzerinden aynı kayıtları görün, kimin neyi ödediğini bilin.",
            "en": "All of your family's payments in one place. See the same entries as your partner over iCloud and know who paid what.",
        },
        "order": ["karsilama", "ozet", "aylar", "rapor", "tablo", "kalemler"],
        "search": {"shot": "karsilama", "tr": ("Ailenin bütçesi, birlikte", "Eşinizle aynı kayıtları görün"),
                   "en": ("Your family budget, together", "See the same entries as your partner")},
        "header": "header-urun",
    },
    {
        "id": "ev-arkadaslari",
        "name": {"tr": "Ev arkadaşları", "en": "Housemates"},
        "audience": "Kira, aidat ve faturaları ev arkadaşlarıyla paylaşanlar",
        "keywords": {"tr": ["ev arkadaşı", "kira paylaşımı", "fatura bölüşme", "aidat"], "en": ["housemates", "roommates", "split rent", "split bills"]},
        "promotional_text": {
            "tr": "Kira, aidat ve faturalar ortak kalem olsun. Herkes kendi telefonundan görsün, ödendi işaretlesin.",
            "en": "Make rent, building fees and bills shared items. Everyone sees them on their own phone and marks them paid.",
        },
        "order": ["aylar", "karsilama", "ozet", "tablo", "kalemler", "rapor"],
        "search": {"shot": "aylar", "tr": ("Kira ve faturalar, ortak", "Ev arkadaşlarınızla aynı listeyi görün"),
                   "en": ("Rent and bills, shared", "See the same list as your housemates")},
        "header": "header-urun",
    },
    {
        "id": "kart-borc",
        "name": {"tr": "Kart ve borç takibi", "en": "Card and debt tracking"},
        "audience": "Kredi kartı ekstresi, nakit avans ve kredi taksitlerini takip edenler",
        "keywords": {"tr": ["kredi kartı", "ekstre", "kredi taksiti", "borç takibi"], "en": ["credit card", "debt tracker", "loan payments", "statement"]},
        "promotional_text": {
            "tr": "Kart ekstreleri, nakit avans ve kredi taksitleri bankaya göre düzenli. Son ödeme günü gelmeden hatırlatma alın.",
            "en": "Card statements, cash advances and loan installments, organized by bank. Get reminded before each due day.",
        },
        "order": ["aylar", "rapor", "ozet", "tablo", "kalemler", "karsilama"],
        "search": {"shot": "rapor", "tr": ("Kart ve kredi borcunu yönet", "Bankaya göre aylık ödemeler ve son ödeme hatırlatması"),
                   "en": ("Stay on top of card debt", "Monthly payments by bank, with due-day reminders")},
        "header": "header-urun",
    },
    {
        "id": "doviz",
        "name": {"tr": "Döviz ödemeleri", "en": "Foreign currency payments"},
        "audience": "Euro ya da dolarla düzenli ödeme yapan, yurt dışına para gönderenler",
        "keywords": {"tr": ["döviz", "euro", "dolar", "kur", "iban"], "en": ["currency", "euro", "dollar", "exchange rate", "iban"]},
        "promotional_text": {
            "tr": "Euro ve dolar ödemeleri TCMB kuruyla TL'ye çevrilir. Ödenenin kuru sabitlenir, IBAN'lar tek dokunuşla kopyalanır.",
            "en": "Euro and dollar payments are converted at central bank rates. Paid rates stay fixed, and IBANs copy with one tap.",
        },
        "order": ["kalemler", "ozet", "aylar", "rapor", "tablo", "karsilama"],
        "search": {"shot": "kalemler", "tr": ("Döviz ödemeleri, TL karşılığıyla", "21 para birimi, TCMB kurlarıyla"),
                   "en": ("Foreign payments in your currency", "21 currencies at central bank rates")},
        "header": "header-urun",
    },
]

# Ürün sayfası optimizasyonu (Product Page Optimization) testleri
PPO_TESTS = [
    {
        "id": "test-1-ilk-mesaj",
        "name": "İlk ekran görüntüsünün mesajı",
        "hypothesis": "Excel alışkanlığına ya da birlikte kullanıma vurgu yapan ilk görsel, genel özet görseline göre daha çok indirme getirir.",
        "locales": ["tr"],
        "traffic": {"control": 25, "A": 25, "B": 25, "C": 25},
        "control": {"order": DEFAULT_ORDER},
        "treatments": {
            "A": {"order": ["tablo", "ozet", "aylar", "karsilama", "rapor", "kalemler"], "message": "Excel tablon artık cebinde"},
            "B": {"order": ["karsilama", "ozet", "aylar", "tablo", "rapor", "kalemler"], "message": "Hanece, birlikte"},
            "C": {"order": ["aylar", "ozet", "tablo", "karsilama", "rapor", "kalemler"], "message": "Ödendi mi? Kaydır, geç"},
        },
        "metric": "Dönüşüm oranı (ürün sayfası görüntülemesinden indirmeye)",
        "duration": "En az 14 gün; anlamlı sonuç için en fazla 90 gün",
        "decision": "Kontrolden en az %90 güvenle daha iyi olan varyasyon varsayılan sıra yapılır.",
    },
    {
        "id": "test-2-baslik-gorseli",
        "name": "Ürün sayfası başlık görseli",
        "hypothesis": "Uygulamanın ekranlarını gösteren başlık, marka (ikon) odaklı başlığa göre daha çok indirme getirir.",
        "locales": ["tr", "en-US"],
        "traffic": {"control": 50, "A": 50},
        "control": {"header": "header-urun"},
        "treatments": {"A": {"header": "header-marka"}},
        "metric": "Dönüşüm oranı",
        "duration": "En az 14 gün",
        "decision": "Kazanan başlık varsayılan olur ve Asset Library'de birincil olarak işaretlenir.",
    },
    {
        "id": "test-3-ikon",
        "name": "Uygulama ikonu (ileride)",
        "hypothesis": "Amber bağın daha baskın olduğu bir ikon aramada daha çok dikkat çeker.",
        "status": "Beklemede: alternatif ikonun uygulama paketine eklenip yeni bir sürümle gönderilmesi gerekir.",
    },
]


def main(raw):
    jobs, assets = [], []
    out_shots = os.path.join(ROOT, "screenshots")
    out_creative = os.path.join(ROOT, "creative")

    def raw_path(name):
        path = os.path.join(raw, name + ".png")
        if not os.path.exists(path):
            raise SystemExit(f"Ham görüntü yok: {path}")
        return path

    for L, loc in LOCALES.items():
        for device, spec in DEVICES.items():
            for index, screen in enumerate(spec["screens"], start=1):
                key = spec.get("rawKey", {}).get(screen, screen)
                headline, subhead = SCREENS[screen][L]
                out = os.path.join(out_shots, loc, device, f"{index:02d}-{screen}.jpg")
                jobs.append({"out": out, "width": spec["size"][0], "height": spec["size"][1], "layout": spec["layout"],
                             "shots": [raw_path(spec["raw"].format(L=L, S=key))], "headline": headline, "subhead": subhead})
                assets.append({"id": f"{loc}/{device}/{screen}", "type": "screenshot", "device": device,
                               "size": f"{spec['size'][0]}x{spec['size'][1]}", "locale": loc, "screen": screen,
                               "file": os.path.relpath(out, ROOT), "headline": headline,
                               "usage": ["default"] + [f"cpp:{c['id']}" for c in CPPS] + (["ppo:test-1-ilk-mesaj"] if device.startswith("iPhone-6") else []),
                               **({"note": spec["note"]} if "note" in spec else {})})
        for screen in WATCH["screens"]:
            name = WATCH["names"][screen]
            out = os.path.join(out_shots, loc, "Watch", f"0{int(screen) + 1}-{name}.jpg")
            jobs.append({"out": out, "width": WATCH["size"][0], "height": WATCH["size"][1], "layout": "raw",
                         "shots": [raw_path(WATCH["raw"].format(L=L, S=screen))]})
            assets.append({"id": f"{loc}/Watch/{name}", "type": "screenshot", "device": "Apple Watch Ultra",
                           "size": "422x514", "locale": loc, "file": os.path.relpath(out, ROOT), "usage": ["default"]})

        shot = lambda s: raw_path(f"iphone69_{L}_{s}")
        for cid, spec in CREATIVE.items():
            ext = "jpg" if spec["layout"] == "search" else "png"  # başlık ve evrensel görsel PNG olmalı
            out = os.path.join(out_creative, loc, f"{cid}-{spec['size'][0]}x{spec['size'][1]}.{ext}")
            headline, subhead = spec.get(L, SCREENS.get(spec.get("screen", ""), {}).get(L, (None, None)))
            job = {"out": out, "width": spec["size"][0], "height": spec["size"][1], "layout": spec["layout"],
                   "shots": [shot(s) for s in spec.get("shots", ["ozet"])], "headline": headline, "subhead": subhead}
            if spec["layout"] == "headerBrand":
                job["icon"] = os.path.join(ROOT, "tools", "icon-1024.png")
            jobs.append(job)
            usage = ["default"] if cid in ("header-urun", "search-varsayilan", "universal") else []
            usage += ["ppo:test-2-baslik-gorseli"] if cid.startswith("header") else []
            usage += [f"cpp:{c['id']}" for c in CPPS if c["header"] == cid]
            assets.append({"id": f"{loc}/creative/{cid}", "type": spec["type"], "size": f"{spec['size'][0]}x{spec['size'][1]}",
                           "locale": loc, "file": os.path.relpath(out, ROOT), "headline": headline, "usage": usage})
        for cpp in CPPS:
            s = cpp["search"]
            out = os.path.join(out_creative, loc, f"search-{cpp['id']}-3840x2560.jpg")
            jobs.append({"out": out, "width": 3840, "height": 2560, "layout": "search",
                         "shots": [shot(s["shot"])], "headline": s[L][0], "subhead": s[L][1]})
            assets.append({"id": f"{loc}/creative/search-{cpp['id']}", "type": "searchResults", "size": "3840x2560",
                           "locale": loc, "file": os.path.relpath(out, ROOT), "headline": s[L][0], "usage": [f"cpp:{cpp['id']}"]})

    with open(os.path.join(ROOT, "tools", "jobs.json"), "w") as f:
        json.dump(jobs, f, ensure_ascii=False, indent=1)
    library = {
        "app": {"name": "Çıkı", "bundleId": "com.yakupad.Ciki", "primaryLocale": "tr"},
        "dataNote": "Görsellerdeki kişi, banka ve tutarlar kurgusaldır (örnek hane: Deniz ve Ece).",
        "defaultProductPage": {"screenshotOrder": DEFAULT_ORDER, "header": "header-urun", "searchResults": "search-varsayilan"},
        "customProductPages": [
            {**{k: v for k, v in c.items() if k != "search"}, "searchResults": f"search-{c['id']}",
             "deepLink": None, "deepLinkNote": "İsteğe bağlı: uygulama ilgili ekranı açan bir bağlantı desteklediğinde eklenir."}
            for c in CPPS
        ],
        "productPageOptimization": PPO_TESTS,
        "assets": assets,
    }
    with open(os.path.join(ROOT, "asset-library.json"), "w") as f:
        json.dump(library, f, ensure_ascii=False, indent=2)
    print(f"{len(jobs)} görsel işi, {len(assets)} varlık kaydı")


if __name__ == "__main__":
    main(sys.argv[1])
