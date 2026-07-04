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
                -- Format: "ItemName" or "ItemName|12345"
                local itemName, idStr = line:match('^([^|]+)|?(%d*)$')
                if itemName then
                    itemName = itemName:match('^%s*(.-)%s*$')
                    local id = tonumber(idStr) or 0
                    self:_add(itemName, id, false)
                end
            end
        end
        f:close()
        -- Merge any seeds not already present (picks up new defaults after updates)
        local merged = 0
        for _, entry in ipairs(self._seeds) do
            if self:_add(entry.name, entry.id or 0, false) then
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
            self:_add(entry.name, entry.id or 0, false)
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
        if entry.id and entry.id > 0 then
            f:write(string.format('%s|%d\n', entry.name, entry.id))
        else
            f:write(string.format('%s\n', entry.name))
        end
    end
    f:close()
    self._dirty = false
end

function Base:_add(name, id, markDirty)
    local key = name:lower()
    if self._byName[key] then return false end -- duplicate
    self._byName[key] = true
    if id and id > 0 then self._byId[id] = true end
    table.insert(self._ordered, { name=name, id=id or 0 })
    if markDirty ~= false then self._dirty = true end
    return true
end

function Base:Add(name, id)
    return self:_add(name, id, true)
end

function Base:Remove(name)
    local key = name:lower()
    if not self._byName[key] then return false end
    self._byName[key] = nil
    for i, entry in ipairs(self._ordered) do
        if entry.name:lower() == key then
            if entry.id and entry.id > 0 then self._byId[entry.id] = nil end
            table.remove(self._ordered, i)
            break
        end
    end
    self._dirty = true
    return true
end

-- Primary lookup called by core/loot.lua
function Base:Has(name, id)
    if id and id > 0 and self._byId[id] then return true end
    if name and self._byName[name:lower()] then return true end
    return false
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
