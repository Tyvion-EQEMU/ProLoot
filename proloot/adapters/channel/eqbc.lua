-- EQBC channel adapter: broadcast/observe loot events via /bccmd and MQ2EQBC event parsing

local mq = require('mq')

-- EQBC doesn't have a structured pub/sub model like DanNet, so we use
-- /bct <toon> //docommand to send targeted tells and /bca for broadcast.
-- We register a MQ2 event that fires when we receive our custom prefix tag.

local PREFIX  = '#proloot#'  -- distinguishes our messages from other EQBC traffic
local Adapter = {}
Adapter.name  = 'eqbc'

local _observers = {}
local _seq = 0
local _eventRegistered = false

local function eqbcAvailable()
    return mq.TLO.Plugin('MQ2EQBC').IsLoaded() == true
end

local function myName()
    return mq.TLO.Me.CleanName()
end

local function onEQBCMessage(line, sender, msg)
    -- msg is the text after PREFIX
    local ok, payload = pcall(function() return load('return ' .. msg)() end)
    if not ok or type(payload) ~= 'table' then return end
    if payload.from == myName() then return end -- skip echoes
    for _, cb in ipairs(_observers) do
        cb(payload)
    end
end

function Adapter:Init()
    if not eqbcAvailable() then
        printf('\arEQBC not loaded — channel adapter disabled')
        return
    end

    if not _eventRegistered then
        -- MQ2 event fires when a BCST line contains our prefix
        mq.event('proloot_eqbc', string.format('*%s*', PREFIX), function(line)
            -- Extract sender and payload from the EQBC tell format:
            -- "[EQBC] <from> -> You: #proloot#{...}"
            local sender, msg = line:match('%[EQBC%]%s+(.-)%s*%-%->%s*You:%s*' .. PREFIX .. '(.*)')
            if sender and msg then
                onEQBCMessage(line, sender, msg)
            end
        end)
        _eventRegistered = true
    end
end

function Adapter:Broadcast(payload)
    if not eqbcAvailable() then return end
    _seq = _seq + 1
    payload.seq  = _seq
    payload.from = myName()
    -- Serialize as a Lua table literal (portable, no JSON dep needed for EQBC)
    local parts = {}
    for k, v in pairs(payload) do
        if type(v) == 'string' then
            table.insert(parts, string.format('%s="%s"', k, v:gsub('"', '\\"')))
        else
            table.insert(parts, string.format('%s=%s', k, tostring(v)))
        end
    end
    local encoded = '{' .. table.concat(parts, ',') .. '}'
    mq.cmdf('/bca /bcst %s%s', PREFIX, encoded)
end

-- EQBC's /bca already reaches every connected client regardless of in-game group/raid.
Adapter.BroadcastAll = Adapter.Broadcast

function Adapter:Observe(cb)
    table.insert(_observers, cb)
end

-- EQBC events are processed via mq.doevents() in the main loop; no manual Tick needed
function Adapter:Tick()
    mq.doevents()
end

return Adapter
