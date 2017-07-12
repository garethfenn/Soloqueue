Soloqueue = LibStub("AceAddon-3.0"):NewAddon("Soloqueue", "AceConsole-3.0");
local eventFrame = nil

-- States
local STATE_GET_RATING, STATE_LOOK_FOR_GROUP, STATE_APPLY_TO_GROUPS, STATE_WAITING_HANDSHAKE, STATE_WAITING_INVITE,
      STATE_CREATE_GROUP, STATE_WAIT_TEAMMATES, STATE_DELIST_GROUP, STATE_ROLE_CHECK, STATE_WAIT_BG_ENTRY, STATE_CHECK_TEAMMATES = 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10;
local state = STATE_GET_RATING;

-- Messages
local MSG_REQUEST_HANDSHAKE, MSG_HANDSHAKE, MSG_ACCEPT_HANDSHAKE, MSG_DECLINE = 0, 1, 2, 3;

-- Sometimes the ratings are not available first time around
local attempts = 0
local MAX_ATTEMPTS = 2
local TIMEOUT_SEC = 5

-- Bracket stuff
local BRACKET_2V2, BRACKET_3V3, BRACKET_RATEDBG = 1, 2, 4;
local BRACKETS = { "2v2", "3v3", "5v5", "RBG" }
local bracketNumPlayers = {2, 3, 5, 10};
local CreateGroupID = {6, 7, 0, 19}
local FindGroupID = {4, 4, 0, 9}

local CR_MINIMUM = 1200;
local CR_WINDOW_INCREMENT = 50;

-- Forward declarate some functions
local getCurrentRatings

local SoloqueueLDB_MenuFrame;
local SoloqueueLDB_Menu = {
	{
		text = "Soloqueue Menu",
		isTitle = true,
		notCheckable = true,
		func = function() somesetting = not somesetting end
	},
	{
		text = "Game type",
		hasArrow = true,
		notCheckable = true,
		menuList = {
			{ text = "2v2", notCheckable = false, checked = function() return (bracket == BRACKET_2V2) end, func = function() bracket = BRACKET_2V2; Soloqueue:ResetState(); end },
			{ text = "3v3", notCheckable = false, checked = function() return (bracket == BRACKET_3V3) end, func = function() bracket = BRACKET_3V3; Soloqueue:ResetState(); end },
			{ text = "RatedBG", notCheckable = false, checked = function() return (bracket == BRACKET_RATEDBG) end, func = function() bracket = BRACKET_RATEDBG; Soloqueue:ResetState(); end },
		}
	},
	{
		text = "Healer required",
		notCheckable = false,
		checked = function() return healerRequired end,
		func = function() healerRequired = not healerRequired end,
	},
	{
		text = "Create macro",
		notCheckable = true,
		func = function() Soloqueue:CreateMacro(); end,
	},
	{
		text = "Reset state",
		notCheckable = true,
		func = function() Soloqueue:Print("Reset state."); Soloqueue:ResetState(); end,
	},
	{
		text = "Test",
		notCheckable = true,
		func = function() Soloqueue:Test(); end,
	},
	{
		text = "",
		notClickable = true,
	},
	{
		text = "Close",
		notCheckable = true,
		func = function() CloseDropDownMenus (); end,
	}
}

