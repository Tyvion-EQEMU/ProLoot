-- RGMercs adapter: pause via /rgl pause, resume via /rgl unpause; detects running rgmercs lua script

local mq = require('mq')

local Adapter = {}
Adapter.name    = 'rgmercs'
Adapter._paused = false

-- RGMercs registers the /rgl command when running.
-- /rgl pause   → pauses RGMercs combat assistance (including camp enforcement)
-- /rgl unpause → resumes RGMercs combat assistance

function Adapter:Detect()
    return mq.TLO.Alias('/rgl')() ~= nil
end

function Adapter:Pause()    mq.cmd('/rgl pause')   end
function Adapter:Resume()   mq.cmd('/rgl unpause') end

function Adapter:PauseAndTrack()
    if not self._paused then self:Pause(); self._paused = true end
end

function Adapter:ResumeAndTrack()
    if self._paused then self:Resume(); self._paused = false end
end

function Adapter:IsPaused()
    return self._paused
end

-- Pause RGMercs for the duration of the loot sweep so camp enforcement
-- does not pull the toon back before corpses are reached.
-- Looting only happens in downtime so pausing combat assistance is safe.
-- BeginLoot/EndLoot are called from Loot.LootNearby(); RefreshLoot is a
-- no-op here because the pause is sustained until EndLoot.
function Adapter:BeginLoot()  self:PauseAndTrack()   end
function Adapter:EndLoot()    self:ResumeAndTrack()  end
function Adapter:RefreshLoot() end

return Adapter
