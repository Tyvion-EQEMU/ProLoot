-- Loot list editor: tabbed ImGui window per list type, Add-from-Cursor, live filter
-- Changes are written to disk immediately on every add/remove (auto-save).
-- "Reload for All" broadcasts a reload signal to group peers via channel.

local mq = require('mq')

local Editor = {}

local _open    = false
local _lists   = nil
local _channel = nil
local _filter  = {}

local TAB_ORDER = {
    'keep', 'bank', 'sell',
    'quest', 'event', 'lore', 'astrial',
    'tiered', 'beasts', 'deva', 'specials',
    'destroy', 'skip',
}
local TAB_LABELS = {
    keep     = 'Keep',
    bank     = 'Bank',
    sell     = 'Sell',
    quest    = 'Quest',
    event    = 'Event',
    lore     = 'Lore',
    astrial  = 'Astrial',
    tiered   = 'Tiered',
    beasts   = 'Beasts',
    deva     = 'Deva',
    specials = 'Specials',
    destroy  = 'Force Destroy',
    skip     = 'Force Skip',
}

function Editor.Open(lists, channel)
    _lists   = lists
    _channel = channel
    _open    = true
    for _, name in ipairs(TAB_ORDER) do
        _filter[name] = _filter[name] or ''
    end
end

function Editor.IsOpen()
    return _open
end

function Editor.Close()
    _open = false
end

local function renderTab(listName)
    local lst       = _lists[listName]
    local filterKey = '##filter_' .. listName

    ImGui.SetNextItemWidth(200)
    local newFilter, _ = ImGui.InputText(filterKey, _filter[listName] or '')
    _filter[listName]  = newFilter
    local filterLow    = newFilter:lower()

    ImGui.SameLine()

    if ImGui.Button('Add from Cursor##' .. listName) then
        local cursor = mq.TLO.Cursor
        if cursor and cursor.ID() and cursor.ID() > 0 then
            local name = cursor.Name() or ''
            local id   = cursor.ID()   or 0
            if lst:Add(name, id) then
                lst:Save()
            end
            mq.cmd('/autoinventory')
        end
    end

    ImGui.SameLine()

    if ImGui.Button('Reload for All##' .. listName) then
        if _channel then
            _channel:BroadcastAll({ type='reload_lists' })
        end
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.PushTextWrapPos(260)
        ImGui.TextWrapped('Signal all toons running ProLoot to reload their lists from disk')
        ImGui.PopTextWrapPos()
        ImGui.EndTooltip()
    end

    ImGui.SameLine()

    if ImGui.Button('Revert##' .. listName) then
        lst:Load()
    end

    ImGui.Separator()

    ImGui.BeginChild('##list_' .. listName, ImVec2(0, -30), ImGuiChildFlags.None)

    if ImGui.BeginTable('##tbl_' .. listName, 4,
        bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg,
                  ImGuiTableFlags.SizingStretchProp)) then

        ImGui.TableSetupColumn('#',    ImGuiTableColumnFlags.WidthFixed,  30)
        ImGui.TableSetupColumn('Item', ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn('ID',   ImGuiTableColumnFlags.WidthFixed,  65)
        ImGui.TableSetupColumn('',     ImGuiTableColumnFlags.WidthFixed,  22)
        ImGui.TableHeadersRow()

        local entries  = lst:Entries()
        local toRemove = nil
        for i, entry in ipairs(entries) do
            if filterLow == '' or entry.name:lower():find(filterLow, 1, true) then
                ImGui.TableNextRow()

                ImGui.TableNextColumn()
                ImGui.TextDisabled(tostring(i))

                ImGui.TableNextColumn()
                ImGui.Text(entry.name)
                if ImGui.IsItemHovered() then
                    ImGui.SetMouseCursor(ImGuiMouseCursor.Hand)
                    if ImGui.IsMouseReleased(ImGuiMouseButton.Left) then
                        local found = mq.TLO.FindItem('=' .. entry.name)
                        if found and found.ID() and found.ID() > 0 then
                            found.Inspect()
                        else
                            printf('\ayProLoot: %s is not in your inventory', entry.name)
                        end
                    end
                end

                ImGui.TableNextColumn()
                if entry.id and entry.id > 0 then
                    ImGui.TextDisabled(tostring(entry.id))
                end

                ImGui.TableNextColumn()
                if ImGui.SmallButton('X##' .. listName .. i) then
                    toRemove = entry.name
                end
            end
        end

        if toRemove then
            lst:Remove(toRemove)
            lst:Save()
        end

        ImGui.EndTable()
    end

    ImGui.EndChild()
end

function Editor.Render()
    if not _open or not _lists then return end

    ImGui.SetNextWindowSize(ImVec2(520, 480), ImGuiCond.FirstUseEver)
    local open, shouldDraw = ImGui.Begin('ProLoot — List Editor', _open,
        ImGuiWindowFlags.None)
    _open = open
    if ImGui.IsWindowFocused() and ImGui.IsKeyPressed(ImGuiKey.Escape) then _open = false end

    if shouldDraw then
        if ImGui.BeginTabBar('##tabs') then
            for _, name in ipairs(TAB_ORDER) do
                if ImGui.BeginTabItem(TAB_LABELS[name] .. '##' .. name) then
                    renderTab(name)
                    ImGui.EndTabItem()
                end
            end
            ImGui.EndTabBar()
        end
    end

    ImGui.End()
end

return Editor
