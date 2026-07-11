-- Entry point: wires together config, adapters, core, UI, and lists; drives the main loop via /lua run proloot

local mq     = require('mq')
local imgui  = require('ImGui')

-- Version block — single source of truth
local Version = {
    _AppName  = 'ProLoot',
    _version  = '0.10.1',
    _author   = 'Tyvion',
    _buildTag = 'Beta',   -- change to Stable / Dev / RC as needed per branch
}

local Config   = require('proloot.config')
local Logger   = require('proloot.utils.logger')
local Lists    = require('proloot.lists.init')
local Restock  = require('proloot.lists.restock')
local Loot     = require('proloot.core.loot')
local Corpse  = require('proloot.core.corpse')
local Setup           = require('proloot.ui.setup')
local Editor          = require('proloot.ui.editor')
local BankConfirm     = require('proloot.ui.bankconfirm')
local SellConfirm     = require('proloot.ui.sellconfirm')
local RestockConfirm  = require('proloot.ui.restockconfirm')
local BankSettings    = require('proloot.ui.banksettings')
local UpgradeEval     = require('proloot.ui.upgradeeval')
local Panel           = require('proloot.ui.panel')

-- Framework adapter map
local FRAMEWORK_ADAPTERS = {
    none                = require('proloot.adapters.framework.none'),
    rgmercs             = require('proloot.adapters.framework.rgmercs'),
    ['rgmercs-directed'] = require('proloot.adapters.framework.rgmercs_directed'),
    e3                  = require('proloot.adapters.framework.e3'),
    kissassist          = require('proloot.adapters.framework.kissassist'),
}

-- Channel adapter map
local CHANNEL_ADAPTERS = {
    none   = require('proloot.adapters.channel.none'),
    dannet = require('proloot.adapters.channel.dannet'),
    eqbc   = require('proloot.adapters.channel.eqbc'),
}

-----------------------------------------------------------------------
-- Parse command-line args: /lua run proloot framework=xxx channel=yyy
-----------------------------------------------------------------------
local function parseArgs(args)
    local opts = {}
    if args then
        for _, arg in ipairs(args) do
            local k, v = arg:match('^(%w+)=(.+)$')
            if k and v then opts[k:lower()] = v:lower() end
        end
    end
    return opts
end

-----------------------------------------------------------------------
-- Startup
-----------------------------------------------------------------------
local opts = parseArgs(arg)

Config:Init()
Logger.Init(Config)

-- CLI overrides take precedence over saved config
if opts.framework then Config:Set('Framework', opts.framework) end
if opts.channel   then Config:Set('Channel',   opts.channel)   end

-- Resolve adapters
local frameworkName = Config:Get('Framework')
local channelName   = Config:Get('Channel')
local framework = FRAMEWORK_ADAPTERS[frameworkName] or FRAMEWORK_ADAPTERS.none
local channel   = CHANNEL_ADAPTERS[channelName]     or CHANNEL_ADAPTERS.none

-- Load all lists from disk
Lists.LoadAll()
Restock.Load()

-- Boot channel
channel:Init()

mq.cmd('/hidecorpse looted')

-- Boot core loot engine
Loot.Init(Config, Lists, framework, channel, Restock)

-- Wire panel (pass lists ref into config for editor access)
Config._lists = Lists.All()

Panel.Init(Config, Loot, Setup, Editor, BankSettings, framework, FRAMEWORK_ADAPTERS, channel, Version, UpgradeEval)

-- Shared state accessed by both the bind handler and the main loop
local _pendingAutoBank = nil
local _pendingSell     = nil
local _pendingRestock  = nil

