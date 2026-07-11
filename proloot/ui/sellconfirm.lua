-- Sell Stuff confirmation window.
-- Solo view: review this toon's sell queue and trigger a sell run.
-- Group view: see all toons' sell queues side-by-side.

local mq = require('mq')

local SellConfirm = {}

local _open        = false
local _items       = {}
local _loot        = nil
local _iconAnim    = nil
local _groupView   = false
local _pendingItems          = nil
local _pendingSellAll        = false
local _pendingStatusRequest  = false

local EQ_ICON_OFFSET = 500
local ICON_SIZE      = 40

local GOLD    = ImVec4(1.0, 0.75, 0.2,  1.0)
local GREEN_B = ImVec4(0.4, 0.8,  0.4,  1.0)

local function getIconAnim()
    if not _iconAnim then _iconAnim = mq.FindTextureAnimation('A_DragItem') end
    return _iconAnim
end

local function formatCopper(cp)
    if cp <= 0 then return '\xe2\x80\x94' end
    local pp = math.floor(cp / 1000); cp = cp % 1000
    local gp = math.floor(cp / 100);  cp = cp % 100
    local sp = math.floor(cp / 10);   local c = cp % 10
    local parts = {}
    if pp > 0 then parts[#parts+1] = pp .. 'p' end
    if gp > 0 then parts[#parts+1] = gp .. 'g' end
    if sp > 0 then parts[#parts+1] = sp .. 's' end
    if c  > 0 then parts[#parts+1] = c  .. 'c' end
    return table.concat(parts, ' ')
end

-----------------------------------------------------------------------
-- Exports
-----------------------------------------------------------------------

function SellConfirm.Open(loot)
    _loot      = loot
    _items     = loot.ScanSellItems()
    _groupView = false
    _open      = true
end

function SellConfirm.IsOpen() return _open end

function SellConfirm.ConsumePending()
    local items = _pendingItems
    _pendingItems = nil
    return items
end

function SellConfirm.ConsumePendingSellStatusRequest()
    if _pendingStatusRequest then _pendingStatusRequest = false; return true end
    return false
end

function SellConfirm.ConsumePendingSellAll()
    if _pendingSellAll then _pendingSellAll = false; return true end
    return false
end

-----------------------------------------------------------------------
-- Solo view
-----------------------------------------------------------------------

local function renderSoloHeader()
    if #_items == 0 then
        ImGui.TextDisabled('No sell-list items found in inventory.')
    else
        local totalCopper = 0
        for _, e in ipairs(_items) do totalCopper = totalCopper + e.value end
        ImGui.Text(('%d item(s) ready to sell  \xe2\x80\x94  est. total: %s'):format(
            #_items, formatCopper(totalCopper)))
    end
end

local function renderSoloTable()
    if #_items == 0 then
        ImGui.Spacing()
        ImGui.TextDisabled('Nothing to sell — add items to your sell list first.')
        return
    end

    if not ImGui.BeginTable('##selltbl', 4,
        bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg,
                  ImGuiTableFlags.ScrollY, ImGuiTableFlags.SizingStretchProp),
        ImVec2(0, -1)) then return end

    ImGui.TableSetupScrollFreeze(0, 1)
    ImGui.TableSetupColumn('Item',  ImGuiTableColumnFlags.WidthStretch)
    ImGui.TableSetupColumn('Bag',   ImGuiTableColumnFlags.WidthFixed, 36)
    ImGui.TableSetupColumn('Slot',  ImGuiTableColumnFlags.WidthFixed, 36)
    ImGui.TableSetupColumn('Value', ImGuiTableColumnFlags.WidthFixed, 80)
    ImGui.TableHeadersRow()

    for _, e in ipairs(_items) do
        ImGui.TableNextRow()

        ImGui.TableNextColumn()
        local canSell = e.value > 0
        if canSell then ImGui.Text(e.name) else ImGui.TextDisabled(e.name) end
        if ImGui.IsItemHovered() then
            if ImGui.IsMouseReleased(ImGuiMouseButton.Left) then
                local found = mq.TLO.FindItem('=' .. e.name)
                if found and found.ID() and found.ID() > 0 then found.Inspect() end
            end
            local item = mq.TLO.InvSlot('pack' .. e.bag).Item.Item(e.slot)
            if item and item.ID() and item.ID() > 0 then
                ImGui.BeginTooltip()
                local iconId = item.Icon()
                local anim   = getIconAnim()
                if iconId and iconId > 0 and anim then
                    anim:SetTextureCell(iconId - EQ_ICON_OFFSET)
                    ImGui.DrawTextureAnimation(anim, ICON_SIZE, ICON_SIZE)
                    ImGui.SameLine()
                    ImGui.SetCursorPosY(ImGui.GetCursorPosY() + (ICON_SIZE - ImGui.GetTextLineHeight()) * 0.5)
                end
                ImGui.TextColored(ImVec4(1.0, 1.0, 0.4, 1.0), item.Name() or e.name)
                ImGui.Separator()
                ImGui.PushTextWrapPos(300)
                local itype = item.Type()
                if itype then ImGui.Text('Type:   ' .. itype) end
                local flags = {}
                if item.NoDrop()    then flags[#flags+1] = 'No Drop'   end
                if item.Lore()      then flags[#flags+1] = 'Lore'      end
                if item.Stackable() then flags[#flags+1] = 'Stackable' end
                if #flags > 0 then ImGui.TextDisabled(table.concat(flags, '   ')) end
                if e.value > 0 then
                    ImGui.Text('Value:  ' .. formatCopper(e.value))
                else
                    ImGui.TextColored(ImVec4(1.0, 0.4, 0.4, 1.0), 'No vendor value — will be skipped')
                end
                local wt = item.Weight()
                if wt and wt > 0 then ImGui.Text(('Weight: %.1f'):format(wt)) end
                local loreText = item.LoreText and item.LoreText() or nil
                if loreText and loreText ~= '' then
                    ImGui.Spacing(); ImGui.TextDisabled(loreText)
                end
                ImGui.PopTextWrapPos()
                ImGui.EndTooltip()
            end
        end

        ImGui.TableNextColumn(); ImGui.TextDisabled(tostring(e.bag))
        ImGui.TableNextColumn(); ImGui.TextDisabled(tostring(e.slot))
        ImGui.TableNextColumn()
        if e.value > 0 then ImGui.Text(formatCopper(e.value))
        else ImGui.TextColored(ImVec4(0.6, 0.3, 0.3, 1.0), 'no value') end
    end

    ImGui.EndTable()
end

local function renderSoloFooter()
    local maxX   = select(1, ImGui.GetContentRegionMax())
    local itemSp = ImGui.GetStyle().ItemSpacing.x
    local statusW = 80
    local sellAllW = 75

    if #_items > 0 then
        -- Left: Sell Now (N) | Rescan | Cancel
        if ImGui.Button(('Sell Now (%d)'):format(#_items)) then
            _pendingItems = _items
            _open = false
        end
        ImGui.SameLine()
        if ImGui.Button('Rescan') then _items = _loot.ScanSellItems() end
        ImGui.SameLine()
        if ImGui.Button('Cancel') then _open = false end
        -- Right: Status All | Sell All
        ImGui.SameLine()
        ImGui.SetCursorPosX(maxX - sellAllW - itemSp - statusW)
        if ImGui.Button('Status All', statusW, 0) then
            _groupView = true
            _pendingStatusRequest = true
            if _loot then _loot.ClearSellStatusResponses() end
        end
        ImGui.SameLine()
        if ImGui.Button('Sell All', sellAllW, 0) then
            _pendingSellAll = true
            _open = false
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text('Sell All')
            ImGui.TextDisabled('Sends all group toons running ProLoot to sell immediately.')
            ImGui.EndTooltip()
        end
    else
        -- Left: Rescan | Cancel
        if ImGui.Button('Rescan') then _items = _loot.ScanSellItems() end
        ImGui.SameLine()
        if ImGui.Button('Cancel') then _open = false end
        -- Right: Status All | Sell All
        ImGui.SameLine()
        ImGui.SetCursorPosX(maxX - sellAllW - itemSp - statusW)
        if ImGui.Button('Status All', statusW, 0) then
            _groupView = true
            _pendingStatusRequest = true
            if _loot then _loot.ClearSellStatusResponses() end
        end
        ImGui.SameLine()
        if ImGui.Button('Sell All', sellAllW, 0) then
            _pendingSellAll = true
            _open = false
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text('Sell All')
            ImGui.TextDisabled('Sends all group toons running ProLoot to sell immediately.')
            ImGui.EndTooltip()
        end
    end
end

-----------------------------------------------------------------------
-- Group view
-----------------------------------------------------------------------

local function renderGroupHeader()
    ImGui.TextColored(GOLD, 'All Characters \xe2\x80\x94 Sell Queue')
end

local function renderGroupTable()
    local responses = _loot and _loot.GetSellStatusResponses() or {}
    local charCount = 0
    for _ in pairs(responses) do charCount = charCount + 1 end

    if charCount == 0 then
        ImGui.Spacing()
        ImGui.TextDisabled('Waiting for responses\xe2\x80\xa6 click Rescan to retry.')
        return
    end

    if not ImGui.BeginTable('##sellgrouptbl', 3,
        bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg,
                  ImGuiTableFlags.ScrollY, ImGuiTableFlags.SizingStretchProp),
        ImVec2(0, -1)) then return end

    ImGui.TableSetupScrollFreeze(0, 1)
    ImGui.TableSetupColumn('Character', ImGuiTableColumnFlags.WidthFixed,  110)
    ImGui.TableSetupColumn('Item',      ImGuiTableColumnFlags.WidthStretch)
    ImGui.TableSetupColumn('Value',     ImGuiTableColumnFlags.WidthFixed,   80)
    ImGui.TableHeadersRow()

    local chars = {}
    for name in pairs(responses) do chars[#chars+1] = name end
    table.sort(chars, function(a, b) return a:lower() < b:lower() end)

    for _, charName in ipairs(chars) do
        local items = responses[charName].items or {}
        if #items == 0 then
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.TextColored(GREEN_B, charName)
            ImGui.TableNextColumn()
            ImGui.TextColored(ImVec4(0.4, 0.8, 0.4, 0.7), 'nothing to sell \xe2\x9c\x93')
            ImGui.TableNextColumn()
        else
            for i, item in ipairs(items) do
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                if i == 1 then ImGui.TextColored(GOLD, charName) end
                ImGui.TableNextColumn()
                ImGui.Text(item.name)
                ImGui.TableNextColumn()
                ImGui.TextDisabled(formatCopper(item.value))
            end
        end
    end

    ImGui.EndTable()
end

local function renderGroupFooter()
    local maxX   = select(1, ImGui.GetContentRegionMax())
    local itemSp = ImGui.GetStyle().ItemSpacing.x
    local soloW  = 50

    -- Left: Sell All | Rescan | Cancel
    if ImGui.Button('Sell All') then
        _pendingSellAll = true
        _open = false
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text('Sell All')
        ImGui.TextDisabled('Sends all group toons running ProLoot to sell immediately.')
        ImGui.EndTooltip()
    end
    ImGui.SameLine()
    if ImGui.Button('Rescan') then
        _pendingStatusRequest = true
        if _loot then _loot.ClearSellStatusResponses() end
    end
    ImGui.SameLine()
    if ImGui.Button('Cancel') then _open = false end
    -- Right: Solo
    ImGui.SameLine()
    ImGui.SetCursorPosX(maxX - soloW)
    if ImGui.Button('Solo', soloW, 0) then _groupView = false end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.TextDisabled('Return to Solo View')
        ImGui.EndTooltip()
    end
end

-----------------------------------------------------------------------
-- Main render
-----------------------------------------------------------------------

function SellConfirm.Render()
    if not _open then return end

    ImGui.SetNextWindowSize(ImVec2(480, 320), ImGuiCond.FirstUseEver)
    local open, shouldDraw = ImGui.Begin('ProLoot \xe2\x80\x94 Sell Stuff', _open, ImGuiWindowFlags.None)
    _open = open
    if ImGui.IsWindowFocused() and ImGui.IsKeyPressed(ImGuiKey.Escape) then _open = false end
    if not shouldDraw then ImGui.End(); return end

    if _groupView then renderGroupHeader() else renderSoloHeader() end
    ImGui.Separator()

    local footerH = ImGui.GetTextLineHeight() + ImGui.GetStyle().ItemSpacing.y * 2 + 8
    ImGui.BeginChild('##selllist', ImVec2(0, -footerH), ImGuiChildFlags.None)
    if _groupView then renderGroupTable() else renderSoloTable() end
    ImGui.EndChild()

    ImGui.Separator()
    if _groupView then renderGroupFooter() else renderSoloFooter() end

    ImGui.End()
end

return SellConfirm
