--!strict
-- One flag: is a story cutscene on screen right now (CutsceneUI sets it)? Other modules
-- check it to stay out of the way: CampController hides the sign labels and hitboxes,
-- TutorialUI waits.

local Cinematic = {
	active = false,
}

return Cinematic
