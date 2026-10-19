--[[
    client/main.lua
    ---------------
    Görevleri:
        - Banka gişe görevlisi ped'ini konumunda oluşturmak / temizlemek.
        - Harita blip'i.
        - Yakınlık algılama + E tuşuyla NUI'yi açmak (ox_lib TextUI ipucu).
        - NUI <-> server köprüsü (getData / deposit / withdraw / transfer).
        - Panel açıkken dışarıdan gelen bakiye değişiminde paneli tazelemek.
]]

local Config = loeBank.Config
local Utils  = loeBank.Utils

local pedHandle    = nil
local blipHandle   = nil
local textUIShown  = false
local bankOpen     = false
local refreshLock  = false
local pedReported  = false   -- ilk başarılı spawn'da konsola bir kez bilgi bas

---------------------------------------------------------------------------
-- loe_target (bakılan hedef): açıkken E ipucu ekran ortasındaki noktadan gelir ve E yalnızca ped'e
-- BAKARKEN çalışır; kapalıyken eski davranış (mesafe + TextUI).
---------------------------------------------------------------------------
local focusedEntity = nil

local function targetOn()
    return GetResourceState('loe_target') == 'started'
end

AddEventHandler('loe_target:focus', function(_, entity)
    focusedEntity = entity
end)

local function registerTarget()
    if not (pedHandle and DoesEntityExist(pedHandle) and targetOn()) then return end
    exports.loe_target:addEntity(pedHandle, {
        key      = Config.interaction.keyLabel,
        title    = 'Bankacı',
        hint     = 'Bankacılık işlemleri',
        distance = Config.interaction.distance,
    })
end

AddEventHandler('loe_target:ready', registerTarget)

---------------------------------------------------------------------------
-- PED
---------------------------------------------------------------------------
--- Verilen model listesinden ilk yüklenebileni döner (hash) — yoksa nil.
local function loadFirstModel(names)
    for _, name in ipairs(names) do
        local hash = joaat(name)
        if IsModelValid(hash) then
            RequestModel(hash)
            local deadline = GetGameTimer() + 10000
            while not HasModelLoaded(hash) and GetGameTimer() < deadline do
                Wait(0)
            end
            if HasModelLoaded(hash) then return hash, name end
        end
    end
    return nil
end

local function spawnPed()
    if pedHandle and DoesEntityExist(pedHandle) then return end

    local p = Config.ped
    local candidates = { p.model }
    for _, m in ipairs(p.modelFallbacks or {}) do candidates[#candidates + 1] = m end

    local hash, usedName = loadFirstModel(candidates)
    if not hash then
        print(('^1[loe_bank]^7 ped modeli yüklenemedi (denenen: %s). Config.ped.model kontrol et.')
            :format(table.concat(candidates, ', ')))
        return
    end

    local x, y = p.coords.x, p.coords.y
    local z = p.coords.z + (p.zOffset or 0.0)

    -- Bölge collision'ını hazırla.
    RequestCollisionAtCoord(x, y, z)
    local t = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(PlayerPedId()) and GetGameTimer() < t do
        Wait(50)
    end

    local ped = CreatePed(0, hash, x, y, z, p.coords.w, false, true)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    SetEntityHeading(ped, p.coords.w)

    -- Opsiyonel: verilen z'ye YAKIN (±3 m) bir zemin bulunursa oraya oturt.
    -- Uzaktaki arazi/kat sonuçları reddedilir; yanlış yere ışınlanma olmaz.
    if p.snapToGround then
        for _ = 1, 12 do
            local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 1.5, false)
            if found and groundZ > 1.0 and math.abs(groundZ - z) <= 3.0 then
                SetEntityCoordsNoOffset(ped, x, y, groundZ, false, false, false)
                break
            end
            Wait(50)
        end
    end

    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedDiesWhenInjured(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    FreezeEntityPosition(ped, true)
    if p.scenario then
        TaskStartScenarioInPlace(ped, p.scenario, 0, true)
    end
    SetModelAsNoLongerNeeded(hash)

    pedHandle = ped
    registerTarget()

    if Config.debug or not pedReported then
        pedReported = true
        local pc = GetEntityCoords(ped)
        print(('^2[loe_bank]^7 gişe ped\'i oluşturuldu: model=%s handle=%s konum=%.2f, %.2f, %.2f')
            :format(usedName, ped, pc.x, pc.y, pc.z))
    end
end

local function removePed()
    if pedHandle and DoesEntityExist(pedHandle) then
        DeleteEntity(pedHandle)
    end
    pedHandle = nil
end

---------------------------------------------------------------------------
-- BLIP
---------------------------------------------------------------------------
local function createBlip()
    local b = Config.blip
    if not b.enabled then return end
    local c = Config.ped.coords

    local blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(blip, b.sprite)
    SetBlipColour(blip, b.color)
    SetBlipScale(blip, b.scale)
    SetBlipAsShortRange(blip, b.shortRange)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(Config.bank.name)
    EndTextCommandSetBlipName(blip)

    blipHandle = blip
end

local function removeBlip()
    if blipHandle and DoesBlipExist(blipHandle) then
        RemoveBlip(blipHandle)
    end
    blipHandle = nil
end

---------------------------------------------------------------------------
-- NUI
---------------------------------------------------------------------------
local function closeBank()
    if not bankOpen then return end
    bankOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function openBank()
    if bankOpen then return end

    local data = lib.callback.await('loe_bank:getData', false)
    if not data or not data.success then
        lib.notify({ type = 'error', description = (data and data.reason) or 'Banka verisi alınamadı.' })
        return
    end

    bankOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        bank   = { name = Config.bank.name, tagline = Config.bank.tagline },
        limits = Config.limits,
        data   = data,
    })
