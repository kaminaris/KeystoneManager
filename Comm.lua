local _, KeystoneManager = ...;

local ArrayPush = tinsert;
local ArrayRemove = tremove;
local StringFormat = format;
local StringSplit = strsplit;
local IPairs = ipairs;
local Pairs = pairs;
local ToNumber = tonumber;

local GetTime = GetTime;
local GetGuildInfo = GetGuildInfo;

local LibDeflate = LibStub:GetLibrary('LibDeflate');

local Comm = KeystoneManager:NewModule('Comm', 'AceTimer-3.0', 'AceEvent-3.0', 'AceSerializer-3.0', 'AceComm-3.0');
Comm.MessagePrefix = 'AstralKeys';
Comm.MessagePrefix2 = 'KeystoneManager';
Comm.SendingInProgress = false;
Comm.CurrentGuild = nil;

--- Generic functions --------------------------------------------------------------------------------------------------

function Comm:OnEnable()
	self.db = KeystoneManager.db;
	self:RegisterEvent('PLAYER_ENTERING_WORLD', 'PlayerEnteringWorld');
	self:RegisterComm(self.MessagePrefix, 'AstralHandleMessage');
	self:RegisterComm(self.MessagePrefix2, 'HandleMessage');
	self.CurrentGuild = GetGuildInfo('player');
	self:RegisterEvent('CHAT_MSG_GUILD', 'GuildMessageCheckKeystone');
end

--local function tIndexOf(table, item)
--	local index = 1;
--	while table[index] do
--		if ( item == table[index] ) then
--			return 1;
--		end
--		index = index + 1;
--	end
--	return nil;
--end

function Comm:GuildMessageCheckKeystone(_, msg, playerName, ...)
	if msg:find('Hkeystone:') then
		local splitted = { strsplit(':', msg) };
		local idx = tIndexOf(splitted, '180653');

		if not idx then return end;

		local mapId = tonumber(splitted[idx + 1]);
		local level = tonumber(splitted[idx + 2]);
		local timestamp, week = KeystoneManager:TimeStamp();

		local keyInfo = {
			name       = playerName,
			shortName  = KeystoneManager:NameWithoutRealm(playerName),
			class      = 'MAGE',
			weeklyBest = 0,
			mapId      = mapId,
			timestamp  = timestamp,
			week       = week,
			mapName    = KeystoneManager.mapNames[mapId],
			level      = level,
			guild      = self.CurrentGuild
		};

		if not self.db.guildKeys[playerName] then
			self.db.guildKeys[playerName] = keyInfo;
		else
			self.db.guildKeys[playerName].class = keyInfo.class;
			self.db.guildKeys[playerName].guild = keyInfo.guild;
			self.db.guildKeys[playerName].level = keyInfo.level;
			self.db.guildKeys[playerName].mapId = keyInfo.mapId;
			self.db.guildKeys[playerName].timestamp = keyInfo.timestamp;
			self.db.guildKeys[playerName].week = keyInfo.week;
			self.db.guildKeys[playerName].mapName = keyInfo.mapName;
		end
	else
		print('no key')
	end
end

function Comm:PlayerEnteringWorld()
	self:RequestGuildKeys();
	self.CurrentGuild = GetGuildInfo('player');
	self:RegisterEvent('CHAT_MSG_GUILD', 'GuildMessageCheckKeystone');
end


function Comm:CompressAndEncode(input)
	local compressed = LibDeflate:CompressDeflate(self:Serialize(input));
	return LibDeflate:EncodeForWoWAddonChannel(compressed);
end

function Comm:DecompressAndDecode(input)
	local decoded = LibDeflate:DecodeForWoWAddonChannel(input);
	local success, deserialized = self:Deserialize(LibDeflate:DecompressDeflate(decoded));
	if not success then
		KeystoneManager:Print('There was issue with receiving guild keys, please report this to Addon Author.')
	end
	return deserialized;
end

function Comm:CombineKeystones()
	local keystones = {};

	for name, keyInfo in Pairs(self.db.guildKeys) do
		-- Send only to current guild and not self keys
		if keyInfo.guild == self.CurrentGuild and not self.db.keystones[name] then
			keystones[name] = keyInfo;
		end
	end

	-- Override guild keys with own keys
	for name, keyInfo in Pairs(self.db.keystones) do
		if keyInfo.guild == self.CurrentGuild then
			keystones[name] = keyInfo;
		end
	end

	return keystones;
end

local lastRequested = 0;
function Comm:RequestGuildKeys()
	local now = GetTime();
	if now - lastRequested < 5 then
		KeystoneManager:Print('Can only request guild keys once per 5 seconds');
		return;
	end
	lastRequested = now;

	self:SendCommMessage(self.MessagePrefix, 'request', 'GUILD');
	self:SendCommand('request');
end

--- KeystoneManager communication --------------------------------------------------------------------------------------

function Comm:SendCommand(command, data)
	local request = {
		command = command,
		data = data
	};

	local message = self:CompressAndEncode(request);
	self:SendCommMessage(self.MessagePrefix2, message, 'GUILD');
