local MAP = LUASQUARE_MAP
MAP.Client = {state = {}, catalog = nil}
local transfer, nextHeartbeat = nil, 0
local requests, nextRequest = {}, 0
local function sendRequest(operation, family, path)
    net.Start('LUASQUARE_MAP_Request'); net.WriteUInt(operation, 3)
    if operation == 2 then net.WriteString(family); net.WriteString(path)
    elseif operation == 3 then
        local ids = family or {}
        net.WriteUInt(math.min(#ids, 32), 6)
        for index = 1, math.min(#ids, 32) do net.WriteString(ids[index]) end
    end
    net.SendToServer()
end
function MAP.InspectionRequest(operation, family, path)
    if operation == 0 then requests = {}; sendRequest(0); return end
    -- Keep the newest selection/heartbeat and serialize requests above the
    -- server cooldown so opening a window cannot discard its first selection.
    if operation == 3 or operation == 4 then
        for index = #requests, 1, -1 do if requests[index].operation == operation then table.remove(requests, index) end end
    end
    if #requests >= 64 then return false end
    requests[#requests + 1] = {operation = operation, family = MAP.Copy(family), path = path}
    return true
end
net.Receive('LUASQUARE_MAP_Transfer', function()
    if not MAP.Editor or not IsValid(MAP.Editor.Frame) then return end
    local kind, serial, index, count, bytes = net.ReadUInt(2), net.ReadUInt(32), net.ReadUInt(10), net.ReadUInt(10), net.ReadUInt(15)
    if count < 1 or count > 350 or index < 1 or index > count or bytes > 24000 then return end
    if not transfer or transfer.serial ~= serial then
        if index ~= 1 then return end
        transfer = {serial = serial, kind = kind, count = count, chunks = {}, bytes = 0, expires = RealTime() + 30}
    end
    if transfer.kind ~= kind or transfer.count ~= count or transfer.chunks[index] then return end
    transfer.chunks[index] = net.ReadData(bytes); transfer.bytes = transfer.bytes + bytes
    if transfer.bytes > 8 * 1024 * 1024 then transfer = nil; return end
    for part = 1, count do if not transfer.chunks[part] then return end end
    local text = table.concat(transfer.chunks); transfer = nil
    -- Trusted server data is still bounded before parsing; source grammar is
    -- validated separately when a document is loaded into the editor.
    local value, err = MAP.DecodeJSON(text, 8 * 1024 * 1024, kind == 2 and MAP.Limits.bytes or nil)
    if type(value) ~= 'table' then
        print('[LUASQUARE MAP] Inspection transfer rejected: ' .. tostring(err or 'invalid payload'))
        hook.Run('LUASQUARE_MAP_TransferError', err or 'invalid payload')
        return
    end
    if kind == 1 then
        MAP.Client.catalog = value
        MAP.Types, MAP.Packages, MAP.StartupNamespaces = value.types, value.packages, value.startupNamespaces or {}
        hook.Run('LUASQUARE_MAP_Catalog', value)
    elseif kind == 2 then hook.Run('LUASQUARE_MAP_Source', value)
    elseif kind == 3 and MAP.Client.catalog and value.revision == MAP.Client.catalog.revision then
        for id, state in pairs(value.state or {}) do MAP.Client.state[id] = state end
        hook.Run('LUASQUARE_MAP_State')
    end
end)
net.Receive('LUASQUARE_MAP_Reset', function()
    transfer, requests = nil, {}
    MAP.Client = {state = {}}
    if MAP.Editor and IsValid(MAP.Editor.Frame) then MAP.Editor.Frame.CloseApproved = true; MAP.Editor.Frame:Close() end
end)
hook.Add('Think', 'LUASQUARE_MAP_InspectionClient', function()
    if #requests > 0 and RealTime() >= nextRequest then
        local request = table.remove(requests, 1)
        nextRequest = RealTime() + 0.2
        sendRequest(request.operation, request.family, request.path)
    end
    if transfer and RealTime() > transfer.expires then transfer = nil end
    if MAP.Editor and IsValid(MAP.Editor.Frame) and RealTime() >= nextHeartbeat then
        nextHeartbeat = RealTime() + 10; MAP.InspectionRequest(4)
    end
end)
function MAP.CloseInspection()
    transfer = nil; MAP.Client.state = {}
    MAP.InspectionRequest(0)
end
