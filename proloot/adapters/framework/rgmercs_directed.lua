-- RGMercs Directed adapter: coordinates looting via RGMercs Actors mailbox protocol.
--
-- Unlike the standard rgmercs adapter (which issues /rgl pause), this adapter signals
-- RGMercs's loot_module via Actors so RGMercs holds camp enforcement cooperatively
-- without pausing combat assistance entirely.
--
-- Requirements (all three must be true):
--   1. RGMercs LootModuleType = 2 (LootNScoot module loaded — registers loot_module mailbox)
--   2. DoLoot = true in RGMercs loot settings (enables GiveTime to enter DoLooting())
--   3. A ProLoot-native loot module in RGMercs, OR LootNScoot running in directed mode
--
-- Use this adapter with a forked RGMercs that has ProLoot built in natively.
-- For stock RGMercs, use the rgmercs adapter instead.

local mq     = require('mq')
local Actors = require('actors')

local Adapter = {}
Adapter.name   = 'rgmercs-directed'
Adapter._actor = nil

function Adapter:Detect()
    return mq.TLO.Alias('/rgl')() ~= nil
end

-- Pause/Resume are no-ops: coordination is handled via BeginLoot/EndLoot Actors
-- messages, not a full framework pause. This also prevents the init.lua outer
-- PauseAndTrack() wrapper from issuing /rgl pause on each loot sweep.
function Adapter:Pause()          end
function Adapter:Resume()         end
function Adapter:PauseAndTrack()  end
function Adapter:ResumeAndTrack() end
function Adapter:IsPaused()       return false end

function Adapter:_ensureActor()
    if not self._actor then
        self._actor = Actors.register('proloot', function() end)
    end
end

-- Signal RGMercs's loot_module that looting is in progress. This causes
-- DoLooting() to block the RGMercs main loop, implicitly holding camp
-- enforcement for the duration of the sweep.
function Adapter:BeginLoot()
    self:_ensureActor()
    self._actor:send(
        { mailbox = 'loot_module', script = 'rgmercs' },
        { Subject = 'processing', Who = mq.TLO.Me.CleanName() }
    )
end

-- Signal RGMercs's loot_module that looting is complete, releasing the hold.
function Adapter:EndLoot()
    self:_ensureActor()
    self._actor:send(
        { mailbox = 'loot_module', script = 'rgmercs' },
        { Subject = 'done_looting', Who = mq.TLO.Me.CleanName() }
    )
end

-- RGMercs's DoLooting() has a hard timeout (LootingTimeoutLNS, default 5s).
-- Reset it per corpse by ending and immediately re-beginning so multi-corpse
-- sweeps without warp stay covered past that window.
function Adapter:RefreshLoot()
    self:EndLoot()
    self:BeginLoot()
end

return Adapter
