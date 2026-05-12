if RBMK.Initialized then return end
RBMK.Initialized = true

-- LAYOUT FILE
-- This is orchestration script to build an RBMK reactor.

-- TEST REACTOR
RBMK.ModelName = 'LRBMK-400'

-- Define size (Rectangle)
RBMK.CreateMatrix(13, 13)

--RBMK.SetCell(X-vertical, Y-horizontal, CONSTRUCTOR-FUNCTION)
-- X is red arrow and Y is green arrow in Hammer.

-- Fuel channels (Fuel Type:fueltype[Default:'MEU'])
RBMK.SetCell(5, 5, RBMK.CreateFuelChannel('HEU'))
RBMK.SetCell(9, 9, RBMK.CreateFuelChannel())
RBMK.SetCell(9, 5, RBMK.CreateFuelChannel('MOX'))
RBMK.SetCell(5, 9, RBMK.CreateFuelChannel())
RBMK.SetCell(5, 11, RBMK.CreateFuelChannel('EMPTY')) --Empty fuel rod acts like blank

-- Neutron Sources (constantFlux:float)
RBMK.SetCell(1, 5, RBMK.CreateNeutronSource(26))

-- Control rods (Name:string, Group:string, visualEnt:func_movelinear targetname string[nil], graphiteTip:bool[true], reflectorCore:bool[false], startingInsertion:float[1.0])
RBMK.SetCell(3, 5, RBMK.CreateControlRod('NS', 'white', 'ctlRod_lid_NS'))
RBMK.SetCell(5, 7, RBMK.CreateControlRod('U1', 'red', 'ctlRod_lid_U1'))
RBMK.SetCell(7, 5, RBMK.CreateControlRod('U2', 'red', 'ctlRod_lid_U2'))
RBMK.SetCell(9, 7, RBMK.CreateControlRod('U3', 'red', 'ctlRod_lid_U3'))
RBMK.SetCell(7, 9, RBMK.CreateControlRod('U4', 'red', 'ctlRod_lid_U4'))

RBMK.SetCell(4, 5, RBMK.CreateControlRod('R1', 'yellow', 'ctlRod_lid_R1'))
RBMK.SetCell(5, 4, RBMK.CreateControlRod('R2', 'yellow', 'ctlRod_lid_R2'))
RBMK.SetCell(10, 5, RBMK.CreateControlRod('R3', 'yellow', 'ctlRod_lid_R3'))
RBMK.SetCell(9, 4, RBMK.CreateControlRod('R4', 'yellow', 'ctlRod_lid_R4'))
RBMK.SetCell(9, 10, RBMK.CreateControlRod('R5', 'yellow', 'ctlRod_lid_R5'))
RBMK.SetCell(10, 9, RBMK.CreateControlRod('R6', 'yellow', 'ctlRod_lid_R6'))
RBMK.SetCell(5, 10, RBMK.CreateControlRod('R7', 'yellow', 'ctlRod_lid_R7'))
RBMK.SetCell(4, 9, RBMK.CreateControlRod('R8', 'yellow', 'ctlRod_lid_R8'))


-- Reflectors (isIn:bool[true])
RBMK.SetCell(2, 5, RBMK.CreateReflector(false))
RBMK.SetCell(2, 9, RBMK.CreateReflector())
RBMK.SetCell(5, 12, RBMK.CreateReflector())
RBMK.SetCell(5, 2, RBMK.CreateReflector())
RBMK.SetCell(9, 2, RBMK.CreateReflector())
RBMK.SetCell(12, 5, RBMK.CreateReflector())
RBMK.SetCell(12, 9, RBMK.CreateReflector())
RBMK.SetCell(9, 12, RBMK.CreateReflector())

-- Steam Channels 
RBMK.SetCell(7, 7, RBMK.CreateSteamChannel())
RBMK.SetCell(6, 9, RBMK.CreateSteamChannel())
RBMK.SetCell(5, 8, RBMK.CreateSteamChannel())
RBMK.SetCell(6, 5, RBMK.CreateSteamChannel())
RBMK.SetCell(5, 6, RBMK.CreateSteamChannel())
RBMK.SetCell(8, 9, RBMK.CreateSteamChannel())
RBMK.SetCell(9, 8, RBMK.CreateSteamChannel())
RBMK.SetCell(9, 6, RBMK.CreateSteamChannel())
RBMK.SetCell(8, 5, RBMK.CreateSteamChannel())

-- Always RecalculatePools after adding steam channels
RBMK.RecalculatePools()

-- Voids
RBMK.SetCell(1, 1, RBMK.CreateVoid())
RBMK.SetCell(1, 2, RBMK.CreateVoid())
RBMK.SetCell(2, 1, RBMK.CreateVoid())
RBMK.SetCell(1, 12, RBMK.CreateVoid())
RBMK.SetCell(1, 13, RBMK.CreateVoid())
RBMK.SetCell(2, 13, RBMK.CreateVoid())
RBMK.SetCell(12, 13, RBMK.CreateVoid())
RBMK.SetCell(13, 13, RBMK.CreateVoid())
RBMK.SetCell(13, 12, RBMK.CreateVoid())
RBMK.SetCell(12, 1, RBMK.CreateVoid())
RBMK.SetCell(13, 1, RBMK.CreateVoid())
RBMK.SetCell(13, 2, RBMK.CreateVoid())