-- Null channel adapter: no-op broadcast/observe; used when running fully solo with no group communication

local Adapter = {}
Adapter.name = 'none'

function Adapter:Init()     end
function Adapter:Broadcast(_msg)  end
function Adapter:BroadcastAll(_msg) end
function Adapter:Observe(_cb) end
function Adapter:Tick()     end

return Adapter
