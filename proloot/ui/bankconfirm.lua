-- Bank Stuff confirmation window.
-- Solo view: review this toon's bank queue and trigger a deposit run.
-- Group view: see all toons' bank queues side-by-side.

local mq = require('mq')

local BankConfirm = {}

local _open       = false
local _items      = {}
local _loot       = nil
local _iconAnim   = nil
local _groupView  = false
local _pendingItems          = nil
local _pendingBankAll        = false
local _pendingConsolidate    = false
local _pendingConsolidateAll = false
local _pendingStatusRequest  = false

local EQ_ICON_OFFSET = 500
local ICON_SIZE      = 40

local GOLD    = ImVec4(1.0, 0.75, 0.2,  1.0)
local GREEN_B = ImVec4(0.4, 0.8,  0.4,  1.0)

local function getIconAnim()
    if not _iconAnim then _iconAnim = mq.FindTextureAnimation('A_DragItem') end
    return _iconAnim
end

-----------------------------------------------------------------------
-- Exports
-----------------------------------------------------------------------

function BankConfirm.Open(loot)
    _loot      = loot
    _items     = loot.ScanBankItems()
    _groupView = false
    _open      = true
end

function BankConfirm.IsOpen() return _open end

function BankConfirm.ConsumePending()
    local items = _pendingItems
    _pendingItems = nil
    return items
end

function BankConfirm.ConsumePendingConsolidate()
    local pending = _pendingConsolidate
    _pendingConsolidate = false
    return pending
end

function BankConfirm.ConsumePendingConsolidateAll()
    if _pendingConsolidateAll then _pendingConsolidateAll = false; return true end
    return false
end

function BankConfirm.ConsumePendingBankAll()
    if _pendingBankAll then _pendingBankAll = false; return true end
    return false
end

function BankConfirm.ConsumePendingBankStatusRequest()
    if _pendingStatusRequest then _pendingStatusRequest = false; return true end
    return false
end

-----------------------------------------------------------------------
-- Solo view
-----------------------------------------------------------------------

