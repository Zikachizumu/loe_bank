# loe_bank

Qbox framework'ü için **standalone NPC bankacılık** resource'u. Belirlenen
konumda `E` tuşuyla etkileşime giren bir gişe görevlisi (ped) açar; **"Los Santos
Bank" tasarımlı** özel bir NUI ile nakit ↔ banka para yatırma/çekme ve **banka
hesap numarası** üzerinden başka oyunculara havale yaptırır.

`loe_724` / `loe_weaponshop` ile **aynı mimariyi** paylaşır
(`config/` · `shared/` · `client/` · `server/` · `web/`).

## Özellikler

- **NPC + E etkileşimi** — `vec4(313.84, -280.46, 54.17, 340.96)` (Alta St
  Fleeca). Yakınlıkta ox_lib TextUI ipucu, `E` ile panel açılır. `ESC` ile kapanır.
- **Banka hesap numarası** — her karaktere bu resource **4 haneli** (harf+rakam,
  kendi içinde tekrarsız, GLOBAL benzersiz — ör. `K7P2`) bir kod atar.
  `loe_bank_accounts` tablosunda tutulur, qbx `charinfo.account`'tan
  bağımsızdır. Server açılışında mevcut tüm karakterlere, sonra her yeni girişte
  atanır. Karışan karakterler (0/O, 1/I) kullanılmaz.
- **Hesap Özeti** — nakit + banka bakiyesi, hesap no'su (kopyala düğmesiyle),
  hızlı işlem kısayolları, alt istatistikler (Nakit / Banka / Toplam Varlık /
  Son 24 saat). Sağ üstte "Bakiyeyi gizle" ile bakiye bulanıklaştırılır.
- **Para Yatır / Para Çek** — nakit ↔ banka. Hızlı tutar butonları **yüzde**
  bazlı: %25 / %50 / %75 / %100 (Yatır'da nakdin, Çek'te bankanın yüzdesi).
