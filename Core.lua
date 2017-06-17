Soloqueue = LibStub("AceAddon-3.0"):NewAddon("Soloqueue", "AceConsole-3.0");

local SoloqueueLDB = LibStub("LibDataBroker-1.1"):NewDataObject("Soloqueue", {
	type = "data source",
	text = "Soloqueue",
	icon = "Interface\\Icons\\INV_Chest_Cloth_17",
	OnClick = function() print("BUNNIES ARE TAKING OVER THE WORLD") end,
});
local icon = LibStub("LibDBIcon-1.0");

function Soloqueue:OnInitialize()
	-- Obviously you'll need a ## SavedVariables: BunniesDB line in your TOC, duh!
	self:Print("Soloqueue")
	self.db = LibStub("AceDB-3.0"):New("SoloqueueDB", {
		profile = {
			minimap = {
				hide = false,
			},
		},
	});
	icon:Register("Soloqueue", SoloqueueLDB, self.db.profile.minimap);
	self:RegisterChatCommand("soloqueue", "ToggleMinimap");
end;

function Soloqueue:ToggleMinimap()
	self.db.profile.minimap.hide = not self.db.profile.minimap.hide;
	if self.db.profile.minimap.hide then
		icon:Hide("Soloqueue");
	else
		icon:Show("Soloqueue");
	end
end;