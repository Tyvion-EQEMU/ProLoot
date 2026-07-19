-- Shared list factory: persistent name/id sets backed by a flat text file, one entry per line

local mq     = require('mq')
local Logger = require('proloot.utils.logger')

local Base = {}
Base.__index = Base

-- name  : short label (e.g. "currency") used as filename
-- seeds : default entries pre-populated on first load
function Base.new(name, seeds)
    local self = setmetatable({}, Base)
    self._name    = name
    self._byName  = {}   -- [lowercase name] = true
    self._byId    = {}   -- [id] = true
    self._ordered = {}   -- ordered list of {name, id} for UI display
    self._dirty   = false
    self._seeds   = seeds or {}
    return self
end

local _listDir    = nil
local _serverTag  = nil

local function prolootDir()
    if not _listDir then
        _listDir = mq.configDir .. '/proloot'
        local ok, _, code = os.rename(_listDir, _listDir)
        if not ok and code ~= 13 then
            os.execute('mkdir "' .. _listDir .. '"')
        end
    end
    return _listDir
end

local function serverTag()
    if not _serverTag then
        _serverTag = mq.TLO.EverQuest.Server():gsub(' ', '_')
    end
    return _serverTag
end

local function filePath(name)
    return string.format('%s/LootList_%s_%s.txt', prolootDir(), serverTag(), name)
end

function Base:Load()
    self._byName  = {}
    self._byId    = {}
    self._ordered = {}

    local path = filePath(self._name)
    local f    = io.open(path, 'r')
    if f then
        for line in f:lines() do
            line = line:match('^%s*(.-)%s*$') -- trim
            if line ~= '' and line:sub(1,1) ~= '#' then
                -- Format: "ItemName", "ItemName|12345", "ItemName|12345|3" (3rd field
                -- is the desired pickup count — 0/absent means unlimited), or
                -- "ItemName|12345|3|0" (4th field is enabled — 0 = soft-disabled,
                -- absent/anything else = enabled).
                local fields = {}
                for part in (line .. '|'):gmatch('([^|]*)|') do fields[#fields+1] = part end
                local itemName = fields[1] and fields[1]:match('^%s*(.-)%s*$')
                if itemName and itemName ~= '' then
                    local id      = tonumber(fields[2]) or 0
                    local count   = tonumber(fields[3]) or 0
                    local enabled = not (fields[4] and fields[4] ~= '' and tonumber(fields[4]) == 0)
                    self:_add(itemName, id, count, enabled, false)
                end
            end
        end
        f:close()
        -- Merge any seeds not already present (picks up new defaults after updates)
        local merged = 0
        for _, entry in ipairs(self._seeds) do
            if self:_add(entry.name, entry.id or 0, entry.count or 0, entry.enabled, false) then
                Logger.Info('Lists: merged new seed "%s" into %s list', entry.name, self._name)
                merged = merged + 1
            end
        end
        if merged > 0 then
            Logger.Info('Lists: saved %d new seed(s) to %s list', merged, self._name)
            self:Save()
        end
    else
        -- First run: seed defaults
        for _, entry in ipairs(self._seeds) do
            self:_add(entry.name, entry.id or 0, entry.count or 0, entry.enabled, false)
        end
        self:Save()
    end
    self._dirty = false
end

function Base:Save()
    local path = filePath(self._name)
    local f    = io.open(path, 'w')
    if not f then
        printf('\arProLoot: failed to write %s', path)
        return
    end
    for _, entry in ipairs(self._ordered) do
        if entry.enabled == false then
            -- Disabled entries always write all 4 fields so the 0 lands in position 4.
            f:write(string.format('%s|%d|%d|0\n', entry.name, entry.id or 0, entry.count or 0))
        elseif entry.count and entry.count > 0 then
            f:write(string.format('%s|%d|%d\n', entry.name, entry.id or 0, entry.count))
        elseif entry.id and entry.id > 0 then
            f:write(string.format('%s|%d\n', entry.name, entry.id))
        else
            f:write(string.format('%s\n', entry.name))
        end
    end
    f:close()
    self._dirty = false
end

function Base:_add(name, id, count, enabled, markDirty)
    local key = name:lower()
    if self._byName[key] then return false end -- duplicate
    local entry = { name=name, id=id or 0, count=count or 0, enabled=(enabled ~= false) }
    self._byName[key] = entry
    if entry.id > 0 then self._byId[entry.id] = entry end
    table.insert(self._ordered, entry)
    if markDirty ~= false then self._dirty = true end
    return true
end

function Base:Add(name, id, count, enabled)
    return self:_add(name, id, count, enabled, true)
end

function Base:Remove(name)
    local key   = name:lower()
    local entry = self._byName[key]
    if not entry then return false end
    self._byName[key] = nil
    if entry.id and entry.id > 0 then self._byId[entry.id] = nil end
    for i, e in ipairs(self._ordered) do
        if e == entry then
            table.remove(self._ordered, i)
            break
        end
    end
    self._dirty = true
    return true
end

-- Sets the desired pickup count for an existing entry (0 = unlimited). Caller
-- is responsible for calling Save() afterward, matching the Add/Remove pattern.
function Base:SetCount(name, count)
    local entry = self._byName[name:lower()]
    if not entry then return false end
    entry.count = count or 0
    self._dirty = true
    return true
end

-- Soft-disables/re-enables an entry without removing it from the list (keeps
-- the item name/id/count on file so it can be flipped back on later). Caller
-- is responsible for calling Save() afterward, matching the Add/Remove pattern.
function Base:SetEnabled(name, enabled)
    local entry = self._byName[name:lower()]
    if not entry then return false end
    entry.enabled = (enabled ~= false)
    self._dirty = true
    return true
end

-- Primary lookup called by core/loot.lua. A soft-disabled entry (enabled=false)
-- reports as not-found here so loot logic treats it as if it weren't on the
-- list at all, while it still shows up (greyed out) in the List Editor via
-- Entries(). Second return is the entry's desired pickup count (0 = unlimited)
-- when found, 0 otherwise.
function Base:Has(name, id)
    local entry = (id and id > 0 and self._byId[id]) or (name and self._byName[name:lower()])
    if entry and entry.enabled ~= false then return true, entry.count or 0 end
    return false, 0
end

function Base:Entries()
    return self._ordered
end

function Base:IsDirty()
    return self._dirty
end

function Base:Name()
    return self._name
end

return Base
