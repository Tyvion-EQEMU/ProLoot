-- Restock confirmation / management window.
-- Solo view: edit this toon's restock list and trigger a buy run.
-- Group view: see all toons' needs side-by-side; trigger Restock All.

local mq = require('mq')

local RestockConfirm = {}

local _open         = false
local _rows         = {}   -- {name, want, have, need} — solo view, refreshed on open/rescan
local _loot         = nil
local _restockList  = nil
local _groupView    = false  -- false = solo view, true = group view

local _pendingItems         = nil    -- consumed by main loop → RestockStuff
local _pendingBroadcast     = nil    -- consumed by main loop → broadcast one item
local _pendingStatusRequest = false  -- consumed by main loop → scan self + broadcast status request
local _pendingRestockAll    = false  -- consumed by main loop → broadcast Restock All

local _addName = ''
local _addQty  = 1

-- -----------------------------------------------------------------------
-- Exports
-- -----------------------------------------------------------------------

function RestockConfirm.Open(loot, restockList)
    _loot        = loot
    _restockList = restockList
    _rows        = loot.ScanRestockNeeds(restockList)
    _groupView   = false
    _open        = true
end

function RestockConfirm.IsOpen()
    return _open
end

function RestockConfirm.ConsumePending()
    local items = _pendingItems
    _pendingItems = nil
    return items
end

function RestockConfirm.ConsumePendingBroadcast()
    local item = _pendingBroadcast
    _pendingBroadcast = nil
    return item
end

function RestockConfirm.ConsumePendingStatusRequest()
    if _pendingStatusRequest then _pendingStatusRequest = false; return true end
    return false
end

function RestockConfirm.ConsumePendingRestockAll()
    if _pendingRestockAll then _pendingRestockAll = false; return true end
    return false
end

-- -----------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------

local function sortedRows()
    local display = {}
    for _, r in ipairs(_rows) do display[#display+1] = r end
    table.sort(display, function(a, b)
        local aNeed = a.need > 0
        local bNeed = b.need > 0
        if aNeed ~= bNeed then return aNeed end
        return a.name:lower() < b.name:lower()
    end)
    return display
end

local GOLD = ImVec4(1.0, 0.75, 0.2, 1.0)
local GREEN = ImVec4(0.4, 0.7, 0.4, 0.8)
local GREEN_B = ImVec4(0.4, 0.8, 0.4, 1.0)
local DIM = ImVec4(0.35, 0.35, 0.35, 1.0)

local function restockAllButton()
    if ImGui.Button('Restock All') then
        _pendingRestockAll = true
        _open = false
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text('Restock All')
        ImGui.TextDisabled('Sends all group toons running ProLoot to restock immediately.')
        ImGui.TextDisabled('Ignores the Auto Restock setting \xe2\x80\x94 no review window shown.')
        ImGui.EndTooltip()
    end
end

-- -----------------------------------------------------------------------
-- Solo view rendering
-- -----------------------------------------------------------------------

local function renderSoloHeader()
    local totalNeed, totalOk = 0, 0
    for _, r in ipairs(_rows) do
        if r.need > 0 then totalNeed = totalNeed + 1 else totalOk = totalOk + 1 end
    end
    if totalNeed > 0 then
        ImGui.Text(('%d need restocking'):format(totalNeed))
        ImGui.SameLine()
        ImGui.TextDisabled(('  |  %d satisfied'):format(totalOk))
    else
        ImGui.TextColored(ImVec4(0.3, 0.9, 0.3, 1.0), 'All stocked!')
        ImGui.SameLine()
        ImGui.TextDisabled(('  %d items'):format(totalOk))
    end
end

local function renderSoloTable()
    if #_rows == 0 then
        ImGui.Spacing()
        ImGui.TextDisabled('No items in restock list. Add items below.')
        return
    end

    if not ImGui.BeginTable('##restocktbl', 6,
        bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg,
                  ImGuiTableFlags.ScrollY, ImGuiTableFlags.SizingStretchProp),
        ImVec2(0, -1)) then return end

    ImGui.TableSetupScrollFreeze(0, 1)
    ImGui.TableSetupColumn('Item',  ImGuiTableColumnFlags.WidthStretch)
    ImGui.TableSetupColumn('Have',  ImGuiTableColumnFlags.WidthFixed, 42)
    ImGui.TableSetupColumn('Want',  ImGuiTableColumnFlags.WidthFixed, 80)
    ImGui.TableSetupColumn('Need',  ImGuiTableColumnFlags.WidthFixed, 42)
    ImGui.TableSetupColumn('',      ImGuiTableColumnFlags.WidthFixed, 28)  -- broadcast
    ImGui.TableSetupColumn('',      ImGuiTableColumnFlags.WidthFixed, 18)  -- remove
    ImGui.TableHeadersRow()

    local display     = sortedRows()
    local drewDivider = false

    for _, r in ipairs(display) do
        local isSatisfied = r.need == 0

        if isSatisfied and not drewDivider then
            drewDivider = true
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.PushStyleColor(ImGuiCol.Text, DIM.x, DIM.y, DIM.z, DIM.w)
            ImGui.Text('\xe2\x94\x80\xe2\x94\x80 satisfied \xe2\x94\x80\xe2\x94\x80')
            ImGui.PopStyleColor()
            ImGui.TableNextColumn(); ImGui.TableNextColumn()
            ImGui.TableNextColumn(); ImGui.TableNextColumn()
            ImGui.TableNextColumn()
        end

        ImGui.TableNextRow()

        -- Item (clickable inspect)
        ImGui.TableNextColumn()
        if isSatisfied then ImGui.TextColored(GREEN, r.name) else ImGui.Text(r.name) end
        if ImGui.IsItemHovered() then
            ImGui.SetMouseCursor(ImGuiMouseCursor.Hand)
            if ImGui.IsMouseReleased(ImGuiMouseButton.Left) then
                local found = mq.TLO.FindItem('=' .. r.name)
                if found and found.ID() and found.ID() > 0 then found.Inspect() end
            end
        end

        -- Have
        ImGui.TableNextColumn()
        if isSatisfied then ImGui.TextColored(GREEN, tostring(r.have)) else ImGui.Text(tostring(r.have)) end

        -- Want (single-click InputInt)
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(-1)
        local newWant, wantChanged = ImGui.InputInt('##want_' .. r.name, r.want, 0, 0)
        if wantChanged and newWant >= 1 then
            _restockList.Set(r.name, newWant)
            r.want = newWant
            r.need = math.max(0, newWant - r.have)
        end

        -- Need
        ImGui.TableNextColumn()
        if r.need > 0 then ImGui.TextColored(GOLD, tostring(r.need))
        else ImGui.TextColored(GREEN, '\xe2\x80\x94') end

        -- Broadcast (fa-share)
        ImGui.TableNextColumn()
        if ImGui.SmallButton('\xef\x81\xa4##bc_' .. r.name) then
            _pendingBroadcast = { name = r.name, qty = r.want }
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text(('Share with group: %s x%d'):format(r.name, r.want))
            ImGui.TextDisabled('Adds or updates this entry on all toons running ProLoot')
            ImGui.EndTooltip()
        end

        -- Remove
        ImGui.TableNextColumn()
        if ImGui.SmallButton('\xc3\x97##rm_' .. r.name) then
            _restockList.Remove(r.name)
            _rows = _loot.ScanRestockNeeds(_restockList)
            break
        end
    end

    ImGui.EndTable()
