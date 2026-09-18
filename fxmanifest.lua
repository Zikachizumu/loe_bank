fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'loe_bank'
author 'loe Framework'
description 'Los Santos Bank — NPC bankacılık: nakit/banka para yatır-çek + banka hesap no ile havale (Qbox)'
version '0.1.0'

--[[
    loe Bank
    ------------
    Qbox framework'ü için standalone bir NPC bankacılık resource'u. Belirlenen
    konumda E tuşuyla etkileşime giren bir gişe görevlisi (ped) açar; banka
    paneli tasarımlı bir NUI ile:

        - Hesap Özeti      -> nakit + banka bakiyesi, hesap no, hızlı işlemler
        - Para Yatır       -> nakit -> banka
        - Para Çek         -> banka -> nakit
        - Havale / EFT     -> banka -> başka oyuncunun bankası (hesap no ile;
                              hedef offline olsa bile çalışır)
        - Son İşlemler     -> kalıcı işlem geçmişi (oxmysql tablosu)

    Server-authoritative: tutar/limit/bakiye kontrolü ve tüm para hareketi
    tamamen server'da qbx_core (AddMoney/RemoveMoney) ile yapılır. Client'tan
    yalnızca "ne kadar / hangi hesaba" bilgisi gelir.

    Dependencies (bu resource tarafından ASLA değiştirilmez):
        - qbx_core     (oyuncu / para: cash | bank, charinfo.account)
        - ox_lib       (TextUI, callback, requestModel)
        - oxmysql      (işlem geçmişi tablosu)

    Mimari (loe_724 ile aynı):
        config/  -> saf veri: NPC konumu, etkileşim, limitler, blip
        shared/  -> client + server ortak yardımcılar (tutar doğrulama, format)
        client/  -> ped spawn, yakınlık + E, NUI köprüsü
        server/  -> işlem doğrulama + para hareketi + geçmiş kaydı
        web/     -> NUI (index.html / css / js)
        sql/     -> işlem geçmişi tablosu (server ilk başlarken de otomatik kurulur)
]]

dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql',
}

-- ox_lib her şeyden önce yüklenmeli.
shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'shared/utils.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/style.css',
    'web/js/app.js',
}

