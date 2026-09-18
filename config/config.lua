--[[
    config/config.lua
    -----------------
    Çekirdek yapılandırma. Buradaki her şey veridir — mantık config'te yaşamaz.
    Tüm dosyalar `loeBank` global namespace'ini paylaşır.
]]

loeBank = loeBank or {}

loeBank.Config = {
    -- Ana debug anahtarı. true iken tanılama logları basar (bkz shared/utils.lua).
    debug = false,

    ---------------------------------------------------------------------------
    -- BANKA KİMLİĞİ (NUI'da gösterilir)
    ---------------------------------------------------------------------------
    bank = {
        name    = 'LOS SANTOS BANK',
        tagline = 'Your Money. A Stronger Los Santos.',
    },

    ---------------------------------------------------------------------------
    -- NPC (gişe görevlisi)
    ---------------------------------------------------------------------------
    ped = {
        -- Alta St Fleeca gişesi. x/y/heading kullanıcının verdiği değer; z,
        -- 53.16'dan Fleeca zemin hizasına (~54.17) yükseltildi — 53.16 zeminin
        -- ~1 m altındaydı, ped görünmüyordu. Kendi noktanı ayarlamak için
        -- oyunda istediğin yere geç ve  /bankhere  yaz: konsola tam vec4 basar.
        coords   = vec4(313.84, -280.46, 54.17, 340.96),
        -- Oyun ped modeli (client'ta hash'lenir). Klasik banka görevlisi.
        -- Yüklenemezse sırayla `modelFallbacks` denenir.
        model          = 'ig_bankman',
        modelFallbacks = { 'a_m_y_business_01', 'a_m_m_business_01', 'mp_m_shopkeep_01' },
        -- Ambiyans senaryosu (nil = senaryo yok). Gişe arkasında bekler.
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        -- Z ince ayarı (metre). Ped havada kalırsa azalt, yere gömülürse artır.
        zOffset  = 0.0,
        -- true iken ped, verilen z yerine o noktadaki ZEMİN yüksekliğine oturur
        -- AMA sadece bulunan zemin verilen z'ye ±3 m yakınsa (yanlış kata/araziye
        -- ışınlanmayı önler). Doğru z'yi biliyorsan false bırak. Varsayılan: kapalı.
        snapToGround  = false,
        -- Oyuncu bu mesafeye (metre) girince ped spawn edilir, uzaklaşınca
        -- silinir. Bölge stream'e girmişken (collision hazır) oluşturulur.
        spawnDistance = 120.0,
    },

    ---------------------------------------------------------------------------
    -- ETKİLEŞİM (E tuşu)
    ---------------------------------------------------------------------------
    interaction = {
        key      = 38,        -- 38 = INPUT_PICKUP = "E"
        keyLabel = 'E',
        distance = 2.0,       -- panelin açılabildiği maksimum mesafe (metre)
        helpText = 'bankacılık işlemleri için',
    },

    ---------------------------------------------------------------------------
    -- HARİTA BLIP'İ
    ---------------------------------------------------------------------------
    blip = {
        enabled    = true,
        sprite     = 108,   -- banka ikonu
        color      = 2,     -- yeşil
        scale      = 0.8,
        shortRange = true,
    },

    ---------------------------------------------------------------------------
    -- LİMİTLER / KURALLAR (hepsi server'da uygulanır)
    ---------------------------------------------------------------------------
    limits = {
        -- Tek işlemde izin verilen en düşük tutar.
        minAmount   = 1,
        -- Tek işlemde izin verilen en yüksek tutar. 0 = sınırsız.
        maxDeposit  = 0,
        maxWithdraw = 0,
        maxTransfer = 0,
        -- Havale ücreti: gönderenin bankasından `tutar + ücret` düşülür,
        -- alıcı `tutar` kadar alır. 0.0 = ücretsiz. Örn 0.02 = %2.
        transferFee = 0.0,
        -- Havale ücretinin taban/tavan sınırı ($). 0 = sınır yok.
        transferFeeMin = 0,
        transferFeeMax = 0,
    },

    ---------------------------------------------------------------------------
    -- BAĞIŞ (sol alttaki "DAHA GÜÇLÜ BİR LOS SANTOS İÇİN — BAĞIŞ" kartı)
    ---------------------------------------------------------------------------
    donation = {
        -- Bağış hangi hesaptan çekilsin: 'bank' | 'cash'
        account = 'bank',
        -- Tek bağışta üst sınır ($). 0 = sınırsız.
        max     = 0,
        -- Bağış tamamlanınca çağrılır (opsiyonel). Sunucuda bir devlet/society
        -- banka sistemi varsa parayı oraya buradan aktarabilirsin; tanımlı
        -- değilse bağış yalnızca ekonomiden düşülür (para sink) + geçmişe yazılır.
        -- örn:
        --   onDonate = function(src, citizenid, amount)
        --       exports.some_banking:AddSocietyMoney('government', amount)
        --   end,
        onDonate = nil,
    },

    ---------------------------------------------------------------------------
    -- İŞLEM GEÇMİŞİ
    ---------------------------------------------------------------------------
    history = {
        -- NUI "Son İşlemler" panelinde gösterilecek kayıt sayısı.
        limit = 20,
        -- oxmysql tablo adı. sql/loe_bank.sql ile aynı olmalı.
        table = 'loe_bank_transactions',
    },
}

