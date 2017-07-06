Soloqueue = LibStub("AceAddon-3.0"):NewAddon("Soloqueue", "AceConsole-3.0");
local eventFrame = nil

-- States
local STATE_GET_RATING, STATE_LOOK_FOR_GROUP, STATE_APPLY_TO_GROUPS, STATE_PENDING_INVITE, STATE_CREATE_GROUP, STATE_WAIT_TEAMMATES, STATE_CLOSE_POPUP, STATE_CHECK_TEAMMATES = 0, 1, 2, 3, 4, 5, 6, 7;
local state = STATE_GET_RATING;

-- Messages
local MSG_REQUEST_HANDSHAKE, MSG_HANDSHAKE, MSG_ACCEPT_HANDSHAKE, MSG_DECLINE = 0, 1, 2, 3;

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
	elseif event == "CHAT_MSG_WHISPER" then
		Soloqueue:ChatMsgEventHandler(...)
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

	-- Addon comms
	eventFrame:RegisterEvent("CHAT_MSG_WHISPER");

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
	self.leaders = {};
	self.pendingLeader = nil

	-- Looking for players
	self.CRUpper = 0;
	self.CRLower = 0;
	self.pendingHandshakes = 0;
	self.invitees = {};
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
		-- nothing to do
	elseif state == STATE_CHECK_TEAMMATES then
		-- nothing to do
	else
		print ("Invalid state!");
	end
end

function Soloqueue:SendChatMessage(target, message)
		SendChatMessage("#SQ:" .. message, "WHISPER", nil, target)
end

function Soloqueue:HandshakeTimeout(slot)
	if not UnitInParty(self.invitees[slot]) then
	self:Print (self.invitees[slot] .. " handshake timeout...")
	self.invitees[slot] = nil;
	self.pendingHandshakes = self.pendingHandshakes + 1;
	end
end

function Soloqueue:InviteTimeout(name)
	if not UnitInParty(name) then
	self:Print (name .. " invitiation timeout... restarting group.")
	LeaveParty();
	C_LFGList:DeclineApplicant(application);
	self.pendingHandshakes = 0;
	end
end

function Soloqueue:TrackInvitee(invitee)
	for slot = 1, 3 do
		if self.invitees[slot] == nil then
			self.invitees[slot] = invitee;
			return;
		end
	end

	print ("Error. No free slots?");
	return nil;
end

function Soloqueue:ChatMsgEventHandler(string, sender)
	local msg = string.match(string, "#SQ:(%d+)");
	msg = tonumber(msg);

	if msg == MSG_REQUEST_HANDSHAKE then
		local freeHandshakes = (3 - self.pendingHandshakes);
		if (freeHandshakes > 0) then
			self:TrackInvitee(sender);
			self:SendChatMessage(sender, MSG_HANDSHAKE);
			C_Timer.After(2, function () Soloqueue:HandshakeTimeout(slot) end)
			self.pendingHandshakes = self.pendingHandshakes + 1;
		else
			self:SendChatMessage(sender, MSG_DECLINE);
		end
	elseif msg == MSG_HANDSHAKE then
		self.pendingLeader = sender;
		eventFrame:RegisterEvent("PARTY_INVITE_REQUEST")
		self:SendChatMessage(sender, MSG_ACCEPT_HANDSHAKE);
	elseif msg == MSG_ACCEPT_HANDSHAKE then
		InviteUnit(sender)
	elseif msg == MSG_DECLINE then
		print ("Declined!");
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
					table.insert(self.leaders, leader);
				end
			end
		end
	end

	if (table.getn(self.leaders) == 0) then
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
	for _,leader in pairs(self.leaders) do
		self:SendChatMessage(leader, MSG_REQUEST_HANDSHAKE);
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
		--StaticPopup_Hide("PARTY_INVITE");
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
	self.pendingHandshakes = 0;
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