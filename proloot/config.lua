-- INI-based settings: load/save defaults for framework, channel, weaponmode, warpdist, trashprice, and all user toggles
--
-- Two INI files are used:
--   SharedSettings_<Server>.ini        — group-wide settings; written by any toon, read by all at startup
--   CharSettings_<Server>_<Name>.ini   — per-character overrides (WeaponMode, UI state, LootEnabled)
--
-- Load order: defaults → shared INI → per-character INI (later layers win).
-- Save: shared keys write to both files; per-character keys write only to per-char file.

local mq = require('mq')

local function fileExists(path)
    local f = io.open(path, 'r')
    if f then f:close(); return true end
    return false
end

local Config = {}

local _cfgDir = nil
local function prolootDir()
    if not _cfgDir then
        _cfgDir = mq.configDir .. '/proloot'
        -- os.rename to self: returns true/EACCES(13) if dir exists, ENOENT(2) if not.
        -- Avoids spawning cmd.exe on every startup after the folder already exists.
        local ok, _, code = os.rename(_cfgDir, _cfgDir)
        if not ok and code ~= 13 then
            os.execute('mkdir "' .. _cfgDir .. '"')
        end
    end
    return _cfgDir
end

local _serverTag = nil
local function serverTag()
    if not _serverTag then
        _serverTag = mq.TLO.EverQuest.Server():gsub(' ', '_')
    end
    return _serverTag
end

local function iniPath()
    return string.format('%s/CharSettings_%s_%s.ini', prolootDir(), serverTag(), mq.TLO.Me.CleanName())
end

local function sharedIniPath()
    return string.format('%s/SharedSettings_%s.ini', prolootDir(), serverTag())
end

-- Default values — all settings live here; add new keys here first
Config.Defaults = {
    -- Adapter selection
    Framework    = 'none',   -- rgmercs | e3 | kissassist | none
    Channel      = 'none',   -- dannet | eqbc | none

    -- Loot behaviour
    WeaponMode   = 'DW',      -- DW | 2H | SNB | ANY | always | never
    RangedMode   = 'any',     -- any | bows
    LootRange    = 200,       -- radius in units to scan for corpses
    WarpDist     = 100,       -- max distance before warping to corpse (0 = warp always)
    UseWarp      = true,      -- true = /warp target, false = /nav to corpse
    TrashPrice   = 0,         -- sell anything >= this value (pp); 0 = sell nothing

    -- Feature toggles
    LootEnabled        = true,
    LootDuringCombat   = false,   -- allow loot sweeps while Me.CombatState()=='COMBAT' (per-character; ignored in rgmercs-directed mode)
    LootCorpses        = true,
    LootPets           = false,
    LootGroup          = false,   -- loot group members' nearby corpses
    AnnounceGroup      = false,   -- broadcast loot events to group channel
    AnnounceChannel    = 'group', -- group | raid — channel for per-item loot pickup announcements
    AnnounceDone       = true,    -- send /g Done Looting after a sweep clears all corpses
    AutoEquipUpgrades  = true,    -- equip upgrade immediately; false = bag it for manual equip
    ExcludedSlots      = '',      -- comma-sep slot IDs excluded from upgrade eval (per-char)
    LootSpells         = false,   -- pick up spell scrolls (per-character); NoDrop scrolls always require class-usability
    LootOffClassSpells = false,   -- also pick up TRADEABLE scrolls your class can't use; no effect if LootSpells is off, or on NoDrop scrolls

    -- Vendor / Bank behaviour
    AutoConsolidateCoins = true,   -- consolidate CP/SP/GP→PP automatically after BankStuff deposit
    BankAutoDeposit      = false,  -- skip confirm window and deposit bank-list items immediately
    SellAutoSell         = false,  -- skip confirm window and sell sell-list items immediately
    RestockAutoRestock   = false,  -- skip confirm window and restock items immediately

    -- Debug / logging (per-character)
    LogLevel      = 3,        -- 1=Error 2=Warn 3=Info 4=Debug
    LogToFile     = false,
    LogTimestamps = false,

    -- UI state (not shown in setup dialog)
    SetupDone    = false,     -- true after first-launch setup is saved
    PanelOpen    = true,
    HistoryOpen  = false,
    EditorOpen   = false,
}

-- Keys written to the shared INI so all toons inherit them on startup.
-- Per-character keys (WeaponMode, LootEnabled, UI state) are intentionally excluded.
local SHARED_KEYS = {
    Framework     = true,
    Channel       = true,
    UseWarp       = true,
    LootRange     = true,
    WarpDist      = true,
    TrashPrice    = true,
    LootCorpses   = true,
    LootPets      = true,
    LootGroup     = true,
    AnnounceGroup         = true,
    AnnounceChannel       = true,
    AnnounceDone          = true,
    AutoConsolidateCoins  = true,
    BankAutoDeposit       = false,
}

-- Live config table — starts as a copy of defaults, then overwritten by INI
Config.Settings = {}

local function toBool(v)
    if type(v) == 'boolean' then return v end
    if v == nil then return false end
    return tostring(v):lower() == 'true' or tostring(v) == '1'
end

local function coerce(default, raw)
    if raw == nil then return default end
    local t = type(default)
    if t == 'boolean' then return toBool(raw) end
    if t == 'number'  then return tonumber(raw) or default end
    return tostring(raw)
end

local function readIni(iniFile, settings, defaults)
    if not fileExists(iniFile) then return end
    for k, default in pairs(defaults) do
        local raw = mq.TLO.Ini(iniFile, 'proloot', k, tostring(default))()
        settings[k] = coerce(default, raw)
    end
end

function Config:Load()
    -- Layer 1: defaults
    for k, v in pairs(self.Defaults) do
        self.Settings[k] = v
    end

    -- Layer 2: shared INI (group-wide settings)
    readIni(sharedIniPath(), self.Settings, self.Defaults)

    -- Layer 3: per-character INI (class-specific / individual overrides)
    readIni(iniPath(), self.Settings, self.Defaults)
end

function Config:Save()
    local ini    = iniPath()
    local shared = sharedIniPath()
    for k, v in pairs(self.Settings) do
        mq.cmdf('/ini "%s" "proloot" "%s" "%s"', ini, k, tostring(v))
        if SHARED_KEYS[k] then
            mq.cmdf('/ini "%s" "proloot" "%s" "%s"', shared, k, tostring(v))
        end
    end
end

function Config:Get(key)
    if self.Settings[key] == nil then
        return self.Defaults[key]
    end
    return self.Settings[key]
end

function Config:Set(key, value)
    self.Settings[key] = coerce(self.Defaults[key], value)
end

function Config:SetAndSave(key, value)
    self:Set(key, value)
    self:Save()
end

-- Call once at startup
function Config:Init()
    self:Load()
end

return Config
