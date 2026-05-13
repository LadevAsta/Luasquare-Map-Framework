RBMK = RBMK or {}
RBMK.Debug = RBMK.Debug or {}
RBMK.Rods = RBMK.Rods or {}

RBMK.CELL_FUEL = 1
RBMK.CELL_STEAM = 2
RBMK.CELL_CONTROL = 3
RBMK.CELL_REFLECTOR = 4
RBMK.CELL_BLANK = 5
RBMK.CELL_AUTOROD = 6
RBMK.CELL_SOURCE = 7
RBMK.CELL_ABSORBER = 8
RBMK.CELL_VOID = 9

RBMK.CellSymbols = {

    [RBMK.CELL_BLANK] = 'B',
    [RBMK.CELL_FUEL] = 'F',
    [RBMK.CELL_STEAM] = 'S',
    [RBMK.CELL_CONTROL] = 'C',
    [RBMK.CELL_REFLECTOR] = 'RF',
    [RBMK.CELL_AUTOROD] = 'CA',
    [RBMK.CELL_SOURCE] = 'NS',
    [RBMK.CELL_ABSORBER] = 'AB',
    [RBMK.CELL_VOID] = 'X'

}


RBMK.WorldOrigin = Vector(0, 0, 0)
RBMK.CellSpacing = 64

RBMK.TickInterval = 0.1

RBMK.FluxRange = 12
RBMK.TotalFluxSubtractDefine = 0

RBMK.ControlrodScramBoost = 2
RBMK.RodMoveDistance = 64