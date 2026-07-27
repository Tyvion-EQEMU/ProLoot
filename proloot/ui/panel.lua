-- Main ImGui panel: header, pause/resume, two-column settings, history, mini-mode

local mq      = require('mq')
local Icons   = require('mq.ICONS')
local Corpse  = require('proloot.core.corpse')
local Upgrade = require('proloot.core.upgrade')
local Mini    = require('proloot.ui.mini')
local Logger  = require('proloot.utils.logger')
local Widgets = require('proloot.ui.widgets')
local Credits = require('proloot.ui.credits')

local Panel = {}

local _config       = nil
local _loot         = nil
local _setup        = nil
local _editor       = nil
local _bankSettings = nil
local _upgradeEval  = nil
local _framework    = nil
local _adapters     = nil
local _channel      = nil
local _version      = nil

-- Slot exclusions: set kept in sync with config, built at Panel.Init
local _excludedSlotsSet = {}
local _slotItems = (function()
    local t = {}
    for _, id in ipairs(Upgrade.SLOT_ORDER) do
        t[#t+1] = { id=id, name=Upgrade.SLOT_NAMES[id] }
    end
    return t
end)()

-- Weapon mode
local WEAPONMODES       = { 'DW', '2H', 'SNB', 'ANY', 'always' }
local WEAPONMODE_LABELS = {
    DW      = 'Dual Wield',
    ['2H']  = 'Two-Handed',
    SNB     = 'Sword and Board',
    ANY     = 'Any / No Restriction',
    always  = 'Always Keep',
}
local WEAPONMODE_TOOLTIPS = {
    DW     = 'Evaluates 1H weapons only. Shields and 2H weapons are ignored. Best for classes that dual wield (Rogue, Monk, Ranger, etc.).',
    ['2H'] = 'Evaluates 2H weapons only. 1H weapons and shields are ignored. Best for classes that use two-handed weapons.',
    SNB    = 'Evaluates 1H weapons and shields only. 2H weapons are ignored. Best for tanks using a weapon and shield.',
    ANY    = 'Evaluates all weapon types — 1H, 2H, and shields. Use when you have no preference or want all options considered.',
    always = 'Keeps every wearable item regardless of stat comparison. Useful for fresh characters that need to fill all gear slots quickly.',
}
local _wmIdx = 1

local function wmIndexOf(val)
    for i, v in ipairs(WEAPONMODES) do if v == val then return i end end
    return 1
end

-- Framework / channel combo lists
local FRAMEWORKS = { 'none', 'rgmercs', 'rgmercs-directed', 'e3', 'kissassist' }
local FRAMEWORK_LABELS = { none='None', rgmercs='RG Mercs', ['rgmercs-directed']='RG Mercs (Directed)', e3='E3', kissassist='Kiss Assist' }

local CHANNELS = { 'none', 'dannet', 'eqbc' }
local CHANNEL_LABELS = { none='None', dannet='DanNet', eqbc='EQBC' }

local RANGEDMODES = { 'any', 'bows' }
local RANGEDMODE_LABELS = { any='Any Ranged', bows='Only Bows' }

local function indexOfStr(tbl, val)
    for i, v in ipairs(tbl) do if v == val then return i end end
    return 1
end

local _logoTex = nil

-- Panel open state (tracks X button)
local _panelOpen = true

-- History state
local _histOpen           = false
local _histFilter         = ''
local _histDecisionFilter = { keep=false, bank=false, sell=false, destroy=false, skip=false }

-- Restart modal
local _wantRestartModal = false

-- Dev Info window
local _devInfoOpen = false

-- Shared gold used for active-state buttons and author link
local BUTTON_GOLD = ImVec4(1.0, 0.72, 0.20, 1.0)

-- Build notes — update this block each release; no UI changes needed.
-- Format: first line is "vX.Y.Z Tag  —  YYYY-MM-DD", blank line, then
-- bullet entries starting with "  • ". Prepend a new block for each release
-- (older blocks stay for history) or trim if it gets too long.
local BUILD_NOTES = [[
v0.10.6 Dev  —  2026-07-26

  New Features:
  • "Loot in Combat" toggle (per-character) — allows loot sweeps to run while
    you're in combat, instead of waiting for combat to end. For RG Mercs, ProLoot
    now avoids pausing it while you're actually fighting. Has no effect in
    RG Mercs (Directed) mode — that's controlled entirely by RG Mercs' own
    "Combat Looting" setting.

  Other Changes:
  • Debug log files (LogToFile) now write to MacroQuest's Logs\proloot folder
    instead of Config\proloot, so they no longer clutter the per-character
    settings folder alongside 18+ characters' ini/list files.

v0.10.5 Beta  —  2026-07-26

  New Features:
  • rgmercs-directed framework is now fully reactive — RGMercs's native
    ProLoot loot module tells ProLoot exactly when it's safe to loot and
    ProLoot waits for that signal instead of sweeping on its own timer.
    Requires a matching RGMercs build (Tyvion-EQEMU/rgmercs
    feat/proloot-directed-loot).
  • Fixed a bug where framework=rgmercs-directed (and any other
    framework=... launch argument) could silently fail to apply

v0.10.4 Beta  —  2026-07-19

  New Features:
  • List Editor: "Need" column — set how many copies of a non-lore item to
    pick up before ProLoot leaves the rest on the corpse (0 = unlimited,
    same as before). Fixes over-looting progression items that drop more
    copies per corpse than you actually need.
  • List Editor: "Active" toggle — soft-disable an item (e.g. quest done)
    without removing it from the list; flip it back on any time
  • Tiered list items now default to Need = 1 for new users

v0.10.3 Beta  —  2026-07-18

  New Features:
  • Raid Chat toggle — loot pickups, and now Sell/Bank/Restock completion
    messages, can broadcast to Raid (/rs) instead of Group (/g)
  • Bank Stuff now announces completion to group/raid, matching Sell/Restock
  • Shift+Click on "...All" buttons (Status/Sell/Bank/Restock/Consolidate)
    now reaches every online toon instead of just your group

  Fixes:
  • "Reload for All" in the List Editor now actually reaches every toon
    instead of just your in-game group
  • Shift+Click "Status All" replies now reach out-of-group requesters

v0.10.2 Beta  —  2026-07-10

  New Features:
  • Upgrade Evaluator — now has its own quick-action button on the main panel
    (previously command-only via /proloot eval)

v0.10.1 Beta  —  2026-07-10

  New Features:
  • Upgrade Evaluator — scan bags for gear upgrades against what you have
    equipped, via /proloot eval
  • Automatic aug carryover — Equip now pulls augments off the item being
    replaced and reinserts them into the new upgrade automatically
  • Remove Aug action — pull an augment out of an item before deleting it
    (requires a Perfected Augmentation Distiller)

  Fixes:
  • RGMercs: ProLoot no longer unpauses RGMercs if you had paused it yourself
    before a loot sweep started
  • RGMercs: camp-return no longer interrupts loot sweeps mid-corpse
  • Lore items you already own are now skipped before announcing to the
    group, instead of announcing and then failing to pick up
  • More reliable combat detection during loot sweeps
  • All sub-windows now close on Escape

v0.9.2 Beta  —  2026-06-12

  New Features:
  • Auto Equip toggle — when off, upgrades go to bags instead of equipping
    immediately; great for reviewing gear before committing (per-character)
  • Slot Exclusions — exclude specific gear slots from upgrade evaluation so
    those slots are never replaced during looting (per-character)
  • Weapon Mode: Always Keep — keep every wearable item regardless of stat
    comparison; ideal for fresh characters filling all gear slots
  • Upgrade Evaluator — scan bags for equippable gear and see upgrade verdicts
    at a glance with green/gray color coding (button coming soon)

  UI Fixes:
  • Weapon mode dropdown now shows per-item tooltips explaining each mode
  • Auto Equip toggle sits inline with Use Warp to keep the panel compact
  • Action button row reflows correctly when a scrollbar is present
  • Default panel size increased to better fit all settings without scrolling

v0.9.0 Beta  —  2026-06-10

  • Rebranded as ProLoot — renamed from e9loot; /lua run proloot; all /proloot commands
  • ProLoot display name throughout UI, chat output, and window titles

v0.8.0 Beta  —  2026-06-09

  • Sell Stuff: confirm window with solo/group views, Status All, Sell All broadcast
  • Restock: per-toon item lists, confirm window, per-item broadcast, Restock All
  • Bank Stuff: Consolidate All broadcasts coin consolidation to group
  • Quick-action buttons (Sell Stuff | Bank Stuff | Restock) in main panel
  • Group broadcasts: *_all and *_status_request/response message types
  • Build tag ([Beta]/[Stable]/[Dev]) in header with barber-pole animation
  • Vendor Settings button (renamed from Bank & Vendor)
  • All confirm windows: primary action left, Cancel right
]]

local REPO_URL = 'https://github.com/Tyvion-EQEMU/ProLoot'

-- 64x64 square button: silver face, black text, rounded corners, snake border on hover.
local function squareActionButton(label, size)
    ImGui.PushStyleColor(ImGuiCol.Button,        ImVec4(0.78, 0.78, 0.82, 1.0))
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ImVec4(0.86, 0.86, 0.90, 1.0))
    ImGui.PushStyleColor(ImGuiCol.ButtonActive,  ImVec4(0.68, 0.68, 0.72, 1.0))
    ImGui.PushStyleColor(ImGuiCol.Text,          ImVec4(0.0,  0.0,  0.0,  1.0))
    ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 10)
    local clicked = ImGui.Button(label, size, size)
    ImGui.PopStyleVar()
    ImGui.PopStyleColor(4)
    if ImGui.IsItemHovered() then
        local bmin = ImGui.GetItemRectMinVec()
        local bmax = ImGui.GetItemRectMaxVec()
        Credits.DrawSnake(bmin, ImVec2(bmax.x - bmin.x, bmax.y - bmin.y), false, 10)
    end
    return clicked