end

local function renderSoloAddRow()
    ImGui.SetNextItemWidth(180)
    local newName, _ = ImGui.InputText('##addname', _addName)
    _addName = newName
    ImGui.SameLine()
    ImGui.SetNextItemWidth(90)
    local newQty, _ = ImGui.InputInt('##addqty', _addQty, 1, 10)
    _addQty = math.max(1, newQty)
    ImGui.SameLine()
    local canAdd = _addName ~= ''
    if not canAdd then ImGui.BeginDisabled() end
    if ImGui.Button('Add') and canAdd then
        _restockList.Set(_addName, _addQty)
        _rows    = _loot.ScanRestockNeeds(_restockList)
        _addName = ''
    end
    if not canAdd then ImGui.EndDisabled() end

    ImGui.SameLine()
    local cur       = mq.TLO.Cursor
    local hasCursor = cur and cur.ID() and cur.ID() > 0
    if not hasCursor then ImGui.BeginDisabled() end
    if ImGui.Button('from Cursor') then
        local cname = cur.Name() or ''
        if cname ~= '' then
            _restockList.Set(cname, _addQty)
            _rows = _loot.ScanRestockNeeds(_restockList)
            mq.cmd('/autoinventory')
        end
    end
    if hasCursor and ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text(('Add: %s  x%d'):format(cur.Name() or '?', _addQty))
        ImGui.TextDisabled('Uses qty set above. Item returned to inventory.')
        ImGui.EndTooltip()
    end
    if not hasCursor then ImGui.EndDisabled() end
end

