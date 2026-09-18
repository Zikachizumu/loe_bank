--[[
    server/main.lua
    ---------------
    Tek sorumluluk: bankacılık isteklerini DOĞRULAMAK, para hareketini
    gerçekleştirmek ve geçmişe yazmak.

    Güvenlik ilkesi: client yalnızca "ne kadar / hangi hesaba" bilgisi gönderir.
    Tutar, limit, bakiye ve tüm para hareketi server'da qbx_core ile yapılır.
    Client'ın gönderdiği hiçbir bakiye/isim bilgisine güvenilmez.

        deposit   : nakit  -> banka   (kendi hesabın)
        withdraw  : banka  -> nakit   (kendi hesabın)
        transfer  : banka  -> banka   (hedef: 4 haneli banka hesap no; online/offline)

    Banka hesap no'su: her karaktere bu resource tarafından atanan, 4 haneli
    (harf+rakam, tekrarsız, global benzersiz) bir kod. `loe_bank_accounts`
    tablosunda tutulur; qbx charinfo.account'tan bağımsızdır.
]]

local Config = loeBank.Config
local Utils  = loeBank.Utils

local TABLE   = Config.history.table
local ACCTBL  = 'loe_bank_accounts'
local HISTORY = math.max(1, math.floor(tonumber(Config.history.limit) or 20))

math.randomseed(os.time() + (GetGameTimer and GetGameTimer() or 0))

-- Aşağıda tanımlanır; tablo kurulum thread'i backfill için kullanıyor.
local assignAccount

---------------------------------------------------------------------------
-- TABLOLAR (server ilk başlarken otomatik kurulur — sql/loe_bank.sql ile eş)
--   Collation qbx `players` tablosuyla AYNI olmalı (utf8mb4_unicode_ci); aksi
--   halde citizenid karşılaştırmaları "Illegal mix of collations" verir.
---------------------------------------------------------------------------
--- Tablo collation'ı players ile eşit değilse düzeltir (mevcut kurulumları da
--- kurtarır — yanlış collation ile açılmış tabloları).
local function alignCollation(tbl)
    local ok, row = pcall(function()
        return MySQL.single.await(
            'SELECT TABLE_COLLATION AS c FROM information_schema.TABLES '
            .. 'WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', { tbl }
        )
    end)
    if ok and row and row.c and row.c ~= 'utf8mb4_unicode_ci' then
        pcall(function()
            MySQL.query.await(
                ('ALTER TABLE `%s` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci'):format(tbl)
            )
        end)
        Utils.log(('%s collation -> utf8mb4_unicode_ci (%s idi)'):format(tbl, row.c))
    end
end

