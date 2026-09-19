-- Runs real server engines against packed sources and read-only VMF entity data.
-- Source movement, rendering, networking transport and audio playback still need GMod.
SERVER, CLIENT, FCVAR_ARCHIVE = true, false, 0
unpack = table.unpack
function AddCSLuaFile() end
function Color(r, g, b, a) return {r = r, g = g, b = b, a = a or 255} end
function IsColor(value) return type(value) == 'table' and value.r ~= nil end
function isstring(value) return type(value) == 'string' end
function istable(value) return type(value) == 'table' end
function isnumber(value) return type(value) == 'number' end
function isfunction(value) return type(value) == 'function' end
function tobool(value) return value == true or value == 1 or value == '1' end
local vector = {}; vector.__index = vector
function Vector(x, y, z) return setmetatable({x = x or 0, y = y or 0, z = z or 0}, vector) end
vector.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
vector.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
vector.__mul = function(a, b) if type(a) == 'number' then a, b = b, a end; return Vector(a.x * b, a.y * b, a.z * b) end
function vector:LengthSqr() return self.x * self.x + self.y * self.y + self.z * self.z end
function vector:DistToSqr(other) return (self - other):LengthSqr() end
function vector:Dot(other) return self.x * other.x + self.y * other.y + self.z * other.z end
function isvector(value) return getmetatable(value) == vector end
local angle = {}; angle.__index = angle
function Angle(p, y, r) return setmetatable({p = p or 0, y = y or 0, r = r or 0}, angle) end
function angle:Forward() return Vector(1, 0, 0) end
function angle:Right() return Vector(0, 1, 0) end
function angle:Up() return Vector(0, 0, 1) end
function isangle(value) return getmetatable(value) == angle end
function CurTime() return 1 end
function RealTime() return 1 end
function SysTime() return 1 end
function Lerp(t, a, b) return a + (b - a) * t end
math.Clamp = function(value, low, high) return math.max(low, math.min(high, value)) end
math.Round = function(value, digits) local scale = 10 ^ (digits or 0); return math.floor(value * scale + 0.5) / scale end
math.Rand = function(low, high) return (low + high) / 2 end
table.Copy = function(value) if type(value) ~= 'table' then return value end; local result = {}; for key, child in pairs(value) do result[key] = table.Copy(child) end; return result end
table.Count = function(value) local count = 0; for _ in pairs(value) do count = count + 1 end; return count end
table.IsEmpty = function(value) return next(value) == nil end
string.Trim = function(value) return value:match('^%s*(.-)%s*$') end
string.StartWith = function(value, prefix) return value:sub(1, #prefix) == prefix end
string.EndsWith = function(value, suffix) return suffix == '' or value:sub(-#suffix) == suffix end
string.Explode = function(separator, value) local result = {}; local from = 1; while true do local at = value:find(separator, from, true); if not at then result[#result + 1] = value:sub(from); return result end; result[#result + 1] = value:sub(from, at - 1); from = at + #separator end end
local hooks, timers, commands, receivers = {}, {}, {}, {}
hook = {Add = function(event, id, callback) hooks[event] = hooks[event] or {}; hooks[event][id] = callback end,
    Remove = function(event, id) if hooks[event] then hooks[event][id] = nil end end,
    Run = function(event, ...) for _, callback in pairs(hooks[event] or {}) do callback(...) end end}
timer = {Create = function(id, delay, count, callback) timers[id] = {delay = delay, count = count, callback = callback} end,
    Exists = function(id) return timers[id] ~= nil end, Remove = function(id) timers[id] = nil end,
    GetTable = function() return timers end, Simple = function() end}
concommand = {Add = function(id, callback) commands[id] = callback end, Remove = function(id) commands[id] = nil end, GetTable = function() return commands end}
net = {Receive = function(name, callback) receivers[name] = callback end}
for _, method in ipairs({'Start', 'WriteUInt', 'WriteInt', 'WriteFloat', 'WriteDouble', 'WriteBool', 'WriteString', 'WriteData', 'WriteTable', 'WriteVector', 'WriteAngle', 'Send', 'Broadcast'}) do net[method] = function() end end
util = {AddNetworkString = function() end, JSONToTable = TEST_JSON_DECODE,
    TableToJSON = function(value) return LUASQUARE_MAP.CanonicalJSON(value) end, Compress = function(value) return value end,
    Decompress = function(value) return value end, CRC = function(value) return tostring(#value) end}
file = {Read = function(path) return TEST_FILES[path] end, Size = function(path) return TEST_FILES[path] and #TEST_FILES[path] or -1 end,
    Find = function() return {}, {} end, Exists = function() return true end, IsDir = function() return true end}
function GetConVar() return nil end
function CreateConVar(_, value) return {GetString = function() return value end, GetBool = function() return value == '1' end, GetFloat = function() return tonumber(value) or 0 end} end
function SetGlobal2Bool() end
function ErrorNoHalt(message) error(message) end
function MsgC() end
local entities = {}
function IsValid(value) return type(value) == 'table' and value.valid == true end
for index, properties in ipairs(TEST_ENTITIES) do
    local entity = {valid = true, properties = properties, index = index, skin = tonumber(properties.skin) or 0}
    function entity:GetClass() return self.properties.classname end
    function entity:GetName() return self.properties.targetname or '' end
    function entity:GetPos() return Vector(0, 0, 0) end
    function entity:GetAngles() return Angle(0, 0, 0) end
    function entity:GetInternalVariable(key) if key == 'm_toggle_state' then return 1 elseif key == 'm_bLocked' then return false end; return 0 end
    function entity:GetKeyValues() return self.properties end
    function entity:EntIndex() return self.index end
    function entity:IsPlayer() return false end
    function entity:Fire() end
    function entity:GetSkin() return self.skin end
    function entity:SetSkin(value) self.skin = value end
    function entity:StopSound() end
    function entity:EmitSound() end
    entities[#entities + 1] = entity
end
ents = {GetAll = function() return entities end,
    FindByName = function(name) local result = {}; for _, entity in ipairs(entities) do if entity:GetName() == name then result[#result + 1] = entity end end; return result end,
    FindByClass = function(class) local result = {}; for _, entity in ipairs(entities) do if entity:GetClass() == class then result[#result + 1] = entity end end; return result end}
player = {GetAll = function() return {} end, GetHumans = function() return {} end}
game = {GetMap = function() return 'experiment_rbmk' end, SinglePlayer = function() return true end, GetWorld = function() return {} end}
engine = {TickCount = function() return 1 end}
function include(path) return dofile('lua/' .. path) end
include('luasquare_module/map/engine.lua')
local instance, err = LUASQUARE_MAP.Load('experiment_rbmk/main.json')
assert(instance, err)
assert(instance.running and LUASQUARE_CONTROL.Running and LUASQUARE_ANNUNCIATOR.RuntimeStarted and LUASQUARE_3D2D.RuntimeStarted)
assert(LUASQUARE_CONTROL.GetControl('fwlevelctrl').acceptedValue == 80)
assert(LUASQUARE_PUMP.GetPump('reference.feedwater_pump_a').regulationTarget == 80)
assert(LUASQUARE_PUMP.GetPump('reference.feedwater_pump_b').regulationTarget == 80)
assert(not LUASQUARE_3D2D.DataProviders['rbmk.rpv'] and not LUASQUARE_CONTROL.Actions['rbmk.scram'])
assert(LUASQUARE_3D2D.TickInterval == 0.2 and LUASQUARE_ANNUNCIATOR.TickInterval == 0.5, 'reference cadence preserved')
assert(not LUASQUARE_MAP.Types['telemetry.panel'] and not instance.nodes['reference.panel.feedwater']
    and not instance.nodes['reference.panel.cooling'] and not instance.nodes['reference.panel.electrical'],
    'obsolete presentation placeholders must not be constructed')
for _, id in ipairs({'fw_flow_panel', 'condensate_pump_status_panel', 'electrical_status_panel'}) do
    assert(LUASQUARE_3D2D.Displays[id] and LUASQUARE_3D2D.Displays[id].definition.buildMode == 'complex',
        id .. ' must use the complex dashboard layout')
end
local columnsDisplay = LUASQUARE_3D2D.CompileSource({schema = LUASQUARE_3D2D.Schema, id = 'obsolete_columns', buildMode = 'simple',
    target = 'fixture', unitWidth = 10, unitHeight = 10, scale = 0.1, lines = {{type = 'columns', columns = {}}}}, 'simple columns regression')
assert(not columnsDisplay, 'simple-build columns must be rejected')
local hotwell = instance:Get('reference.hotwell')
local hotwellBefore = hotwell.amount
LUASQUARE_VALVE.SetValve('reference.hotwell_drain_valve', true)
LUASQUARE_VALVE.UpdateValve('reference.hotwell_drain_valve', 0.1)
assert(hotwell.amount < hotwellBefore and LUASQUARE_VALVE.GetValve('reference.hotwell_drain_valve').lastFlow > 0,
    'hotwell drain transfers to its declared zero-pressure drain')
LUASQUARE_VALVE.SetValve('reference.hotwell_drain_valve', false)
LUASQUARE_POWERPLANT.Debug.BuildNetworks(); LUASQUARE_POWERPLANT.Debug.BuildPumps(); LUASQUARE_POWERPLANT.Debug.BuildValves(); LUASQUARE_POWERPLANT.Debug.BuildCondensers()
LUASQUARE_POWERPLANT.Debug.BuildHeatExchangers(); LUASQUARE_POWERPLANT.Debug.BuildDeaerators(); LUASQUARE_POWERPLANT.Debug.BuildTurbines(); LUASQUARE_POWERPLANT.Debug.BuildCoolingTowers()
for _, category in ipairs({'Pumps', 'Valves', 'Condensers', 'HeatExchangers', 'Deaerators', 'Turbines', 'CoolingTowers'}) do for _, item in ipairs(LUASQUARE_POWERPLANT.Debug.ClientState[category]) do
    for _, field in ipairs({'source', 'target', 'a', 'b', 'input', 'output', 'coolantNetwork', 'coolantPump', 'hotNetwork', 'coldNetwork',
        'hotPump', 'coldPump', 'tankNetwork', 'steamInput', 'steamSource', 'overflowTarget', 'boiler', 'condenser', 'bypassCondenser',
        'condenserOutput', 'bypassCondenserOutput', 'basin'}) do
        assert(type(item[field]) ~= 'table', category .. '.' .. field .. ' leaked an endpoint table to the debug wire')
        if item[field] ~= nil then
            assert(type(item[field]) == 'string' and item[field]:find('/', 1, true),
                category .. '.' .. field .. ' is not a readable component/port label')
        end
    end
end end
for _, network in ipairs(LUASQUARE_POWERPLANT.Debug.ClientState.Networks) do
    if network.overflowTarget ~= nil then
        assert(type(network.overflowTarget) == 'string' and network.overflowTarget:find('/', 1, true),
            'network overflow target is not a readable component/port label')
    end
end
local generator = LUASQUARE_POWERGENERATOR.GetGenerator('reference.tg1_generator')
local turbine = LUASQUARE_TURBINE.GetTurbine('reference.tg1')
local breaker = LUASQUARE_POWERGRID.GetBreaker(generator.breaker)
generator.tripped, generator.enabled, generator.synced = false, true, true
turbine.tripped, turbine.enabled, turbine.synced = false, true, true
breaker.closed = true
assert(LUASQUARE_POWERGENERATOR.Sync(generator.name) and not generator.synced and not turbine.synced and not breaker.closed,
    'sync command opens the breaker when an already synchronized generator is selected')
generator.tripped, generator.enabled, generator.synced = false, true, false
turbine.tripped, turbine.enabled, turbine.synced, turbine.rpm, turbine.phase = false, true, false, 0, 90
assert(LUASQUARE_POWERGENERATOR.Sync(generator.name) and generator.tripped and turbine.tripped and not breaker.closed,
    'mismatched synchronization is consumed by the generator while retaining configured trips')
local tripReason = generator.tripReason
assert(LUASQUARE_POWERGENERATOR.Sync(generator.name) and generator.tripReason == tripReason,
    'sync command has no additional reaction while the generator is tripped')
assert(LUASQUARE_POWERGENERATOR.ResetTrip(generator.name))
local catalog = LUASQUARE_MAP.InspectionCatalog()
local catalogBytes = assert(LUASQUARE_MAP.CanonicalJSON(catalog))
assert(#catalogBytes < 8 * 1024 * 1024 and LUASQUARE_MAP.DecodeJSON(catalogBytes, 8 * 1024 * 1024))
assert(#catalog.active.experiment_rbmk.nodes.reference.telemetry > 0)
-- Exercise the actual bounded inspection protocol with an untrusted sender.
local clock, input, packets, packet = 10, {}, {}, nil
CurTime = function() return clock end
net.ReadUInt = function() return table.remove(input, 1) end
net.ReadString = function() return table.remove(input, 1) end
net.Start = function(name) packet = {name = name, numbers = {}} end
net.WriteUInt = function(value) packet.numbers[#packet.numbers + 1] = value end
net.WriteData = function(value, bytes) assert(#value == bytes and bytes <= 24000); packet.data = value end
net.Send = function() packets[#packets + 1] = packet end
local admin = {valid = true, IsAdmin = function() return true end}
local guest = {valid = true, IsAdmin = function() return false end}
game.SinglePlayer = function() return false end
local function request(sender, values, bits)
    clock = clock + 1; input = values; receivers.LUASQUARE_MAP_Request(bits or 128, sender)
end
local function drain()
    for _ = 1, 350 do hooks.Think.LUASQUARE_MAP_Inspection() end
end
request(guest, {1}); drain(); assert(#packets == 0, 'catalog authorization')
request(admin, {1}, 35001); drain(); assert(#packets == 0, 'request bit limit')
request(admin, {1}); drain(); assert(#packets > 1, 'catalog uses bounded chunks')
local chunks = {}; for _, part in ipairs(packets) do chunks[part.numbers[3]] = part.data end
local transferredCatalog = assert(LUASQUARE_MAP.DecodeJSON(table.concat(chunks), 8 * 1024 * 1024))
assert(LUASQUARE_MAP.IsArray(transferredCatalog.types['rbmk.core'].fields.fuelPresets.default)
    and LUASQUARE_MAP.IsArray(transferredCatalog.types['source.binding'].fields.tags.default),
    'catalog round trip preserves empty array defaults')
assert(not LUASQUARE_MAP.IsArray(transferredCatalog.types['rbmk.core'].fields.settings.default),
    'catalog round trip preserves empty object defaults')
packets = {}; request(admin, {3, 1, 'reference'}); drain()
assert(#packets == 1 and packets[1].numbers[1] == 3, 'late subscription gets initial state')
local state = assert(LUASQUARE_MAP.DecodeJSON(packets[1].data)).state
assert(state.reference and not state['reference.main_steam'], 'only subscribed components transmitted')
packets = {}; clock = clock + 1; drain(); assert(#packets == 0, 'unchanged state is not retransmitted')
instance:Get('reference').Water = instance:Get('reference').Water + 1
clock = clock + 1; drain(); assert(#packets == 1, 'changed telemetry sends one delta')
packets = {}; request(admin, {0}); clock = clock + 1; drain(); assert(#packets == 0, 'close removes subscription')
local function transferredSource(path)
    packets = {}; request(admin, {2, 'components', path}); drain()
    local chunks = {}; for _, part in ipairs(packets) do chunks[part.numbers[3]] = part.data end
    local transferText = table.concat(chunks)
    assert(transferText:sub(1, 1) == '{', 'source transfer did not begin with a JSON object: ' .. transferText:sub(1, 16))
    local envelope = assert(LUASQUARE_MAP.DecodeJSON(transferText, 8 * 1024 * 1024, LUASQUARE_MAP.Limits.bytes))
    assert(type(envelope.sourceText) == 'string' and envelope.source == nil, 'source transfer uses an independent canonical document')
    return assert(LUASQUARE_MAP.DecodeJSON(envelope.sourceText, LUASQUARE_MAP.Limits.bytes))
end
local transferredCore = transferredSource('experiment_rbmk/core.json')
assert(transferredCore.components[1].config.fuelPresets == nil, 'omitted fuel presets stay omitted in canonical source text')
local transferredBindings = transferredSource('experiment_rbmk/bindings.json')
assert(transferredBindings.components[1].config.tags == nil, 'omitted binding tags stay omitted in canonical source text')
packets = {}
request(admin, {2, 'map', '../escape.json'}); drain(); assert(#packets == 0, 'traversal source request rejected')
game.SinglePlayer = function() return true end
net.Start, net.WriteUInt, net.Send = function() end, function() end, function() end
assert(LUASQUARE_MAP.Destroy(instance))
assert(not next(LUASQUARE_MAP.Instances) and not next(LUASQUARE_RBMK.Instances) and not next(LUASQUARE_ENDPOINT.Ports))
assert(not LUASQUARE_CONTROL.Running and not LUASQUARE_ANNUNCIATOR.RuntimeStarted and not LUASQUARE_3D2D.RuntimeStarted)
local corePath = 'data_static/luasquare/components/experiment_rbmk/core.json'
local saved = TEST_FILES[corePath]
local replacements
TEST_FILES[corePath], replacements = saved:gsub('"fuel"%s*:%s*"[^"]+"', '"fuel":"UNKNOWN_FUEL"', 1)
assert(replacements == 1)
local failed, diagnostic = LUASQUARE_MAP.Load('experiment_rbmk/main.json')
assert(not failed and diagnostic:find('unknown fuel preset', 1, true))
assert(not next(LUASQUARE_MAP.Instances) and not next(LUASQUARE_RBMK.Instances))
TEST_FILES[corePath] = saved
local controlPath = 'data_static/luasquare/control/experiment_rbmk/operator_controls.json'
local savedControls = TEST_FILES[controlPath]
TEST_FILES[controlPath], replacements = savedControls:gsub('reference%.scram', 'reference.missing_action', 1)
assert(replacements == 1)
local sourceFailure, sourceDiagnostic = LUASQUARE_MAP.Load('experiment_rbmk/main.json')
assert(not sourceFailure and sourceDiagnostic, 'invalid selected source fails after component construction')
assert(not next(LUASQUARE_MAP.Instances) and not next(LUASQUARE_RBMK.Instances) and not next(LUASQUARE_ENDPOINT.Ports), 'source failure unwinds constructed owners')
assert(not LUASQUARE_CONTROL.Actions['reference.scram'] and not LUASQUARE_CONTROL.Running, 'source failure unwinds registered actions and controls')
TEST_FILES[controlPath] = savedControls
local timelinePath = 'data_static/luasquare/timeline/_fixtures/isolation_scram.json'
TEST_FILES[timelinePath] = LUASQUARE_MAP.CanonicalJSON({schema = 'luasquare.timeline/v1', id = 'isolation_scram', duration = 0.1,
    tracks = {{id = 'scram', target = {kind = 'child', id = 'alpha'}, clips = {{id = 'press', kind = 'marker', at = 0, action = 'press'}}}}})
local fixtureManifestPath = 'data_static/luasquare/map/_fixtures/two_core.json'
local fixturePackPath = 'data_static/luasquare/components/_fixtures/two_core.json'
local fixtureManifest = assert(LUASQUARE_MAP.DecodeJSON(TEST_FILES[fixtureManifestPath]))
local fixturePack = assert(LUASQUARE_MAP.DecodeJSON(TEST_FILES[fixturePackPath]))
fixtureManifest.sources.timeline = {'_fixtures/isolation_scram.json'}
fixturePack.components[#fixturePack.components + 1] = {id = 'fixture.procedure', type = 'timeline.owner', config = {
    targets = {{alias = 'alpha', component = 'control.fixture.alpha.scram'}}, timelines = {{slot = 'scram', source = '_fixtures/isolation_scram.json'}}}}
TEST_FILES[fixtureManifestPath], TEST_FILES[fixturePackPath] = LUASQUARE_MAP.CanonicalJSON(fixtureManifest), LUASQUARE_MAP.CanonicalJSON(fixturePack)
local fixture, problem = LUASQUARE_MAP.Load('_fixtures/two_core.json')
assert(fixture, problem)
assert(LUASQUARE_TIMELINE.Bindings['fixture.procedure'].scram)
local alpha, beta = fixture:Get('fixture.alpha'), fixture:Get('fixture.beta')
local water = beta.Water
alpha.Destroy()
assert(not LUASQUARE_CONTROL.Actions['fixture.alpha.scram'].callback())
assert(fixture.telemetry['fixture.alpha']().available == false and beta.Water == water and not beta.Destroyed)
assert(LUASQUARE_MAP.Destroy(fixture))
print('Validated complete reference manifest loading, actual JSON engines, VMF bindings, control initialization and shutdown.')
