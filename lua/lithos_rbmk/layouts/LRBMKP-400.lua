if RBMK.Initialized then return end
RBMK.Initialized = true

-- LAYOUT FILE
-- This is orchestration script to build an RBMK reactor.

-- TEST REACTOR
RBMK.ModelName = 'LRBMKP-400'

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

-- Neutron Sources (constantFlux:float, closedSource(become reflector):bool[false])
RBMK.SetCell(3, 5, RBMK.CreateNeutronSource(26, true))

-- Control rods (Name:string, Group:string, indicatorSprite:env_sprite targetname string[nil], visualEnt:func_movelinear targetname string[nil], graphiteTip:bool[true], reflectorCore:bool[false], startingInsertion:float[1.0])
RBMK.SetCell(5, 7, RBMK.CreateControlRod('U1', 'red', 'sel_U1', 'ctlRod_lid_U1'))
RBMK.SetCell(7, 5, RBMK.CreateControlRod('U2', 'red', 'sel_U2', 'ctlRod_lid_U2'))
RBMK.SetCell(9, 7, RBMK.CreateControlRod('U3', 'red', 'sel_U3', 'ctlRod_lid_U3'))
RBMK.SetCell(7, 9, RBMK.CreateControlRod('U4', 'red', 'sel_U4', 'ctlRod_lid_U4'))

RBMK.SetCell(4, 5, RBMK.CreateControlRod('R1', 'yellow', 'sel_R1', 'ctlRod_lid_R1'))
RBMK.SetCell(5, 4, RBMK.CreateControlRod('R2', 'yellow', 'sel_R2', 'ctlRod_lid_R2'))
RBMK.SetCell(10, 5, RBMK.CreateControlRod('R3', 'yellow', 'sel_R3', 'ctlRod_lid_R3'))
RBMK.SetCell(9, 4, RBMK.CreateControlRod('R4', 'yellow', 'sel_R4', 'ctlRod_lid_R4'))
RBMK.SetCell(9, 10, RBMK.CreateControlRod('R5', 'yellow', 'sel_R5', 'ctlRod_lid_R5'))
RBMK.SetCell(10, 9, RBMK.CreateControlRod('R6', 'yellow', 'sel_R6', 'ctlRod_lid_R6'))
RBMK.SetCell(5, 10, RBMK.CreateControlRod('R7', 'yellow', 'sel_R7', 'ctlRod_lid_R7'))
RBMK.SetCell(4, 9, RBMK.CreateControlRod('R8', 'yellow', 'sel_R8', 'ctlRod_lid_R8'))

-- Reflectors (isIn:bool[true])
RBMK.SetCell(2, 9, RBMK.CreateReflector())
RBMK.SetCell(5, 12, RBMK.CreateReflector())
RBMK.SetCell(5, 2, RBMK.CreateReflector(true))
RBMK.SetCell(9, 2, RBMK.CreateReflector())
RBMK.SetCell(12, 5, RBMK.CreateReflector())
RBMK.SetCell(12, 9, RBMK.CreateReflector())
RBMK.SetCell(9, 12, RBMK.CreateReflector())

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

-- Steam autofill
RBMK.FillBlanksWithSteam({
    ignoreEdge = true,
    ignoreNearVoid = true
})