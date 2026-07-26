-- RGMercs Directed adapter: coordinates looting via RGMercs Actors mailbox protocol.
--
-- Unlike the standard rgmercs adapter (which issues /rgl pause), this adapter signals
-- RGMercs's loot_module via Actors so RGMercs holds camp enforcement cooperatively
-- without pausing combat assistance entirely. RGMercs also decides *when* to loot —
-- it sends a 'doloot' directive to our own 'proloot' mailbox (see ConsumeDirective
-- below), and init.lua's main loop sweeps only in response, not on its own timer.
--
-- Requirements (all three must be true):
--   1. RGMercs LootModuleType = ProLoot (modules/proloot.lua loaded — registers
--      the loot_module mailbox and sends 'doloot' directives)
--   2. DoLoot = true in RGMercs's ProLoot loot settings
--   3. ProLoot launched with framework=rgmercs-directed (RGMercs does this
--      automatically when its ProLoot module's DoLoot setting is enabled)
--
-- Use this adapter with a forked RGMercs that has the native ProLoot module
-- (modules/proloot.lua). For stock RGMercs, use the rgmercs adapter instead.

local mq     = require('mq')
local Actors = require('actors')

local Adapter = {}
Adapter.name   = 'rgmercs-directed'
Adapter._actor = nil
Adapter._pendingDirective = false

-- Marks this adapter as trigger-driven: init.lua's main loop suppresses its
-- own autonomous LOOT_INTERVAL sweep and loots only when ConsumeDirective()
-- reports a directive received from RGMercs's loot module.
Adapter.directed = true

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

-- RGMercs's loot_module sends a { who, directions='doloot' } message here
-- (mailbox 'proloot') when it decides it is safe for us to sweep. We just
-- latch a flag; init.lua's main loop consumes it via ConsumeDirective().
function Adapter:_ensureActor()
    if not self._actor then
        self._actor = Actors.register('proloot', function(message)
            local mail = message()
            if mail.who ~= mq.TLO.Me.CleanName() then return end
            if mail.directions == 'doloot' then
                self._pendingDirective = true
            end
        end)
    end
end

-- Returns true (once) if RGMercs has signaled it's our turn to loot, and
-- clears the flag. Ensures the mailbox is registered even before the first
-- BeginLoot/EndLoot call, so directives aren't missed while idle.
function Adapter:ConsumeDirective()
    self:_ensureActor()
    if self._pendingDirective then
        self._pendingDirective = false
        return true
    end
    return false
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