end

function Comm:HandleMessage(prefix, message, _, sender)
	if prefix ~= self.MessagePrefix2 or sender == UnitName('player') then
		return;
	end

	local request = self:DecompressAndDecode(message);

	if not request then
		KeystoneManager:Print('Communication error from: ' .. sender);
		return;
	end

	if request.command == 'request' then
		self:SendAllKeys();
	elseif request.command == 'updateKeys' then
		local data = self:DecompressAndDecode(request.data);
		Comm:ReceiveKeys(data);
	end
end

function Comm:SendAllKeys()
	local keystones = self:CombineKeystones();

	local serializedKeys = self:CompressAndEncode(keystones);
	self:SendCommand('updateKeys', serializedKeys);
end

function Comm:ReceiveKeys(keystones)
	if type(keystones) ~= 'table' then return end

	for name, keyInfo in Pairs(keystones) do
		if not self.db.guildKeys[name] then
			self.db.guildKeys[name] = keyInfo;
		else
			local dbKey = self.db.guildKeys[name];

			if dbKey.timestamp < keyInfo.timestamp then
				self.db.guildKeys[name] = keyInfo;
			else
				if not dbKey.weeklyBest or dbKey.weeklyBest < keyInfo.weeklyBest then
					dbKey.weeklyBest = keyInfo.weeklyBest;
				end
			end
		end
	end

	KeystoneManager:RefreshGuildKeyTable();
end

function Comm:SendNewKey()
	local keystones = {};

	local name = KeystoneManager:NameAndRealm();
	local keystone = KeystoneManager.db.keystones[name];
	if not keystone then
		-- Should not happen
		KeystoneManager:Print('Error occurred while trying to update keystone');
		return;
	end

	-- Just one keystone
	keystones[name] = keystone;
	local serializedKeys = self:CompressAndEncode(keystones);
	self:SendCommand('updateKeys', serializedKeys);
end

--- AstralKeys communication -------------------------------------------------------------------------------------------

function Comm:AstralHandleMessage(prefix, message, _, sender)
	if prefix ~= self.MessagePrefix or sender == UnitName('player') then
		return;
	end

	local method = message:match('%w+');
	if method == 'request' then
		self:AstralSendAllKeys();
	elseif method == 'sync5' then
		message = message:sub(6);
		self:AstralReceiveKeys(message);
	elseif method == 'updateV8' then
		message = message:sub(9);
		self:AstralReceiveKeys(message);
	end
end

function Comm:AstralFormatKeystone(keyInfo)
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
function Comm:AstralSendAllKeys()
	local now = GetTime();
	if now - lastResponded < 5 then return; end
	lastResponded = now;

	local keystones = self:CombineKeystones();

	-- Respond to AstralKeys
	for _, keyInfo in IPairs(keystones) do
		local oneChar = Comm:AstralFormatKeystone(keyInfo);
		self:SendCommMessage(self.MessagePrefix, 'sync5 ' .. oneChar, 'GUILD');
	end
end

function Comm:AstralSendNewKey()
	local name = KeystoneManager:NameAndRealm();
	local keystone = KeystoneManager.db.keystones[name];
	if not keystone then
		-- Should not happen
		KeystoneManager:Print('Error occurred while trying to update keystone');
		return;
	end

	local oneChar = Comm:AstralFormatKeystone(keystone);
	self:SendCommMessage(self.MessagePrefix, 'sync5 ' .. oneChar, 'GUILD');
end

local function trim(s)
	return (s:gsub('^%s*(.-)%s*$', '%1'))
end

-- AstralKeys compat
function Comm:AstralReceiveKeys(message)
	local guildKeys = {StringSplit('_', message)};

	if not self.db.guildKeys then
		self.db.guildKeys = {};
	end

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
			if not timestamp then
				timestamp = 1;
			end

			if mapId and level then
				local mapName = KeystoneManager.mapNames[mapId];

				if weekly == 1 then
					weekly = 10;
				end

				local newKey = {
					name       = name,
					shortName  = shortName,
					class      = class,
					mapId      = mapId,
					mapName    = mapName,
					level      = level,
					week       = week,
					weeklyBest = weekly,
					timestamp  = timestamp,
					guild      = GetGuildInfo(name) or self.CurrentGuild
				};

				if not self.db.guildKeys[name] then
					self.db.guildKeys[name] = newKey;
				else
					local oldKey = self.db.guildKeys[name];

					-- Don't update if we had new key
					if oldKey.timestamp == 1 or oldKey.timestamp < newKey.timestamp then
						local oldWeeklyBest = oldKey.weeklyBest;
						local newWeeklyBest = newKey.weeklyBest;
						self.db.guildKeys[name] = newKey;

						-- If old key had higher weeklyBest we keep it
						if oldWeeklyBest and (not newWeeklyBest or newWeeklyBest < oldKey.weeklyBest) then
							self.db.guildKeys[name].weeklyBest = oldWeeklyBest;
						end
					end
				end
			end
		end
	end

	KeystoneManager:RefreshGuildKeyTable();
end