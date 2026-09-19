if SERVER then
    AddCSLuaFile()
    AddCSLuaFile('luasquare_rbmk/schema.lua')
end
include('luasquare_module/map/engine.lua')
include('luasquare_rbmk/schema.lua')
