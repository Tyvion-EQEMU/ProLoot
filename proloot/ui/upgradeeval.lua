-- Upgrade Evaluator window: scans bag inventory for equippable items and reports upgrade verdicts

local mq      = require('mq')
local Icons   = require('mq.ICONS')
local Upgrade = require('proloot.core.upgrade')

local UpgradeEval = {}

local _open          = false
local _config        = nil
local _results       = {}
local _needsRefresh  = false
local _evalIgnore    = {}  -- name:lower() -> true; UI-only filter, no effect on looting
local _ignorePath    = nil -- set on first Open()

local _pendingEquip     = nil  -- { bag, slot, equipSlot, name }
local _pendingDestroy   = nil  -- { bag, slot, name }
local _pendingRemoveAug = nil  -- { itemName, augName }

local _sortCol = 0     -- 0=Item, 1=Slot, 2=Equipped, 3=Verdict
local _sortAsc = true
local _maxAugs = 0     -- most augs on any single scanned item; drives Actions column width

local COL_PROLOOT_BLUE = ImVec4(0.16, 0.29, 0.48, 1.0)  -- ProLoot Blue: ImGui dark theme TitleBgActive; used for row highlights
local COL_GOLD         = ImVec4(1.0,  0.72, 0.20, 1.0)  -- ProLoot Gold: matches BUTTON_GOLD in panel.lua
local UNDERLINE_U32    = 0xCCFFFFFF  -- white at ~80% alpha for clickable underlines
local COL_GAIN         = ImVec4(0.4, 0.9, 0.4, 1.0)
local COL_LOSS         = ImVec4(0.9, 0.4, 0.4, 1.0)

local SKIP_SLOTS = { [0]=true, [21]=true, [22]=true }

-- Ordered stat list for delta tooltips.  invert=true means lower is better (Delay).
local STAT_MAP = {
    { label='Damage',        get=function(i) return i.Damage() or 0 end },
    { label='Delay',         get=function(i) return i.ItemDelay() or 0 end, invert=true },
    { label='Haste',         get=function(i) return i.Haste() or 0 end },
    { label='AC',            get=function(i) return i.AC() or 0 end },
    { label='HP',            get=function(i) return i.HP() or 0 end },
    { label='Mana',          get=function(i) return i.Mana() or 0 end },
    { label='Endurance',     get=function(i) return i.Endurance() or 0 end },
    { label='HP Regen',      get=function(i) return i.HPRegen() or 0 end },
    { label='Mana Regen',    get=function(i) return i.ManaRegen() or 0 end },
    { label='End Regen',     get=function(i) return i.EnduranceRegen() or 0 end },
    { label='STR',           get=function(i) return i.STR() or 0 end },
    { label='STA',           get=function(i) return i.STA() or 0 end },
    { label='AGI',           get=function(i) return i.AGI() or 0 end },
    { label='DEX',           get=function(i) return i.DEX() or 0 end },
    { label='WIS',           get=function(i) return i.WIS() or 0 end },
    { label='INT',           get=function(i) return i.INT() or 0 end },
    { label='CHA',           get=function(i) return i.CHA() or 0 end },
    { label='H-STR',         get=function(i) return i.HeroicSTR() or 0 end },
    { label='H-STA',         get=function(i) return i.HeroicSTA() or 0 end },
    { label='H-AGI',         get=function(i) return i.HeroicAGI() or 0 end },
    { label='H-DEX',         get=function(i) return i.HeroicDEX() or 0 end },
    { label='H-WIS',         get=function(i) return i.HeroicWIS() or 0 end },
    { label='H-INT',         get=function(i) return i.HeroicINT() or 0 end },
    { label='H-CHA',         get=function(i) return i.HeroicCHA() or 0 end },
    { label='Magic Res',     get=function(i) return i.svMagic() or 0 end },
    { label='Fire Res',      get=function(i) return i.svFire() or 0 end },
    { label='Disease Res',   get=function(i) return i.svDisease() or 0 end },
    { label='Poison Res',    get=function(i) return i.svPoison() or 0 end },
    { label='Cold Res',      get=function(i) return i.svCold() or 0 end },
    { label='Corrupt Res',   get=function(i) return i.svCorruption() or 0 end },
    { label='H-MR',          get=function(i) return i.HeroicSvMagic() or 0 end },
    { label='H-FR',          get=function(i) return i.HeroicSvFire() or 0 end },
    { label='H-DR',          get=function(i) return i.HeroicSvDisease() or 0 end },
    { label='H-PR',          get=function(i) return i.HeroicSvPoison() or 0 end },
    { label='H-CR',          get=function(i) return i.HeroicSvCold() or 0 end },
    { label='H-COR',         get=function(i) return i.HeroicSvCorruption() or 0 end },
    { label='Dmg Shield',    get=function(i) return i.DamShield() or 0 end },
    { label='DS Mitigation', get=function(i) return i.DamageShieldMitigation() or 0 end },
    { label='Avoidance',     get=function(i) return i.Avoidance() or 0 end },
    { label='DoT Shielding', get=function(i) return i.DoTShielding() or 0 end },
    { label='Accuracy',      get=function(i) return i.Accuracy() or 0 end },
    { label='Spell Shield',  get=function(i) return i.SpellShield() or 0 end },
    { label='Heal Amount',   get=function(i) return i.HealAmount() or 0 end },
    { label='Spell Damage',  get=function(i) return i.SpellDamage() or 0 end },
    { label='Stun Resist',   get=function(i) return i.StunResist() or 0 end },
    { label='Clairvoyance',  get=function(i) return i.Clairvoyance() or 0 end },
    { label='Instrument Mod',get=function(i) return i.InstrumentMod() or 0 end },
}

