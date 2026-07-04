-- First-launch ImGui setup dialog: auto-detects frameworks, lets user pick framework/channel/weaponmode, saves to config

local mq = require('mq')

local Setup = {}

-- Framework and channel options in display order
local FRAMEWORKS  = { 'none', 'rgmercs', 'e3', 'kissassist' }
local CHANNELS    = { 'none', 'dannet', 'eqbc' }
local WEAPONMODES = { 'DW', '2H', 'SNB', 'ANY' }

local FRAMEWORK_LABELS = {
    none       = 'None (standalone)',
    rgmercs    = 'RGMercs',
    e3         = 'E3Next',
    kissassist = 'KISSAssist',
}
local CHANNEL_LABELS = {
    none   = 'None (solo)',
    dannet = 'DanNet',
    eqbc   = 'EQBC',
}
local WEAPONMODE_LABELS = {
    DW      = 'Dual Wield',
    ['2H']  = 'Two-Handed',
    SNB     = 'Sword and Board',
    ANY     = 'Any / No Restriction',
}

-- State
local _open     = false
local _config   = nil
local _adapters = nil
local _fwIdx    = 1
local _wmIdx    = 1
local _chIdx    = 1
local _detected = {}

local function indexOf(t, val)
    for i, v in ipairs(t) do if v == val then return i end end
    return 1
end

local function detect()
    _detected = {}
    for name, adapter in pairs(_adapters) do
        if adapter.Detect and adapter:Detect() then
            _detected[name] = true
        end
    end
end

function Setup.Open(cfg, adapters)
    _config   = cfg
    _adapters = adapters
    _open     = true
    detect()

    local saved = cfg:Get('Framework')
    _fwIdx = indexOf(FRAMEWORKS,  saved)
    _wmIdx = indexOf(WEAPONMODES, cfg:Get('WeaponMode'))
    _chIdx = indexOf(CHANNELS,    cfg:Get('Channel'))

    if saved == 'none' then
        for i, name in ipairs(FRAMEWORKS) do
            if _detected[name] then _fwIdx = i; break end
        end
    end
end

function Setup.IsOpen()
    return _open
end

function Setup.Render()
    if not _open then return end

    ImGui.SetNextWindowSize(ImVec2(440, 340), ImGuiCond.FirstUseEver)
    local open, shouldDraw = ImGui.Begin('ProLoot — First Time Setup', _open,
        ImGuiWindowFlags.NoResize)
    _open = open
    if ImGui.IsWindowFocused() and ImGui.IsKeyPressed(ImGuiKey.Escape) then _open = false end

    if shouldDraw then
        ImGui.TextWrapped('Welcome to ProLoot! Choose your combat framework, weapon mode, and communication channel.')
        ImGui.Separator()
        ImGui.Spacing()

        -- Framework picker
        ImGui.Text('Combat Framework:')
        ImGui.SameLine()
        ImGui.SetNextItemWidth(200)
        local fwLabels = {}
        for _, name in ipairs(FRAMEWORKS) do
            local label = FRAMEWORK_LABELS[name]
            if _detected[name] then label = label .. '  [detected]' end
            table.insert(fwLabels, label)
        end
        local changed
        _fwIdx, changed = ImGui.Combo('##fw', _fwIdx, fwLabels, #fwLabels)

        ImGui.Spacing()

        -- Weapon mode picker
        ImGui.Text('Weapon Mode:     ')
        ImGui.SameLine()
        ImGui.SetNextItemWidth(200)
        local wmLabels = {}
        for _, key in ipairs(WEAPONMODES) do
            table.insert(wmLabels, WEAPONMODE_LABELS[key])
        end
        _wmIdx, changed = ImGui.Combo('##wm', _wmIdx, wmLabels, #wmLabels)

        ImGui.Spacing()

        -- Channel picker
        ImGui.Text('Group Channel:   ')
        ImGui.SameLine()
        ImGui.SetNextItemWidth(200)
        local chLabels = {}
        for _, name in ipairs(CHANNELS) do
            table.insert(chLabels, CHANNEL_LABELS[name])
        end
        _chIdx, changed = ImGui.Combo('##ch', _chIdx, chLabels, #chLabels)

        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()

        -- Detection status
        local anyDetected = false
        for _, v in pairs(_detected) do if v then anyDetected = true; break end end
        if anyDetected then
            ImGui.TextColored(0.4, 1.0, 0.4, 1.0, 'Auto-detected: ')
            for name, v in pairs(_detected) do
                if v then
                    ImGui.SameLine()
                    ImGui.TextColored(0.4, 1.0, 0.4, 1.0, FRAMEWORK_LABELS[name])
                end
            end
        else
            ImGui.TextColored(0.8, 0.8, 0.2, 1.0, 'No running framework detected.')
        end

        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()

        if ImGui.Button('Save & Start', 120, 0) then
            _config:Set('Framework',  FRAMEWORKS[_fwIdx])
            _config:Set('WeaponMode', WEAPONMODES[_wmIdx])
            _config:Set('Channel',    CHANNELS[_chIdx])
            _config:Set('SetupDone',  true)
            _config:Save()
            _open = false
        end

        ImGui.SameLine()

        if ImGui.Button('Cancel', 80, 0) then
            _open = false
        end
    end

    ImGui.End()
end

return Setup
