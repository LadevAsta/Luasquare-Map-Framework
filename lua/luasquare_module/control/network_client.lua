local CONTROL = LUASQUARE_CONTROL
CONTROL.Client = {controls = {}, history = {}}
local transfers = {}

local function receive(message, callback)
    net.Receive('LUASQUARE_CONTROL_' .. message, function()
        local serial, index, count, bytes = net.ReadUInt(32), net.ReadUInt(16), net.ReadUInt(16), net.ReadUInt(16)
        if count < 1 or count > math.ceil(CONTROL.MaxTransferBytes / CONTROL.ChunkBytes) or index < 1 or index > count or bytes > CONTROL.ChunkBytes then return end
        local key = message .. serial
        local bucket = transfers[key]
        if not bucket then
            local active = 0
            for _ in pairs(transfers) do active = active + 1 end
            if active >= 4 then return end
            bucket = {chunks = {}, count = count, size = 0, time = RealTime()}
            transfers[key] = bucket
        end
        if bucket.count ~= count or bucket.chunks[index] then return end
        bucket.chunks[index] = net.ReadData(bytes)
        bucket.size = bucket.size + bytes
        if bucket.size > CONTROL.MaxTransferBytes then transfers[key] = nil; return end
        for part = 1, count do if not bucket.chunks[part] then return end end
        transfers[key] = nil
        local json = util.Decompress(table.concat(bucket.chunks), CONTROL.MaxTransferBytes)
        local value = json and #json <= CONTROL.MaxTransferBytes and util.JSONToTable(json, false, true)
        if value then callback(value) end
    end)
end

receive('Catalog', function(value)
    CONTROL.Client.catalog = value
    hook.Run('LUASQUARE_CONTROL_ClientCatalog', value)
end)
receive('Source', function(value)
    local catalog = CONTROL.Client.catalog
    if catalog and value.revision == catalog.revision and catalog.sources[value.path] ~= nil then
        catalog.sources[value.path] = value.source
        hook.Run('LUASQUARE_CONTROL_ClientCatalog', catalog)
    end
end)
receive('State', function(value)
    if value.full then
        CONTROL.Client.controls = value.snapshot.controls
        CONTROL.Client.revision = value.snapshot.revision
    elseif value.revision == CONTROL.Client.revision then
        for id, state in pairs(value.controls or {}) do CONTROL.Client.controls[id] = state end
    else return end
    if value.history then CONTROL.Client.history = value.history end
    for _, entry in ipairs(value.historyAppend or {}) do table.insert(CONTROL.Client.history, entry) end
    while #CONTROL.Client.history > 500 do table.remove(CONTROL.Client.history, 1) end
    if value.diagnostic then
        print('[LUASQUARE_CONTROL EDITOR] ' .. value.diagnostic)
        if CONTROL.Editor and IsValid(CONTROL.Editor.Frame) then CONTROL.Editor.Frame:Report(value.diagnostic) end
    end
    hook.Run('LUASQUARE_CONTROL_ClientState')
end)
net.Receive('LUASQUARE_CONTROL_Reset', function()
    transfers = {}
    CONTROL.Client = {controls = {}, history = {}}
    if CONTROL.Editor and IsValid(CONTROL.Editor.Frame) then CONTROL.Editor.Frame:Close() end
end)
hook.Add('Think', 'LUASQUARE_CONTROL_TransferExpiry', function()
    for key, bucket in pairs(transfers) do if RealTime() - bucket.time > 10 then transfers[key] = nil end end
end)

function CONTROL.EditorCommand(command, id, operation, value)
    net.Start('LUASQUARE_CONTROL_Command')
    net.WriteString(command)
    if command ~= 'subscribe' and command ~= 'close' then net.WriteString(id or '') end
    if command == 'request' then
        net.WriteString(operation)
        net.WriteBool(value ~= nil)
        if value ~= nil then net.WriteDouble(value) end
    end
    net.SendToServer()
end
