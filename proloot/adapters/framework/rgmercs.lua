-- RGMercs adapter: pause via /rgl pause, resume via /rgl unpause; detects running rgmercs lua script
-- Loot coordination uses RGMercs's Actors mailbox protocol so camp enforcement is held cooperatively
-- rather than pausing the entire framework.

local mq     = require('mq')
local Actors = require('actors')

local Adapter = {}
Adapter.name    = 'rgmercs'
Adapter._paused = false
Adapter._actor  = nil

-- RGMercs registers the /rgl command when running.
-- /rgl pause   → pauses RGMercs combat assistance
-- /rgl unpause → resumes RGMercs combat assistance

function Adapter:Detect()
    return mq.TLO.Alias('/rgl')() ~= nil
end

function Adapter:Pause()    mq.cmd('/rgl pause')   end
function Adapter:Resume()   mq.cmd('/rgl unpause') end

Adapter._paused = false

function Adapter:PauseAndTrack()
    if not self._paused then self:Pause(); self._paused = true end
end

function Adapter:ResumeAndTrack()
    if self._paused then self:Resume(); self._paused = false end
end

function Adapter:IsPaused()
    return self._paused
end

-- Lazy-init our actor so Actors is only loaded when this adapter is actually active.
function Adapter:_ensureActor()
    if not self._actor then
        self._actor = Actors.register('proloot', function() end)
    end
end

-- Signal RGMercs's loot_module that looting is in progress.
-- This causes DoLooting() to block the RGMercs main loop, which implicitly
-- holds camp enforcement for the duration of the loot sweep.
-- Requires RGMercs to have DoLoot enabled so loot_module is loaded.
-- If the mailbox isn't registered the message is silently dropped and we fall
-- back to normal behaviour (no camp hold).
function Adapter:BeginLoot()
    self:_ensureActor()
    self._actor:send(
        { mailbox = 'loot_module', script = 'rgmercs' },
        { Subject = 'processing', Who = mq.TLO.Me.CleanName() }
    )
end

-- Signal RGMercs's loot_module that looting is finished, releasing camp enforcement.
function Adapter:EndLoot()
    self:_ensureActor()
    self._actor:send(
        { mailbox = 'loot_module', script = 'rgmercs' },
        { Subject = 'done_looting', Who = mq.TLO.Me.CleanName() }
    )
end

-- Reset the loot hold window per corpse. RGMercs's DoLooting() has a hard timeout
-- (LootingTimeoutLNS, default 5s). Ending and immediately re-beginning restarts
-- that timer so multi-corpse sweeps without warp stay covered.
function Adapter:RefreshLoot()
    self:EndLoot()
    self:BeginLoot()
end

return Adapter
