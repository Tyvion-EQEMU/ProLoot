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

local _pendingEquip   = nil  -- { bag, slot, equipSlot, name }
local _pendingDestroy = nil  -- { bag, slot, name }

local COL_PROLOOT_BLUE = ImVec4(0.16, 0.29, 0.48, 1.0)  -- ProLoot Blue: ImGui dark theme TitleBgActive; used for row highlights
local COL_GOLD         = ImVec4(1.0,  0.72, 0.20, 1.0)  -- ProLoot Gold: matches BUTTON_GOLD in panel.lua
local UNDERLINE_U32    = 0xCCFFFFFF  -- white at ~80% alpha for clickable underlines

local SKIP_SLOTS = { [0]=true, [21]=true, [22]=true }

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
                            if displaySlot then
                                local eq = mq.TLO.Me.Inventory(displaySlot)
                                if eq and eq.ID() and eq.ID() > 0 then
                                    equippedName = eq.Name()
                                end
                            end

                            _results[#_results+1] = {
                                name          = name,
                                id            = item.ID(),
                                isUpgrade     = upgradeSlot ~= nil,
                                slotName      = slotName,
                                equippedName  = equippedName,
                                displaySlotId = displaySlot,
                                bag           = bag,
                                slot          = slot,
                            }
                        end
                    end
                end
            end
        end
    end

    -- Upgrades first, then alphabetical within each group
    table.sort(_results, function(a, b)
        if a.isUpgrade ~= b.isUpgrade then return a.isUpgrade end
        return a.name:lower() < b.name:lower()
    end)
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

function UpgradeEval.Render()
    if not _open then return end

    if _needsRefresh then
        _needsRefresh = false
        scan()
    end

    ImGui.SetNextWindowSize(ImVec2(740, 400), ImGuiCond.FirstUseEver)
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

    if ImGui.BeginTable('##evalresults', 5,
        bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg,
                  ImGuiTableFlags.ScrollY, ImGuiTableFlags.SizingStretchProp),
        ImVec2(0, -1)) then

        ImGui.TableSetupScrollFreeze(0, 1)
        ImGui.TableSetupColumn('Item',               ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('Slot',               ImGuiTableColumnFlags.WidthFixed,   80)
        ImGui.TableSetupColumn('Currently Equipped', ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('Verdict',            ImGuiTableColumnFlags.WidthFixed,   90)
        ImGui.TableSetupColumn('Actions',            ImGuiTableColumnFlags.WidthFixed,  120)
        ImGui.TableHeadersRow()

        local dl = ImGui.GetWindowDrawList()
        for i, r in ipairs(_results) do
            ImGui.TableNextRow()

            -- Blue row tint for upgrades; no tint for non-upgrades
            if r.isUpgrade then
                local bg = ImGui.ColorConvertFloat4ToU32(ImVec4(COL_PROLOOT_BLUE.x, COL_PROLOOT_BLUE.y, COL_PROLOOT_BLUE.z, 0.70))
                ImGui.TableSetBgColor(ImGuiTableBgTarget.RowBg0, bg)
                ImGui.TableSetBgColor(ImGuiTableBgTarget.RowBg1, bg)
            end

            -- Item (bag item — clickable, opens EQ examine window)
            ImGui.TableNextColumn()
            if r.isUpgrade then
                ImGui.TextColored(COL_GOLD, r.name)
            else
                ImGui.Text(r.name)
            end
            local rmin = ImGui.GetItemRectMinVec()
            local rmax = ImGui.GetItemRectMaxVec()
            local itemUL = r.isUpgrade and ImGui.ColorConvertFloat4ToU32(COL_GOLD) or UNDERLINE_U32
            dl:AddLine(ImVec2(rmin.x, rmax.y), rmax, itemUL, 1.0)
            if ImGui.IsItemHovered() then
                ImGui.SetMouseCursor(ImGuiMouseCursor.Hand)
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

            -- Verdict
            ImGui.TableNextColumn()
            if r.isUpgrade then
                ImGui.TextColored(COL_GOLD, 'Upgrade')
            else
                ImGui.TextDisabled('No Upgrade')
            end

            -- Actions
            ImGui.TableNextColumn()
            local tag = '##' .. i

            if not r.isUpgrade then ImGui.BeginDisabled() end
            if ImGui.SmallButton('Equip' .. tag) then
                _pendingEquip = { bag=r.bag, slot=r.slot, equipSlot=r.displaySlotId, name=r.name }
            end
            if ImGui.IsItemHovered() and r.isUpgrade then
                ImGui.SetTooltip('Equip this item now')
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
        end

        ImGui.EndTable()
    end

    ImGui.End()
end

return UpgradeEval
