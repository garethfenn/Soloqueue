Soloqueue = LibStub("AceAddon-3.0"):NewAddon("Soloqueue", "AceConsole-3.0");
local eventFrame = nil

-- States
local STATE_GET_GET_RATING, STATE_LOOK_FOR_GROUP, STATE_CREATE_GROUP, STATE_WAIT_TEAMMATES, STATE_CHECK_TEAMMATES = 0, 1, 2, 3, 4;
local state = STATE_GET_GET_RATING;

-- Stack of players to get ratings from
local player_stack = {}
local player_stack_idx = 0

-- Sometimes the ratings are not available first time around
local attempts = 0
local MAX_ATTEMPTS = 3

-- 5v5 isn't used anymore...
local BRACKETS = { "2v2", "3v3", "5v5", "RBG" }

local CR_MINIMUM = 1200;
local CR_WINDOW_INCREMENT = 100;

-- Forward declarate some functions
local getCurrentRatings

local SoloqueueLDB = LibStub("LibDataBroker-1.1"):NewDataObject("Soloqueue", {
	type = "data source",
	text = "Soloqueue",
	icon = "Interface\\Icons\\Achievement_arena_2v2_7",
	OnClick = function(clickedframe, button) Soloqueue:StateMachine() end,
});

local icon = LibStub("LibDBIcon-1.0");

function Soloqueue:IsInGroupOrRaid()
	if IsInGroup() or IsInGroup() then
		return true;
	else
		return false;
	end
end

function Soloqueue:GroupStateInvalid()

	if state == STATE_GET_GET_RATING then
		if self:IsInGroupOrRaid() then 
			self.Print("Must leave group.");
			return true;
		end
	elseif (state == STATE_LOOK_FOR_GROUP) or (state == STATE_CREATE_GROUP) then
		if self:IsInGroupOrRaid() then 
			self.Print("Resetting soloqueue");
			state = STATE_GET_GET_RATING;
			return true;
		end
	elseif state == STATE_CHECK_TEAMMATES then
		if not self:IsInGroupOrRaid() then 
			self.Print("Resetting soloqueue");
			state = STATE_GET_GET_RATING;
			return true;
		end
	end

	return false;
end


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

function Soloqueue:CallRatingCallback(player, ratings)
  	if state == STATE_GET_GET_RATING then
		Soloqueue:GetPlayerRatingCallback(player, ratings);
  	elseif state == STATE_CHECK_TEAMMATES then
		Soloqueue:CheckTeamMatesCallback(player, ratings);
  	end
end

local function eventHandler(self, event, ...)
	--print("got event:" .. event)
  	if event == "INSPECT_HONOR_UPDATE" then
  		eventFrame:UnregisterEvent("INSPECT_HONOR_UPDATE");
  		Soloqueue:ParseArenaRatings();
  	elseif event == "INSPECT_READY" then
  		eventFrame:UnregisterEvent("INSPECT_READY");
  	    eventFrame:RegisterEvent("INSPECT_HONOR_UPDATE");
 		RequestInspectHonorData();
  	elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
  		eventFrame:UnregisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED");
		Soloqueue:LookForGroupCallback();
  	elseif event == "LFG_LIST_APPLICANT_UPDATED" then
		Soloqueue:ApplicantEventHandler(...);
  	elseif event == "GROUP_ROSTER_UPDATE" then
		Soloqueue:RosterUpdateEventHandler();
  	else
  		print ("Unexpected event");
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
	self:RegisterChatCommand("soloqueue", "LookForGroup");

	-- Minimap
	icon:Register("Soloqueue", SoloqueueLDB, self.db.profile.minimap);

	-- Set up event handler
	eventFrame = CreateFrame("Frame", "SoloqueueEventFrame", UIParent)
	eventFrame:SetScript("OnEvent", eventHandler);

	hooksecurefunc(C_LFGList, "RemoveListing", function(self)
		if (state == STATE_WAIT_TEAMMATES) then
			state = STATE_GET_GET_RATING;
		end
	end);

	-- Init context
	self.CallbackPending = false;
	self.CRUpper = 0;
	self.CRLower = 0;
end

function Soloqueue:ParseArenaRatings()
	local succsess = false;
	local player = self:CurPlayer();

  	ratings = {}
  	for i, b in pairs(BRACKETS) do
  		local cr = GetInspectArenaData(i)
  		if cr > 0 then succsess = true end
    	ratings[i] = cr;
  	end

  	ClearInspectPlayer();

  	if (succsess == true) then
		self:CallRatingCallback(player, ratings);
		self:PopPlayer();
		attempts = 0;
	else
		attempts = attempts + 1
		if attempts >= MAX_ATTEMPTS then
			self:CallRatingCallback(player, ratings);
  			self:PopPlayer();
  			attempts = 0;
  		end
  	end

  	if (self:CurPlayer()) then
		self:InitRatingRequest();
	end
