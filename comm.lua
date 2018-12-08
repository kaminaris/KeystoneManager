local _, KeystoneManager = ...;

local ArrayPush = tinsert;
local ArrayRemove = tremove;
local StringFormat = format;
local StringSplit = strsplit;
local IPairs = ipairs;
local Pairs = pairs;
local ToNumber = tonumber;

local GetTime = GetTime;
local SendAddonMessage = C_ChatInfo.SendAddonMessage;
local RegisterAddonMessagePrefix = C_ChatInfo.RegisterAddonMessagePrefix;

local Comm = KeystoneManager:NewModule('Comm', 'AceTimer-3.0', 'AceEvent-3.0');
Comm.Queue = {};
Comm.MessagePrefix = 'AstralKeys';
Comm.SendingInProgress = false;

function Comm:Enable()
	self.db = KeystoneManager.db;
	self:RegisterEvent('CHAT_MSG_ADDON', 'ChatAddonMsg');
	self:RegisterEvent('PLAYER_ENTERING_WORLD', 'PlayerEnteringWorld');
	RegisterAddonMessagePrefix('AstralKeys');
end

function Comm:PlayerEnteringWorld()
	self:RequestGuildKeys();
end

--- Pure communication protocols ---------------------------------------------------------------------------------------

function Comm:StartSending()
	if self.SendingInProgress then
		return;
	end

	self.timer = self:ScheduleRepeatingTimer('Ticker', 0.2);
end

function Comm:Ticker()
	if #self.Queue == 0 then
		if self.timer then
			self:CancelTimer(self.timer);
			self.SendingInProgress = false;
		end
		return;
	end

	local messageToSend = self:PopQueue();
	if not messageToSend and self.timer then
		self:CancelTimer(self.timer);
		self.SendingInProgress = false;
		return;
	end

	self:SendMessage(messageToSend);
end

function Comm:AddToQueue(prefix, data, channel)
	for _, item in IPairs(self.Queue) do
		if item.data == data and item.channel == channel then
			return;
		end
	end

	ArrayPush(self.Queue, {
		prefix  = prefix,
		data    = data,
		channel = channel
	});
end

function Comm:PopQueue()
	return ArrayRemove(self.Queue, 1);
end

function Comm:SendMessage(entry)
	local message = entry.prefix;
	if entry.data and entry.data:len() > 0 then
		message = message .. ' ' .. entry.data;
	end

	SendAddonMessage(self.MessagePrefix, message, entry.channel or 'GUILD');
end

function Comm:ChatAddonMsg(_, prefix, message, distribution, sender)
	local name = KeystoneManager:NameAndRealm();
	if sender == name then
		return;
	end

	if prefix == 'AstralKeys' then
		local method = message:match('%w+');

		if method == 'request' then
			self:RespondKeys();
		elseif method == 'sync5' then
			message = message:sub(6);
			self:GatherGuildKeys(message);
		end
	end
end

--- Keystone formatting, sending and requesting ------------------------------------------------------------------------

function Comm:FormatKeystone(keyInfo)
	local timestamp, week = KeystoneManager:TimeStamp();

	return StringFormat(
		'%s:%s:%s:%s:%s:%s:%s_',
		keyInfo.name,
		keyInfo.class or 'MAGE',
		keyInfo.mapId,
		keyInfo.level,
		keyInfo.weeklyBest or '0',
		week,
		timestamp
	);
end

local lastResponded = 0;
function Comm:RespondKeys()
	local now = GetTime();
	if now - lastResponded < 5 then return; end
	lastResponded = now;

	local currentGuild = GetGuildInfo('player');

	for name, keyInfo in Pairs(self.db.keystones) do
		if keyInfo.guild == currentGuild then
			local oneChar = Comm:FormatKeystone(keyInfo);
			self:AddToQueue('sync5', oneChar);
		end
	end

	for name, keyInfo in Pairs(self.db.guildKeys) do
		-- Send only to current guild and not self keys
		if keyInfo.guild == currentGuild and not self.db.keystones[name] then
			local oneChar = self:FormatKeystone(keyInfo);
			self:AddToQueue('sync5', oneChar);
		end
	end

	self:StartSending();
end


local function trim(s)
	return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function Comm:GatherGuildKeys(message)
	local guildKeys = {StringSplit('_', message)};

	if not self.db.guildKeys then
		self.db.guildKeys = {};
	end

	local guild = GetGuildInfo('player');

	for i = 1, #guildKeys do
		local name, class, mapId, level, weekly, week, timestamp = StringSplit(':', guildKeys[i]);
		name = trim(name);

		if name and name ~= nil and name ~= '' and name:find('-') and not self.db.keystones[name] then
			local shortName = KeystoneManager:NameWithoutRealm(name);

			mapId = ToNumber(mapId);
			level = ToNumber(level);
			weekly = ToNumber(weekly);
			week = ToNumber(week);
			timestamp = ToNumber(timestamp);

			if mapId and level then
				local mapName = KeystoneManager.mapNames[mapId];

				self.db.guildKeys[name] = {
					name      = name,
					shortName = shortName,
					class     = class,
					mapId     = mapId,
					mapName   = mapName,
					level     = level,
					week      = week,
					weekly    = weekly,
					timestamp = timestamp,
					guild     = GetGuildInfo(name) or guild
				};
			end
		end
	end

	KeystoneManager:RefreshGuildKeyTable();
end

local lastRequested = 0;
function Comm:RequestGuildKeys()
	local now = GetTime();
	if now - lastRequested < 5 then
		KeystoneManager:Print('Can only request guild keys once per 5 seconds');
		return;
	end
	lastRequested = now;

	self:AddToQueue('request');
	self:StartSending();
end