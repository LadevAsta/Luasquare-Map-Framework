-- Annunciator system is similar to how seg7display works.

-- It will utilizes skin-based model to change skin of defined prop_dynamic in the map.
-- And play alarm sounds Either from the prop position (if possible and I can do that) or with existing ambient generic (more troublesome)?
-- Those prop dynamics will have 4 skins. Off, fast flash, On, slow flash. (Can I have just 1 animated VTF and have 4 VMTs per model?)

-- Have 3 input from operator. ACKnowledge, MUTE and RESET.
-- When start, start off with OFF skin
-- When a problem arises, change the offender to fast flash.
-- When ACK is pressed, unresolved problem get to ON skin
-- When problem is resolved, get to slow flash whenther or not it is ACKnowledged.
-- When RESET is pressed, problem with slow flash change to OFF skin.
-- MUTE simply stop all the current alarm sounds. But 5 minutes after that, play audio cue turn them up again if not resolved.