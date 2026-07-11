-- RGMercs adapter: pause via /rgl pause, resume via /rgl unpause; detects running rgmercs lua script

local mq = require('mq')

local Adapter = {}
Adapter.name       = 'rgmercs'
Adapter._ownsPause = false  -- true only while ProLoot itself is holding the pause it issued

-- RGMercs registers the /rgl command when running.
-- /rgl pause   → pauses RGMercs combat assistance (including camp enforcement)
-- /rgl unpause → resumes RGMercs combat assistance
-- RGMercs also exposes ${RGMercs.Paused} — the live, ground-truth pause state —
-- which lets ProLoot tell "someone else already paused this" apart from
-- "we paused this ourselves", so it never unpauses a manually-paused RGMercs.

function Adapter:Detect()
    return mq.TLO.Alias('/rgl')() ~= nil
end

function Adapter:Pause()    mq.cmd('/rgl pause')   end
function Adapter:Resume()   mq.cmd('/rgl unpause') end

function Adapter:IsExternallyPaused()
    local ok, paused = pcall(function() return mq.TLO.RGMercs.Paused() end)
    return ok and paused == true
end

function Adapter:PauseAndTrack()
    if self._ownsPause then return end        -- already holding our own pause
    if self:IsExternallyPaused() then return end -- already paused by someone else — leave it alone
    self:Pause()
    self._ownsPause = true
end

function Adapter:ResumeAndTrack()
    if self._ownsPause then
        self:Resume()
        self._ownsPause = false
    end
end

function Adapter:IsPaused()
    return self:IsExternallyPaused()
end

-- Pause RGMercs for the duration of the loot sweep so camp enforcement
-- does not pull the toon back before corpses are reached. If RGMercs was
-- already paused when the sweep began (e.g. paused manually), ProLoot leaves
-- it alone and will not unpause it at EndLoot.
-- Looting only happens in downtime so pausing combat assistance is safe.
-- BeginLoot/EndLoot are called from Loot.LootNearby(); RefreshLoot is a
-- no-op here because the pause is sustained until EndLoot.
function Adapter:BeginLoot()  self:PauseAndTrack()   end
function Adapter:EndLoot()    self:ResumeAndTrack()  end
function Adapter:RefreshLoot() end

return Adapter
