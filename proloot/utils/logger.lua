-- Structured logger: routes messages to the in-panel ConsoleWidget and optionally a log file.
-- Log levels: 1=Error  2=Warn  3=Info  4=Debug  (default 3)

local mq = require('mq')

local Logger = {}

local LEVEL_LABELS = { 'Error', 'Warn', 'Info', 'Debug' }
local LEVEL_TAGS   = { 'ERROR', 'WARN ', 'INFO ', 'DEBUG' }

local _config      = nil
local _console     = nil
local _fh          = nil
local _dirCache    = nil
local _serverCache = nil

-- Log files live under MacroQuest's Logs directory (not the config directory) so they
-- don't clutter Config/proloot alongside per-character ini/list files. Use
-- MacroQuest.Path[logs] rather than hardcoding a path — it's user-configurable.
local function prolootLogDir()
    if not _dirCache then
        _dirCache = mq.TLO.MacroQuest.Path('logs')() .. '/proloot'
        local ok, _, code = os.rename(_dirCache, _dirCache)
        if not ok and code ~= 13 then
            os.execute('mkdir "' .. _dirCache .. '"')
        end
    end
    return _dirCache
end

local function serverTag()
    if not _serverCache then
        _serverCache = mq.TLO.EverQuest.Server():gsub(' ', '_')
    end
    return _serverCache
end

local function getConsole()
    if not _console then
        _console                = ImGui.ConsoleWidget.new('##proloot_console')
        _console.autoScroll     = true
        _console.maxBufferLines = 200
    end
    return _console
end

local function ensureFile()
    if _fh then return end
    local path = string.format('%s/ConsoleLogs_%s_%s.log',
        prolootLogDir(), serverTag(), mq.TLO.Me.CleanName())
    _fh = io.open(path, 'a')
    if _fh then
        _fh:write(string.format('\n=== Session %s ===\n', os.date('%Y-%m-%d %H:%M:%S')))
        _fh:flush()
    end
end

local function closeFile()
    if _fh then _fh:close(); _fh = nil end
end

local function log(levelNum, fmt, ...)
    if not _config then return end
    if levelNum > (_config:Get('LogLevel') or 3) then return end

    local msg = (... ~= nil) and string.format(fmt, ...) or tostring(fmt)
    local tag = LEVEL_TAGS[levelNum] or 'INFO '
    local ts  = _config:Get('LogTimestamps')
        and string.format('[%s] ', os.date('%H:%M:%S')) or ''

    getConsole():AppendText(string.format('%s[%s] %s', ts, tag, msg))

    if _config:Get('LogToFile') then
        ensureFile()
        if _fh then
            _fh:write(string.format('[%s][%s] %s\n', os.date('%H:%M:%S'), tag, msg))
            _fh:flush()
        end
    else
        closeFile()
    end
end

function Logger.Init(config)
    _config = config
end

function Logger.GetConsole()
    return getConsole()
end

function Logger.LevelLabels()
    return LEVEL_LABELS
end

function Logger.Error(fmt, ...) log(1, fmt, ...) end
function Logger.Warn(fmt, ...)  log(2, fmt, ...) end
function Logger.Info(fmt, ...)  log(3, fmt, ...) end
function Logger.Debug(fmt, ...) log(4, fmt, ...) end

return Logger
