local timers = {}
timer = {Create = function(name, delay, count, callback) timers[name] = callback end,
    Remove = function(name) timers[name] = nil end, Exists = function(name) return timers[name] ~= nil end}
util = {AddNetworkString = function() end}
SERVER = false
function include(path) return dofile('lua/' .. path) end
function Vector(x, y, z) return {x = x, y = y, z = z} end
function IsValid() return false end
function CurTime() return 1 end
function Lerp(t, a, b) return a + t * (b - a) end
math.Clamp = function(value, low, high) return math.max(low, math.min(high, value)) end
math.Rand = function(low, high) return high end
ents = {FindByName = function() return {} end}
player = {GetAll = function() return {} end}
game = {SinglePlayer = function() return true end}
include('luasquare_rbmk/init.lua')
local a = assert(LUASQUARE_RBMK.Create('core_a'))
local b = assert(LUASQUARE_RBMK.Create('core_b'))
assert(not LUASQUARE_RBMK.Create('core_a'))
for _, core in ipairs({a, b}) do
    core.CreateMatrix(3, 3)
    core.SetCell(2, 2, core.CreateSteamChannel())
    core.SetCell(1, 1, core.CreateControlRod('rod', 'group', nil, nil, false, false, 0))
    core.RecalculatePools()
    core.AddInitialWater(50)
end
assert(not a.Rods.rod.graphiteTip and a.Rods.rod ~= b.Rods.rod)
assert(a.Matrix ~= b.Matrix and a.EventState ~= b.EventState and a.Debug.ClientState ~= b.Debug.ClientState)
assert(a.FuelTypes ~= b.FuelTypes and a.FuelTypes.MEU ~= b.FuelTypes.MEU)
a.SetAutoRegulatorTargetMW(50)
a.Selector.Toggle('rod')
a.Selector.Apply(20)
assert(b.AutoRegulatorTargetMW == 0 and b.Rods.rod.targetInsertion == 0 and b.Selector.GetSelectionCount() == 0)
local waterB = b.Water
assert(a.AddWaterFromPump(10, 100, 30) == 10)
assert(b.Water == waterB)
a.SCRAM()
assert(a.Rods.rod.targetInsertion == 1 and b.Rods.rod.targetInsertion == 0)
a.Start(); b.Start()
assert(timers[a.TimerName('tick')] and timers[b.TimerName('tick')])
a.FuelMeltdown(2, 2)
b.FuelMeltdown(2, 2)
assert(timers[a.TimerName('meltdown.2.2')] and timers[b.TimerName('meltdown.2.2')])
a.Destroy()
assert(not LUASQUARE_RBMK.Get('core_a') and LUASQUARE_RBMK.Get('core_b') == b)
assert(timers[b.TimerName('tick')] and timers[b.TimerName('meltdown.2.2')])
assert(not a.Start() and not b.EventState.Failed)
timers[b.TimerName('meltdown.2.2')]()
assert(b.EventState.Failed and not timers[b.TimerName('tick')])
b.Destroy()
assert(next(timers) == nil)
print('Validated independent core state, fuel presets, selection, controls, inventories, timers and destruction.')
include('luasquare_powerplant/endpoints.lua')
local c = assert(LUASQUARE_RBMK.Create('core_c'))
local d = assert(LUASQUARE_RBMK.Create('core_d'))
for _, core in ipairs({c, d}) do
    core.CreateMatrix(3, 3); core.SetCell(2, 2, core.CreateSteamChannel()); core.RecalculatePools(); core.AddInitialWater(50)
end
include('luasquare_powerplant/fluidvalve.lua')
local waterTotal = c.Water + d.Water
local moved = LUASQUARE_VALVE.Transfer({component = 'core_c', port = 'water'}, {component = 'core_d', port = 'water'}, 10, 100)
assert(moved == 10 and c.Water + d.Water == waterTotal)
d.FeedwaterInletOpen = false
local beforeC, beforeD = c.Water, d.Water
assert(LUASQUARE_VALVE.Transfer({component = 'core_c', port = 'water'}, {component = 'core_d', port = 'water'}, 10, 100) == 0)
assert(c.Water == beforeC and d.Water == beforeD, 'rejected transfer restored to owning core')
c.Destroy(); d.Destroy()
assert(next(LUASQUARE_ENDPOINT.Ports) == nil)
print('Validated explicit cross-core transfer, accepted accounting, rollback and endpoint release.')