end

-- Renders a button that turns gold when active, shows a snake border on hover
-- instead of a colour change, and returns true when clicked.
local function actionButton(label, w, isActive)
    local col = isActive and BUTTON_GOLD or ImGui.GetStyleColorVec4(ImGuiCol.Button)
    ImGui.PushStyleColor(ImGuiCol.Button,        col)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, col)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive,  col)
    local clicked = ImGui.Button(label, w, 0)
    ImGui.PopStyleColor(3)
    if ImGui.IsItemHovered() then
        local bmin = ImGui.GetItemRectMinVec()
        local bmax = ImGui.GetItemRectMaxVec()
        Credits.DrawSnake(bmin, ImVec2(bmax.x - bmin.x, bmax.y - bmin.y), isActive)
    end
    return clicked
end

-- Quick-action button scan cache (throttled to avoid per-frame TLO spam)
local _actionCounts     = { sell=0, bank=0, restock=0 }
local _actionCountsTime = 0

local function refreshActionCounts()
    local now = os.clock()
    if now - _actionCountsTime < 3.0 then return end
    _actionCountsTime = now
    _actionCounts.sell    = #_loot.ScanSellItems()
    _actionCounts.bank    = #_loot.ScanBankItems()
    _actionCounts.restock = _loot.GetRestockNeedCount()
end

-- Mini mode
local _miniMode = false

local DECISION_COLORS = {
    keep    = { 0.3, 1.0, 0.3, 1.0 },
    bank    = { 0.3, 0.7, 1.0, 1.0 },
    sell    = { 1.0, 0.8, 0.2, 1.0 },
    destroy = { 0.6, 0.6, 0.6, 1.0 },
    skip    = { 0.5, 0.5, 0.5, 0.7 },
}

-- Active / inactive button colors for decision filter toggles
local FILTER_BTNCOLS = {
    keep    = { a={ 0.20, 0.75, 0.20, 1.0 }, i={ 0.07, 0.26, 0.07, 1.0 } },
    bank    = { a={ 0.20, 0.55, 0.85, 1.0 }, i={ 0.07, 0.19, 0.30, 1.0 } },
    sell    = { a={ 0.82, 0.62, 0.10, 1.0 }, i={ 0.28, 0.21, 0.04, 1.0 } },
    destroy = { a={ 0.60, 0.60, 0.60, 1.0 }, i={ 0.20, 0.20, 0.20, 1.0 } },
    skip    = { a={ 0.80, 0.80, 0.80, 1.0 }, i={ 0.24, 0.24, 0.24, 1.0 } },
}

local DECISION_ORDER  = { 'keep', 'bank', 'sell', 'destroy', 'skip' }
local DECISION_LABELS = { keep='Keep', bank='Bank', sell='Sell', destroy='Destroy', skip='Skip' }

