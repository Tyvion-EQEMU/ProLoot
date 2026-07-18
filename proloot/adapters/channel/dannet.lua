-- DanNet channel adapter: broadcast loot events via /dgge, receive via a registered slash command

local mq = require('mq')

local Adapter    = {}
Adapter.name     = 'dannet'

local _observers      = {}
local _seq            = 0
local _bindRegistered = false

local function myName()
    return mq.TLO.Me.CleanName()
end

local function dannetAvailable()
    return mq.TLO.Plugin('MQ2DanNet').IsLoaded() == true
end

function Adapter:Init()
    if not dannetAvailable() then
        printf('\arDanNet not loaded — channel adapter disabled')
        return
    end

    if not _bindRegistered then
        -- Peers call /proloot_recv {lua-table} via /dgge/dgae — no chat output, fully silent.
        mq.bind('/proloot_recv', function(data)
            if not data or data == '' then return end
            local ok, payload = pcall(function() return load('return ' .. data)() end)
            if not ok or type(payload) ~= 'table' then return end
            if payload.from == myName() then return end -- skip echoes (dgae includes self)
            for _, cb in ipairs(_observers) do
                cb(payload)
            end
        end)
        _bindRegistered = true
    end
end

local function encode(payload)
    _seq         = _seq + 1
    payload.seq  = _seq
    payload.from = myName()
    local parts = {}
    for k, v in pairs(payload) do
        if type(v) == 'string' then
            table.insert(parts, string.format('%s="%s"', k, v:gsub('"', '\\"')))
        else
            table.insert(parts, string.format('%s=%s', k, tostring(v)))
        end
    end
    return '{' .. table.concat(parts, ',') .. '}'
end

-- Broadcast a table payload to the current in-game group via /dgge (excludes self).
-- Sender records its own events locally via pushHistory(), so self-exclusion is correct.
function Adapter:Broadcast(payload)
    if not dannetAvailable() then return end
    mq.cmdf('/squelch /dgge /proloot_recv %s', encode(payload))
end

-- Broadcast a table payload to every DanNet peer regardless of group/raid, via /dgae.
-- /dgae includes self, so the recv bind above filters echoes by payload.from.
function Adapter:BroadcastAll(payload)
    if not dannetAvailable() then return end
    mq.cmdf('/squelch /dgae /proloot_recv %s', encode(payload))
end

function Adapter:Observe(cb)
    table.insert(_observers, cb)
end

-- mq.doevents() in the main loop is sufficient; no per-tick DanNet polling needed
function Adapter:Tick()
    mq.doevents()
end

return Adapter