local function renderSoloHeader()
    if #_items == 0 then
        ImGui.TextDisabled('No bank-list items found in inventory.')
    else
        ImGui.Text(('%d item(s) ready to deposit:'):format(#_items))
    end
end

local function renderSoloTable()
    if #_items == 0 then
        ImGui.Spacing()
        ImGui.TextDisabled('Nothing to bank — add items to your bank list first.')
        return
    end

    if not ImGui.BeginTable('##banktbl', 3,
        bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg,
                  ImGuiTableFlags.ScrollY, ImGuiTableFlags.SizingStretchProp),
        ImVec2(0, -1)) then return end

    ImGui.TableSetupScrollFreeze(0, 1)
    ImGui.TableSetupColumn('Item', ImGuiTableColumnFlags.WidthStretch)
    ImGui.TableSetupColumn('Bag',  ImGuiTableColumnFlags.WidthFixed, 40)
    ImGui.TableSetupColumn('Slot', ImGuiTableColumnFlags.WidthFixed, 40)
    ImGui.TableHeadersRow()

    for _, e in ipairs(_items) do
        ImGui.TableNextRow()

        ImGui.TableNextColumn()
        ImGui.Text(e.name)
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
                local val = item.Value() or 0
                if val > 0 then
                    local rem = val
                    local pp  = math.floor(rem / 1000); rem = rem % 1000
                    local gp  = math.floor(rem / 100);  rem = rem % 100
                    local sp  = math.floor(rem / 10);   local cp = rem % 10
                    local parts = {}
                    if pp > 0 then parts[#parts+1] = pp .. 'p' end
                    if gp > 0 then parts[#parts+1] = gp .. 'g' end
                    if sp > 0 then parts[#parts+1] = sp .. 's' end
                    if cp > 0 then parts[#parts+1] = cp .. 'c' end
                    if #parts > 0 then ImGui.Text('Value:  ' .. table.concat(parts, ' ')) end
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
    end

    ImGui.EndTable()
end

local function renderSoloFooter()
    local maxX    = select(1, ImGui.GetContentRegionMax())
    local itemSp  = ImGui.GetStyle().ItemSpacing.x
    local statusW = 80
    local bankAllW = 75

    -- Row 1: primary actions left, Status All | Bank All right
    if #_items > 0 then
        if ImGui.Button(('Bank Now (%d)'):format(#_items)) then
            _pendingItems = _items
            _open = false
        end
        ImGui.SameLine()
    end
    if ImGui.Button('Rescan') then _items = _loot.ScanBankItems() end
    ImGui.SameLine()
    if ImGui.Button('Cancel') then _open = false end
    ImGui.SameLine()
    ImGui.SetCursorPosX(maxX - bankAllW - itemSp - statusW)
    if ImGui.Button('Status All', statusW, 0) then
        _groupView = true
        _pendingStatusRequest = true
        if _loot then _loot.ClearBankStatusResponses() end
    end
    ImGui.SameLine()
    if ImGui.Button('Bank All', bankAllW, 0) then
        _pendingBankAll = true
        _open = false
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text('Bank All')
        ImGui.TextDisabled('Sends all group toons running ProLoot to deposit immediately.')
        ImGui.EndTooltip()
    end

    -- Row 2: utility action on its own line
    if ImGui.Button('Consolidate Coins') then
        _pendingConsolidate = true
        _open = false
    end
end

-----------------------------------------------------------------------
-- Group view
-----------------------------------------------------------------------

local function renderGroupHeader()
    ImGui.TextColored(GOLD, 'All Characters \xe2\x80\x94 Bank Queue')
end

local function renderGroupTable()
    local responses = _loot and _loot.GetBankStatusResponses() or {}
    local charCount = 0
    for _ in pairs(responses) do charCount = charCount + 1 end

    if charCount == 0 then
        ImGui.Spacing()
        ImGui.TextDisabled('Waiting for responses\xe2\x80\xa6 click Rescan to retry.')
        return
    end

    if not ImGui.BeginTable('##bankgrouptbl', 2,
        bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg,
                  ImGuiTableFlags.ScrollY, ImGuiTableFlags.SizingStretchProp),
        ImVec2(0, -1)) then return end

    ImGui.TableSetupScrollFreeze(0, 1)
    ImGui.TableSetupColumn('Character', ImGuiTableColumnFlags.WidthFixed,  110)
    ImGui.TableSetupColumn('Item',      ImGuiTableColumnFlags.WidthStretch)
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
            ImGui.TextColored(ImVec4(0.4, 0.8, 0.4, 0.7), 'nothing to bank \xe2\x9c\x93')
        else
            for i, item in ipairs(items) do
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                if i == 1 then ImGui.TextColored(GOLD, charName) end
                ImGui.TableNextColumn()
                ImGui.Text(item.name)
            end
        end
    end

    ImGui.EndTable()
end

local function renderGroupFooter()
    local maxX   = select(1, ImGui.GetContentRegionMax())
    local itemSp = ImGui.GetStyle().ItemSpacing.x
    local soloW  = 50

    -- Left: Bank All | Rescan | Cancel | Consolidate All
    if ImGui.Button('Bank All') then
        _pendingBankAll = true
        _open = false
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text('Bank All')
        ImGui.TextDisabled('Sends all group toons running ProLoot to deposit immediately.')
        ImGui.EndTooltip()
    end
    ImGui.SameLine()
    if ImGui.Button('Rescan') then
        _pendingStatusRequest = true
        if _loot then _loot.ClearBankStatusResponses() end
    end
    ImGui.SameLine()
    if ImGui.Button('Cancel') then _open = false end
    ImGui.SameLine()
    if ImGui.Button('Consolidate All') then
        _pendingConsolidateAll = true
        _open = false
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text('Consolidate All')
        ImGui.TextDisabled('Sends all group toons running ProLoot to consolidate coins.')
        ImGui.EndTooltip()
    end
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

function BankConfirm.Render()
    if not _open then return end

    ImGui.SetNextWindowSize(ImVec2(480, 320), ImGuiCond.FirstUseEver)
    local open, shouldDraw = ImGui.Begin('ProLoot \xe2\x80\x94 Bank Stuff', _open, ImGuiWindowFlags.None)
    _open = open
    if ImGui.IsWindowFocused() and ImGui.IsKeyPressed(ImGuiKey.Escape) then _open = false end
    if not shouldDraw then ImGui.End(); return end

    if _groupView then renderGroupHeader() else renderSoloHeader() end
    ImGui.Separator()

    local lineH   = ImGui.GetTextLineHeight() + ImGui.GetStyle().ItemSpacing.y * 2 + 6
    local footerH = _groupView and (lineH + 4) or (lineH * 2 + ImGui.GetStyle().ItemSpacing.y + 4)
    ImGui.BeginChild('##banklist', ImVec2(0, -footerH), ImGuiChildFlags.None)
    if _groupView then renderGroupTable() else renderSoloTable() end
    ImGui.EndChild()

    ImGui.Separator()
    if _groupView then renderGroupFooter() else renderSoloFooter() end

    ImGui.End()
end

return BankConfirm
