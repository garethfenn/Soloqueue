Soloqueue = LibStub("AceAddon-3.0"):NewAddon("Soloqueue", "AceConsole-3.0");
local eventFrame = nil

-- States
local STATE_GET_RATING, STATE_LOOK_FOR_GROUP, STATE_APPLY_TO_GROUPS, STATE_PENDING_INVITE, STATE_CREATE_GROUP, STATE_WAIT_TEAMMATES, STATE_CLOSE_POPUP, STATE_CHECK_TEAMMATES = 0, 1, 2, 3, 4, 5, 6, 7;
local state = STATE_GET_RATING;

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

function Soloqueue:CurPlayer()
	local head = table.getn(self.player_stack);
	if head > 0 then
		return self.player_stack[head];
	else
		return nil
	end
end

function Soloqueue:PutPlayer(player)
	--print ("Put " .. player)
	table.insert(self.player_stack, player);
end

function Soloqueue:PopPlayer()
	local player = table.remove(self.player_stack, 1);
	--print ("Pop " .. player);
end

function Soloqueue:PrintRatings(player, ratings)
	local name = UnitName(player);
	print(name .. " ratings:");
	for i, r in pairs(ratings) do
		print (BRACKETS[i] .. " : " .. r)
	end
end

function Soloqueue:CallRatingCallback(player, ratings)
	if state == STATE_GET_RATING then
		Soloqueue:GetPlayerRatingCallback(player, ratings);
	elseif state == STATE_CHECK_TEAMMATES then
		Soloqueue:CheckTeamMatesCallback(player, ratings);
	end
end

local function eventHandler(self, event, ...)
	print("got event:" .. event)
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
	elseif event == "PARTY_INVITE_REQUEST" then
		Soloqueue:ApplyToGroupsCallback(...)
	elseif event == "GROUP_JOINED" then
		eventFrame:UnregisterEvent("GROUP_JOINED");
		Soloqueue:UICallback();
	else
		print ("Unexpected event: " .. event);
	end
end

local function hook_SetAction(a, b, c, d, e)
	print(type(a))
	print(a)
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
	self:RegisterChatCommand("soloqueue", "Test");

	-- Minimap
	icon:Register("Soloqueue", SoloqueueLDB, self.db.profile.minimap);

	-- Set up event handler
	eventFrame = CreateFrame("Frame", "SoloqueueEventFrame", UIParent)
	eventFrame:SetScript("OnEvent", eventHandler);

	hooksecurefunc(C_LFGList, "RemoveListing", function(self)
		if (state == STATE_WAIT_TEAMMATES) then
			state = STATE_GET_RATING;
		end
	end);

	hooksecurefunc(C_LFGList, "InviteApplicant", hook_SetAction);

	-- Set/reset macro
	self:CreateMacro()

	-- Init context
	self.CallbackPending = false;
	self.CR = 0;
	self.playerName = nil;
	self.realm = nil;

	-- Stack of players to get ratings from
	self.player_stack = {};

	-- Applying to groups
	self.groupIDs = {};
	self.leaders = {};
	self.pendingLeader = nil
	self.pendingInvite = 0;

	-- Looking for players
	self.CRUpper = 0;
	self.CRLower = 0;
	self.pendingInvites = 0;
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

	print ("Current state:" .. state)

	if (self.CallbackPending == true) then
		print ("Callback pending ...")
		return;
	end

	if state == STATE_GET_RATING then
		self:GetPlayerRating();
	elseif state == STATE_LOOK_FOR_GROUP then
		self:LookForGroup();
	elseif state == STATE_APPLY_TO_GROUPS then
		self:ApplyToGroup();
	elseif state == STATE_CREATE_GROUP then
		self:CreateGroup();
	elseif state == STATE_WAIT_TEAMMATES then
		self:InviteApplications();
	elseif state == STATE_CHECK_TEAMMATES then
		-- nothing to do
	else
		print ("Invalid state!");
	end
end

function Soloqueue:GetPlayerRating()
	self:Print("Refreshing current player ratings...");
	self:PutPlayer("player");
	self.CallbackPending = true;
	self:InitRatingRequest();
end

function Soloqueue:GetPlayerRatingCallback(player, ratings)
	self.CR = ratings[1];
	self.playerName, self.realm = UnitFullName("player");
	state = STATE_LOOK_FOR_GROUP;
	self.CallbackPending = false;
end

function Soloqueue:LookForGroup()
	self.CallbackPending = true;
	eventFrame:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED");
	local languages = C_LFGList.GetLanguageSearchFilter();
	C_LFGList.Search(6, LFGListSearchPanel_ParseSearchTerms("Soloqueue"), 0, 8, languages) -- arena 4
end

function Soloqueue:LookForGroupCallback()
	local numResults, results = C_LFGList.GetSearchResults()
	if numResults > 0 then
		for _,groupID in pairs(results) do
			local _,_,_,description,_,_,_,_,_,_,_,_,leader,_ = C_LFGList.GetSearchResultInfo(groupID)
			if description then
				local low, high = string.match(description, "#L:(%d+) #H:(%d+)");
				low = tonumber(low);
				high = tonumber(high);
				if ((self.CR >= low) and (self.CR < high)) then
					table.insert(self.groupIDs, groupID);
					table.insert(self.leaders, leader);
				end
			end
		end
	end

	if (table.getn(self.groupIDs) == 0) then
		state = STATE_CREATE_GROUP;
		if (self.CRUpper > CR_MINIMUM) then
			self.CRUpper = ratings[1];
			self.CRLower = ratings[1] - CR_WINDOW_INCREMENT;
		else
			self.CRUpper = CR_MINIMUM;
			self.CRLower = 0;
		end
	else
		state = STATE_APPLY_TO_GROUPS;
	end

	self.CallbackPending = false;