local function renderSoloFooter()
    local needItems = {}
    for _, r in ipairs(_rows) do
        if r.need > 0 then needItems[#needItems+1] = r end
    end

    if #needItems > 0 then
        if ImGui.Button(('Restock Now (%d)'):format(#needItems)) then
            _pendingItems = needItems
            _open = false
        end
    else
        ImGui.BeginDisabled()
        ImGui.Button('All Stocked')
        ImGui.EndDisabled()
    end

    ImGui.SameLine()
    if ImGui.Button('Rescan') then _rows = _loot.ScanRestockNeeds(_restockList) end
    ImGui.SameLine()
    if ImGui.Button('Close') then _open = false end

    -- Right-align Status All | Restock All
    local maxX      = select(1, ImGui.GetContentRegionMax())
    local itemSp    = ImGui.GetStyle().ItemSpacing.x
    local statusW   = 80
    local restockW  = 90
    ImGui.SameLine()
    ImGui.SetCursorPosX(maxX - restockW - itemSp - statusW)
    if ImGui.Button('Status All', statusW, 0) then
        _groupView = true
        _pendingStatusRequest = true
        if _loot then _loot.ClearRestockStatusResponses() end
    end
    ImGui.SameLine()
    if ImGui.Button('Restock All', restockW, 0) then
        _pendingRestockAll = true
        _open = false
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text('Restock All')
        ImGui.TextDisabled('Sends all group toons running ProLoot to restock immediately.')
        ImGui.TextDisabled('Ignores the Auto Restock setting \xe2\x80\x94 no review window shown.')
        ImGui.EndTooltip()
    end
end

-- -----------------------------------------------------------------------
-- Group view rendering
-- -----------------------------------------------------------------------

local function renderGroupHeader()
    ImGui.TextColored(GOLD, 'All Characters \xe2\x80\x94 Status')
end

local function renderGroupTable()
    local responses = _loot and _loot.GetRestockStatusResponses() or {}
    local charCount = 0
    for _ in pairs(responses) do charCount = charCount + 1 end

    if charCount == 0 then
        ImGui.Spacing()
        ImGui.TextDisabled('Waiting for responses\xe2\x80\xa6 click Rescan to retry.')
        return
    end

    if not ImGui.BeginTable('##grouptbl', 5,
        bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg,
                  ImGuiTableFlags.ScrollY, ImGuiTableFlags.SizingStretchProp),
        ImVec2(0, -1)) then return end

    ImGui.TableSetupScrollFreeze(0, 1)
    ImGui.TableSetupColumn('Character', ImGuiTableColumnFlags.WidthFixed,  110)
    ImGui.TableSetupColumn('Item',      ImGuiTableColumnFlags.WidthStretch)
    ImGui.TableSetupColumn('Have',      ImGuiTableColumnFlags.WidthFixed,   42)
    ImGui.TableSetupColumn('Want',      ImGuiTableColumnFlags.WidthFixed,   42)
    ImGui.TableSetupColumn('Need',      ImGuiTableColumnFlags.WidthFixed,   42)
    ImGui.TableHeadersRow()

    local chars = {}
    for name in pairs(responses) do chars[#chars+1] = name end
    table.sort(chars, function(a, b) return a:lower() < b:lower() end)

    for _, charName in ipairs(chars) do
        local needs = responses[charName].needs or {}

        if #needs == 0 then
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.TextColored(GREEN_B, charName)
            ImGui.TableNextColumn()
            ImGui.TextColored(ImVec4(0.4, 0.8, 0.4, 0.7), 'all stocked \xe2\x9c\x93')
            ImGui.TableNextColumn(); ImGui.TableNextColumn(); ImGui.TableNextColumn()
        else
            for i, r in ipairs(needs) do
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                if i == 1 then ImGui.TextColored(GOLD, charName) end
                ImGui.TableNextColumn()
                ImGui.Text(r.name)
                ImGui.TableNextColumn()
                ImGui.Text(tostring(r.have))
                ImGui.TableNextColumn()
                ImGui.Text(tostring(r.want))
                ImGui.TableNextColumn()
                ImGui.TextColored(GOLD, tostring(r.need))
            end
        end
    end

    ImGui.EndTable()
end

local function renderGroupFooter()
    restockAllButton()
    ImGui.SameLine()
    if ImGui.Button('Rescan') then
        _pendingStatusRequest = true
        if _loot then _loot.ClearRestockStatusResponses() end
    end
    ImGui.SameLine()
    if ImGui.Button('Close') then _open = false end

    -- Right-align Solo
    local maxX  = select(1, ImGui.GetContentRegionMax())
    local soloW = 50
    ImGui.SameLine()
    ImGui.SetCursorPosX(maxX - soloW)
    if ImGui.Button('Solo', soloW, 0) then _groupView = false end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.TextDisabled('Return to Solo Status')
        ImGui.EndTooltip()
    end
end

-- -----------------------------------------------------------------------
-- Main render
-- -----------------------------------------------------------------------

function RestockConfirm.Render()
    if not _open then return end

    ImGui.SetNextWindowSize(ImVec2(480, 400), ImGuiCond.FirstUseEver)
    local open, shouldDraw = ImGui.Begin('ProLoot \xe2\x80\x94 Restock', _open, ImGuiWindowFlags.None)
    _open = open
    if ImGui.IsWindowFocused() and ImGui.IsKeyPressed(ImGuiKey.Escape) then _open = false end
    if not shouldDraw then ImGui.End(); return end

    if _groupView then renderGroupHeader() else renderSoloHeader() end

    ImGui.Separator()

    -- Reserve footer: group view has no add-row so it needs less space
    local footerH = _groupView
        and (ImGui.GetTextLineHeight() + ImGui.GetStyle().ItemSpacing.y * 2 + 8)
        or  (ImGui.GetTextLineHeight() * 2 + ImGui.GetStyle().ItemSpacing.y * 4 + 8)

    ImGui.BeginChild('##restocklist', ImVec2(0, -footerH), ImGuiChildFlags.None)
    if _groupView then renderGroupTable() else renderSoloTable() end
    ImGui.EndChild()

    if not _groupView then renderSoloAddRow() end

    ImGui.Separator()

    if _groupView then renderGroupFooter() else renderSoloFooter() end

    ImGui.End()
end

return RestockConfirm
