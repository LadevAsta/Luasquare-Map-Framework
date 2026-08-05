-- Item receptacle
-- This module should contain reusable SENT receptacle.

-- How this should work :
-- 1. The receptacle is declared by bootstrap, placed at a position, probably will be pointed by info_target, copying both position and orientation.
-- 2. receptacle is passive receiver of compatible SENT (Will be RBMK Fuel rods and Darkfusion Fuel Cells). When this SENT got moved close enough to the receptacle it will tell the nearby receptacle to attach it.
-- Insertion Workflow
-- 1. receptacle 'attach' the SENT item by pulling SENT's by the SENT's origin(probably will also be prop's origin) to +X axis offseted point of receptacle.
-- 2. receptacle will then wait until it receives insert signal or can be configured to auto insert when an item is attached.
-- 3. prior to insertion, receptacle makes information about SENT available to outside system but allows no change. This is 'holding' state.
-- 4. receptacle when inserting, it will slowly move the offseted point(moving the attached item) closer to its own origin with ease-in ease-out or linear interpolation. This is the animation.
-- 5. when fully inserted, it make the content of the inserted item available to outside system to use.
-- Extraction Workflow
-- 1. receptacle when receiving extraction signal, it will lock down content of the SENT.
-- 2. receptacle slowly move away the item to original offseted point before detaching it automatically. This will give the SENT a 20 seconds cooldown before it could run checks to be attached to any receptacles again.

-- receptacle should also be able to :
-- 1. optionally detach item prior to insertion
-- 2. stream the item's data to assigned 3D2D display if there is one.