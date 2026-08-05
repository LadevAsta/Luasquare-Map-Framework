-- This module will wrap itemreceptacle.lua
-- Add some functions to itself.

-- Varient : Darkfusion Fuel Cell Receptacle (Corechamber, DEFER)
-- Accepts inactive and active darkfusion fuelcells.
-- Active darkfusion fuel workflow (Corechamber, One receptacle is linked to TWO catalyzers (12,34,56)):
-- 1. Bring in and insert active Darkfusion Fuel cell. (Enrichment > 50%)
-- 2. After fuel cell is inserted, an extra step is needed. Which is to switch on Fuel Excitation, enabling the catalyzers to use it and pause fuel's purity loss.
-- 2.1 if excitation is switched off at high enrichment (>=20%), trigger a small energy explosion, causing the fuel to instantly loose 99% of current enrichment, become impure and deal enough damage to anything standing nearby to leave them at 1 health, if they have less than 99 health, disslove them instantly.
-- 2.2 if fuel explosion happens during any point of Darkfusion stage, the lost 99% enrichment is absorbed by the reactor core at 10~20% efficiency. potentially causing a huge spike.
-- 2.3 if 3 fuel explosions with at least 35% enrichment happen during Meltdown stage 3 within 5 seconds of each other, Stall all reaction and save the citadel from final terminal disaster while killing everyone in the map but not the entire continent lore-wise, This is honorable shutdown ending.
-- 3. Excitation lever is locked outside of emergencies after initial excitation. If safety override A is enabled in control room, this is unlocked.
-- 4. When darkfusion fuelcell is depleted (Enrichment < 10%) unlock excitation lever.
-- 5. Operator comes and eject the fuel cell by disabling the excitation and extract the cell.
-- Inactive darkfusion fuel workflow (DEFER, One receptacle is linked to one Tower system)
-- 1. Bring in and insert inactive Darkfusion Fuel cell.

-- Varient : Fissile Booster Receptacle (DEFER)
-- Accepts RBMK Fuel Rods.
-- Can insert and extract freely but is locked if DEFER is working.
-- This is used to increase product darkfusion fuelcell's stats such as yield(or max enrichment%), reactivity, purity half-life.

-- Varient : Meta-Positive Stasis Cell Receptacle (Catalyzer Hulls)
-- Accepts Stasis Cells.
-- Can insert only, only open at Meltdown Stage 2.