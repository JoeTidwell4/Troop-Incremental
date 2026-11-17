--!strict
-- One flag: is a story cutscene on screen right now (CutsceneUI sets it)? Other modules
-- check it to stay out of the way: CampController hides the sign labels and hitboxes,
-- TutorialUI waits.

local Cinematic = {
	active = false,
	-- A tutorial card is on screen (TutorialUI sets it). Arrival scenes wait for it, so the
	-- prologue never cuts into the first lesson.
	tutorialOpen = false,
}

return Cinematic
