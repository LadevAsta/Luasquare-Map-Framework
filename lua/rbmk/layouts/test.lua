-- TEST REACTOR
if RBMK.Initialized then return end
RBMK.Initialized = true

RBMK.CreateMatrix(15, 15)
RBMK.SetCell(5, 5, RBMK.CreateFuelChannel())
RBMK.SetCell(9, 9, RBMK.CreateFuelChannel())
RBMK.SetCell(9, 5, RBMK.CreateFuelChannel())
RBMK.SetCell(5, 9, RBMK.CreateFuelChannel())

RBMK.SetCell(1, 5, RBMK.CreateNeutronSource(20))