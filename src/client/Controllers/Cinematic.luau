--!strict
-- One flag: is a story cutscene on screen right now (CutsceneUI sets it)? Other modules
-- check it to stay out of the way: CampController hides the sign labels and hitboxes,
-- TutorialUI waits.

local Cinematic = {
	active = false,
	-- A tutorial card is on screen (TutorialUI sets it). Arrival scenes wait for it, so the
	-- prologue never cuts into the first lesson.
	tutorialOpen = false,
	busyAt = -math.huge, -- os.clock() when a cutscene or lesson card was last on screen
}

-- True when nothing guided is on screen and hasn't been for a few seconds. Popups that
-- open by themselves (the daily calendar, the faction picker) wait for this, so a new
-- player never gets two things thrown at them at once.
function Cinematic.calm(): boolean
	if Cinematic.active or Cinematic.tutorialOpen then
		Cinematic.busyAt = os.clock()
		return false
	end
	return os.clock() - Cinematic.busyAt >= 4
end

return Cinematic