local SoloqueueLDB = LibStub("LibDataBroker-1.1"):NewDataObject("Soloqueue", {
	type = "data source",
	text = "Soloqueue",
	icon = "Interface\\Icons\\Achievement_arena_2v2_7",
	OnClick = function (clickedframe, button)
		EasyMenu (SoloqueueLDB_Menu, SoloqueueLDB_MenuFrame, "cursor", 10, 0, "MENU");
	end,
	OnTooltipShow = function (tt)
		tt:AddLine("Soloqueue", 1, 1, 1);
	end,
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

function Soloqueue:StripOwnRealm(sender)
	local name, realm = sender:match("^([^%-]+)%-(.+)$")
	if realm == GetRealmName() then
		return name;
	else
		return sender;
	end
end

function Soloqueue:PrintRatings(player, ratings)
	local name, realm = UnitName(player);
	if (realm == nil) then
		fullname = name;
	else
		fullname = name .. "-" .. realm;
	end
	self:Print(fullname .. " ratings:");
	for i, r in pairs(ratings) do
		self:Print (BRACKETS[i] .. " : " .. r)
	end
end

function Soloqueue:SpecializationChanged(player)
	if player == "player" and state ~= STATE_GET_RATING then
		local role = GetSpecializationRole(GetSpecialization());
		if (role ~= "HEALER") then
			role = "DAMAGER"
		end
		if (role ~= self.role) then
			self:Print("Player changed role: " .. role .. " Resetting state.")
			LeaveParty();
			state = STATE_GET_RATING;
		end
	end
end

function Soloqueue:CallRatingCallback(player, ratings)
	if state == STATE_GET_RATING then
		Soloqueue:GetPlayerRatingCallback(ratings);
	elseif state == STATE_CHECK_TEAMMATES then
		Soloqueue:CheckTeamMatesCallback(player, ratings);
	end
end

local function eventHandler(self, event, ...)
	print("got event: " .. event)
	if event == "ADDON_LOADED" then
		eventFrame:UnregisterEvent("ADDON_LOADED");
		Soloqueue:WelcomeMessage();
	elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
		Soloqueue:SpecializationChanged(...);
	elseif event == "INSPECT_HONOR_UPDATE" then
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
	elseif event == "GROUP_ROSTER_UPDATE" then
		Soloqueue:RosterUpdateEventHandler();
	elseif event == "LFG_ROLE_CHECK_SHOW" then
		eventFrame:UnregisterEvent("LFG_ROLE_CHECK_SHOW");
		Soloqueue:RoleCheckEventHandler();
	elseif event == "PLAYER_ENTERING_BATTLEGROUND" then
		eventFrame:UnregisterEvent("PLAYER_ENTERING_BATTLEGROUND");
		Soloqueue:RoleCheckEventHandler();
	else
		print ("Unexpected event: " .. event);
	end
end

local function hook_dummy(a, b, c, d, e)
	print(a)
	print(b)
	print(c)
	print(d)
end

function Soloqueue:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("SoloqueueDB", {
		profile = {
			minimap = {
				hide = false,
			},
		},
	});

	SoloqueueLDB_MenuFrame = CreateFrame ("Frame", "SoloqueueLDB_MenuFrame", UIParent, "UIDropDownMenuTemplate");

	-- Commands
	self:RegisterChatCommand("soloqueue", "StateMachine");
	self:RegisterChatCommand("soloqueue-reset", "ResetState");

	-- Minimap
	icon:Register("Soloqueue", SoloqueueLDB, self.db.profile.minimap);

	-- Set up event handler
	eventFrame = CreateFrame("Frame", "SoloqueueEventFrame", UIParent)
	eventFrame:SetScript("OnEvent", eventHandler);

	-- Welcome message if required
	eventFrame:RegisterEvent("ADDON_LOADED");

	-- Watch for specialization changes
	eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED");

	-- Addon comms
	eventFrame:RegisterEvent("CHAT_MSG_WHISPER");
	self.hid = 0;

	--hooksecurefunc(C_LFGList, "Search", hook_dummy);

	hooksecurefunc(C_LFGList, "RemoveListing", function(self)
		state = STATE_GET_RATING;
	end);

	-- Init context
	self.CallbackPending = false;
	self.role = nil;
	self.CR = 0;

	-- Stack of players to get ratings from
	self.player_stack = {};

	-- Applying to groups
	self.groups = {};
	self.pendingLeader = nil
	self.retryAttempts = 0;

	-- Looking for players
	self.inviteesHealer = {};
	self.inviteesHealerFree = 0;
	self.inviteesDamager = {};
	self.inviteesDamagerFree = 0;

	-- Information about the group
	self.CRUpper = 0;
	self.CRLower = 0;
end

function Soloqueue:WelcomeMessage()
	if DisplayedWelcomeMessage == nil then
		DisplayedWelcomeMessage = true;
		bracket = 2;
		healerRequired = false;
		blacklist = {};
		self:Print("Welcome to Soloqueue. Create your macro using the minimap button.")
	end
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
	else
		self.CallbackPending = false;
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

	print ("Current state: " .. state)

	if (self.CallbackPending == true) then
		--print ("Callback pending ...")
		return;
	end

	if state == STATE_GET_RATING then
		self:GetPlayerRating();
	elseif state == STATE_LOOK_FOR_GROUP then
		self:LookForGroup();
	elseif state == STATE_APPLY_TO_GROUPS then
		self:ApplyToGroups();
	elseif state == STATE_CREATE_GROUP then
		self:CreateGroup();
	elseif state == STATE_CHECK_TEAMMATES then
		self:CheckTeammates();
	end
end

function Soloqueue:SendChatMessage(target, tid, message)
	-- Switch perspectives. Host ID becomes TID in message and vice versa
	SendChatMessage("#SQ#MSG:" .. message .. "#ROLE:" .. self.role .. "#HID:" .. tid .. "#TID:" .. self.hid, "WHISPER", nil, target)
end

function Soloqueue:RemoveInvitee(player, role)
	if not UnitInParty(player) then
		if (role == "HEALER") then
			for slot, invitee in pairs(self.inviteesHealer) do
				if invitee == player then
					self.inviteesHealer[slot] = nil;
					self.inviteesHealerFree = self.inviteesHealerFree + 1;
					break;
				end
			end
		else -- DAMAGER
			for slot, invitee in pairs(self.inviteesDamager) do
				if invitee == player then
					self.inviteesDamager[slot] = nil;
					self.inviteesDamagerFree = self.inviteesDamagerFree + 1;
					break;
				end
			end
		end
	end
end

function Soloqueue:HandshakeTimeout()
	if (state == STATE_WAITING_HANDSHAKE) then
		self.retryAttempts = self.retryAttempts + 1;
		self:Print ("No handshakes... Looking again for groups. Keep clicking button...")
		self.groups = {};
		state = STATE_LOOK_FOR_GROUP;
	end
end

function Soloqueue:InviteTimeout()
	if (state == STATE_WAITING_INVITE) then
		self:Print ("Invite didn't come...")
		self.pendingLeader = nil;
		state = STATE_LOOK_FOR_GROUP;
	end
end

function Soloqueue:AcceptInviteTimeout(name)
	if not UnitInParty(name) then
	self:Print (name .. " didn't accept invite in time... restarting group. Keep clicking button...")
	LeaveParty();
	self.pendingHandshakes = 0;
	end
end

function Soloqueue:ChatMsgEventHandler(string, sender)

	-- Is this a Soloqueue message?
	local prefix = string.match(string, "#SQ");
	if (prefix == nil) then
		return
	end

	local name = self:StripOwnRealm(sender);
	if (blacklist[name] == true) then
		return
	end

	-- Validate host ID mateches ours
	local hid = string.match(string, "#HID:(%d+)");
	if (hid == nil) then
		return
	end
	hid = tonumber(hid);

	if (hid ~= self.hid) then
		self:SendChatMessage(sender, tid, MSG_DECLINE);
		return
	end

	-- Get the target ID for responce
	local tid = string.match(string, "#TID:(%d+)");
	if (tid == nil) then
		return
	end
	tid = tonumber(tid);

	-- Get their reported role
	local senderRole = string.match(string, "#ROLE:(%a+)");
	if (senderRole == nil) then
		return
	end

	-- Finally get the message
	local msg = string.match(string, "#MSG:(%d+)");
	if (msg == nil) then
		return
	end
	msg = tonumber(msg);

	if msg == MSG_REQUEST_HANDSHAKE then
		if senderRole == "HEALER" then
			if self.inviteesHealerFree ~= 0 then
				table.insert(self.inviteesHealer, sender);
				self:SendChatMessage(sender, tid, MSG_HANDSHAKE);
				C_Timer.After(TIMEOUT_SEC, function () Soloqueue:RemoveInvitee(sender, senderRole) end)
				self.inviteesHealerFree = self.inviteesHealerFree - 1;
			else
				self:SendChatMessage(sender, tid, MSG_DECLINE);
			end
		else -- DAMAGER
			if self.inviteesDamagerFree ~= 0 then
				table.insert(self.inviteesDamager, sender);
				self:SendChatMessage(sender, tid, MSG_HANDSHAKE);
				C_Timer.After(TIMEOUT_SEC, function () Soloqueue:RemoveInvitee(sender, senderRole) end)
				self.inviteesDamagerFree = self.inviteesDamagerFree - 1;
			else
				if healerRequired == false and self.inviteesHealerFree ~= 0 then
					-- DPS taking a healer's spot
					table.insert(self.inviteesHealer, sender);
					self:SendChatMessage(sender, tid, MSG_HANDSHAKE);
					C_Timer.After(TIMEOUT_SEC, function () Soloqueue:RemoveInvitee(sender, senderRole) end)
					self.inviteesHealerFree = self.inviteesHealerFree - 1;
				else
					self:SendChatMessage(sender, tid, MSG_DECLINE);
				end
			end
		end
	elseif msg == MSG_HANDSHAKE then
		if (state == STATE_WAITING_HANDSHAKE) then
			self.pendingLeader = name;
			for _, group in pairs(self.groups) do
				if (group.leader == name) then
					self.CRUpper = group.high;
					self.CRLower = group.low;
					break;
				end
			end
			self.groups = {};
			eventFrame:RegisterEvent("PARTY_INVITE_REQUEST")
			state = STATE_WAITING_INVITE;
			self:SendChatMessage(sender, tid, MSG_ACCEPT_HANDSHAKE);
			C_Timer.After(TIMEOUT_SEC, function () Soloqueue:InviteTimeout(sender) end)
		else
			self:SendChatMessage(sender, tid, MSG_DECLINE);
		end
	elseif msg == MSG_ACCEPT_HANDSHAKE then
		eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
		InviteUnit(name)
		C_Timer.After(TIMEOUT_SEC, function () Soloqueue:AcceptInviteTimeout(name) end)
	elseif msg == MSG_DECLINE then
		if (state == STATE_WAIT_TEAMMATES) then
			Soloqueue:RemoveInvitee(sender, senderRole);
		end
	end
end

function Soloqueue:GetPlayerRating()
	self:ResetState();
	self.role = GetSpecializationRole(GetSpecialization());
	if (self.role ~= "HEALER") then
		self.role = "DAMAGER"
	end
	SetPVPRoles(false, (self.role == "HEALER"), (self.role == "DAMAGER"));
	self:PutPlayer("player");
	self.CallbackPending = true;
	self:InitRatingRequest();
end

function Soloqueue:GetPlayerRatingCallback(ratings)
	self.CR = ratings[bracket];
	self.retryAttempts = 0;
	state = STATE_LOOK_FOR_GROUP;
end

function Soloqueue:LookForGroup()
	self.CallbackPending = true;
	eventFrame:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED");
	local languages = C_LFGList.GetLanguageSearchFilter();
	C_LFGList.Search(FindGroupID[bracket], LFGListSearchPanel_ParseSearchTerms("Soloqueue"), 0, 8, languages)
end

function Soloqueue:LookForGroupCallback()
	local numResults, results = C_LFGList.GetSearchResults()
	if numResults > 0 then
		for _,groupID in pairs(results) do
			local _,_,_,description,_,_,_,_,_,_,_,_,leader,_ = C_LFGList.GetSearchResultInfo(groupID)
			if description then
				local prefix = string.match(description, "Soloqueue");
				local low, high = string.match(description, "#L:(%d+) #H:(%d+)");
				local tid = string.match(description, "#TID:(%d+)");
				local groupBracket = string.match(description, "#B:(%d+)");
				local groupHealerReq, groupHasHealer;
				if string.match(description, "#HEALREQ") then
					groupHealerReq = true;
				else
					groupHealerReq = false;
				end
				if string.match(description, "#HASHEALER") then
					groupHasHealer = true;
				else
					groupHasHealer = false;
				end
				low = tonumber(low);
				high = tonumber(high);
				tid = tonumber(tid);
				groupBracket = tonumber(groupBracket);
				-- Healer always meet healer requirements!
				if ((self.CR >= low) and (self.CR < high)) and (groupBracket == bracket) and ((groupHealerReq == healerRequired) or (self.role == "HEALER") or groupHasHealer) and (blacklist[leader] ~= true) then
					local group = { leader = leader, tid = tid, low = low, high = high };
					table.insert(self.groups, group);
				end
			end
		end
	end

	if (table.getn(self.groups) == 0) or self.retryAttempts == MAX_ATTEMPTS then
		state = STATE_CREATE_GROUP;
		if (self.CR >= CR_MINIMUM) then
			self.CRUpper = ratings[bracket] + CR_WINDOW_INCREMENT;
			self.CRLower = ratings[bracket] - CR_WINDOW_INCREMENT;
		else
			self.CRUpper = CR_MINIMUM;
			self.CRLower = 0;
		end

		self.inviteesHealer = {};
		self.inviteesDamager = {};

		if (bracket == BRACKET_2V2) then
			self.inviteesHealerFree = 1;
			self.inviteesDamagerFree = 1;
		elseif (bracket == BRACKET_3V3) then
			self.inviteesHealerFree = 1;
			self.inviteesDamagerFree = 2;
		elseif (bracket == BRACKET_RATEDBG) then
			self.inviteesHealerFree = 2;
			self.inviteesDamagerFree = 8;
		end

		if (self.role == "HEALER") then
			self.inviteesHealerFree = self.inviteesHealerFree - 1;
		else
			self.inviteesDamagerFree = self.inviteesDamagerFree - 1;
		end
	else
		state = STATE_APPLY_TO_GROUPS;
	end

	self.CallbackPending = false;
end

function Soloqueue:ApplyToGroups()
	state = STATE_WAITING_HANDSHAKE;
	self.hid = fastrandom(0x7fffffff);
	eventFrame:RegisterEvent("PARTY_INVITE_REQUEST")
	for _,group in pairs(self.groups) do
		self:SendChatMessage(group.leader, group.tid, MSG_REQUEST_HANDSHAKE);
	end
	C_Timer.After(TIMEOUT_SEC, function () Soloqueue:HandshakeTimeout() end)
end

function Soloqueue:ApplyToGroupsCallback(sender)
	if (sender == self.pendingLeader) then
		AcceptGroup()
		eventFrame:UnregisterEvent("PARTY_INVITE_REQUEST");
		eventFrame:RegisterEvent("GROUP_JOINED")
		self.groups = {};
	end
end

function Soloqueue:UICallback(sender)
	if IsInRaid() or IsInGroup() then
		StaticPopupSpecial_Hide(LFGInvitePopup);
		eventFrame:RegisterEvent("LFG_ROLE_CHECK_SHOW");
		state = STATE_ROLE_CHECK;
	else
		self:Print("Something went wrong... reset.")
		state = STATE_GET_RATING;
	end
	self.CallbackPending = false;
end

function Soloqueue:CreateGroup()
	state = STATE_WAIT_TEAMMATES
	local healerString
	-- If current role is healer, then healer req is removed. Unless it's ratedBG...
	if (healerRequired) then
		healerString = "#HEALREQ";
	else
		healerString = "";
	end
	if ((self.role == "HEALER") and (bracket ~= BRACKET_RATEDBG)) then
		healerString = healerString .. "#HASHEALER"
	end
	self:Print ("No groups found. Creating group for ratings " .. self.CRLower .. ":" .. self.CRUpper);

	self.hid = fastrandom(0x7fffffff);
	C_LFGList.CreateListing(CreateGroupID[bracket], "Soloqueue", 0, 0, "", "Do not join. #TID:" .. self.hid .. " #L:" .. self.CRLower .. " #H:" .. self.CRUpper .. "#B:" .. bracket .. healerString, false, false);
	self.pendingHandshakes = 0;
end

function Soloqueue:RosterUpdateEventHandler()
	if (state == STATE_WAIT_TEAMMATES) then
		local numPlayers = GetNumGroupMembers();
		if (numPlayers == bracketNumPlayers[bracket]) then
			eventFrame:UnregisterEvent("GROUP_ROSTER_UPDATE");
			StaticPopupSpecial_Hide(StaticPopup1)
			self:Print("Full group. Keep pressing button...")
			eventFrame:RegisterEvent("PLAYER_ENTERING_BATTLEGROUND");
			state = STATE_WAIT_BG_ENTRY;
		end
	end
end

function Soloqueue:RoleCheckEventHandler()
	CompleteLFGRoleCheck(true);
	eventFrame:RegisterEvent("PLAYER_ENTERING_BATTLEGROUND");
	state = STATE_WAIT_BG_ENTRY;
end

function Soloqueue:BattlegroundEventHandler()
	self:Print("Entered arena. Press button to check teammates ratings are legit.")
	state = STATE_CHECK_TEAMMATES;
end

function Soloqueue:CreateMacro()
	local text =
[[
/soloqueue
/run TogglePVPUI()
/click PVPQueueFrameCategoryButton2
/click ConquestFrame.RatedBG
/click ConquestJoinButton
/click ConquestFrame.Arena3v3
/click ConquestJoinButton
/click ConquestFrame.Arena2v2
/click ConquestJoinButton
/run TogglePVPUI()
]]

	DeleteMacro("Soloqueue")
	CreateMacro("Soloqueue", "Achievement_arena_2v2_7", text)
	self:Print("Created macro \"Soloqueue\" under General Macros. Place it on your bars and spam it to join your game.")
end

function Soloqueue:ResetState()
	self.CallbackPending = false;
	C_LFGList.RemoveListing();
	LeaveParty();
end

function Soloqueue:CheckTeammates()
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
	if (ratings[bracket] < self.CRLower or ratings[bracket] >= self.CRUpper) then
		local cheater;
		local name, realm = UnitName(player);
		if (realm == nil) then
			cheater = name;
		else
			cheater = name .. "-" .. realm;
		end
		self:PrintRatings(player, ratings);
		self.Print("Cheater caught! Blacklisted " .. cheater)
		blacklist[cheater] = true;
	else
		self:Print ("Validated " .. player)
	end
end

----------------------------------------------------------
-- Straight copy paste. Credit goes to Maunotavast-Zenedar
-- https://eu.battle.net/forums/en/wow/topic/15161349869
----------------------------------------------------------

local function createbutton(button)
	if _G[button] then return _G[button] end -- button already exists

	local v = _G
	for w in button:gmatch("[^%.]+") do
		v = v[w]
		if v == nil then return end
	end

	local b = CreateFrame("button", button, nil, "SecureActionButtonTemplate")
	b:RegisterForClicks("AnyDown")
	b:SetAttribute("type","click")
	b:SetAttribute("clickbutton", v)
	-- print("proxybutton created: "..button)

	return b
end

local function createbuttons(buttons)
	for _, button in ipairs(buttons) do
		createbutton(button)
	end
end

--------------------------
-- Dynamic button creating
--------------------------
-- we'll hook into strmatch and check for a specific pattern being used to see if we're /clicking.
-- it's the only sensible place to do this, really!
-- feel free to remove this section if you don't need it :P

local BTN_MATCH_PATTERN = "([^%s]+)%s+([^%s]+)%s*(.*)"

local function findbtn(action, pattern)
	if InCombatLockdown() then
		return
	end

	if pattern == BTN_MATCH_PATTERN then
		-- we're calling match here again, but it's not actually the SAME function we hooked into
		-- so no need to worry about infinite recursion
		name = action:match(BTN_MATCH_PATTERN) or action

		local b = createbutton(name)
	-- print(b and ("button found: "..name) or ("no button found: "..name))
	end
end

hooksecurefunc("strmatch", findbtn)

--------------------------
--------------------------

-- To preload buttons:

UIParentLoadAddOn("Blizzard_PVPUI") -- load pvpui so the buttons exist in the first place

createbuttons{
	"ConquestFrame.Arena2v2",
	"ConquestFrame.Arena3v3",
	"ConquestFrame.RatedBG"
}

function Soloqueue:Test()

end