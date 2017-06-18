Soloqueue = LibStub("AceAddon-3.0"):NewAddon("Soloqueue", "AceConsole-3.0");

local eventFrame = nil
local BRACKETS = { "2v2", "3v3", "5v5", "RBG" }

local player_stack = {}
local player_stack_idx = 0

local attempts = 0
local MAX_ATTEMPTS = 3

local SoloqueueLDB = LibStub("LibDataBroker-1.1"):NewDataObject("Soloqueue", {
	type = "data source",
	text = "Soloqueue",
	icon = "Interface\\Icons\\INV_Chest_Cloth_17",
	OnClick = function() print("BUNNIES ARE TAKING OVER THE WORLD") end,
});

local icon = LibStub("LibDBIcon-1.0");

local function PrintRatings(player, ratings)
	local name = UnitName(player);
	print(name .. " ratings:");
  	for i, r in pairs(ratings) do
    	print (BRACKETS[i] .. " : " .. r)
  	end
end

local function getCurrentRatings()
	local succsess = false;
	local player = Soloqueue:CurPlayer();

  	targetCurrentRatings = {}
  	for i, b in pairs(BRACKETS) do
  		local cr = GetInspectArenaData(i)
  		if cr > 0 then succsess = true end
    	targetCurrentRatings[i] = cr
  	end

  	ClearInspectPlayer();

  	if (succsess == true) then
		PrintRatings(player, targetCurrentRatings);
		Soloqueue:PopPlayer();
		attempts = 0;
	else
		attempts = attempts + 1
		if attempts >= MAX_ATTEMPTS then
			PrintRatings(player, targetCurrentRatings);
  			Soloqueue:PopPlayer()
  			attempts = 0;
  		end
  	end

  	if (Soloqueue:CurPlayer()) then
		Soloqueue:GetRatings();
	end
end

local function eventHandler(self, event)
	--print("got event:" .. event)
  	if event == "INSPECT_HONOR_UPDATE" then
  		eventFrame:UnregisterEvent("INSPECT_HONOR_UPDATE");
  		getCurrentRatings();
  	elseif event == "INSPECT_READY" then
  		eventFrame:UnregisterEvent("INSPECT_READY");
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

function Soloqueue:CurPlayer()
	if player_stack_idx > 0 then
		return player_stack[player_stack_idx];
	else
		return nil
	end
end

function Soloqueue:PutPlayer(player)
	--print ("Put " .. player)
	player_stack_idx = player_stack_idx + 1
	player_stack[player_stack_idx] = player;
end

function Soloqueue:PopPlayer()
	local player = self:CurPlayer();
	--print ("Pop " .. player);
	player_stack_idx = player_stack_idx - 1;
end

function Soloqueue:GetAllRatings()
	self:Print("Getting ratings...");

	local selfName = UnitName('player');

	self:PutPlayer("player");

	if IsInRaid() then
	    for i = 1, 10 do
	    	local playerName = UnitName('raid' .. i);
	        if (playerName and (playerName ~= selfName)) then
	            self:PutPlayer('raid' .. i);
	        end
	    end
	end

	self:GetRatings();
end

function Soloqueue:GetRatings()
	local player = Soloqueue:CurPlayer();
	if (player) then
		eventFrame:RegisterEvent("INSPECT_READY");
    	NotifyInspect(player);
    end
end;