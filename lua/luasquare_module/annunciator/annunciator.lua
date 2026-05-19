-- Annunciator system is a module for alarms and keeping track of what is registered and throw warnings.

-- It comprises of 3 different

-- Core, the place where registry and status is. It controls display.
-- It will read values, and act accordingly by itself.

-- Prop_dynamic Display, A type of display, It will utilizes skin-based model to change skin of defined prop_dynamic in the map similar to how seg7display works.
-- And play looping alarm sounds Either from the prop position (if possible) or with existing ambient_generic.
-- Those prop dynamics will have 4 skins. Off, fast flash, On, slow flash. (Can I have just 1 animated VTF and have 4 VMTs per model?)
-- This may be easier to set up in map script but more troublesome to make models for it.

-- 3D2D display panels, A type of display, function similarly to prop_dynamic display but uses 3d2d panels for visual instead.
-- It can many display indicators in one (eg. 4x3 panel) on one 3D2D panel, rendering (or clocks for flashing) happens clientside.
-- It will NOT going to use 3d2display.lua module! It will have it's own 3d2d handler module.
-- This has no need to setting up map entities or making models but will need to be networked to client.

-- Have 3 input from operator. ACKnowledge, MUTE and RESET.
-- When start, start off with OFF skin
-- When a problem arises, change the offender to fast flash.
-- When ACK is pressed, unresolved problem get to ON skin
-- When problem is resolved, play audio cue and get to slow flash whenther or not it is ACKnowledged.
-- When RESET is pressed, problem with slow flash change to OFF skin.
-- MUTE simply stop all the current alarm sounds. But 5 minutes after that, play audio cue then turn them up again if not yet resolved.