end

--- Panel açıkken güncel veriyi çekip NUI'ye iter (aksiyon dışı tazeleme).
local function pushRefresh()
    if not bankOpen or refreshLock then return end
    refreshLock = true
    SetTimeout(250, function() refreshLock = false end)

    local data = lib.callback.await('loe_bank:getData', false)
    if bankOpen and data and data.success then
        SendNUIMessage({ action = 'update', data = data })
    end
end

-- NUI: kapat
RegisterNUICallback('close', function(_, cb)
    closeBank()
    cb(true)
end)

-- NUI: elle tazele
RegisterNUICallback('refresh', function(_, cb)
    local data = lib.callback.await('loe_bank:getData', false)
    cb(data or { success = false, reason = 'Sunucudan yanıt yok.' })
end)

-- NUI: para yatır  { amount = number }
RegisterNUICallback('deposit', function(payload, cb)
    local amount = type(payload) == 'table' and payload.amount or nil
    local res = lib.callback.await('loe_bank:deposit', false, amount)
    cb(res or { success = false, reason = 'Sunucudan yanıt yok.' })
end)

-- NUI: para çek  { amount = number }
RegisterNUICallback('withdraw', function(payload, cb)
    local amount = type(payload) == 'table' and payload.amount or nil
    local res = lib.callback.await('loe_bank:withdraw', false, amount)
    cb(res or { success = false, reason = 'Sunucudan yanıt yok.' })
end)

-- NUI: havale  { account = string, amount = number, note = string? }
RegisterNUICallback('transfer', function(payload, cb)
    local data = type(payload) == 'table' and payload or {}
    local res = lib.callback.await('loe_bank:transfer', false, {
        account = data.account,
        amount  = data.amount,
        note    = data.note,
    })
    cb(res or { success = false, reason = 'Sunucudan yanıt yok.' })
end)

-- NUI: bağış  { amount = number }
RegisterNUICallback('donate', function(payload, cb)
    local amount = type(payload) == 'table' and payload.amount or nil
    local res = lib.callback.await('loe_bank:donate', false, amount)
    cb(res or { success = false, reason = 'Sunucudan yanıt yok.' })
end)

---------------------------------------------------------------------------
-- DIŞARIDAN BAKİYE DEĞİŞİMİ (ör. sana havale gelmesi) -> paneli tazele
---------------------------------------------------------------------------
RegisterNetEvent('QBCore:Client:OnMoneyChange', function()
    if bankOpen then pushRefresh() end
end)

---------------------------------------------------------------------------
-- YAKINLIK + E TUŞU
---------------------------------------------------------------------------
local function hideTextUI()
    if textUIShown then
        lib.hideTextUI()
        textUIShown = false
    end
end

CreateThread(function()
    local c = Config.ped.coords
    local center = vec3(c.x, c.y, c.z)
    local interactDist = Config.interaction.distance
    local spawnDist = Config.ped.spawnDistance or 120.0

    while true do
        local sleep = 1000
        local coords = GetEntityCoords(PlayerPedId())
        local dist = #(coords - center)

        -- ped'i yaklaşınca oluştur, uzaklaşınca sil
        if dist < spawnDist then
            if not (pedHandle and DoesEntityExist(pedHandle)) then spawnPed() end
        elseif pedHandle then
            removePed()
        end

        if dist < 15.0 then
            sleep = 0
            local useTarget = targetOn()
            local canUse
            if useTarget then
                canUse = pedHandle ~= nil and focusedEntity == pedHandle
                hideTextUI()
            else
                canUse = dist <= interactDist
            end
            if canUse and not bankOpen then
                if not useTarget and not textUIShown then
                    lib.showTextUI(
                        ('[%s] %s'):format(Config.interaction.keyLabel, Config.interaction.helpText),
                        { position = 'left-center' }
                    )
                    textUIShown = true
                end
                if IsControlJustReleased(0, Config.interaction.key) then
                    hideTextUI()
                    openBank()
                end
            else
                hideTextUI()
            end
        else
            hideTextUI()
        end

        Wait(sleep)
    end
end)

---------------------------------------------------------------------------
-- YARDIMCI KOMUTLAR (ped konumu ayarlamak / teşhis)
---------------------------------------------------------------------------
-- Durduğun yerin tam vec4'ünü konsola basar — Config.ped.coords için.
RegisterCommand('bankhere', function()
    local pc = GetEntityCoords(PlayerPedId())
    local h  = GetEntityHeading(PlayerPedId())
    local line = ('vec4(%.2f, %.2f, %.2f, %.2f)'):format(pc.x, pc.y, pc.z, h)
    print('^3[loe_bank]^7 Config.ped.coords = ' .. line)
    lib.notify({ title = 'loe_bank', description = line, type = 'inform', duration = 12000 })
end, false)

-- Ped'i sil + yeniden oluştur, durumu bildir.
RegisterCommand('bankped', function()
    CreateThread(function()
        removePed()
        pedReported = false
        spawnPed()
        local exists = pedHandle and DoesEntityExist(pedHandle)
        local desc = exists and ('ped var (handle %s)'):format(pedHandle) or 'ped OLUŞMADI — konsola bak (model?)'
        print('^3[loe_bank]^7 /bankped -> ' .. desc)
        lib.notify({ title = 'loe_bank', description = desc, type = exists and 'success' or 'error' })
    end)
end, false)

---------------------------------------------------------------------------
-- YAŞAM DÖNGÜSÜ
---------------------------------------------------------------------------
CreateThread(function()
    createBlip()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    removePed()
    removeBlip()
    hideTextUI()
    if bankOpen then SetNuiFocus(false, false) end
end)