CreateThread(function()
    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `id`           INT UNSIGNED    NOT NULL AUTO_INCREMENT,
            `citizenid`    VARCHAR(50)     NOT NULL,
            `type`         VARCHAR(24)     NOT NULL,
            `amount`       BIGINT          NOT NULL,
            `balance`      BIGINT          NOT NULL,
            `title`        VARCHAR(64)     NOT NULL,
            `description`  VARCHAR(160)             DEFAULT NULL,
            `counterparty` VARCHAR(64)              DEFAULT NULL,
            `created_at`   TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_cid_id` (`citizenid`, `id`),
            KEY `idx_type` (`type`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]]):format(TABLE))

    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `citizenid`  VARCHAR(50) NOT NULL,
            `account`    VARCHAR(8)  NOT NULL,
            `created_at` TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`citizenid`),
            UNIQUE KEY `uniq_account` (`account`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]]):format(ACCTBL))

    alignCollation(TABLE)
    alignCollation(ACCTBL)
    Utils.log('tablolar hazır:', TABLE, ACCTBL)

    -- Hesap no'su olmayan tüm karakterlere kod ata (bir kerelik, idempotent).
    -- Fark Lua'da hesaplanır — SQL'de kolon-kolon karşılaştırması YOK (collation
    -- uyuşmazlığından etkilenmez).
    local players = MySQL.query.await('SELECT `citizenid` FROM `players`') or {}
    local existing = MySQL.query.await(('SELECT `citizenid` FROM `%s`'):format(ACCTBL)) or {}

    local have = {}
    for _, r in ipairs(existing) do have[r.citizenid] = true end

    local n = 0
    for _, r in ipairs(players) do
        if r.citizenid and not have[r.citizenid] then
            if assignAccount(r.citizenid) then n = n + 1 end
        end
    end
    if n > 0 then Utils.log(('%d karaktere banka hesap no atandı'):format(n)) end
end)

---------------------------------------------------------------------------
-- YARDIMCILAR
---------------------------------------------------------------------------
local function playerName(player)
    local ci = player.PlayerData.charinfo
    if ci and ci.firstname then
        return ci.firstname .. (ci.lastname and (' ' .. ci.lastname) or '')
    end
    return GetPlayerName(player.PlayerData.source) or 'Müşteri'
end

---------------------------------------------------------------------------
-- BANKA HESAP NUMARASI (4 hane, harf+rakam, tekrarsız, global benzersiz)
--   `loe_bank_accounts` tablosunda tutulur; qbx charinfo.account'tan ayrı.
---------------------------------------------------------------------------
local accountCache = {}   -- citizenid -> code (bellekte)

--- Karaktere hesap no'su döndürür; yoksa üretip kaydeder. (function = yukarıda
--- forward-declare edilen local'e atanıyor.)
function assignAccount(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' then return nil end
    if accountCache[citizenid] then return accountCache[citizenid] end

    local existing = MySQL.single.await(
        ('SELECT `account` FROM `%s` WHERE `citizenid` = ? LIMIT 1'):format(ACCTBL), { citizenid }
    )
    if existing and existing.account then
        accountCache[citizenid] = existing.account
        return existing.account
    end

    for _ = 1, 50 do
        local code = Utils.genAccountCode()
        if code then
            -- account UNIQUE veya citizenid PK çakışırsa sessizce atlanır.
            MySQL.insert.await(
                ('INSERT IGNORE INTO `%s` (`citizenid`, `account`) VALUES (?, ?)'):format(ACCTBL),
                { citizenid, code }
            )
            local row = MySQL.single.await(
                ('SELECT `account` FROM `%s` WHERE `citizenid` = ? LIMIT 1'):format(ACCTBL), { citizenid }
            )
            if row and row.account then
                accountCache[citizenid] = row.account
                return row.account
            end
        end
    end
    return nil
end

--- citizenid -> hesap no (bellekten hızlı; yoksa üretir).
local function accountOf(citizenid)
    return assignAccount(citizenid)
end

--- hesap no -> citizenid (havale hedefi bulmak için).
local function citizenidByAccount(account)
    local row = MySQL.single.await(
        ('SELECT `citizenid` FROM `%s` WHERE `account` = ? LIMIT 1'):format(ACCTBL), { account }
    )
    return row and row.citizenid or nil
end

-- Yeni giren / karakter değiştiren oyuncuya hesap no garanti et.
AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local cid = player and player.PlayerData and player.PlayerData.citizenid
    if cid then
        CreateThread(function() assignAccount(cid) end)
    end
end)

--- Bir oyuncunun son işlemlerini NUI'nin beklediği biçimde döner.
local function recentTransactions(citizenid)
    local rows = MySQL.query.await(
        ('SELECT `type`, `amount`, `balance`, `title`, `description`, `counterparty`, UNIX_TIMESTAMP(`created_at`) AS ts '
        .. 'FROM `%s` WHERE `citizenid` = ? ORDER BY `id` DESC LIMIT %d'):format(TABLE, HISTORY),
        { citizenid }
    )
    return rows or {}
end

--- Şimdiye kadar yapılan toplam bağış ($).
local function donationTotal()
    local row = MySQL.single.await(
        ("SELECT COALESCE(SUM(`amount`), 0) AS total FROM `%s` WHERE `type` = 'donation'"):format(TABLE)
    )
    return row and tonumber(row.total) or 0
end

--- Geçmişe bir satır yazar (senkron — hemen ardından liste okunacağı için).
local function logTx(citizenid, txType, amount, balance, title, description, counterparty)
    MySQL.insert.await(
        ('INSERT INTO `%s` (`citizenid`, `type`, `amount`, `balance`, `title`, `description`, `counterparty`) '
        .. 'VALUES (?, ?, ?, ?, ?, ?, ?)'):format(TABLE),
        { citizenid, txType, math.floor(amount), math.floor(balance), title, description, counterparty }
    )
end

--- Her callback'in NUI'ye döndüğü standart yanıt. success=false olduğunda bile
--- güncel bakiye + geçmiş döner ki panel her koşulda tazelensin.
local function respond(player, ok, message)
    return {
        success      = ok,
        message      = ok and message or nil,
        reason       = ok and nil or message,
        name         = playerName(player),
        account      = accountOf(player.PlayerData.citizenid),
        cash         = player.Functions.GetMoney('cash') or 0,
        bank         = player.Functions.GetMoney('bank') or 0,
        bankName     = Config.bank.name,
        transactions = recentTransactions(player.PlayerData.citizenid),
    }
end

---------------------------------------------------------------------------
-- PANEL VERİSİ
---------------------------------------------------------------------------
lib.callback.register('loe_bank:getData', function(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return { success = false, reason = 'Oyuncu bulunamadı.' } end
    local r = respond(player, true)
    r.donationTotal = donationTotal()
    return r
end)

---------------------------------------------------------------------------
-- PARA YATIR  (nakit -> banka)
---------------------------------------------------------------------------
lib.callback.register('loe_bank:deposit', function(source, amount)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return { success = false, reason = 'Oyuncu bulunamadı.' } end

    local value, reason = Utils.validateAmount(amount, Config.limits.maxDeposit)
    if not value then return respond(player, false, reason) end

    if (player.Functions.GetMoney('cash') or 0) < value then
        return respond(player, false, 'Üzerinde yeterli nakit yok.')
    end

    if not player.Functions.RemoveMoney('cash', value, 'loe_bank-deposit') then
        return respond(player, false, 'Nakit çekilemedi.')
    end
    if not player.Functions.AddMoney('bank', value, 'loe_bank-deposit') then
        player.Functions.AddMoney('cash', value, 'loe_bank-deposit-refund')
        return respond(player, false, 'İşlem tamamlanamadı, nakit iade edildi.')
    end

    logTx(player.PlayerData.citizenid, 'deposit', value, player.Functions.GetMoney('bank') or 0,
        'Para Yatırma', 'Gişe · ' .. Config.bank.name, nil)

    Utils.log(('deposit src=%d %s'):format(source, value))
    return respond(player, true, ('%s yatırıldı.'):format(Utils.money(value)))
end)

---------------------------------------------------------------------------
-- PARA ÇEK  (banka -> nakit)
---------------------------------------------------------------------------
lib.callback.register('loe_bank:withdraw', function(source, amount)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return { success = false, reason = 'Oyuncu bulunamadı.' } end

    local value, reason = Utils.validateAmount(amount, Config.limits.maxWithdraw)
    if not value then return respond(player, false, reason) end

    if (player.Functions.GetMoney('bank') or 0) < value then
        return respond(player, false, 'Banka bakiyen yetersiz.')
    end

    if not player.Functions.RemoveMoney('bank', value, 'loe_bank-withdraw') then
        return respond(player, false, 'Bankadan çekilemedi.')
    end
    if not player.Functions.AddMoney('cash', value, 'loe_bank-withdraw') then
        player.Functions.AddMoney('bank', value, 'loe_bank-withdraw-refund')
        return respond(player, false, 'İşlem tamamlanamadı, tutar iade edildi.')
    end

    logTx(player.PlayerData.citizenid, 'withdraw', value, player.Functions.GetMoney('bank') or 0,
        'Para Çekme', 'Gişe · ' .. Config.bank.name, nil)

    Utils.log(('withdraw src=%d %s'):format(source, value))
    return respond(player, true, ('%s çekildi.'):format(Utils.money(value)))
end)

---------------------------------------------------------------------------
-- HAVALE / EFT  (banka -> banka, hedef: hesap no)
---------------------------------------------------------------------------
lib.callback.register('loe_bank:transfer', function(source, data)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return { success = false, reason = 'Oyuncu bulunamadı.' } end

    data = type(data) == 'table' and data or {}

    local account = Utils.normalizeAccount(data.account)
    if not account then return respond(player, false, 'Geçerli bir hesap no gir.') end

    local value, reason = Utils.validateAmount(data.amount, Config.limits.maxTransfer)
    if not value then return respond(player, false, reason) end

    local note = type(data.note) == 'string' and data.note:sub(1, 80):gsub('[%c]', '') or nil
    if note == '' then note = nil end

    -- Hedef hesabı bul (banka hesap no -> citizenid; online/offline fark etmez).
    local targetCid = citizenidByAccount(account)
    if not targetCid then
        return respond(player, false, 'Böyle bir hesap yok.')
    end
    if targetCid == player.PlayerData.citizenid then
        return respond(player, false, 'Kendi hesabına havale yapamazsın.')
    end

    -- Alıcının görünen adı (players tablosundan).
    local trow = MySQL.single.await(
        "SELECT JSON_VALUE(`charinfo`, '$.firstname') AS fn, JSON_VALUE(`charinfo`, '$.lastname') AS ln "
        .. "FROM `players` WHERE `citizenid` = ? LIMIT 1",
        { targetCid }
    )
    local row = { citizenid = targetCid, fn = trow and trow.fn or nil, ln = trow and trow.ln or nil }

    local fee   = Utils.transferFee(value)
    local debit = value + fee
    if (player.Functions.GetMoney('bank') or 0) < debit then
        return respond(player, false, fee > 0
            and ('Yetersiz bakiye. %s + %s ücret = %s gerekli.'):format(Utils.money(value), Utils.money(fee), Utils.money(debit))
            or 'Banka bakiyen yetersiz.')
    end

    -- Gönderenden düş.
    if not player.Functions.RemoveMoney('bank', debit, 'loe_bank-transfer-out') then
        return respond(player, false, 'İşlem tamamlanamadı.')
    end

    -- Alıcıya ekle (string identifier => qbx online'sa online, değilse offline yazar).
    local credited = exports.qbx_core:AddMoney(row.citizenid, 'bank', value, 'loe_bank-transfer-in')
    if not credited then
        player.Functions.AddMoney('bank', debit, 'loe_bank-transfer-refund')
        return respond(player, false, 'Havale tamamlanamadı, tutar iade edildi.')
    end

    local senderBank  = player.Functions.GetMoney('bank') or 0
    local senderName  = playerName(player)
    local senderAcc   = accountOf(player.PlayerData.citizenid)
    local targetName  = row.fn and (row.fn .. (row.ln and (' ' .. row.ln) or '')) or account
    local targetBank  = exports.qbx_core:GetMoney(row.citizenid, 'bank') or 0

    local outDesc = ('Alıcı: %s'):format(targetName)
    if fee > 0 then outDesc = outDesc .. (' · Ücret %s'):format(Utils.money(fee)) end
    if note then outDesc = outDesc .. ' · ' .. note end

    logTx(player.PlayerData.citizenid, 'transfer_out', value, senderBank, 'Havale — Gönderildi', outDesc, account)
    logTx(row.citizenid, 'transfer_in', value, targetBank, 'Havale — Alındı',
        ('Gönderen: %s'):format(senderName) .. (note and (' · ' .. note) or ''), senderAcc)

    -- Alıcı online ise bilgilendir.
    local targetPlayer = exports.qbx_core:GetPlayerByCitizenId(row.citizenid)
    if targetPlayer then
        exports.qbx_core:Notify(targetPlayer.PlayerData.source,
            ('%s: %s hesabına havale geldi (%s).'):format(Config.bank.name, Utils.money(value), senderName),
            'success')
    end

    Utils.log(('transfer src=%d -> %s %s (fee %s)'):format(source, row.citizenid, value, fee))
    return respond(player, true, ('%s, %s hesabına gönderildi.'):format(Utils.money(value), targetName))
end)

---------------------------------------------------------------------------
-- BAĞIŞ  (hesaptan -> Los Santos hazinesi; para sink + geçmiş)
---------------------------------------------------------------------------
lib.callback.register('loe_bank:donate', function(source, amount)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return { success = false, reason = 'Oyuncu bulunamadı.' } end

    local dcfg = Config.donation or {}
    local acct = (dcfg.account == 'cash') and 'cash' or 'bank'

    local function fail(msg)
        local r = respond(player, false, msg)
        r.donationTotal = donationTotal()
        return r
    end
    local function ok(msg)
        local r = respond(player, true, msg)
        r.donationTotal = donationTotal()
        return r
    end

    local value, reason = Utils.validateAmount(amount, dcfg.max)
    if not value then return fail(reason) end

    if (player.Functions.GetMoney(acct) or 0) < value then
        return fail(acct == 'cash' and 'Üzerinde yeterli nakit yok.' or 'Banka bakiyen yetersiz.')
    end

    if not player.Functions.RemoveMoney(acct, value, 'loe_bank-donation') then
        return fail('Bağış tamamlanamadı.')
    end

    -- İleride devlet/society banka sistemi eklenirse buradan aktarılır.
    if type(dcfg.onDonate) == 'function' then
        pcall(dcfg.onDonate, source, player.PlayerData.citizenid, value)
    end

    logTx(player.PlayerData.citizenid, 'donation', value, player.Functions.GetMoney('bank') or 0,
        'Bağış', 'Los Santos Hazinesi', nil)

    Utils.log(('donation src=%d %s (%s)'):format(source, value, acct))
    return ok(('%s bağışladın. Los Santos sana minnettar!'):format(Utils.money(value)))
end)

