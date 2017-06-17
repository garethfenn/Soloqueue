Soloqueue = LibStub("AceAddon-3.0"):NewAddon("Soloqueue", "AceConsole-3.0");

local eventFrame = nil

local SoloqueueLDB = LibStub("LibDataBroker-1.1"):NewDataObject("Soloqueue", {
	type = "data source",
	text = "Soloqueue",
	icon = "Interface\\Icons\\INV_Chest_Cloth_17",
	OnClick = function() print("BUNNIES ARE TAKING OVER THE WORLD") end,
});

local icon = LibStub("LibDBIcon-1.0");

local function eventHandler(self, event, unit, ...)
  if event == "INSPECT_HONOR_UPDATE" then
  		print("Honor Ready");
    	--onHonorInspectReady()
  elseif event == "INSPECT_READY" then
  	    print("Inspect Ready");
    	--onInspectReady()
  end
end

function Soloqueue:OnInitialize()
	self:Print("Soloqueue")
	self.db = LibStub("AceDB-3.0"):New("SoloqueueDB", {
		profile = {
			minimap = {
				hide = false,
			},
		},
	});

	-- Commands
	self:RegisterChatCommand("soloqueue", "GetRatings");

	-- Minimap
	icon:Register("Soloqueue", SoloqueueLDB, self.db.profile.minimap);

	-- Set up event handler
	eventFrame = CreateFrame("Frame", "SoloqueueEventFrame", UIParent)
	eventFrame:SetScript("OnEvent", eventHandler);
end;

function Soloqueue:GetRatings()
	self:Print("Getting rating...");
	local playerName = UnitName("player");
	eventFrame:RegisterEvent("INSPECT_READY")
    NotifyInspect(playerName)
end;

function Soloqueue:getNameRealmSlug()
  local name, realm = UnitName(TARGET)
  if realm == nil then realm = "" end
  local slug = name .. realm

  return  name, realm, slug
end