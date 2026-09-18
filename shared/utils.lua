--[[
    shared/utils.lua
    ----------------
    Client ve server'ın ortak kullandığı, yan etkisiz yardımcılar.
    loeBank.Utils üzerinden erişilir.

    Tutar/hesap-no doğrulama mantığının TEK kaynağı burasıdır; hem NUI (client)
    hem de para hareketi doğrulaması (server) aynı fonksiyonları kullanır.
]]

loeBank = loeBank or {}

local Config = loeBank.Config
local Utils  = {}

--- Sadece Config.debug açıkken konsola log basar.
function Utils.log(...)
    if Config and Config.debug then
        print('^5[loe_bank]^7', ...)
    end
end

--- Para değerini görünür biçime çevirir ($1,234). Negatifi korur.
function Utils.money(amount)
    local n = math.floor((tonumber(amount) or 0) + 0.5)
    local sign = n < 0 and '-' or ''
    local s = tostring(math.abs(n))
    local k
    repeat
        s, k = s:gsub('^(%d+)(%d%d%d)', '%1,%2')
    until k == 0
    return sign .. '$' .. s
end

--- Client'tan gelen tutarı doğrular.
--- @param value any
--- @param maxAmount? number  0/nil = sınırsız
--- @return number|nil amount, string|nil reason
function Utils.validateAmount(value, maxAmount)
    local amount = tonumber(value)
    if not amount then
        return nil, 'Geçerli bir tutar gir.'
    end
    if amount ~= amount or amount == math.huge or amount == -math.huge then
        return nil, 'Geçerli bir tutar gir.'
    end
    amount = math.floor(amount)
    local minAmount = (Config and Config.limits and Config.limits.minAmount) or 1
    if amount < minAmount then
        return nil, ('En az %s işlem yapabilirsin.'):format(Utils.money(minAmount))
    end
    if maxAmount and maxAmount > 0 and amount > maxAmount then
        return nil, ('Tek işlemde en fazla %s.'):format(Utils.money(maxAmount))
    end
    return amount
end

--- Havale ücreti (yapılandırmaya göre). Her zaman tam sayı.
--- @param amount number
--- @return number fee
function Utils.transferFee(amount)
    local l = (Config and Config.limits) or {}
    local rate = tonumber(l.transferFee) or 0
    if rate <= 0 then return 0 end
    local fee = math.floor(amount * rate)
    if l.transferFeeMin and l.transferFeeMin > 0 and fee < l.transferFeeMin then fee = l.transferFeeMin end
    if l.transferFeeMax and l.transferFeeMax > 0 and fee > l.transferFeeMax then fee = l.transferFeeMax end
    return fee
end

--- Kullanıcının girdiği hesap numarasını normalize eder: boşlukları ve baştaki
--- '#' işaretini atar, büyük harfe çevirir. Geçerli banka hesap no'su TAM
--- 4 haneli harf/rakamdır (ör. "K7P2"); değilse nil.
--- @param value any
--- @return string|nil
function Utils.normalizeAccount(value)
    if type(value) == 'number' then value = tostring(math.floor(value)) end
    if type(value) ~= 'string' then return nil end
    local acc = value:gsub('%s+', ''):gsub('^#+', ''):upper()
    if not acc:match('^[A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]$') then return nil end
    return acc
end

--- 4 haneli banka hesap kodu üretir: harf+rakam, kendi içinde tekrarsız,
--- en az bir harf + en az bir rakam. Karışan karakterler (0/O, 1/I) kullanılmaz.
--- Benzersizlik server'da DB UNIQUE + tekrar denemesiyle sağlanır.
--- @return string|nil
do
    local LETTERS = 'ABCDEFGHJKLMNPQRSTUVWXYZ'   -- I, O yok
    local DIGITS  = '23456789'                    -- 0, 1 yok
    local POOL    = LETTERS .. DIGITS

    function Utils.genAccountCode()
        for _ = 1, 200 do
            local chars = {}
            for c in POOL:gmatch('.') do chars[#chars + 1] = c end
            local pick = {}
            for i = 1, 4 do
                local idx = math.random(#chars)
                pick[i] = chars[idx]
                table.remove(chars, idx)
            end
            local code = table.concat(pick)
            if code:find('%a') and code:find('%d') then
                return code
            end
        end
        return nil
    end
end

loeBank.Utils = Utils