local function safeStatGet(item, fn)
    local ok, v = pcall(fn, item)
    return (ok and type(v) == 'number') and v or 0
end

local function renderDeltaTooltip(bagItem, eqItem)
    local hasEquipped = eqItem and eqItem.ID and eqItem.ID() and eqItem.ID() > 0
    if hasEquipped then
        ImGui.TextDisabled('vs. %s', eqItem.Name() or '(equipped)')
    else
        ImGui.TextDisabled('vs. (empty slot)')
    end
    ImGui.Separator()

    local diffs = {}
    for _, s in ipairs(STAT_MAP) do
        local bagVal = safeStatGet(bagItem, s.get)
        local eqVal  = hasEquipped and safeStatGet(eqItem, s.get) or 0
        if bagVal ~= 0 or eqVal ~= 0 then
            diffs[#diffs+1] = { label=s.label, diff=bagVal - eqVal, invert=s.invert }
        end
    end

    if #diffs == 0 then ImGui.TextDisabled('No stat differences'); return end

    if ImGui.BeginTable('##cmpStats', 2, ImGuiTableFlags.None) then
        ImGui.TableSetupColumn('Stat', ImGuiTableColumnFlags.WidthFixed, 120)
        ImGui.TableSetupColumn('Diff', ImGuiTableColumnFlags.WidthFixed, 70)
        for _, e in ipairs(diffs) do
            ImGui.TableNextRow()
            ImGui.TableNextColumn(); ImGui.Text(e.label)
            ImGui.TableNextColumn()
            if e.diff > 0 then
                ImGui.TextColored(e.invert and COL_LOSS or COL_GAIN, '+%d', e.diff)
            elseif e.diff < 0 then
                ImGui.TextColored(e.invert and COL_GAIN or COL_LOSS, '%d', e.diff)
            else
                ImGui.TextDisabled('\xe2\x80\x94')
            end
        end
        ImGui.EndTable()
    end
end

local function loadIgnore()
    _evalIgnore = {}
    if not _ignorePath then return end
    local f = io.open(_ignorePath, 'r')
    if not f then return end
    for line in f:lines() do
        local name = line:match('^%s*(.-)%s*$')
        if name ~= '' then _evalIgnore[name:lower()] = true end
    end
    f:close()
end

local function saveIgnore()
    if not _ignorePath then return end
    local f = io.open(_ignorePath, 'w')
    if not f then return end
    for name in pairs(_evalIgnore) do f:write(name .. '\n') end
    f:close()
end

local function applySort()
    table.sort(_results, function(a, b)
        local col = _sortCol
        local asc = _sortAsc
        if col == 1 then  -- Slot
            local an = (a.slotName or ''):lower()
            local bn = (b.slotName or ''):lower()
            if an == bn then return a.name:lower() < b.name:lower() end
            if an == '' then return not asc end
            if bn == '' then return asc end
            if asc then return an < bn else return an > bn end
        elseif col == 3 then  -- Currently Equipped
            local ae = (a.equippedName or ''):lower()
            local be = (b.equippedName or ''):lower()
            if ae == be then return a.name:lower() < b.name:lower() end
            if ae == '' then return not asc end
            if be == '' then return asc end
            if asc then return ae < be else return ae > be end
        elseif col == 5 then  -- Verdict: Upgrade(2) > Weaker(1) > No Upgrade(0)
            local function vp(r)
                if r.isUpgrade and not r.isWeaker then return 2
                elseif r.isUpgrade                then return 1
                else                                   return 0 end
            end
            local ap, bp = vp(a), vp(b)
            if ap ~= bp then
                if asc then return ap > bp else return ap < bp end
            end
            return a.name:lower() < b.name:lower()
        else  -- Item (col 0, default)
            if a.isUpgrade ~= b.isUpgrade then
                if asc then return a.isUpgrade else return b.isUpgrade end
            end
            if asc then return a.name:lower() < b.name:lower()
            else return a.name:lower() > b.name:lower() end
        end
    end)
end

local function rankUpgrades()
    -- Among upgrades sharing the same slot, mark all but the highest scorer as weaker.
    -- Ties both keep isWeaker=false (both show "Upgrade").
    local slotBest = {}
    for _, r in ipairs(_results) do
        if r.isUpgrade and r.displaySlotId then
            local found = mq.TLO.InvSlot('pack' .. r.bag).Item.Item(r.slot)
            if found and found.ID() and found.ID() > 0 then
                r._score = Upgrade.ItemScore(found, r.displaySlotId, _config:Get('RangedMode'))
                local best = slotBest[r.displaySlotId]
                if not best or r._score > best then slotBest[r.displaySlotId] = r._score end
            end
        end
    end
    for _, r in ipairs(_results) do
        r.isWeaker = r.isUpgrade and r.displaySlotId
                     and r._score and slotBest[r.displaySlotId]
                     and r._score < slotBest[r.displaySlotId]
    end
end

local function scan()
    _results = {}
    if not _config then return end

    local weaponMode    = _config:Get('WeaponMode')
    local rangedMode    = _config:Get('RangedMode')
    local excludedSlots = Upgrade.ParseExcludedSlots(_config:Get('ExcludedSlots'))

    for bag = 1, 10 do
        local bagSlot = mq.TLO.InvSlot('pack' .. bag).Item
        if bagSlot and bagSlot.ID() and bagSlot.ID() > 0 then
            local size = bagSlot.Container()
            if size and size > 0 then
                for slot = 1, size do
                    local item = bagSlot.Item(slot)
                    if item and item.ID() and item.ID() > 0 then
                        local name = item.Name() or '(unknown)'
                        if (item.WornSlots() or 0) > 0 and not _evalIgnore[name:lower()] then
                            local upgradeSlot = Upgrade.FindUpgradeSlot(item, weaponMode, rangedMode, excludedSlots)

                            -- Find display slot for Slot/Equipped columns even when not an upgrade
                            local displaySlot = upgradeSlot
                            if not displaySlot then
                                for i = 1, (item.WornSlots() or 0) do
                                    local sid = tonumber(item.WornSlot(i)()) or -1
                                    if sid >= 0 and not SKIP_SLOTS[sid] then
                                        displaySlot = sid
                                        break
                                    end
                                end
                            end

                            local slotName     = displaySlot and (Upgrade.SLOT_NAMES[displaySlot] or ('Slot ' .. displaySlot)) or nil
                            local equippedName = nil
                            local equippedAugs = {}
                            if displaySlot then
                                local eq = mq.TLO.Me.Inventory(displaySlot)
                                if eq and eq.ID() and eq.ID() > 0 then
                                    equippedName = eq.Name()
                                    for aug_i = 1, 6 do
                                        local ok, eslot = pcall(function() return eq.AugSlot(aug_i) end)
                                        if ok and eslot and eslot.Item() and eslot.Item.ID and eslot.Item.ID() and eslot.Item.ID() > 0 then
                                            equippedAugs[#equippedAugs+1] = {
                                                name = eslot.Item.Name() or '(aug)',
                                                slot = aug_i,
                                            }
                                        end
                                    end
                                end
                            end

                            local augs = {}
                            for aug_i = 1, 6 do
                                local ok, slot = pcall(function() return item.AugSlot(aug_i) end)
                                if ok and slot and slot.Item() and slot.Item.ID and slot.Item.ID() and slot.Item.ID() > 0 then
                                    augs[#augs+1] = {
                                        name    = slot.Item.Name() or '(aug)',
                                        slot    = aug_i,
                                        solvent = slot.Solvent() or 0,
                                    }
                                end
                            end

                            _results[#_results+1] = {
                                name          = name,
                                id            = item.ID(),
                                isUpgrade     = upgradeSlot ~= nil,
                                slotName      = slotName,
                                equippedName  = equippedName,
                                equippedAugs  = equippedAugs,
                                displaySlotId = displaySlot,
                                bag           = bag,
                                slot          = slot,
                                augs          = augs,
                            }
                        end
                    end
                end
            end
        end
    end

    applySort()
    rankUpgrades()

    _maxAugs = 0
    for _, r in ipairs(_results) do
        if #r.augs > _maxAugs then _maxAugs = #r.augs end
    end
end

-- Width needed to show every Actions-column button (Equip/Trash/Ignore plus one
-- Remove-Aug scissors button per aug slot) without clipping, so the fixed-width
-- column never has to be scrolled to reveal a button.
local function actionsColumnWidth()
    local style   = ImGui.GetStyle()
    local padX    = style.FramePadding.x
    local spacing = style.ItemSpacing.x

    local function btnW(label)
        return (ImGui.CalcTextSize(label)) + padX * 2
    end

    local w = btnW('Equip') + spacing + btnW(Icons.FA_TRASH_O) + spacing + btnW(Icons.FA_BAN)
    if _maxAugs > 0 then
        w = w + _maxAugs * (spacing + btnW(Icons.FA_SCISSORS))
    end
    return w + style.CellPadding.x * 2
end

function UpgradeEval.Open(config)
    _config      = config
    _open        = true
    _ignorePath  = mq.configDir .. 'proloot_evalignore.txt'
    loadIgnore()
    scan()
end

function UpgradeEval.Close()
    _open = false
end

function UpgradeEval.IsOpen()
    return _open
end

function UpgradeEval.RequestRefresh()
    _needsRefresh = true
end

function UpgradeEval.ConsumePendingEquip()
    local v = _pendingEquip
    _pendingEquip = nil
    return v
end

function UpgradeEval.ConsumePendingDestroy()
    local v = _pendingDestroy
    _pendingDestroy = nil
    return v
end

function UpgradeEval.ConsumePendingRemoveAug()
    local v = _pendingRemoveAug
    _pendingRemoveAug = nil
    return v
end

function UpgradeEval.Render()
    if not _open then return end

    if _needsRefresh then
        _needsRefresh = false
        scan()
    end

    ImGui.SetNextWindowSize(ImVec2(900, 400), ImGuiCond.FirstUseEver)
    local open, shouldDraw = ImGui.Begin('ProLoot \xe2\x80\x94 Upgrade Evaluator', _open, ImGuiWindowFlags.None)
    _open = open
    if ImGui.IsWindowFocused() and ImGui.IsKeyPressed(ImGuiKey.Escape) then _open = false end
    if not shouldDraw then ImGui.End(); return end

    local upgradeCount = 0
    for _, r in ipairs(_results) do if r.isUpgrade then upgradeCount = upgradeCount + 1 end end

    if ImGui.Button('Refresh') then scan() end
    ImGui.SameLine()
    ImGui.TextDisabled(string.format('%d item(s) scanned  |  %d upgrade(s) found', #_results, upgradeCount))

    ImGui.Separator()

    if ImGui.BeginTable('##evalresults', 7,
        bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg,
                  ImGuiTableFlags.ScrollY, ImGuiTableFlags.SizingStretchProp),
        ImVec2(0, -1)) then

        ImGui.TableSetupScrollFreeze(0, 1)
        ImGui.TableSetupColumn('Item',               ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('Slot',               ImGuiTableColumnFlags.WidthFixed,   80)
        ImGui.TableSetupColumn('Augment',            ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('Currently Equipped', ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('Equipped Augs',      ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('Verdict',            ImGuiTableColumnFlags.WidthFixed,   90)
        ImGui.TableSetupColumn('Actions',            ImGuiTableColumnFlags.WidthFixed,  actionsColumnWidth())

        -- Manual sortable header row (avoids TableGetSortSpecs binding quirks)
        -- Col 2 (Augment), col 4 (Equipped Augs), and col 6 (Actions) not sortable
        local HDR = { 'Item', 'Slot', 'Augment', 'Currently Equipped', 'Equipped Augs', 'Verdict', 'Actions' }
        ImGui.TableNextRow(ImGuiTableRowFlags.Headers)
        for i, label in ipairs(HDR) do
            local col = i - 1
            ImGui.TableSetColumnIndex(col)
            local sortable = col ~= 2 and col ~= 4 and col ~= 6
            local arrow = (sortable and _sortCol == col) and (_sortAsc and (' ' .. Icons.FA_SORT_ASC) or (' ' .. Icons.FA_SORT_DESC)) or ''
            ImGui.TableHeader(label .. arrow)
            if sortable and ImGui.IsItemClicked() then
                if _sortCol == col then _sortAsc = not _sortAsc
                else _sortCol = col; _sortAsc = true end
                applySort()
            end
        end

        local dl = ImGui.GetWindowDrawList()
        for i, r in ipairs(_results) do
            ImGui.TableNextRow()

            -- Blue row tint for best upgrades only; weaker upgrades and non-upgrades get no tint
            if r.isUpgrade and not r.isWeaker then
                local bg = ImGui.ColorConvertFloat4ToU32(ImVec4(COL_PROLOOT_BLUE.x, COL_PROLOOT_BLUE.y, COL_PROLOOT_BLUE.z, 0.70))
                ImGui.TableSetBgColor(ImGuiTableBgTarget.RowBg0, bg)
                ImGui.TableSetBgColor(ImGuiTableBgTarget.RowBg1, bg)
            end

            -- Item (bag item — clickable, opens EQ examine window)
            ImGui.TableNextColumn()
            if r.isUpgrade and not r.isWeaker then
                ImGui.TextColored(COL_GOLD, r.name)
            else
                ImGui.Text(r.name)
            end
            local rmin = ImGui.GetItemRectMinVec()
            local rmax = ImGui.GetItemRectMaxVec()
            local itemUL = (r.isUpgrade and not r.isWeaker) and ImGui.ColorConvertFloat4ToU32(COL_GOLD) or UNDERLINE_U32
            dl:AddLine(ImVec2(rmin.x, rmax.y), rmax, itemUL, 1.0)
            if ImGui.IsItemHovered() then
                ImGui.SetMouseCursor(ImGuiMouseCursor.Hand)
                local bagItem = mq.TLO.InvSlot('pack' .. r.bag).Item.Item(r.slot)
                local eqItem  = r.displaySlotId and mq.TLO.Me.Inventory(r.displaySlotId) or nil
                if bagItem and bagItem.ID and bagItem.ID() and bagItem.ID() > 0 then
                    ImGui.BeginTooltip()
                    renderDeltaTooltip(bagItem, eqItem)
                    ImGui.EndTooltip()
                end
                if ImGui.IsMouseReleased(ImGuiMouseButton.Left) then
                    local found = mq.TLO.FindItem('=' .. r.name)
                    if found and found.ID() and found.ID() > 0 then
                        found.Inspect()
                    else
                        printf('\ayProLoot: %s is not in your inventory', r.name)
                    end
                end
            end

            -- Slot (always shown)
            ImGui.TableNextColumn()
            if r.slotName then
                ImGui.Text(r.slotName)
            else
                ImGui.TextDisabled('\xe2\x80\x94')
            end

            -- Augment (clickable per aug — opens EQ examine window)
            ImGui.TableNextColumn()
            if #r.augs == 0 then
                ImGui.TextDisabled('\xe2\x80\x94')
            else
                for aug_i, aug in ipairs(r.augs) do
                    if aug_i > 1 then ImGui.Spacing() end
                    ImGui.Text(aug.name)
                    local amin = ImGui.GetItemRectMinVec()
                    local amax = ImGui.GetItemRectMaxVec()
                    dl:AddLine(ImVec2(amin.x, amax.y), amax, UNDERLINE_U32, 1.0)
                    if ImGui.IsItemHovered() then
                        ImGui.SetMouseCursor(ImGuiMouseCursor.Hand)
                        if ImGui.IsMouseReleased(ImGuiMouseButton.Left) then
                            local parent = mq.TLO.FindItem('=' .. r.name)
                            if parent and parent.ID() and parent.ID() > 0 then
                                local augSlot = parent.AugSlot(aug.slot)
                                if augSlot and augSlot.Item() and augSlot.Item.ID and augSlot.Item.ID() > 0 then
                                    augSlot.Item.Inspect()
                                end
                            end
                        end
                    end
                end
            end

            -- Currently Equipped (always shown — clickable if an item is there)
            ImGui.TableNextColumn()
            if r.equippedName then
                ImGui.Text(r.equippedName)
                local ermin = ImGui.GetItemRectMinVec()
                local ermax = ImGui.GetItemRectMaxVec()
                dl:AddLine(ImVec2(ermin.x, ermax.y), ermax, UNDERLINE_U32, 1.0)
                if ImGui.IsItemHovered() then
                    ImGui.SetMouseCursor(ImGuiMouseCursor.Hand)
                    if ImGui.IsMouseReleased(ImGuiMouseButton.Left) then
                        local eq = mq.TLO.Me.Inventory(r.displaySlotId)
                        if eq and eq.ID() and eq.ID() > 0 then
                            eq.Inspect()
                        end
                    end
                end
            elseif r.displaySlotId then
                ImGui.TextDisabled('(empty slot)')
            else
                ImGui.TextDisabled('\xe2\x80\x94')
            end

            -- Equipped Augs (clickable per aug — opens EQ examine window)
            ImGui.TableNextColumn()
            if #r.equippedAugs == 0 then
                ImGui.TextDisabled('\xe2\x80\x94')
            else
                for aug_i, aug in ipairs(r.equippedAugs) do
                    if aug_i > 1 then ImGui.Spacing() end
                    ImGui.Text(aug.name)
                    local eamin = ImGui.GetItemRectMinVec()
                    local eamax = ImGui.GetItemRectMaxVec()
                    dl:AddLine(ImVec2(eamin.x, eamax.y), eamax, UNDERLINE_U32, 1.0)
                    if ImGui.IsItemHovered() then
                        ImGui.SetMouseCursor(ImGuiMouseCursor.Hand)
                        if ImGui.IsMouseReleased(ImGuiMouseButton.Left) then
                            local eq = r.displaySlotId and mq.TLO.Me.Inventory(r.displaySlotId) or nil
                            if eq and eq.ID and eq.ID() and eq.ID() > 0 then
                                local eqAugSlot = eq.AugSlot(aug.slot)
                                if eqAugSlot and eqAugSlot.Item() and eqAugSlot.Item.ID and eqAugSlot.Item.ID() > 0 then
                                    eqAugSlot.Item.Inspect()
                                end
                            end
                        end
                    end
                end
            end

            -- Verdict
            ImGui.TableNextColumn()
            if r.isUpgrade and not r.isWeaker then
                ImGui.TextColored(COL_GOLD, 'Upgrade')
            elseif r.isUpgrade then
                ImGui.TextDisabled('Weaker')
            else
                ImGui.TextDisabled('No Upgrade')
            end

            -- Actions
            ImGui.TableNextColumn()
            local tag = '##' .. i
            local distiller = mq.TLO.FindItem('=Perfected Augmentation Distiller')
            local hasDistiller = distiller and distiller.ID and distiller.ID() and distiller.ID() > 0
            local willCarryAugs = hasDistiller and #r.equippedAugs > 0

            if not r.isUpgrade then ImGui.BeginDisabled() end
            if ImGui.SmallButton('Equip' .. tag) then
                _pendingEquip = {
                    bag = r.bag, slot = r.slot, equipSlot = r.displaySlotId, name = r.name,
                    oldItemName  = r.equippedName,
                    augsToCarry  = willCarryAugs and r.equippedAugs or nil,
                }
            end
            if ImGui.IsItemHovered() and r.isUpgrade then
                if willCarryAugs then
                    local names = {}
                    for _, aug in ipairs(r.equippedAugs) do names[#names+1] = aug.name end
                    ImGui.SetTooltip('Equip this item now\nWill carry over: ' .. table.concat(names, ', '))
                elseif #r.equippedAugs > 0 then
                    ImGui.SetTooltip('Equip this item now\n' .. r.equippedName .. '\'s augment(s) will NOT be carried over\n(requires Perfected Augmentation Distiller)')
                else
                    ImGui.SetTooltip('Equip this item now')
                end
            end
            if not r.isUpgrade then ImGui.EndDisabled() end

            ImGui.SameLine()
            if ImGui.SmallButton(Icons.FA_TRASH_O .. tag) then
                _pendingDestroy = { bag=r.bag, slot=r.slot, name=r.name }
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Destroy this item')
            end

            ImGui.SameLine()
            if ImGui.SmallButton(Icons.FA_BAN .. tag) then
                _evalIgnore[r.name:lower()] = true
                saveIgnore()
                scan()
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip('Hide from Upgrade Evaluator\n(does not affect looting)')
            end

            for _, aug in ipairs(r.augs) do
                ImGui.SameLine()
                if not hasDistiller then ImGui.BeginDisabled() end
                if ImGui.SmallButton(Icons.FA_SCISSORS .. tag .. '_' .. aug.slot) then
                    _pendingRemoveAug = { itemName = r.name, augName = aug.name, augSlot = aug.slot }
                end
                if ImGui.IsItemHovered() then
                    if hasDistiller then
                        ImGui.SetTooltip('Remove aug: ' .. aug.name)
                    else
                        ImGui.SetTooltip('Remove aug: ' .. aug.name .. '\nRequires Perfected Augmentation Distiller (none in inventory)')
                    end
                end
                if not hasDistiller then ImGui.EndDisabled() end
            end
        end

        ImGui.EndTable()
    end

    ImGui.End()
end

return UpgradeEval
