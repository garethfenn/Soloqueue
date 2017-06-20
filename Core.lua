Soloqueue = LibStub("AceAddon-3.0"):NewAddon("Soloqueue", "AceConsole-3.0");
local eventFrame = nil

-- Operation types
local OP_GET_CUR_RATING, OP_QUEUE, OP_CHECKTEAMMATES = 0, 1, 2;
local operation = OP_GET_CUR_RATING;

-- Stack of players to get ratings from
local player_stack = {}
local player_stack_idx = 0

-- Sometimes the ratings are not available first time around
local attempts = 0
local MAX_ATTEMPTS = 3

-- 5v5 isn't used anymore...
local BRACKETS = { "2v2", "3v3", "5v5", "RBG" }

local CR_WINDOW_INCREMENT = 100;

-- Forward declarate some functions
local getCurrentRatings

local SoloqueueLDB = LibStub("LibDataBroker-1.1"):NewDataObject("Soloqueue", {
	type = "data source",
	text = "Soloqueue",
	icon = "Interface\\Icons\\Achievement_arena_2v2_7",
	OnClick = function(clickedframe, button) Soloqueue:Queue() end,
});

local icon = LibStub("LibDBIcon-1.0");

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

function Soloqueue:PrintRatings(player, ratings)
	local name = UnitName(player);
	print(name .. " ratings:");
  	for i, r in pairs(ratings) do
    	print (BRACKETS[i] .. " : " .. r)
  	end
end

function CallTheCallback(player, ratings)
	--print("Callback operation " .. operation)
  	if operation == OP_QUEUE then
		Soloqueue:GetPlayerRatingCallback(player, ratings);
  	elseif operation == OP_CHECKTEAMMATES then
		Soloqueue:CheckTeamMatesCallback(player, ratings);
  	end
end;

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
	self:RegisterChatCommand("soloqueue", "CheckTeammates");

	-- Minimap
	icon:Register("Soloqueue", SoloqueueLDB, self.db.profile.minimap);

	-- Set up event handler
	eventFrame = CreateFrame("Frame", "SoloqueueEventFrame", UIParent)
	eventFrame:SetScript("OnEvent", eventHandler);

	-- Init context
	self.CurCr = 0;
	self.CRWindow = 0;
end;

function getCurrentRatings()
	local succsess = false;
	local player = Soloqueue:CurPlayer();

  	targetCurrentRatings = {}
  	for i, b in pairs(BRACKETS) do
  		local cr = GetInspectArenaData(i)
  		if cr > 0 then succsess = true end
    	targetCurrentRatings[i] = cr;
  	end

  	ClearInspectPlayer();

  	if (succsess == true) then
		CallTheCallback(player, targetCurrentRatings);
		Soloqueue:PopPlayer();
		attempts = 0;
	else
		attempts = attempts + 1
		if attempts >= MAX_ATTEMPTS then
			CallTheCallback(player, targetCurrentRatings);
  			Soloqueue:PopPlayer();
  			attempts = 0;
  		end
  	end

  	if (Soloqueue:CurPlayer()) then
		Soloqueue:GetRatings();
	end
end

function Soloqueue:GetRatings()
	local player = Soloqueue:CurPlayer();
	if (player) then
		eventFrame:RegisterEvent("INSPECT_READY");
    	NotifyInspect(player);
    end
end;

function Soloqueue:Queue()
	if operation == OP_GET_CUR_RATING then
		self:GetPlayerRating();
	elseif operation == OP_QUEUE then
		self:QueueGame();
	elseif operation == OP_CHECKTEAMMATES then
		self:CheckTeammates();
	else
		print ("Invalid state!");
	end
end

function Soloqueue:GetPlayerRating()
	operation = OP_QUEUE;
	self.CRWindow = self.CRWindow + CR_WINDOW_INCREMENT;
	self:Print("Finding group...");
	self:PutPlayer("player");
	self:GetRatings();
end

function Soloqueue:GetPlayerRatingCallback(player, ratings)
	self.curCr = ratings[1];
	operation = OP_QUEUE;
end

function Soloqueue:QueueGame()
	local rating_high = self.curCr;
	local rating low = 0;
	if ((self.curCr - self.CRWindow) > 0) then
		rating_low = self.curCr - self.CRWindow;
	end

	print ("Finding game with rating " .. rating_low .. ":" .. rating_high);
	C_LFGList.CreateListing(7, "Soloqueue", 0, 0, "", "Do not join unless your arena CR is between #L:".. rating_low .. " and #H:" .. rating_high, false, 0);

	-- Reset state
	operation = OP_GET_CUR_RATING
end

function Soloqueue:CheckTeammates()
	operation = OP_CHECKTEAMMATES;
	self:Print("Checking teammates ratings are correct...");

	local selfName = UnitName('player');
	if IsInRaid() then
	    for i = 1, 10 do
	    	local playerName = UnitName('raid' .. i);
	        if (playerName and (playerName ~= selfName)) then
	            self:PutPlayer('raid' .. i);
	        end
	    end
	    self:GetRatings();
	end
end

function Soloqueue:CheckTeamMatesCallback(player, ratings)
	self:PrintRatings(player, targetCurrentRatings);
end