end

function Soloqueue:ApplyToGroup()
	eventFrame:RegisterEvent("PARTY_INVITE_REQUEST")
	local group = table.remove(self.groupIDs, 1)
	self.pendingLeader = table.remove(self.leaders, 1)
	if (group) then
		self.CallbackPending = true;
		C_LFGList.ApplyToGroup(group, "Soloqueue #CR:" .. self.CR .. " #NAME:" .. self.playerName .. " #REALM:" .. self.realm, false, false, true)
	else
		state = STATE_LOOK_FOR_GROUP;
	end
end

function Soloqueue:ApplyToGroupsCallback(sender)
	if (sender == self.pendingLeader) then
		AcceptGroup()
		eventFrame:UnregisterEvent("PARTY_INVITE_REQUEST");
		eventFrame:RegisterEvent("GROUP_JOINED")
		self.groupIDs = {};
		self.leaders = {};
	end
end

function Soloqueue:UICallback(sender)
	self:Print("UiCallback")
	if IsInRaid() or IsInGroup() then
		StaticPopupSpecial_Hide(LFGInvitePopup);
		state = STATE_CHECK_TEAMMATES;
	else
		self:Print("Something went wrong... reset.")
		state = STATE_GET_RATING;
	end
	self.CallbackPending = false;
end

function Soloqueue:CreateGroup()
	self:Print ("Creating group with rating requirements " .. self.CRLower .. ":" .. self.CRUpper);
	C_LFGList.CreateListing(16, "Soloqueue", 0, 0, "", "Do not join. #L:" .. self.CRLower .. " #H:" .. self.CRUpper, false, true); -- arena 7
	state = STATE_WAIT_TEAMMATES
	self.pendingInvites = 0;
	self:InviteApplications();
end

function Soloqueue:InviteApplicationTimeout(name, application)
	if not UnitInParty(name) then
	self:Print (name .. " invitiation timeout... restarting group.")
	LeaveParty();
	C_LFGList:DeclineApplicant(application);
	self.pendingInvites = 0;
	end
end

function Soloqueue:InviteApplications()
	local players_to_invite = (3 - self.pendingInvites);
	if (players_to_invite) then
		local applications = C_LFGList.GetApplicants();
		if (applications ~= nil) then
			for _, application in pairs(applications) do
				local id, status, pendingStatus, numMembers, isNew, comment = C_LFGList.GetApplicantInfo(application);
				if (numMembers <= players_to_invite) then
					if (comment ~= nil) then
						local CR = string.match(comment, "#CR:(%d+)");
						local name = string.match(comment, "#NAME:(%a+)");
						local realm = string.match(comment, "#REALM:(%a+)");
						CR = tonumber(CR);
						if (CR ~= nil) then
							if (CR >= self.CRLower) then
								local fullname = name .. "-" .. realm;
								InviteUnit(fullname)
								self.pendingInvites = self.pendingInvites + 1;
								players_to_invite = players_to_invite - numMembers;
								C_Timer.After(2, function () Soloqueue:InviteApplicationTimeout(fullname, application) end)
							else
								-- Applied with too low CR
								C_LFGList:DeclineApplicant(application);
							end
						else
							-- Invalid CR string
							C_LFGList:DeclineApplicant(application);
						end
					else
						-- No comment provided
						C_LFGList:DeclineApplicant(application);
					end
				end
			end
		end
	end
end

function Soloqueue:ReduceRequirements()
	if (self.CRLower >= CR_WINDOW_INCREMENT) then
		self.CRLower = self.CRLower - CR_WINDOW_INCREMENT;
	elseif (self.CRLower > 0) then
		self.CRLower = 0;
	else
		self:Print ("Already at lowest rating. Sorry!");
		return;
	end

	self:Print ("Reducing rating requirement.");
	C_LFGList.UpdateListing(7, "Soloqueue", 0, 0, "", "Do not join. #L:".. self.CRLower .. " #H:" .. self.CRUpper, false, 0);
end

function Soloqueue:CreateMacro()
	local text =
[[
/soloqueue
/run TogglePVPUI()
/click PVPQueueFrameCategoryButton2
/click ConquestFrame.Arena3v3
/cick ConquestJoinButton
/run TogglePVPUI()
]]

	DeleteMacro("Soloqueue")
	CreateMacro("Soloqueue", "Achievement_arena_2v2_7", text)
end

function Soloqueue:Test()
	state = STATE_GET_RATING
	self.CallbackPending = false;
end

function Soloqueue:CheckTeammates()
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
	elseif IsInGroup() then
		for i = 1, 5 do
			local playerName = UnitName('party' .. i);
			if (playerName and (playerName ~= selfName)) then
				self:PutPlayer('party' .. i);
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