end

function Soloqueue:InitRatingRequest()
	local player = Soloqueue:CurPlayer();
	if (player) then
		eventFrame:RegisterEvent("INSPECT_READY");
    	NotifyInspect(player);
    end
end

function Soloqueue:StateMachine()

	--print ("Current state:" .. state)

	if Soloqueue:GroupStateInvalid() then return end

	if (self.CallbackPending == true) then return end

	if state == STATE_GET_GET_RATING then
		self:GetPlayerRating();
	elseif state == STATE_LOOK_FOR_GROUP then
		self:LookForGroup();
	elseif state == STATE_CREATE_GROUP then
		self:CreateGroup();
	elseif state == STATE_WAIT_TEAMMATES then
		self:WaitTeammates();
	elseif state == STATE_CHECK_TEAMMATES then
		self:CheckTeammates();
	else
		print ("Invalid state!");
	end
end

function Soloqueue:GetPlayerRating()
	if Soloqueue:GroupStateInvalid() then return end
	self:Print("Refreshing current player ratings...");
	self:PutPlayer("player");
	self.CallbackPending = true;
	self:InitRatingRequest();
end

function Soloqueue:GetPlayerRatingCallback(player, ratings)
	if (self.CRUpper > CR_MINIMUM) then
		self.CRUpper = ratings[1];
		self.CRLower = ratings[1] - CR_WINDOW_INCREMENT;
	else
		self.CRUpper = CR_MINIMUM;
		self.CRLower = 0;
	end

	state = STATE_LOOK_FOR_GROUP;
	self.CallbackPending = false;
end

function Soloqueue:LookForGroup()
	if Soloqueue:GroupStateInvalid() then return end
	eventFrame:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED");
	local languages = C_LFGList.GetLanguageSearchFilter();
	C_LFGList.Search(4, LFGListSearchPanel_ParseSearchTerms("Soloqueue Game"), 0, 8, languages)
end

function Soloqueue:LookForGroupCallback()
	local numResults, results = C_LFGList.GetSearchResults()
	if numResults > 0 then
	    -- deep-filter results
	    for _,id in ipairs(results) do
	        local _,_,_,description,_,_,_,_,_,_,_,_,_,_ = C_LFGList.GetSearchResultInfo(id)
	        if description then
	            print(description);
	        end
	    end
	else
		self:Print("Couldn't find group. Click again to create group.")
		state = STATE_CREATE_GROUP;
	end
end

function Soloqueue:CreateGroup()
	if Soloqueue:GroupStateInvalid() then return end
	self:Print ("Creating group with rating requirements " .. self.CRLower .. ":" .. self.CRUpper);
	eventFrame:RegisterEvent("LFG_LIST_APPLICANT_UPDATED");
	eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE");
	C_LFGList.CreateListing(7, "Soloqueue", 0, 0, "", "Do not join unless your arena rating is between #L:".. self.CRLower .. " and #H:" .. self.CRUpper, false, 0);
	state = STATE_WAIT_TEAMMATES
end

function Soloqueue:RosterUpdateEventHandler()
	-- Check for num people in group
end

function Soloqueue:ApplicantEventHandler(applicantID)
	local id, status, pendingStatus, numMembers, isNew, comment = C_LFGList.GetApplicantInfo(applicantID)
	print (id .. " " .. status .. " " .. pendingStatus .. " " .. numMembers .. " " .. isNew .. " " .. comment);
	if (currentWQ and status == "inviteaccepted" and comment == "WorldQuestGroupFinderUser-"..currentWQ) then
		if (numMembers > 1) then
			C_LFGList:DeclineApplicant(applicantID);
		else
			C_LFGList:InviteApplicant(applicantID);
		end
	end
end

function Soloqueue:WaitTeammates()
	if (self.CRLower >= CR_WINDOW_INCREMENT) then
		self.CRLower = self.CRLower - CR_WINDOW_INCREMENT;
	elseif (self.CRLower > 0) then
		self.CRLower = 0;
	else
		self:Print ("Already at lowest rating. Sorry!");
		return;
	end

	self:Print ("Reduced rating requirement. Repress button.");
	C_LFGList.RemoveListing();
	state = STATE_LOOK_FOR_GROUP;
end

function Soloqueue:CheckTeammates()
	if Soloqueue:GroupStateInvalid() then return end
	self:Print("Checking teammates ratings are correct...");

	local selfName = UnitName('player');
	if IsInRaid() then
	    for i = 1, 10 do
	    	local playerName = UnitName('raid' .. i);
	        if (playerName and (playerName ~= selfName)) then
	            self:PutPlayer('raid' .. i);
	        end
	    end
	    self.CallbackPending = true;
	    self:InitRatingRequest();
	end
end

function Soloqueue:CheckTeamMatesCallback(player, ratings)
	self:PrintRatings(player, targetCurrentRatings);
	self.CallbackPending = false;
end