local function formatPP(pp)
    if pp <= 0 then return 'Disabled' end
    local copper = math.floor(pp * 1000 + 0.5)
    local p = math.floor(copper / 1000); copper = copper % 1000
    local g = math.floor(copper / 100);  copper = copper % 100
    local s = math.floor(copper / 10);   local c = copper % 10
    local parts = {}
    if p > 0 then parts[#parts+1] = p .. 'p' end
    if g > 0 then parts[#parts+1] = g .. 'g' end
    if s > 0 then parts[#parts+1] = s .. 's' end
    if c > 0 then parts[#parts+1] = c .. 'c' end
    return table.concat(parts, ' ')
end

-----------------------------------------------------------------------
-- History window
-----------------------------------------------------------------------
local function renderHistory()
    if not _histOpen then return end

    ImGui.SetNextWindowSize(ImVec2(820, 400), ImGuiCond.FirstUseEver)
    local open, shouldDraw = ImGui.Begin('ProLoot — Loot History', _histOpen,
        ImGuiWindowFlags.None)
    _histOpen = open
    if ImGui.IsWindowFocused() and ImGui.IsKeyPressed(ImGuiKey.Escape) then _histOpen = false end

    if shouldDraw then
        ImGui.SetNextItemWidth(220)
        local newFilter, _ = ImGui.InputText('##histfilter', _histFilter)
        _histFilter = newFilter
        local filterLow = newFilter:lower()

        ImGui.SameLine()
        if ImGui.Button('Clear Filter') then
            _histFilter = ''
            for _, d in ipairs(DECISION_ORDER) do
                _histDecisionFilter[d] = false
            end
        end

        -- Decision filter toggles
        for _, d in ipairs(DECISION_ORDER) do
            ImGui.SameLine()
            local active = _histDecisionFilter[d]
            local bc     = active and FILTER_BTNCOLS[d].a or FILTER_BTNCOLS[d].i
            ImGui.PushStyleColor(ImGuiCol.Button,
                bc[1], bc[2], bc[3], bc[4])
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered,
                math.min(1.0, bc[1]*1.25), math.min(1.0, bc[2]*1.25), math.min(1.0, bc[3]*1.25), 1.0)
            ImGui.PushStyleColor(ImGuiCol.ButtonActive,
                bc[1]*0.8, bc[2]*0.8, bc[3]*0.8, 1.0)
            if ImGui.Button(DECISION_LABELS[d]) then
                _histDecisionFilter[d] = not _histDecisionFilter[d]
            end
            ImGui.PopStyleColor(3)
        end

        ImGui.Separator()

        local history = _loot.GetHistory()
        local kept, banked, sold, destroyed = 0, 0, 0, 0

        local anyDecision = _histDecisionFilter.keep or _histDecisionFilter.bank
            or _histDecisionFilter.sell or _histDecisionFilter.destroy or _histDecisionFilter.skip

        if ImGui.BeginTable('##histtbl', 7,
            bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg,
                      ImGuiTableFlags.ScrollY, ImGuiTableFlags.SizingStretchProp),
            ImVec2(0, -22)) then

            ImGui.TableSetupScrollFreeze(0, 1)
            ImGui.TableSetupColumn('Date',     ImGuiTableColumnFlags.WidthFixed,  42)
            ImGui.TableSetupColumn('Time',     ImGuiTableColumnFlags.WidthFixed,  50)
            ImGui.TableSetupColumn('Toon',     ImGuiTableColumnFlags.WidthFixed,  75)
            ImGui.TableSetupColumn('Action',   ImGuiTableColumnFlags.WidthFixed,  55)
            ImGui.TableSetupColumn('Item',     ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableSetupColumn('Reason',   ImGuiTableColumnFlags.WidthFixed, 100)
            ImGui.TableSetupColumn('Replaced', ImGuiTableColumnFlags.WidthFixed, 140)
            ImGui.TableHeadersRow()

            for i, entry in ipairs(history) do
                if     entry.decision == 'keep'    then kept      = kept     + 1
                elseif entry.decision == 'bank'    then banked    = banked   + 1
                elseif entry.decision == 'sell'    then sold      = sold     + 1
                elseif entry.decision == 'destroy' then destroyed = destroyed + 1
                end

                local toonLow      = (entry.toon or ''):lower()
                local decisionPass = not anyDecision or _histDecisionFilter[entry.decision]
                local textPass     = filterLow == ''
                    or entry.name:lower():find(filterLow, 1, true)
                    or toonLow:find(filterLow, 1, true)

                if decisionPass and textPass then
                    local col = DECISION_COLORS[entry.decision] or { 1, 1, 1, 1 }

                    ImGui.TableNextRow()

                    ImGui.TableNextColumn()
                    ImGui.TextDisabled(entry.date or '')

                    ImGui.TableNextColumn()
                    ImGui.TextDisabled(entry.time or '')

                    ImGui.TableNextColumn()
                    ImGui.Text(entry.toon or '?')

                    ImGui.TableNextColumn()
                    ImGui.TextColored(col[1], col[2], col[3], col[4], (entry.decision or ''):upper())

                    ImGui.TableNextColumn()
                    local canInspect = entry.decision == 'keep' or entry.decision == 'bank' or entry.decision == 'sell'
                    ImGui.TextColored(col[1], col[2], col[3], col[4], entry.name)
                    if canInspect then
                        local rmin = ImGui.GetItemRectMinVec()
                        local rmax = ImGui.GetItemRectMaxVec()
                        local dl2  = ImGui.GetWindowDrawList()
                        dl2:AddLine(ImVec2(rmin.x, rmax.y), rmax,
                            ImGui.ColorConvertFloat4ToU32(ImVec4(col[1], col[2], col[3], col[4])), 1.0)
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
                    end

                    ImGui.TableNextColumn()
                    ImGui.TextDisabled(entry.reason or '')

                    ImGui.TableNextColumn()
                    if entry.replacedName then
                        local rn = entry.replacedName
                        ImGui.TextDisabled(rn)
                        local rmin2 = ImGui.GetItemRectMinVec()
                        local rmax2 = ImGui.GetItemRectMaxVec()
                        ImGui.GetWindowDrawList():AddLine(
                            ImVec2(rmin2.x, rmax2.y), rmax2,
                            ImGui.ColorConvertFloat4ToU32(ImVec4(0.5, 0.5, 0.5, 0.7)), 1.0)
                        if ImGui.IsItemHovered() then
                            ImGui.SetMouseCursor(ImGuiMouseCursor.Hand)
                            ImGui.BeginTooltip()
                            ImGui.Text(rn)
                            ImGui.TextDisabled('Click to inspect \xe2\x80\x94 check for augments')
                            ImGui.EndTooltip()
                            if ImGui.IsMouseReleased(ImGuiMouseButton.Left) then
                                local found = mq.TLO.FindItem('=' .. rn)
                                if found and found.ID() and found.ID() > 0 then
                                    found.Inspect()
                                else
                                    printf('\ayProLoot: %s is not in your inventory', rn)
                                end
                            end
                        end
                    end
                end
            end

            ImGui.EndTable()
        end

        ImGui.TextDisabled(string.format(
            'Session: %d kept  |  %d banked  |  %d sold  |  %d destroyed', kept, banked, sold, destroyed))
    end

    ImGui.End()
end

-----------------------------------------------------------------------
-- Dev Info window
-----------------------------------------------------------------------
local function renderDevInfo()
    if not _devInfoOpen then return end

    ImGui.SetNextWindowSize(ImVec2(430, 360), ImGuiCond.FirstUseEver)
    local open, shouldDraw = ImGui.Begin('ProLoot Dev Info', _devInfoOpen, ImGuiWindowFlags.None)
    _devInfoOpen = open
    if ImGui.IsWindowFocused() and ImGui.IsKeyPressed(ImGuiKey.Escape) then _devInfoOpen = false end

    if shouldDraw then
        ImGui.TextColored(BUTTON_GOLD, "What's New")
        ImGui.Separator()
        ImGui.Spacing()
        ImGui.BeginChild('##devnotes', ImVec2(0, 170), true, ImGuiWindowFlags.None)
        ImGui.TextWrapped(BUILD_NOTES)
        ImGui.EndChild()

        ImGui.Spacing()

        ImGui.TextColored(BUTTON_GOLD, 'Feedback & Bug Reports')
        ImGui.Separator()
        ImGui.Spacing()
        ImGui.TextWrapped(
            'Found a bug or have a suggestion? Open an issue on GitHub. ' ..
            'A helpful report includes: character name, zone, what happened, ' ..
            'and what you expected instead.')
        ImGui.Spacing()
        ImGui.SetNextItemWidth(-88)
        ImGui.InputText('##repourl', REPO_URL, ImGuiInputTextFlags.ReadOnly)
        ImGui.SameLine()
        if ImGui.Button('Copy URL', 83, 0) then
            ImGui.SetClipboardText(REPO_URL)
        end
    end

    ImGui.End()
end

-----------------------------------------------------------------------
-- Panel API
-----------------------------------------------------------------------
function Panel.Init(config, loot, setup, editor, bankSettings, framework, adapters, channel, version, upgradeEval)
    _config       = config
    _loot         = loot
    _setup        = setup
    _editor       = editor
    _bankSettings = bankSettings
    _upgradeEval  = upgradeEval
    _framework    = framework
    _adapters     = adapters
    _channel      = channel
    _version      = version
    _histOpen     = config:Get('HistoryOpen')
    _wmIdx        = wmIndexOf(config:Get('WeaponMode'))
    _excludedSlotsSet = Upgrade.ParseExcludedSlots(config:Get('ExcludedSlots'))

    _logoTex = mq.CreateTexture(mq.TLO.Lua.Dir() .. '/proloot/profusion_logo_64x64.png')

    Mini.Init(config, loot, version, channel)
end

function Panel.ToggleMini()
    _miniMode = not _miniMode
end

function Panel.SetMini(value)
    _miniMode = value
end

function Panel.Show()
    _panelOpen = true
    _miniMode  = false
end

function Panel.Render()
    if not _config then return end

    -- Mini mode: show compact overlay, hide main window
    if _miniMode then
        Mini.Render(function() _miniMode = false end)
        renderHistory()
        renderDevInfo()
        _editor.Render()
        _setup.Render()
        _bankSettings.Render()
        if _upgradeEval then _upgradeEval.Render() end
        return
    end

    -- Hidden: X was clicked; /proloot show restores
    if not _panelOpen then return end

    ImGui.SetNextWindowSize(ImVec2(360, 605), ImGuiCond.FirstUseEver)
    local _lootEnabled = _config:Get('LootEnabled')
    local _inCombat    = _loot.IsInCombat()
    if not _lootEnabled then
        ImGui.PushStyleColor(ImGuiCol.TitleBg,       0.40, 0.10, 0.08, 1.0)
        ImGui.PushStyleColor(ImGuiCol.TitleBgActive, 0.55, 0.12, 0.08, 1.0)
    end
    local open, shouldDraw = ImGui.Begin('ProLoot', _panelOpen)
    if not _lootEnabled then ImGui.PopStyleColor(2) end
    _panelOpen = open
    if not shouldDraw then ImGui.End(); return end

    if shouldDraw then
        local footerH = ImGui.GetTextLineHeight() + ImGui.GetStyle().ItemSpacing.y * 2 + 2
        ImGui.BeginChild('##panelmain', ImVec2(0, -footerH), false, ImGuiWindowFlags.None)

        -- Minimize button — top right, y aligned to content start, FA_COMPRESS (core glyph range)
        -- GetContentRegionMax x accounts for child scrollbar width when present
        local _savedPos = ImGui.GetCursorPosVec()
        local contentMaxX = select(1, ImGui.GetContentRegionMax())
        ImGui.SetCursorPos(ImVec2(contentMaxX - 18, _savedPos.y))
        if ImGui.SmallButton(Icons.FA_COMPRESS) then
            _miniMode = true
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text('Activate Mini Mode')
            ImGui.EndTooltip()
        end
        ImGui.SetCursorPos(_savedPos)

        -- Header: logo + version info
        if _version then
            if _logoTex then
                ImGui.Image(_logoTex:GetTextureID(), ImVec2(64, 64))
            else
                local sp = ImGui.GetCursorScreenPosVec()
                local dl = ImGui.GetWindowDrawList()
                dl:AddRectFilled(sp, ImVec2(sp.x + 64, sp.y + 64), IM_COL32(40, 80, 140, 200))
                dl:AddRect(sp,       ImVec2(sp.x + 64, sp.y + 64), IM_COL32(100, 150, 210, 180))
                ImGui.Dummy(ImVec2(64, 64))
            end
            ImGui.SameLine()
            ImGui.BeginGroup()
            local verStr = string.format('%s  v%s', _version._AppName, _version._version)
            ImGui.Text(verStr)
            if ImGui.IsItemHovered() then
                ImGui.SetMouseCursor(ImGuiMouseCursor.Hand)
                ImGui.BeginTooltip()
                ImGui.TextDisabled("What's New / Dev Info")
                ImGui.EndTooltip()
            end
            if ImGui.IsItemClicked(0) then _devInfoOpen = not _devInfoOpen end
            if _version._buildTag then
                ImGui.SameLine()
                -- Barber-pole: each character's phase offset by its index so the
                -- gold→white highlight sweeps diagonally across the tag text.
                local tag   = '[' .. _version._buildTag .. ']'
                local t     = os.clock() * 0.5   -- stripe speed (cycles/sec)
                local pitch = 0.12               -- phase offset per character
                for i = 1, #tag do
                    local w = (math.sin((t - i * pitch) * math.pi * 2) + 1.0) * 0.5
                    if i > 1 then ImGui.SameLine(0, 1) end
                    ImGui.TextColored(
                        ImVec4(1.0, 0.72 + 0.28 * w, 0.20 + 0.80 * w, 1.0),
                        tag:sub(i, i))
                end
            end
            ImGui.TextDisabled('by ')
            ImGui.SameLine(0, 0)
            ImGui.TextColored(BUTTON_GOLD, 'Tyvion')
            if ImGui.IsItemHovered() then ImGui.SetMouseCursor(ImGuiMouseCursor.Hand) end
            if ImGui.IsItemClicked(0) then
                os.execute('start "" "https://github.com/Tyvion-EQEMU"')
            end
            local btnW = 60
            ImGui.SetCursorPosX(select(1, ImGui.GetContentRegionMax()) - btnW)
            ImGui.Button('Credits', btnW, 0)
            if ImGui.IsItemHovered() then
                local bmin = ImGui.GetItemRectMinVec()
                local bmax = ImGui.GetItemRectMaxVec()
                Credits.RenderTooltip()
                Credits.DrawSnake(bmin, ImVec2(bmax.x - bmin.x, bmax.y - bmin.y))
            end
            ImGui.EndGroup()
            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()
        end

        local enabled = _config:Get('LootEnabled')
        local availW  = select(1, ImGui.GetContentRegionAvail())

        -- Single wide toggle button: green when running, red when paused
        if enabled then
            ImGui.PushStyleColor(ImGuiCol.Button,        0.16, 0.50, 0.16, 1.0)
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.22, 0.62, 0.22, 1.0)
            ImGui.PushStyleColor(ImGuiCol.ButtonActive,  0.22, 0.62, 0.22, 1.0)
        else
            ImGui.PushStyleColor(ImGuiCol.Button,        0.60, 0.16, 0.16, 1.0)
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.72, 0.22, 0.22, 1.0)
            ImGui.PushStyleColor(ImGuiCol.ButtonActive,  0.72, 0.22, 0.22, 1.0)
        end

        if ImGui.Button(enabled and 'Running' or 'Paused', availW, 0) then
            local newVal = not enabled
            _loot.SetEnabled(newVal)
            if ImGui.GetIO().KeyShift and _channel then
                _channel:Broadcast({ type='set_enabled', value=newVal })
            end
        end
        ImGui.PopStyleColor(3)

        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text('Click: Pause / Unpause')
            ImGui.Text('Shift+Click: Pause All / Unpause All')
            ImGui.EndTooltip()
        end

        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()

        -- Two-column settings table
        if ImGui.BeginTable('##settings', 2, 0) then
            ImGui.TableSetupColumn('##lbl', ImGuiTableColumnFlags.WidthFixed,  120)
            ImGui.TableSetupColumn('##ctl', ImGuiTableColumnFlags.WidthStretch)

            -- Weapon Mode
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.Text('Weapon Mode')
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.PushTextWrapPos(280)
                ImGui.TextWrapped('Controls which weapon types are considered when evaluating gear upgrades for the Primary and Secondary slots')
                ImGui.PopTextWrapPos()
                ImGui.EndTooltip()
            end
            ImGui.TableNextColumn()
            ImGui.SetNextItemWidth(-1)
            local wmCurrent = WEAPONMODE_LABELS[WEAPONMODES[_wmIdx]] or WEAPONMODES[_wmIdx]
            if ImGui.BeginCombo('##wm', wmCurrent) then
                for i, key in ipairs(WEAPONMODES) do
                    local selected = (i == _wmIdx)
                    if ImGui.Selectable(WEAPONMODE_LABELS[key], selected) then
                        _wmIdx = i
                        _config:SetAndSave('WeaponMode', WEAPONMODES[_wmIdx])
                    end
                    if selected then ImGui.SetItemDefaultFocus() end
                    if ImGui.IsItemHovered() and WEAPONMODE_TOOLTIPS[key] then
                        ImGui.BeginTooltip()
                        ImGui.PushTextWrapPos(280)
                        ImGui.TextWrapped(WEAPONMODE_TOOLTIPS[key])
                        ImGui.PopTextWrapPos()
                        ImGui.EndTooltip()
                    end
                end
                ImGui.EndCombo()
            end

            -- Ranged Slot
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.Text('Ranged Slot')
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.PushTextWrapPos(280)
                ImGui.TextWrapped("Controls how items in the Ranged slot are evaluated. Choose 'Only Bows' to prevent non-bow ranged items from displacing a bow — recommended for Rangers and melee toons that pull.")
                ImGui.PopTextWrapPos()
                ImGui.EndTooltip()
            end
            ImGui.TableNextColumn()
            ImGui.SetNextItemWidth(-1)
            local rmIdx = indexOfStr(RANGEDMODES, _config:Get('RangedMode'))
            local rmLabels = {}
            for _, k in ipairs(RANGEDMODES) do table.insert(rmLabels, RANGEDMODE_LABELS[k] or k) end
            local newRmIdx, rmChanged = ImGui.Combo('##rm', rmIdx, rmLabels, #rmLabels)
            if rmChanged then
                _config:SetAndSave('RangedMode', RANGEDMODES[newRmIdx])
            end

            -- Loot Range
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.Text('Loot Range')
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.PushTextWrapPos(280)
                ImGui.TextWrapped('Scans for corpses within this range, anything outside this range is ignored')
                ImGui.PopTextWrapPos()
                ImGui.EndTooltip()
            end
            ImGui.TableNextColumn()
            ImGui.SetNextItemWidth(-1)
            local curRange = _config:Get('LootRange')
            local newRange, rangeChanged = ImGui.SliderInt('##lootrange', curRange, 50, 600)
            if rangeChanged then
                _config:SetAndSave('LootRange', newRange)
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text('Ctrl+Click to type a value')
                ImGui.EndTooltip()
            end

            -- Trash Sell Threshold
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.Text('Min. Sell Value')
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.PushTextWrapPos(280)
                ImGui.TextWrapped('Loot and sell any unlisted item worth at least this much at a vendor. Set to 0 to disable.')
                ImGui.PopTextWrapPos()
                ImGui.EndTooltip()
            end
            ImGui.TableNextColumn()
            ImGui.SetNextItemWidth(-1)
            local curTrash = _config:Get('TrashPrice')
            local newTrash, trashChanged = ImGui.InputFloat('##trashprice', curTrash, 0.25, 1.0, '%.2f')
            if trashChanged then
                if newTrash < 0 then newTrash = 0 end
                _config:SetAndSave('TrashPrice', newTrash)
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                local displayTrash = trashChanged and newTrash or curTrash
                if displayTrash <= 0 then
                    ImGui.Text('Disabled — set above 0 to enable')
                else
                    ImGui.Text(string.format('%.2fpp  =  %s', displayTrash, formatPP(displayTrash)))
                end
                ImGui.EndTooltip()
            end

            -- Use Warp
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.Text('Use Warp')
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.PushTextWrapPos(280)
                ImGui.TextWrapped('This will leverage /warp to navigate to corpses instead of /nav')
                ImGui.PopTextWrapPos()
                ImGui.EndTooltip()
            end
            ImGui.TableNextColumn()
            local useWarp = _config:Get('UseWarp')
            local newUseWarp, warpChanged = Widgets.Toggle('##usewarp', useWarp)
            if warpChanged then _config:SetAndSave('UseWarp', newUseWarp) end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text('MQ2RWarp.dll required')
                ImGui.EndTooltip()
            end
            ImGui.SameLine(0, 14)
            ImGui.Text('Auto Equip')
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.PushTextWrapPos(280)
                ImGui.TextWrapped('When on, upgrade items are equipped immediately on loot. When off, upgrades go into bags for you to equip manually.')
                ImGui.PopTextWrapPos()
                ImGui.EndTooltip()
            end
            ImGui.SameLine(0, 6)
            local autoEquip = _config:Get('AutoEquipUpgrades')
            local newAutoEquip, autoEquipChanged = Widgets.Toggle('##autoequip', autoEquip)
            if autoEquipChanged then _config:SetAndSave('AutoEquipUpgrades', newAutoEquip) end

            -- Done Looting
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.Text('Share Done Looting')
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.PushTextWrapPos(280)
                ImGui.TextWrapped('When enabled, characters will broadcast via /g (group chat) when they are finished looting all available corpses')
                ImGui.PopTextWrapPos()
                ImGui.EndTooltip()
            end
            ImGui.TableNextColumn()
            local announceDone = _config:Get('AnnounceDone')
            local newAnnounceDone, doneChanged = Widgets.Toggle('##announcedone', announceDone)
            if doneChanged then _config:SetAndSave('AnnounceDone', newAnnounceDone) end
            ImGui.SameLine(0, 14)
            ImGui.Text('Raid Chat')
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.PushTextWrapPos(280)
                ImGui.TextWrapped('When on, loot pickup, Sell/Bank/Restock completion, and Restock share announcements broadcast to Raid (/rs) instead of Group (/g). Falls back to local chat if not actually in a raid.')
                ImGui.PopTextWrapPos()
                ImGui.EndTooltip()
            end
            ImGui.SameLine(0, 6)
            local announceRaid = _config:Get('AnnounceChannel') == 'raid'
            local newAnnounceRaid, channelChanged = Widgets.Toggle('##announcechannel', announceRaid)
            if channelChanged then _config:SetAndSave('AnnounceChannel', newAnnounceRaid and 'raid' or 'group') end

            -- Loot in Combat
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            local isDirectedFramework = _config:Get('Framework') == 'rgmercs-directed'
            ImGui.Text('Loot in Combat')
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.PushTextWrapPos(280)
                if isDirectedFramework then
                    ImGui.TextWrapped('Controlled by RG Mercs\' own "Combat Looting" setting (ProLoot module) in RG Mercs (Directed) mode — this toggle has no effect here.')
                else
                    ImGui.TextWrapped('When on, loot sweeps run even while you are in combat. For RG Mercs, ProLoot will not pause it while you are actually fighting. Use with caution — looting mid-fight can pull you toward a corpse while mobs are still attacking.')
                end
                ImGui.PopTextWrapPos()
                ImGui.EndTooltip()
            end
            ImGui.TableNextColumn()
            if isDirectedFramework then ImGui.BeginDisabled() end
            local lootInCombat = _config:Get('LootDuringCombat')
            local newLootInCombat, combatLootChanged = Widgets.Toggle('##lootduringcombat', lootInCombat)
            if combatLootChanged then _config:SetAndSave('LootDuringCombat', newLootInCombat) end
            if isDirectedFramework then ImGui.EndDisabled() end

            -- Slot Exclusions
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.Text('Slot Exclusions')
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.PushTextWrapPos(280)
                ImGui.TextWrapped('Exclude specific gear slots from upgrade evaluation. Items in excluded slots will not be replaced during looting.')
                ImGui.PopTextWrapPos()
                ImGui.EndTooltip()
            end
            ImGui.TableNextColumn()
            ImGui.SetNextItemWidth(-1)
            local _, exChanged = Widgets.MultiSelectCombo('##excludedslots', _slotItems, _excludedSlotsSet, 'No exclusions')
            if exChanged then
                _config:SetAndSave('ExcludedSlots', Upgrade.SerializeExcludedSlots(_excludedSlotsSet))
            end

            ImGui.EndTable()
        end

        -- Restart required modal
        if _wantRestartModal then
            ImGui.OpenPopup('##e9restart')
            _wantRestartModal = false
        end

        if ImGui.BeginPopupModal('##e9restart', nil, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text('Restart required — restart ProLoot now?')
            ImGui.Spacing()
            if ImGui.Button('Confirm', 80, 0) then
                mq.cmd('/multiline ; /lua stop proloot ; /timed 50 /lua run proloot')
                ImGui.CloseCurrentPopup()
            end
            ImGui.SameLine()
            if ImGui.Button('Cancel', 80, 0) then
                ImGui.CloseCurrentPopup()
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text('Setting saved. Will take effect on next restart.')
                ImGui.EndTooltip()
            end
            ImGui.EndPopup()
        end

        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()

        -- Action buttons — widths computed from available region so the row
        -- stays flush when a scrollbar is present
        do
            local avail   = select(1, ImGui.GetContentRegionAvail())
            local spacing = ImGui.GetStyle().ItemSpacing.x
            local bw      = math.floor((avail - spacing * 2) / 3)

            if actionButton('History', bw, _histOpen) then
                _histOpen = not _histOpen
                _config:SetAndSave('HistoryOpen', _histOpen)
            end

            ImGui.SameLine()

            local editorOpen = _editor.IsOpen()
            if actionButton('List Editor', bw, editorOpen) then
                if editorOpen then _editor.Close() else _editor.Open(_config._lists, _channel) end
            end

            ImGui.SameLine()

            local bankOpen = _bankSettings.IsOpen()
            if actionButton('Vendor Settings', bw, bankOpen) then
                if bankOpen then _bankSettings.Close() else _bankSettings.Open(_config) end
            end
        end

        ImGui.Spacing()
        if ImGui.CollapsingHeader('System Settings') then
            if ImGui.BeginTable('##syssettings', 2, 0) then
                ImGui.TableSetupColumn('##slbl', ImGuiTableColumnFlags.WidthFixed,  90)
                ImGui.TableSetupColumn('##sctl', ImGuiTableColumnFlags.WidthStretch)

                -- Integration (Framework)
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                ImGui.Text('Integration')
                if ImGui.IsItemHovered() then
                    ImGui.BeginTooltip()
                    ImGui.PushTextWrapPos(280)
                    ImGui.TextWrapped('Which bot framework ProLoot works alongside.')
                    ImGui.PopTextWrapPos()
                    ImGui.EndTooltip()
                end
                ImGui.TableNextColumn()
                ImGui.SetNextItemWidth(-1)
                local fwIdx = indexOfStr(FRAMEWORKS, _config:Get('Framework'))
                local fwDisplayLabels = {}
                for _, k in ipairs(FRAMEWORKS) do table.insert(fwDisplayLabels, FRAMEWORK_LABELS[k] or k) end
                local newFwIdx, fwChanged = ImGui.Combo('##fw', fwIdx, fwDisplayLabels, #fwDisplayLabels)
                if fwChanged then
                    _config:SetAndSave('Framework', FRAMEWORKS[newFwIdx])
                    _wantRestartModal = true
                end

                -- Broadcast (Channel)
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                ImGui.Text('Broadcast')
                if ImGui.IsItemHovered() then
                    ImGui.BeginTooltip()
                    ImGui.PushTextWrapPos(280)
                    ImGui.TextWrapped('The network channel used to share loot events and group pause/resume commands across characters')
                    ImGui.PopTextWrapPos()
                    ImGui.EndTooltip()
                end
                ImGui.TableNextColumn()
                ImGui.SetNextItemWidth(-1)
                local chIdx = indexOfStr(CHANNELS, _config:Get('Channel'))
                local chDisplayLabels = {}
                for _, k in ipairs(CHANNELS) do table.insert(chDisplayLabels, CHANNEL_LABELS[k] or k) end
                local newChIdx, chChanged = ImGui.Combo('##ch', chIdx, chDisplayLabels, #chDisplayLabels)
                if chChanged then
                    _config:SetAndSave('Channel', CHANNELS[newChIdx])
                    _wantRestartModal = true
                end

                ImGui.EndTable()
            end
        end

        ImGui.Spacing()
        if ImGui.CollapsingHeader('Console') then
            if ImGui.BeginTable('##debugopts', 2, 0) then
                ImGui.TableSetupColumn('##dlbl', ImGuiTableColumnFlags.WidthFixed,  115)
                ImGui.TableSetupColumn('##dctl', ImGuiTableColumnFlags.WidthStretch)

                ImGui.TableNextRow()
                ImGui.TableNextColumn(); ImGui.Text('Log Level')
                if ImGui.IsItemHovered() then
                    ImGui.BeginTooltip()
                    ImGui.PushTextWrapPos(280)
                    ImGui.TextWrapped('How much detail do you want in the console window?')
                    ImGui.PopTextWrapPos()
                    ImGui.EndTooltip()
                end
                ImGui.TableNextColumn(); ImGui.SetNextItemWidth(-1)
                local levelIdx = _config:Get('LogLevel') or 3
                local newLevelIdx, levelChanged = ImGui.Combo('##loglevel', levelIdx,
                    Logger.LevelLabels(), #Logger.LevelLabels())
                if levelChanged then _config:SetAndSave('LogLevel', newLevelIdx) end

                ImGui.TableNextRow()
                ImGui.TableNextColumn(); ImGui.Text('Log to File')
                if ImGui.IsItemHovered() then
                    ImGui.BeginTooltip()
                    ImGui.PushTextWrapPos(280)
                    ImGui.TextWrapped('Create a local log file of the Console events')
                    ImGui.PopTextWrapPos()
                    ImGui.EndTooltip()
                end
                ImGui.TableNextColumn()
                local logToFile = _config:Get('LogToFile')
                local newLogToFile, fileChanged = Widgets.Toggle('##logtofile', logToFile)
                if fileChanged then _config:SetAndSave('LogToFile', newLogToFile) end
                if ImGui.IsItemHovered() then
                    ImGui.BeginTooltip()
                    ImGui.Text('Writes to ConsoleLogs_<Server>_<Char>.log')
                    ImGui.EndTooltip()
                end

                ImGui.TableNextRow()
                ImGui.TableNextColumn(); ImGui.Text('Show Timestamps')
                if ImGui.IsItemHovered() then
                    ImGui.BeginTooltip()
                    ImGui.PushTextWrapPos(280)
                    ImGui.TextWrapped('Add Timestamps to the local log file, if Log to File is enabled')
                    ImGui.PopTextWrapPos()
                    ImGui.EndTooltip()
                end
                ImGui.TableNextColumn()
                local logTs = _config:Get('LogTimestamps')
                local newLogTs, tsChanged = Widgets.Toggle('##logts', logTs)
                if tsChanged then _config:SetAndSave('LogTimestamps', newLogTs) end

                ImGui.EndTable()
            end

            ImGui.Spacing()
            if ImGui.CollapsingHeader('ProLoot Output', ImGuiTreeNodeFlags.DefaultOpen) then
                local conW = select(1, ImGui.GetContentRegionAvail())
                Logger.GetConsole():Render(ImVec2(conW, 180))
            end
        end

        -- Quick-action buttons: Sell Stuff | Bank Stuff | Restock | Upgrade Eval — equally spread
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()

        local btnSz = 64
        local avail = select(1, ImGui.GetContentRegionAvail())
        local gap   = math.max(4, (avail - btnSz * 4) / 5)
        local baseX = ImGui.GetCursorPosX()
        local baseY = ImGui.GetCursorPosY()

        ImGui.SetWindowFontScale(1.15)

        ImGui.SetCursorPos(ImVec2(baseX + gap, baseY))
        if squareActionButton('Sell\nStuff', btnSz) then mq.cmd('/proloot sellstuff') end
        if ImGui.IsItemHovered() then
            ImGui.SetWindowFontScale(1.0)
            refreshActionCounts()
            ImGui.BeginTooltip()
            ImGui.Text('Sell Stuff')
            if _actionCounts.sell > 0 then
                ImGui.TextDisabled(_actionCounts.sell .. ' item(s) in bags queued to sell')
            else
                ImGui.TextDisabled('No sell-list items found in bags')
            end
            local sellResp = _loot.GetSellStatusResponses()
            local sellHasGroup = next(sellResp) ~= nil
            if sellHasGroup then
                ImGui.Separator()
                ImGui.TextDisabled('Last group scan:')
                local chars = {}
                for name in pairs(sellResp) do chars[#chars+1] = name end
                table.sort(chars, function(a, b) return a:lower() < b:lower() end)
                for _, name in ipairs(chars) do
                    local n = #(sellResp[name].items or {})
                    if n > 0 then
                        ImGui.TextColored(BUTTON_GOLD, ('  %s: %d item(s)'):format(name, n))
                    else
                        ImGui.TextDisabled(('  %s: nothing to sell'):format(name))
                    end
                end
            end
            ImGui.EndTooltip()
            ImGui.SetWindowFontScale(1.15)
        end

        ImGui.SetCursorPos(ImVec2(baseX + gap * 2 + btnSz, baseY))
        if squareActionButton('Bank\nStuff', btnSz) then mq.cmd('/proloot bankstuff') end
        if ImGui.IsItemHovered() then
            ImGui.SetWindowFontScale(1.0)
            refreshActionCounts()
            ImGui.BeginTooltip()
            ImGui.Text('Bank Stuff')
            if _actionCounts.bank > 0 then
                ImGui.TextDisabled(_actionCounts.bank .. ' item(s) in bags ready to deposit')
            else
                ImGui.TextDisabled('No bank-list items found in bags')
            end
            local bankResp = _loot.GetBankStatusResponses()
            local bankHasGroup = next(bankResp) ~= nil
            if bankHasGroup then
                ImGui.Separator()
                ImGui.TextDisabled('Last group scan:')
                local chars = {}
                for name in pairs(bankResp) do chars[#chars+1] = name end
                table.sort(chars, function(a, b) return a:lower() < b:lower() end)
                for _, name in ipairs(chars) do
                    local n = #(bankResp[name].items or {})
                    if n > 0 then
                        ImGui.TextColored(BUTTON_GOLD, ('  %s: %d item(s)'):format(name, n))
                    else
                        ImGui.TextDisabled(('  %s: nothing to bank'):format(name))
                    end
                end
            end
            ImGui.EndTooltip()
            ImGui.SetWindowFontScale(1.15)
        end

        ImGui.SetCursorPos(ImVec2(baseX + gap * 3 + btnSz * 2, baseY))
        if squareActionButton('Restock', btnSz) then mq.cmd('/proloot restock') end
        if ImGui.IsItemHovered() then
            ImGui.SetWindowFontScale(1.0)
            refreshActionCounts()
            ImGui.BeginTooltip()
            ImGui.Text('Restock')
            if _actionCounts.restock > 0 then
                ImGui.TextDisabled(_actionCounts.restock .. ' item(s) below target quantity')
            else
                ImGui.TextDisabled('All items stocked!')
            end
            local rstResp = _loot.GetRestockStatusResponses()
            local rstHasGroup = next(rstResp) ~= nil
            if rstHasGroup then
                ImGui.Separator()
                ImGui.TextDisabled('Last group scan:')
                local chars = {}
                for name in pairs(rstResp) do chars[#chars+1] = name end
                table.sort(chars, function(a, b) return a:lower() < b:lower() end)
                for _, name in ipairs(chars) do
                    local n = #(rstResp[name].needs or {})
                    if n > 0 then
                        ImGui.TextColored(BUTTON_GOLD, ('  %s: %d item(s) needed'):format(name, n))
                    else
                        ImGui.TextDisabled(('  %s: all stocked'):format(name))
                    end
                end
            end
            ImGui.EndTooltip()
            ImGui.SetWindowFontScale(1.15)
        end

        ImGui.SetCursorPos(ImVec2(baseX + gap * 4 + btnSz * 3, baseY))
        if squareActionButton('Upgrade\nEval', btnSz) then mq.cmd('/proloot eval') end
        if ImGui.IsItemHovered() then
            ImGui.SetWindowFontScale(1.0)
            ImGui.BeginTooltip()
            ImGui.Text('Upgrade Eval')
            ImGui.TextDisabled('Scan bags for gear upgrades against what you have equipped, plus\neasy inventory housekeeping with quick deletes for gear no longer needed')
            ImGui.EndTooltip()
            ImGui.SetWindowFontScale(1.15)
        end

        ImGui.SetWindowFontScale(1.0)

        -- Advance cursor below all four buttons so EndChild renders correctly
        ImGui.SetCursorPosY(baseY + btnSz + ImGui.GetStyle().ItemSpacing.y)
        ImGui.Spacing()

        ImGui.EndChild()

        ImGui.Separator()
        local corpses = #Corpse.FindNearby(_config:Get('LootRange'))
        if not _lootEnabled then
            ImGui.TextColored(0.9, 0.3, 0.2, 1.0,
                string.format('Nearby corpses: %d  |  Paused', corpses))
        elseif _inCombat then
            ImGui.TextColored(1.0, 0.55, 0.1, 1.0,
                string.format('Nearby corpses: %d  |  Combat', corpses))
        else
            ImGui.TextDisabled(string.format('Nearby corpses: %d  |  Running', corpses))
        end
    end

    ImGui.End()

    renderHistory()
    renderDevInfo()
    _editor.Render()
    _setup.Render()
    _bankSettings.Render()
    if _upgradeEval then _upgradeEval.Render() end
end

return Panel
