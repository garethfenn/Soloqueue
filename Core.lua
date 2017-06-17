Soloqueue = LibStub("AceAddon-3.0"):NewAddon("Soloqueue", "AceConsole-3.0");

local eventFrame = nil
local BRACKETS = { "2v2", "3v3", "5v5", "RBG" }

local attempts = 0
local MAX_ATTEMPTS = 3

local SoloqueueLDB = LibStub("LibDataBroker-1.1"):NewDataObject("Soloqueue", {
	type = "data source",
	text = "Soloqueue",
	icon = "Interface\\Icons\\INV_Chest_Cloth_17",
	OnClick = function() print("BUNNIES ARE TAKING OVER THE WORLD") end,
});

local icon = LibStub("LibDBIcon-1.0");

local function getCurrentRatings()
	local succsess = false;
  	if attempts >= MAX_ATTEMPTS then
  		attempts = 0;
    	return false
  	end
  	attempts = attempts + 1

  	targetCurrentRatings = {}
  	for i, b in pairs(BRACKETS) do
  		local cr = GetInspectArenaData(i)
  		if cr > 0 then succsess = true end
    	targetCurrentRatings[i] = cr
  	end

	ClearInspectPlayer();
	eventFrame:UnregisterEvent("INSPECT_READY");
	eventFrame:UnregisterEvent("INSPECT_HONOR_UPDATE");

  	if (succsess == true) then
	  	for i, r in pairs(targetCurrentRatings) do
	    	print (BRACKETS[i] .. " : " .. r)
	  	end
  	else
  		print ("All 0. Retrying...")
  		Soloqueue:GetRatings("target");
  	end
end

local function eventHandler(self, event)
	print("got event:" .. event)
  	if event == "INSPECT_HONOR_UPDATE" then
  		getCurrentRatings();
  	elseif event == "INSPECT_READY" then
  	    eventFrame:RegisterEvent("INSPECT_HONOR_UPDATE");
 		RequestInspectHonorData();
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
	self:RegisterChatCommand("soloqueue", "GetAllRatings");

	-- Minimap
	icon:Register("Soloqueue", SoloqueueLDB, self.db.profile.minimap);

	-- Set up event handler
	eventFrame = CreateFrame("Frame", "SoloqueueEventFrame", UIParent)
	eventFrame:SetScript("OnEvent", eventHandler);
end;

function Soloqueue:GetAllRatings()
	self:Print("Getting ratings...");

	local selfName = UnitName("player");
	--self:GetRatings("player");
	self:GetRatings("target");

	--if IsInRaid() then
	--    for i = 1, 10 do
	--    	local playerName = UnitName('raid' .. i);
	--        if (playerName and (playerName ~= selfName)) then
	--            self:GetRatings('raid' .. i);
	--        end
	--    end
	--end

end

function Soloqueue:GetRatings(player)
	local playerName = UnitName(player);
	print(playerName .. " ratings:");
	eventFrame:RegisterEvent("INSPECT_READY");
    NotifyInspect(player);
end;

names = GetHomePartyInfo()

function Soloqueue:getNameRealmSlug()
  local name, realm = UnitName(TARGET)
  if realm == nil then realm = "" end
  local slug = name .. realm

  return  name, realm, slug
end