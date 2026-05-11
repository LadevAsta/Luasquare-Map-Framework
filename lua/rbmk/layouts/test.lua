if RBMK.Initialized then return end
RBMK.Initialized = true

-- LAYOUT FILE
-- This is orchestration file to build an RBMK reactor.

-- TEST REACTOR

-- Define size (Rectangle)
RBMK.CreateMatrix(13, 13)

--RBMK.SetCell(X-vertical, Y-horizontal, CONSTRUCTOR-FUNCTION)
-- X is red arrow and Y is green arrow in Hammer.

-- Fuel channels (Fuel Type:fueltype[Default:'MEU'])
RBMK.SetCell(5, 5, RBMK.CreateFuelChannel())
RBMK.SetCell(9, 9, RBMK.CreateFuelChannel('HEU'))
RBMK.SetCell(9, 5, RBMK.CreateFuelChannel('MOX'))
RBMK.SetCell(5, 9, RBMK.CreateFuelChannel())
RBMK.SetCell(5, 11, RBMK.CreateFuelChannel('EMPTY'))

-- Neutron Sources (constantFlux:float)
RBMK.SetCell(1, 5, RBMK.CreateNeutronSource(20))

-- Control rods (startingInsertion:float[1.0], Name:string, Group:string)
RBMK.SetCell(2, 5, RBMK.CreateControlRod(1.0, 'NS', 'white'))
RBMK.SetCell(5, 6, RBMK.CreateControlRod(1.0, 'U1', 'red'))
RBMK.SetCell(6, 5, RBMK.CreateControlRod(1.0, 'U2', 'red'))
RBMK.SetCell(9, 8, RBMK.CreateControlRod(1.0, 'U3', 'red'))
RBMK.SetCell(8, 9, RBMK.CreateControlRod(1.0, 'U4', 'red'))