-- Register /proloot slash command for manual triggers
mq.bind('/proloot', function(subcmd, ...)
    subcmd = (subcmd or ''):lower()
    local args = { ... }
    if subcmd == 'loot' then
        Loot.LootNearby()
    elseif subcmd == 'setup' then
        Setup.Open(Config, FRAMEWORK_ADAPTERS)
    elseif subcmd == 'editor' then
        Editor.Open(Lists.All())
    elseif subcmd == 'enable' then
        Loot.SetEnabled(true)
        printf('\agProLoot enabled')
    elseif subcmd == 'disable' then
        Loot.SetEnabled(false)
        printf('\arProLoot disabled')
    elseif subcmd == 'bankstuff' then
        if Config:Get('BankAutoDeposit') then
            _pendingAutoBank = Loot.ScanBankItems()
        else
            BankConfirm.Open(Loot)
        end
    elseif subcmd == 'sellstuff' then
        if Config:Get('SellAutoSell') then
            _pendingSell = Loot.ScanSellItems()
        else
            SellConfirm.Open(Loot)
        end
    elseif subcmd == 'restock' then
        if Config:Get('RestockAutoRestock') then
            local needs = Loot.ScanRestockNeeds(Restock)
            local items = {}
            for _, r in ipairs(needs) do
                if r.need > 0 then items[#items+1] = r end
            end
            _pendingRestock = #items > 0 and items or nil
        else
            RestockConfirm.Open(Loot, Restock)
        end
    elseif subcmd == 'reload' then
        Lists.LoadAll()
        printf('\agProLoot: lists reloaded')
    elseif subcmd == 'set' then
        local rawKey = args[1]
        local value  = args[2]
        if rawKey and value then
            local key = nil
            for k in pairs(Config.Defaults) do
                if k:lower() == rawKey:lower() then key = k; break end
            end
            if key then
                Config:SetAndSave(key, value)
                printf('\agProLoot: %s = %s', key, tostring(Config:Get(key)))
            else
                printf('\arProLoot: unknown setting "%s"', rawKey)
            end
        else
            printf('\ayProLoot set <setting> <value>  (e.g. /proloot set usewarp false)')
        end
    elseif subcmd == 'mini' then
        local miniArg = (args[1] or ''):lower()
        if miniArg == 'on' then
            Panel.SetMini(true)
        elseif miniArg == 'off' then
            Panel.SetMini(false)
        else
            Panel.ToggleMini()
        end
    elseif subcmd == 'show' then
        Panel.Show()
    elseif subcmd == 'eval' then
        UpgradeEval.Open(Config)
    elseif subcmd == 'toggledone' then
        local newVal = not Config:Get('AnnounceDone')
        Config:SetAndSave('AnnounceDone', newVal)
        channel:Broadcast({ type='set_announcedone', value=newVal })
        printf('\agProLoot: Done Looting announce %s (all toons)', newVal and 'ON' or 'OFF')
    else
        printf('\ayProLoot commands: loot | bankstuff | sellstuff | restock | mini [on|off] | show | editor | eval | enable | disable | reload | set <setting> <value> | toggledone')
    end
end)

-- Show setup dialog on first run
if not Config:Get('SetupDone') then
    Setup.Open(Config, FRAMEWORK_ADAPTERS)
end

-----------------------------------------------------------------------
-- ImGui render callback
-----------------------------------------------------------------------
mq.imgui.init('proloot', function()
    Panel.Render()
    BankConfirm.Render()
    SellConfirm.Render()
    RestockConfirm.Render()
    if Loot.IsCoinWarning() then
        local io   = ImGui.GetIO()
        local winW = 420
        local winH = 64
        ImGui.SetNextWindowPos(ImVec2((io.DisplaySize.x - winW) * 0.5, io.DisplaySize.y * 0.3), ImGuiCond.Always)
        ImGui.SetNextWindowSize(ImVec2(winW, winH), ImGuiCond.Always)
        ImGui.Begin('##coinwarn', nil, bit32.bor(
            ImGuiWindowFlags.NoDecoration, ImGuiWindowFlags.NoMove,
            ImGuiWindowFlags.NoSavedSettings, ImGuiWindowFlags.NoInputs,
            ImGuiWindowFlags.NoNav))
        ImGui.Spacing()
        ImGui.SetCursorPosX(14)
        ImGui.TextColored(ImVec4(1.0, 0.75, 0.0, 1.0), 'Consolidating coins \xe2\x80\x94 do not touch the mouse until this closes!')
        ImGui.End()
    end
end)

-----------------------------------------------------------------------
-- Main loop
-----------------------------------------------------------------------
local LOOT_INTERVAL = 5000  -- ms between automatic loot sweeps
local lastLootTime  = 0
local lastZone      = mq.TLO.Zone.ID()

printf('\agProLoot v%s by %s — framework: %s  channel: %s', Version._version, Version._author, frameworkName, channelName)
printf('\ayType /proloot for command help.')
Logger.Info('v%s started - framework: %s  channel: %s', Version._version, frameworkName, channelName)

while true do
    mq.doevents()
    channel:Tick()

    -- BankStuff / ConsolidateOnly: executed from main loop so mq.delay is allowed
    local bankItems = _pendingAutoBank or BankConfirm.ConsumePending()
    if bankItems then
        _pendingAutoBank = nil
        Loot.BankStuff(bankItems)
    elseif BankConfirm.ConsumePendingConsolidate() then
        Loot.ConsolidateOnly()
    end

    -- Bank All: broadcast to group + trigger self immediately
    if BankConfirm.ConsumePendingBankAll() then
        local myName  = mq.TLO.Me.CleanName()
        channel:Broadcast({ type='bank_all', from=myName })
        local myItems = Loot.ScanBankItems()
        if #myItems > 0 then _pendingAutoBank = myItems end
    end

    -- Bank All received from another toon's broadcast
    if Loot.ConsumePendingBankAll() then
        local myItems = Loot.ScanBankItems()
        if #myItems > 0 then _pendingAutoBank = myItems end
    end

    -- Consolidate All: broadcast to group + trigger self immediately
    if BankConfirm.ConsumePendingConsolidateAll() then
        channel:Broadcast({ type='consolidate_all', from=mq.TLO.Me.CleanName() })
        Loot.ConsolidateOnly()
    end

    -- Consolidate All received from another toon's broadcast
    if Loot.ConsumePendingConsolidateAll() then
        Loot.ConsolidateOnly()
    end

    -- SellStuff: executed from main loop so mq.delay is allowed
    local sellItems = _pendingSell or SellConfirm.ConsumePending()
    if sellItems then
        _pendingSell = nil
        Loot.SellStuff(sellItems)
    end

    -- Sell All: broadcast to group + trigger self immediately
    if SellConfirm.ConsumePendingSellAll() then
        local myName = mq.TLO.Me.CleanName()
        channel:Broadcast({ type='sell_all', from=myName })
        local myItems = Loot.ScanSellItems()
        if #myItems > 0 then _pendingSell = myItems end
    end

    -- Sell All received from another toon's broadcast
    if Loot.ConsumePendingSellAll() then
        local myItems = Loot.ScanSellItems()
        if #myItems > 0 then _pendingSell = myItems end
    end

    -- Restock: executed from main loop so mq.delay is allowed
    local restockItems = _pendingRestock or RestockConfirm.ConsumePending()
    if restockItems then
        _pendingRestock = nil
        Loot.RestockStuff(restockItems)
    end

    -- Restock broadcast: share one item+qty with all group toons
    local bcast = RestockConfirm.ConsumePendingBroadcast()
    if bcast then
        channel:Broadcast({ type='restock_set', name=bcast.name, qty=bcast.qty, from=mq.TLO.Me.CleanName() })
        printf('\agProLoot: broadcasting %s x%d to group', bcast.name, bcast.qty)
    end

    -- Sell Status All: scan self + broadcast request so other toons respond
    if SellConfirm.ConsumePendingSellStatusRequest() then
        local myName  = mq.TLO.Me.CleanName()
        local myItems = Loot.ScanSellItems()
        Loot.StoreSellStatusResponse(myName, myItems)
        channel:Broadcast({ type='sell_status_request', from=myName })
    end

    -- Bank Status All: scan self + broadcast request so other toons respond
    if BankConfirm.ConsumePendingBankStatusRequest() then
        local myName  = mq.TLO.Me.CleanName()
        local myItems = Loot.ScanBankItems()
        Loot.StoreBankStatusResponse(myName, myItems)
        channel:Broadcast({ type='bank_status_request', from=myName })
    end

    -- Restock Status All: scan self + broadcast request so other toons respond
    if RestockConfirm.ConsumePendingStatusRequest() then
        local myName  = mq.TLO.Me.CleanName()
        local all     = Loot.ScanRestockNeeds(Restock)
        local myNeeds = {}
        for _, r in ipairs(all) do
            if r.need > 0 then myNeeds[#myNeeds+1] = r end
        end
        Loot.StoreRestockStatusResponse(myName, myNeeds)
        channel:Broadcast({ type='restock_status_request', from=myName })
    end

    -- Restock All: broadcast to group + trigger self immediately
    if RestockConfirm.ConsumePendingRestockAll() then
        local myName = mq.TLO.Me.CleanName()
        channel:Broadcast({ type='restock_all', from=myName })
        local needs = Loot.ScanRestockNeeds(Restock)
        local items = {}
        for _, r in ipairs(needs) do
            if r.need > 0 then items[#items+1] = r end
        end
        if #items > 0 then _pendingRestock = items end
    end

    -- Restock All received from another toon's broadcast
    if Loot.ConsumePendingRestockAll() then
        local needs = Loot.ScanRestockNeeds(Restock)
        local items = {}
        for _, r in ipairs(needs) do
            if r.need > 0 then items[#items+1] = r end
        end
        if #items > 0 then _pendingRestock = items end
    end

    -- Upgrade Eval: equip/destroy actions queued from ImGui, executed here so mq.delay is allowed
    local evalEquip = UpgradeEval.ConsumePendingEquip()
    if evalEquip then
        if evalEquip.augsToCarry and #evalEquip.augsToCarry > 0 then
            Loot.EquipWithAugCarryover(evalEquip.name, evalEquip.equipSlot, evalEquip.oldItemName, evalEquip.augsToCarry)
        else
            Loot.EquipFromBag(evalEquip.name, evalEquip.equipSlot)
        end
        UpgradeEval.RequestRefresh()
    end
    local evalDestroy = UpgradeEval.ConsumePendingDestroy()
    if evalDestroy then
        Loot.DestroyFromBag(evalDestroy.name)
        UpgradeEval.RequestRefresh()
    end
    local evalRemoveAug = UpgradeEval.ConsumePendingRemoveAug()
    if evalRemoveAug then
        Loot.RemoveAugFromBag(evalRemoveAug.itemName, evalRemoveAug.augName, evalRemoveAug.augSlot)
        UpgradeEval.RequestRefresh()
    end

    -- Zone change: clear corpse done-set
    local curZone = mq.TLO.Zone.ID()
    if curZone and curZone ~= lastZone then
        Corpse.ResetDone()
        lastZone = curZone
    end

    Loot.CombatTick()

    -- Periodic auto-loot
    local now = mq.gettime()
    if Config:Get('LootEnabled') and (now - lastLootTime) >= LOOT_INTERVAL then
        Loot.LootNearby()
        lastLootTime = now
    end

    mq.delay(100)
end
