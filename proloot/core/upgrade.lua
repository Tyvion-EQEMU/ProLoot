-- Weapon/armor upgrade evaluation: compares item stats against equipped gear by slot, decides keep-or-destroy

local mq = require('mq')

local Upgrade = {}

-- Numeric worn-slot IDs (from item.WornSlot(i)) that are weapon or shield slots
local PRIMARY_SLOT   = 13
local SECONDARY_SLOT = 14
local RANGED_SLOT    = 11

-- Slots we skip entirely — non-gear equippables
local SKIP_SLOTS = { [0]=true, [21]=true, [22]=true }  -- Charm, Powersource, Ammo

-- Weapon quality: higher damage-to-delay ratio is better
local function weaponScore(item)
    local dmg = item.Damage()   or 0
    local dly = item.ItemDelay() or item.Delay() or 1
    if dly == 0 then dly = 1 end
    return (dmg / dly) * 100
end

-- Armor quality: weighted AC + HP + Mana
local function armorScore(item)
    return (item.AC()   or 0) * 3
         + (item.HP()   or 0) * 0.5
         + (item.Mana() or 0) * 0.3
end

-- True if newItem beats whatever is currently in numeric slot slotId
local function isUpgrade(newItem, slotId, rangedMode)
    local equipped = mq.TLO.Me.Inventory(slotId)
    if not equipped or not equipped.ID() or equipped.ID() == 0 then return true end

    if slotId == PRIMARY_SLOT or slotId == SECONDARY_SLOT then
        return weaponScore(newItem) > weaponScore(equipped)
    elseif slotId == RANGED_SLOT and rangedMode == 'bows' then
        return weaponScore(newItem) > weaponScore(equipped)
    else
        return armorScore(newItem) > armorScore(equipped)
    end
end

-- True if this character's class can equip the item.
-- Items with 0 classes or all 16 classes have no restriction.
function Upgrade.ClassCanUse(item)
    local classCount = item.Classes() or 0
    if classCount == 0 or classCount >= 16 then return true end
    local myClass = mq.TLO.Me.Class.Name() or ''
    for i = 1, classCount do
        local cls = item.Class(i)
        if cls and cls.Name() == myClass then return true end
    end
    return false
end

local function itemType(item)
    return (item.Type() or ''):lower()
end

-- EQ reports types as '2h slashing', '2h blunt', '2h piercing', '1h slashing', etc.
local function is2H(t)     return t:sub(1,2) == '2h' end
local function is1H(t)     return t:sub(1,2) == '1h' or t == 'piercing' or t == 'hand to hand' or t == 'martial' end
local function isShield(t) return t:find('shield') ~= nil end
-- 'archery' covers both bows and crossbows in MQ2
local function isBow(t)    return t == 'archery' or t == 'bow' or t == 'crossbow' end

-- True if the item can go in Primary or Secondary slot
local function fitsWeaponSlot(item)
    for i = 1, (item.WornSlots() or 0) do
        local sid = tonumber(item.WornSlot(i)()) or -1
        if sid == PRIMARY_SLOT or sid == SECONDARY_SLOT then return true end
    end
    return false
end

-- False when weaponMode forbids this item's weapon category; armor always passes
local function allowedByMode(item, weaponMode)
    if not fitsWeaponSlot(item) then return true end

    local t = itemType(item)

    if isShield(t) then
        -- DW and 2H modes don't want shields
        return weaponMode ~= 'DW' and weaponMode ~= '2H'
    end

    if weaponMode == 'DW'  then return not is2H(t) end
    if weaponMode == '2H'  then return not is1H(t) end
    if weaponMode == 'SNB' then return not is2H(t) end
    return true  -- ANY
end

-- Public scoring function: returns a numeric quality score for item in slotId.
-- Used by the Upgrade Evaluator to rank multiple upgrade candidates in the same slot.
function Upgrade.ItemScore(item, slotId, rangedMode)
    if slotId == PRIMARY_SLOT or slotId == SECONDARY_SLOT then
        return weaponScore(item)
    elseif slotId == RANGED_SLOT and (rangedMode or 'any') == 'bows' then
        return weaponScore(item)
    else
        return armorScore(item)
    end
end

-- Public slot name map (slot ID → display name) used by UI widgets and the Upgrade Evaluator.
Upgrade.SLOT_NAMES = {
    [1]  = 'Left Ear',   [2]  = 'Head',       [3]  = 'Face',
    [4]  = 'Right Ear',  [5]  = 'Neck',        [6]  = 'Shoulders',
    [7]  = 'Arms',       [8]  = 'Back',         [9]  = 'Left Wrist',
    [10] = 'Right Wrist',[11] = 'Range',        [12] = 'Hands',
    [13] = 'Primary',    [14] = 'Secondary',    [15] = 'Left Ring',
    [16] = 'Right Ring', [17] = 'Chest',        [18] = 'Legs',
    [19] = 'Feet',       [20] = 'Waist',
}

-- Ordered list of slot IDs for UI iteration (excludes Charm/Powersource/Ammo)
Upgrade.SLOT_ORDER = { 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20 }

-- Parse a comma-separated slot ID string into a set: { [slotId]=true, ... }
function Upgrade.ParseExcludedSlots(str)
    local set = {}
    for id in tostring(str or ''):gmatch('%d+') do
        set[tonumber(id)] = true
    end
    return set
end

-- Serialize a slot set back to a sorted comma-separated string for INI storage
function Upgrade.SerializeExcludedSlots(set)
    local ids = {}
    for id in pairs(set) do ids[#ids+1] = id end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do parts[#parts+1] = tostring(id) end
    return table.concat(parts, ',')
end

-- Returns the first worn slotId where item beats what is currently equipped, or nil.
-- Respects weapon mode, ranged mode, and per-character slot exclusions.
-- Returns nil for 'always'/'never' modes.
function Upgrade.FindUpgradeSlot(item, weaponMode, rangedMode, excludedSlots)
    if not item or not item.ID() or item.ID() == 0 then return nil end
    weaponMode = weaponMode or 'DW'
    rangedMode = rangedMode or 'any'
    if weaponMode == 'always' or weaponMode == 'never' then return nil end
    if not Upgrade.ClassCanUse(item)        then return nil end
    if not allowedByMode(item, weaponMode) then return nil end

    local wornCount = item.WornSlots() or 0
    if wornCount == 0 then return nil end

    local t = itemType(item)
    for i = 1, wornCount do
        local slotId = tonumber(item.WornSlot(i)()) or -1
        if slotId >= 0 and not SKIP_SLOTS[slotId]
                       and not (excludedSlots and excludedSlots[slotId]) then
            if slotId == RANGED_SLOT and rangedMode == 'bows' and not isBow(t) then
                -- skip: non-bow item cannot displace a bow in 'bows' mode
            elseif isUpgrade(item, slotId, rangedMode) then
                return slotId
            end
        end
    end
    return nil
end

-- Public API: true if item is worth keeping given current weapon mode.
-- weaponMode: 'DW' | '2H' | 'SNB' | 'ANY' | 'always' | 'never'
function Upgrade.ShouldKeep(item, weaponMode)
    if not item or not item.ID() or item.ID() == 0 then return false end
    weaponMode = weaponMode or 'DW'
    if weaponMode == 'always' then return true  end
    if weaponMode == 'never'  then return false end
    return Upgrade.FindUpgradeSlot(item, weaponMode) ~= nil
end

return Upgrade