- **Havale / EFT** — banka bakiyesinden, girilen **4 haneli hesap no**'daki
  oyuncunun banka hesabına para gönderir. Hedef **offline olsa bile** çalışır
  (qbx offline para API'si). Opsiyonel açıklama + yapılandırılabilir havale
  ücreti. Hızlı butonlar burada sabit tutar (100…10.000 + Tümü).
- **Bağış** — sol alttaki "DAHA GÜÇLÜ BİR LOS SANTOS İÇİN — BAĞIŞ YAP" kartı ya
  da menüden açılır. Banka bakiyesinden Los Santos hazinesine bağış yaptırır
  (para sink + geçmiş; toplam bağış panelde gösterilir). `Config.donation.onDonate`
  ile ileride bir devlet/society banka hesabına aktarılabilir.
- **Kopyalanabilir hesap no** — hesap kartındaki kodun yanındaki kopyala düğmesi
  panoya alır (chat'e yapıştır → karşı taraf havale ekranına yapıştırır).
- **Son İşlemler** — kalıcı işlem geçmişi (`loe_bank_transactions` tablosu).
  Panel her işlemden sonra otomatik tazelenir; başka birinden havale gelince de
  (açıkken) güncellenir.
- **Server-authoritative** — tutar, limit, bakiye ve tüm para hareketi tamamen
  server'da `qbx_core` (`AddMoney` / `RemoveMoney`) ile yapılır. Client'tan
  yalnızca "ne kadar / hangi hesaba" bilgisi gelir; gönderilen hiçbir
  bakiye/isim değerine güvenilmez. Havalede önce gönderenden düşülür, alıcıya
  eklenemezse tutar iade edilir.

## Kurulum

1. Klasörü `resources/[loe]/loe_bank` altına koy.
2. `server.cfg` → `ensure loe_bank` (qbx_core, ox_lib, oxmysql'den **sonra**).
3. İşlem geçmişi tablosu: server ilk başlarken **otomatik** kurulur
   (`CREATE TABLE IF NOT EXISTS`). Elle kurmak istersen `sql/loe_bank.sql`.

## Bağımlılıklar

Bu resource bağımlılıkları **asla değiştirmez**:

- `qbx_core` — oyuncu / para (`cash` | `bank`), oyuncu adı, offline para API
- `ox_lib` — TextUI, callback, requestModel
- `oxmysql` — işlem geçmişi + hesap no tabloları

## Yapı

```
config/config.lua    NPC konumu, etkileşim, limitler/ücret, bağış, blip, banka adı
shared/utils.lua     tutar doğrulama + para formatı + hesap-no normalize/üretim
client/main.lua      ped, blip, yakınlık + E, NUI köprüsü, /bankhere /bankped
server/main.lua      hesap no atama + getData/deposit/withdraw/transfer/donate + geçmiş
web/                 NUI (index.html / css / js)
sql/loe_bank.sql tablolar (transactions + accounts)
```

## Yapılandırma ipuçları

- **Konum / ped**: `config/config.lua` → `Config.ped`. Ped, oyuncu
  `spawnDistance` metreye girince oluşturulur. Model yüklenmezse `modelFallbacks`
  sırayla denenir; hepsi başarısızsa konsola `^1[loe_bank]` uyarısı düşer.
- **Kendi noktanı ayarlamak**: oyunda gişenin arkasında dur, `/bankhere` yaz →
  konsola ve ekrana tam `vec4(...)` basar; onu `Config.ped.coords`'a yapıştır.
- **Teşhis**: `/bankped` ped'i sil+yeniden oluşturur ve durumu bildirir
  ("ped var / OLUŞMADI"). İlk başarılı spawn'da konsola bir kez
  `^2[loe_bank] gişe ped'i oluşturuldu ... konum=x,y,z` satırı düşer.
- **Ped görünmüyor**: neredeyse her zaman z yanlıştır (zeminin altında). `/bankhere`
  ile doğru z'yi al, ya da `Config.ped.zOffset` ile oynat. `snapToGround = true`
  yaparsan verilen z'ye ±3 m yakın bir zemin bulunursa oraya oturur.
- **Banka adı / slogan**: `Config.bank.name` / `Config.bank.tagline` (NUI'da
  marka ve hesap kartında görünür).
- **Limitler**: `Config.limits` — `minAmount`, `maxDeposit/Withdraw/Transfer`
  (`0` = sınırsız).
- **Havale ücreti**: `Config.limits.transferFee` (`0.0` = ücretsiz, `0.02` = %2)
  + `transferFeeMin` / `transferFeeMax` taban-tavan (`0` = sınır yok). Ücret
  gönderenin bankasından `tutar + ücret` olarak düşülür.
- **Bağış**: `Config.donation.account` (`'bank'` | `'cash'`), `Config.donation.max`
  (`0` = sınırsız), `Config.donation.onDonate` (opsiyonel fonksiyon — parayı bir
  devlet/society hesabına aktarmak için).
- **Geçmiş uzunluğu**: `Config.history.limit` (NUI "Son İşlemler" satır sayısı).

## Hesap no + Havale hakkında

- Her karaktere 4 haneli (harf+rakam, tekrarsız, benzersiz — ör. `K7P2`) bir kod
  atanır (`loe_bank_accounts` tablosu). Oyuncunun kendi kodu hesap kartında +
  sağ üstteki müşteri kartında yazılı, kopyala düğmesi var.
- Server açılışında `players` tablosundaki her karaktere kod atanır (bir kerelik,
  idempotent). Yeni giriş / karakter değişiminde `QBCore:Server:PlayerLoaded` ile
  atanır. Kod eşleşmesi bellekte cache'lenir.
- Havalede hedef, girilen 4 haneli kodla bulunur → `citizenid` → online ise
  online, değilse offline banka hesabına yazılır.
- Kendine havale engellidir. Hedef bulunamazsa / bakiye yetmezse işlem hiç
  başlamaz. Alıcı online ise bir bildirim alır.
- Sunucu ID'si ile havale **bilerek** kullanılmadı (istenirse sonradan eklenir).

## Notlar

- Panel `ESC` / `Backspace` (yazarken hariç) veya sağ üstteki `×` / çıkış
  simgesiyle kapanır.
- `Faturalar` / `Yatırımlar` / `Kredi` menüde **"YAKINDA"** olarak durur —
  ileride bu resource'a eklenecek modüllerin yeri.
- Ürün/eşya satışı bu resource'ta **yoktur**; market ayrı resource'tur
  (`loe_724`).

