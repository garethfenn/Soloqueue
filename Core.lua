Soloqueue = LibStub("AceAddon-3.0"):NewAddon("Soloqueue", "AceConsole-3.0");
local eventFrame = nil

-- States
local STATE_GET_RATING, STATE_LOOK_FOR_GROUP, STATE_APPLY_TO_GROUPS, STATE_WAITING_HANDSHAKE, STATE_WAITING_INVITE,
      STATE_CREATE_GROUP, STATE_WAIT_TEAMMATES, STATE_DELIST_GROUP, STATE_ROLE_CHECK, STATE_CHECK_TEAMMATES = 0, 1, 2, 3, 4, 5, 6, 7, 8, 9;
local state = STATE_GET_RATING;

-- Messages
local MSG_REQUEST_HANDSHAKE, MSG_HANDSHAKE, MSG_ACCEPT_HANDSHAKE, MSG_DECLINE = 0, 1, 2, 3;

-- Sometimes the ratings are not available first time around
local attempts = 0
local MAX_ATTEMPTS = 3

-- 5v5 isn't used anymore...
local BRACKETS = { "2v2", "3v3", "5v5", "RBG" }

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
			{ text = "2v2", notCheckable = false, checked = function() return (playersToInvite == 1) end, func = function() playersToInvite = 1; bracket = 1; end },
			{ text = "3v3", notCheckable = false, checked = function() return (playersToInvite == 2) end, func = function() playersToInvite = 2; bracket = 2; end },
			{ text = "RatedBG", notCheckable = false, checked = function() return (playersToInvite == 9) end, func = function() playersToInvite = 9; bracket = 4 end },
		}
	},
	{
		text = "Create macro",
		notCheckable = true,
		func = function() Soloqueue:CreateMacro(); end,
	},
	{
		text = "Reset state",
		notCheckable = true,
		func = function() Soloqueue:ResetState(); end,
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

function Soloqueue:PrintRatings(player, ratings)
	local name = UnitName(player);
	print(name .. " ratings:");
	for i, r in pairs(ratings) do
		print (BRACKETS[i] .. " : " .. r)
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
	--print("got event:" .. event)
	if event == "ADDON_LOADED" then
		eventFrame:UnregisterEvent("ADDON_LOADED");
		Soloqueue:WelcomeMessage();
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
	else
		print ("Unexpected event: " .. event);
	end
end

local function hook_SetAction(a, b, c, d, e)
	print(type(a))
	print(a)
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

	-- Minimap
	icon:Register("Soloqueue", SoloqueueLDB, self.db.profile.minimap);

	-- Set up event handler
	eventFrame = CreateFrame("Frame", "SoloqueueEventFrame", UIParent)
	eventFrame:SetScript("OnEvent", eventHandler);

	-- Welcome message if required
	eventFrame:RegisterEvent("ADDON_LOADED");

	-- Addon comms
	eventFrame:RegisterEvent("CHAT_MSG_WHISPER");
	self.hid = 0;

	-- Default DPS role.
	SetPVPRoles(false, false, true)

	hooksecurefunc(C_LFGList, "RemoveListing", function(self)
		if (state == STATE_WAIT_TEAMMATES) then
			state = STATE_GET_RATING;
		end
	end);

	-- Init context
	self.CallbackPending = false;
	self.CR = 0;

	-- Stack of players to get ratings from
	self.player_stack = {};

	-- Applying to groups
	self.leaders = {};
	self.leadersTID = {};
	self.pendingLeader = nil

	-- Looking for players
	self.CRUpper = 0;
	self.CRLower = 0;
	self.pendingHandshakes = 0;
	self.invitees = {};
end

function Soloqueue:WelcomeMessage()
	if DisplayedWelcomeMessage == nil then
		DisplayedWelcomeMessage = true;
		playersToInvite = 2;
		bracket = 2;
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
	elseif state == STATE_DELIST_GROUP then
		self:DelistGroup();
	end
end

function Soloqueue:SendChatMessage(target, tid, message)
	-- Switch perspectives. Host ID becomes TID in message and vice versa
	SendChatMessage("#SQ#MSG:" .. message .. "#HID:" .. tid .. "#TID:" .. self.hid, "WHISPER", nil, target)
end

function Soloqueue:RemoveInvitee(player)
	if not UnitInParty(player) then
		for slot, invitee in pairs(self.invitees) do
			if invitee == player then
				self.invitees[slot] = nil;
				self.pendingHandshakes = self.pendingHandshakes + 1;
				break;
			end
		end
	end
end

function Soloqueue:HandshakeTimeout()
	if (state == STATE_WAITING_HANDSHAKE) then
		self:Print ("No handshakes... Looking again for groups. Keep clicking button...")
		self.leaders = {};
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
	self:Print (name .. " didn't accept timeout in time... restarting group. Keep clicking button...")
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

	-- Validate host ID mateches ours
	local hid = string.match(string, "#HID:(%d+)");
	if (hid == nil) then
		return
	end
	hid = tonumber(hid);
	if (hid ~= self.hid) then
		return
	end

	-- Get the target ID for responce
	local tid = string.match(string, "#TID:(%d+)");
	if (tid == nil) then
		return
	end
	tid = tonumber(tid);

	-- Finally get the message
	local msg = string.match(string, "#MSG:(%d+)");
	if (msg == nil) then
		return
	end
	msg = tonumber(msg);

	if msg == MSG_REQUEST_HANDSHAKE then
		local freeHandshakes = (playersToInvite - self.pendingHandshakes);
		if (freeHandshakes > 0) then
			table.insert(self.invitees, sender);
			self:SendChatMessage(sender, tid, MSG_HANDSHAKE);
			C_Timer.After(2, function () Soloqueue:RemoveInvitee(sender) end)
			self.pendingHandshakes = self.pendingHandshakes + 1;
		else
			self:SendChatMessage(sender, tid, MSG_DECLINE);
		end
	elseif msg == MSG_HANDSHAKE then
		if (state == STATE_WAITING_HANDSHAKE) then
			self.pendingLeader = sender;
			self.leaders = {};
			eventFrame:RegisterEvent("PARTY_INVITE_REQUEST")
			self:SendChatMessage(sender, tid, MSG_ACCEPT_HANDSHAKE);
			C_Timer.After(2, function () Soloqueue:InviteTimeout(sender) end)
			state = STATE_WAITING_INVITE;
		else
			self:SendChatMessage(sender, tid, MSG_DECLINE);
		end
	elseif msg == MSG_ACCEPT_HANDSHAKE then
		eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
		InviteUnit(sender)
		C_Timer.After(2, function () Soloqueue:AcceptInviteTimeout(sender) end)
	elseif msg == MSG_DECLINE then
		print ("Declined!");
		if (state == STATE_WAIT_TEAMMATES) then
			Soloqueue:RemoveInvitee(sender);
		end
	end
end

function Soloqueue:GetPlayerRating()
	self:PutPlayer("player");
	self.CallbackPending = true;
	self:InitRatingRequest();
end

function Soloqueue:GetPlayerRatingCallback(ratings)
	self.CR = ratings[bracket];
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
				local prefix = string.match(description, "Soloqueue");
				local low, high = string.match(description, "#L:(%d+) #H:(%d+)");
				local tid = string.match(description, "#TID:(%d+)");
				low = tonumber(low);
				high = tonumber(high);
				tid = tonumber(tid);
				if ((self.CR >= low) and (self.CR < high)) then
					table.insert(self.leaders, leader);
					table.insert(self.leadersTID, tid);
				end
			end
		end
	end

	if (table.getn(self.leaders) == 0) then
		state = STATE_CREATE_GROUP;
		if (self.CR >= CR_MINIMUM) then
			self.CRUpper = ratings[bracket] + CR_WINDOW_INCREMENT;
			self.CRLower = ratings[bracket] - CR_WINDOW_INCREMENT;
		else
			self.CRUpper = CR_MINIMUM;
			self.CRLower = 0;
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
	for i,leader in pairs(self.leaders) do
		self:SendChatMessage(leader, self.leadersTID[i], MSG_REQUEST_HANDSHAKE);
	end
	C_Timer.After(2, function () Soloqueue:HandshakeTimeout() end)
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
	self:Print ("No groups found. Creating group for ratings " .. self.CRLower .. ":" .. self.CRUpper);
	self.hid = fastrandom(0x7fffffff);
	C_LFGList.CreateListing(16, "Soloqueue", 0, 0, "", "Do not join. #TID:" .. self.hid .. " #L:" .. self.CRLower .. " #H:" .. self.CRUpper, false, true); -- arena 7
	self.pendingHandshakes = 0;
end

function Soloqueue:RosterUpdateEventHandler()
	if (state == STATE_WAIT_TEAMMATES) then
		local numPlayers = GetNumGroupMembers();
		if (numPlayers == (playersToInvite + 1)) then -- including ourselves
			eventFrame:UnregisterEvent("GROUP_ROSTER_UPDATE");
			state = STATE_DELIST_GROUP;
		end
	end
end

function Soloqueue:DelistGroup()
	self:Print("Full group. Press button to queue arena!")
	C_LFGList.RemoveListing();
	eventFrame:RegisterEvent("LFG_ROLE_CHECK_SHOW");
	state = STATE_CHECK_TEAMMATES;
end

function Soloqueue:RoleCheckEventHandler()
	CompleteLFGRoleCheck(true);
	state = STATE_CHECK_TEAMMATES;
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
	self:Print("Created Soloqueue macro. Spam it to join your game.")
end

function Soloqueue:ResetState()
	self.CallbackPending = false;
	C_LFGList.RemoveListing();
	state = STATE_GET_RATING;
	self:Print("Reset state")
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