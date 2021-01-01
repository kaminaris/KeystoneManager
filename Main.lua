local addonName, KeystoneManager = ...;

LibStub('AceAddon-3.0'):NewAddon(KeystoneManager, 'KeystoneManager', 'AceConsole-3.0', 'AceEvent-3.0', 'AceTimer-3.0');
_G[addonName] = KeystoneManager;

---@type StdUi
local StdUi = LibStub('StdUi');

local shortNames = {
	[197] = 'EOA',
	[198] = 'DHT',
	[199] = 'BRH',
	[200] = 'HOV',
	[206] = 'NL',
	[207] = 'VOTW',
	[208] = 'MOS',
	[209] = 'ARC',
	[210] = 'COS',
	[233] = 'COEN',
	[227] = 'KARA:L',
	[234] = 'KARA:U',
	[239] = 'SOTT',

	[244] = 'AD',
	[245] = 'FH',
	[246] = 'TD',
	[247] = 'ML',
	[248] = 'WM',
	[249] = 'KR',
	[250] = 'TOS',
	[251] = 'UNDR',
	[252] = 'SOTS',
	[353] = 'SIEGE',

	[375] = 'MOTS',
	[376] = 'NW',
	[377] = 'DOS',
	[378] = 'HOA',
	[379] = 'PF',
	[380] = 'SD',
	[381] = 'SOA',
	[382] = 'TOP',
};

local activities = {
	[197] = 459,
	[198] = 460,
	[199] = 463,
	[200] = 461,
	[206] = 462,
	[207] = 464,
	[208] = 465,
	[209] = 467,
	[210] = 466,
	[233] = 476,
	[227] = 471,
	[234] = 473,
	[239] = 486,

	[244] = 502,
	[245] = 518,
	[246] = 526,
	[247] = 510,
	[248] = 530,
	[249] = 514,
	[250] = 504,
	[251] = 507,
	[252] = 522,
	[353] = 534,
};

function KeystoneManager:OnInitialize()
	self:InitializeDatabase();

	self:ValidateKeys();
	self:RegisterOptionWindow();

	self:RegisterChatCommand('keystonemanager', 'ShowWindow');
	self:RegisterChatCommand('keylist', 'ShowWindow');
	self:RegisterChatCommand('keyprint', 'PrintKeystone');
	self:RegisterChatCommand('keyreport', 'ReportKeys');

	self:RegisterEvent('PLAYER_ENTERING_WORLD');

	self:RegisterEvent('CHALLENGE_MODE_MAPS_UPDATE', 'UpdateWeeklyBest');
	self:RegisterEvent('CHALLENGE_MODE_MEMBER_INFO_UPDATED', 'UpdateWeeklyBest');
	self:RegisterEvent('CHALLENGE_MODE_LEADERS_UPDATE', 'UpdateWeeklyBest');
	self:RegisterEvent('CHALLENGE_MODE_COMPLETED', 'UpdateWeeklyBestAndKeystone');
	self:RegisterEvent('BAG_UPDATE_DELAYED', 'GetKeystone');

	self:EnableModule('Comm');
	self.Comm = self:GetModule('Comm');
end

function KeystoneManager:PLAYER_ENTERING_WORLD()
	if self.onceRequested then
		self:RefreshDataText();
		self:GetKeystone();
		return;
	else
		C_MythicPlus.RequestMapInfo();
		self:GetMapInfo();
	end

	-- Can't really request it faster
	C_Timer.After(5, function()
		for mapId, _ in pairs(self.mapNames) do
			C_ChallengeMode.RequestLeaders(mapId);
		end

		self:RefreshDataText();
		self:GetKeystone();

		self.onceRequested = true;
	end);
end

function KeystoneManager:ValidateKeys()
	if not self.db.keystones then self.db.keystones = {}; end;
	if not self.db.guildKeys then self.db.guildKeys = {}; end;

	local _, week = self:TimeStamp();
	for name, keyInfo in pairs(self.db.keystones) do
		if not keyInfo.week or keyInfo.week < week or not keyInfo.guild or not keyInfo.shortName then
			self.db.keystones[name] = nil;
		end
	end

	for name, keyInfo in pairs(self.db.guildKeys) do
		if not keyInfo.week or keyInfo.week < week or not keyInfo.guild or not keyInfo.shortName or not keyInfo.weeklyBest then
			self.db.guildKeys[name] = nil;
		end
	end
end

function KeystoneManager:ClearGuildKeys()
	wipe(self.db.guildKeys);
end

function KeystoneManager:ShowGuildKeys()
	if self.guildKeysWindow then
		self.guildKeysWindow:Show();
		if self.KeystoneWindow:IsVisible() then
			self.guildKeysWindow:ClearAllPoints();
			self.guildKeysWindow:SetPoint('LEFT', self.KeystoneWindow, 'RIGHT', 10, 0);
		end
		self:RefreshGuildKeyTable();
		return;
	end

	local guildKeysWindow = StdUi:Window(nil, 500, 550, 'Guild Keys');
	guildKeysWindow:SetPoint('CENTER');
	self.guildKeysWindow = guildKeysWindow;

	StdUi:EasyLayout(guildKeysWindow, { padding = { top = 40 } });

	local refreshBtn = StdUi:Button(guildKeysWindow, nil, 20, 'Refresh');
	refreshBtn:SetScript('OnClick', function () self.Comm:RequestGuildKeys(); self:RefreshGuildKeyTable(); end);

	local clearBtn = StdUi:Button(guildKeysWindow, nil, 20, 'Clear');
	clearBtn:SetScript('OnClick', function () self:ClearGuildKeys(); self:RefreshGuildKeyTable(); end);

	local cols = {
		{
			name  = 'Character',
			width = 120,
			index = 'name',
			color = function (_, _, rowData)
				local r, g, b = GetClassColor(rowData.class);
				return { r = r, g = g, b = b, a = 1};
			end,
		},
		{
			name  = 'Weekly Best',
			width = 100,
			index = 'weeklyBest'
		},
		{
			name  = 'Dungeon',
			width = 165,
			index = 'mapName',
		},
		{
			name  = 'Level',
			width = 80,
			index = 'level',
			type  = 'number'
		},
	}

	guildKeysWindow.table = StdUi:ScrollTable(guildKeysWindow, cols, 16, 20);

	self:RefreshGuildKeyTable();
	local btnRow = guildKeysWindow:AddRow();

	btnRow:AddElement(refreshBtn, { column = 4 });
	btnRow:AddElement(clearBtn, { column = 4 });
	guildKeysWindow:AddRow({ margin = {top = 30}}):AddElement(guildKeysWindow.table);
	guildKeysWindow:Show();
	guildKeysWindow:DoLayout();

	if self.KeystoneWindow:IsVisible() then
		self.guildKeysWindow:ClearAllPoints();
		self.guildKeysWindow:SetPoint('LEFT', self.KeystoneWindow, 'RIGHT', 10, 0);
	end
end

function KeystoneManager:RefreshGuildKeyTable()
	if not self.guildKeysWindow or not self.guildKeysWindow.table then
		return;
	end

	local data = {};
	local currentGuild = GetGuildInfo('player');

	for _, keyInfo in pairs(self.db.guildKeys) do
		if (keyInfo.guild == nil or keyInfo.guild == currentGuild) and keyInfo.level then
			tinsert(data, {
				name       = keyInfo.shortName,
				class      = keyInfo.class,
				weeklyBest = keyInfo.weeklyBest,
				mapName    = keyInfo.mapName,
				level      = keyInfo.level,
				guild      = keyInfo.guild or currentGuild
			});
		end
	end

	self.guildKeysWindow.table:SetData(data, true);
end

function KeystoneManager:GetMapInfo()
	self.mapNames = {};
	local maps = C_ChallengeMode.GetMapTable();
	
	for i = 1, #maps do
		local name, id = C_ChallengeMode.GetMapUIInfo(maps[i]);
		self.mapNames[id] = name;
	end
end

function KeystoneManager:UpdateWeeklyBestAndKeystone()
	C_Timer.After(3, function()
		KeystoneManager:GetKeystone();
	end);
end

function KeystoneManager:ShowWindow(input)
	if not self.KeystoneWindow then

		self.KeystoneWindow = StdUi:Window(UIParent, 625, 550, 'Keystone Manager');

		local window = self.KeystoneWindow;
		window.titlePanel:SetBackdrop(nil);
		window:SetPoint('CENTER');
		window:SetFrameStrata('DIALOG');

		local whisperOpts = {
			{text = 'Whisper', value = 'WHISPER'},
			{text = 'Guild', value = 'GUILD'},
			{text = 'Party', value = 'PARTY'},
			{text = 'Raid', value = 'RAID'},
			{text = 'Instance', value = 'INSTANCE_CHAT'},
		}
		local target = StdUi:Dropdown(window, 120, 24, whisperOpts, self.db.target);
		StdUi:AddLabel(window, target, 'Send Message To', 'TOP');
		StdUi:GlueTop(target, window, 10, -50, 'LEFT');
		target.OnValueChanged = function(_, value, text)
			self.db.target = value;
		end;

		local whisper = StdUi:EditBox(window, 120, 24, self.db.whisper);
		StdUi:AddLabel(window, whisper, 'Whisper target', 'TOP');
		StdUi:GlueRight(whisper, target, 10, 0);
		whisper.OnValueChanged = function(_, text)
			self.db.whisper = text;
		end;

		local btn = StdUi:Button(window, 120, 24, 'Report');
		StdUi:GlueRight(btn, whisper, 10, 0);
		btn:SetScript('OnClick', function()
			self:ReportKeys();
		end);

		local gk = StdUi:Button(window, 120, 24, 'Guild Keys');
		StdUi:GlueTop(gk, window, -10, -50, 'RIGHT');
		gk:SetScript('OnClick', function()
			self:ShowGuildKeys();
		end);

		local minLevel = StdUi:NumericBox(window, 120, 24, self.db.minLevel);
		StdUi:AddLabel(window, minLevel, 'Min Level', 'TOP');
		StdUi:GlueBelow(minLevel, target, 0, -30);
		minLevel:SetMinMaxValue(0, 50);
		minLevel.OnValueChanged = function(_, val)
			self.db.minLevel = val;
		end;

		local maxLevel = StdUi:NumericBox(window, 120, 24, self.db.maxLevel);
		StdUi:AddLabel(window, maxLevel, 'Max Level', 'TOP');
		StdUi:GlueRight(maxLevel, minLevel, 10, 0);
		maxLevel:SetMinMaxValue(0, 50);
		maxLevel.OnValueChanged = function(_, val)
			self.db.maxLevel = val;
		end;

		local cols = {
			{
				name  = 'Character',
				width = 120,
				index = 'name',
				color = function (table, value, rowData, columnData)
					local r, g, b = GetClassColor(rowData.class);
					return { r = r, g = g, b = b, a = 1};
				end,
			},

			{
				name  = 'Weekly Best',
				width = 100,
				index = 'weeklyBest'
			},

			{
				name  = 'Dungeon',
				width = 165,
				index = 'mapName',
			},

			{
				name  = 'Level',
				width = 80,
				index = 'level',
				type  = 'number'
			},
		}
		self.ScrollTable = StdUi:ScrollTable(window, cols, 16, 20);
		StdUi:GlueAcross(self.ScrollTable, window, 10, -160, -10, 60);
		self:UpdateTable();

		self.ScrollTable:RegisterEvents({
			OnClick = function(table, cellFrame, rowFrame, rowData, columnData, rowIndex)
				local link = KeystoneManager:CreateLink(rowData);

				if link then
					if IsAltKeyDown() then
						KeystoneManager:CreateGroup(rowData);
					elseif IsShiftKeyDown() then
						HandleModifiedItemClick(link);
					else
						GameTooltip:SetOwner(UIParent);
						GameTooltip:SetHyperlink(link);
						GameTooltip:Show();
					end
				end
				return true;
			end,
		});

		-- Clear button
		local clearBtn = StdUi:Button(window, 120, 24, 'Report');
		StdUi:GlueBottom(clearBtn, window, -10, 10, 'RIGHT');
		clearBtn:SetText('Clear');
		clearBtn:SetScript('OnClick', function()
			self:ClearKeystones();
		end);

		-- Refresh button
		local refreshBtn = StdUi:Button(window, 120, 24, 'Refresh');
		StdUi:GlueBottom(refreshBtn, window, 10, 10, 'LEFT');
		refreshBtn:SetScript('OnClick', function()
			self:GetKeystone(true);
			self:UpdateWeeklyBest();
		end);

		-- Copy button
		local copyBtn = StdUi:Button(window, 120, 24, 'Copy Keys');
		StdUi:GlueRight(copyBtn, refreshBtn, 10, 0);
		copyBtn:SetScript('OnClick', function()
			self:ShowCopyWindow();
		end);
	end

	self.KeystoneWindow:Show();
end

function KeystoneManager:CreateLink(data)
	-- '|cffa335ee|Hkeystone:180653:244:2:10:0:0:0|h[Keystone: Atal'dazar (2)]|h|r'
	local link = string.format(
		'|cffa335ee|Hkeystone:180653:%d:%d:10:0:0:0|h[Keystone: %s (%d)]|h|r',
		data.mapId,
		data.level,
		data.mapNamePlain or data.mapName,
		data.level
	);

	return link;
end

function KeystoneManager:GetKeysText()
	local text = '';
	for char, key in pairs(self.db.keystones) do
		if 	key.level >= self.db.minLevel and
			key.level <= self.db.maxLevel
		then
			text = text .. self:NameWithoutRealm(char) .. ' - ' .. key.mapName .. ' +' .. key.level .. '\n';
		end
	end

	return text;
end

function KeystoneManager:ShowCopyWindow()
	if not self.KeystoneCopyWindow then
		local window = StdUi:Window(UIParent, 400, 350, 'Copy Keystones');
		window:SetPoint('CENTER');
		window:SetFrameStrata('FULLSCREEN_DIALOG');

		local mb = StdUi:MultiLineBox(window, 380, 300, self:GetKeysText());
		StdUi:GlueTop(mb.panel, window, 0, -40, 'CENTER');
		window.editBox = mb;
		self.KeystoneCopyWindow = window;
		return;
	end

	self.KeystoneCopyWindow:Show();
	self.KeystoneCopyWindow.editBox:SetText(self:GetKeysText());
end

function KeystoneManager:GetCurrentKeystoneInfo()
	local name = KeystoneManager:NameAndRealm();
	local keystone = KeystoneManager.db.keystones[name];

	return keystone;
end

local usResetTime = 1500390000 -- US Tuesday at reset
local euResetTime = 1500447600 -- EU Wednesday at reset
local cnResetTime = 1500505200 -- CN Thursday at reset

function KeystoneManager:TimeStamp()
	local region = GetCurrentRegion()
	local serverTime = GetServerTime();
	local resetTime = euResetTime;
	local week;

	if region == 1 then
		resetTime = usResetTime;
	elseif region == 3 then
		resetTime = euResetTime;
	elseif region == 5 then
		resetTime = cnResetTime;
	end

	week = math.floor((serverTime - resetTime) / 604800);
	return serverTime - resetTime - 604800 * week, week;
end

function KeystoneManager:GetKeystone(force)
	force = force or false;
	
	if not self.db.keystones then
		self.db.keystones = {};
	end

	local name, shortName = self:NameAndRealm();
	local _, class = UnitClass('player');
	local keystone = self.db.keystones[name];

	local mapId = C_MythicPlus.GetOwnedKeystoneChallengeMapID();
	local level = C_MythicPlus.GetOwnedKeystoneLevel();
	local weeklyBest = self:UpdateWeeklyBest();
	local mapName = self.mapNames[mapId];
	local timestamp, week = self:TimeStamp();

	if not mapId or not level then
		return nil;
	end

	local keystoneChanged = not keystone or (level ~= keystone.level or mapId ~= keystone.mapId);

	if force or keystoneChanged then
		--keystone has changed
		if self.db.announce and not force then
			SendChatMessage('Keystone Manager: ' .. mapName .. ' +' .. level, 'PARTY');
		end

		self.db.keystones[name] = {
			name       = name,
			shortName  = shortName,
			class      = class,
			mapId      = mapId,
			mapName    = mapName,
			level      = level,
			week       = week,
			weeklyBest = weeklyBest,
			timestamp  = timestamp,
			guild      = GetGuildInfo('player')
		};

		if keystoneChanged then
			self.Comm:SendNewKey();
			self.Comm:AstralSendNewKey();
		end

		self:UpdateTable(self.ScrollTable);
		self:RefreshDataText();
	end

	return keystone;
end

function KeystoneManager:UpdateWeeklyBest()
	local name = self:NameAndRealm();

	local best = C_MythicPlus.GetWeeklyChestRewardLevel();

	if self.db.keystones[name] then
		local oldBest = self.db.keystones[name].weeklyBest;
		self.db.keystones[name].weeklyBest = best;

		if oldBest ~= best then
			local timestamp = self:TimeStamp();
			self.db.keystones[name].timestamp = timestamp;
			self.Comm:SendNewKey();
			self.Comm:AstralSendNewKey();
		end
	end
	
	return best;
end

function KeystoneManager:PrintKeystone()
	local name = self:NameAndRealm();
	local keystone = self.db.keystones[name];

	if keystone then
		keystone = self:GetKeystone();
	end

	self:Print(self:CreateLink(keystone));
end

function KeystoneManager:ReportKeys()
	local target = self.db.whisper;
	if self.db.target ~= 'WHISPER' then
		target = nil;
	end

	for char, key in pairs(self.db.keystones) do
		if  key.level >= self.db.minLevel and
			key.level <= self.db.maxLevel
		then
			SendChatMessage(
				self:NameWithoutRealm(char) .. ' - ' .. key.mapName .. ' +' .. key.level,
				self.db.target,
				nil,
				target
			);
		end
	end
end

function KeystoneManager:ClearKeystones()
	self.db.keystones = {};
	self:UpdateTable(self.ScrollTable);
	self:RefreshDataText()
end

function KeystoneManager:CreateGroup(info)
	--local groupName = '+' .. info.level;

	local activity = activities[info.mapId];

	PVEFrame_ShowFrame('GroupFinderFrame', LFGListPVEStub);

	local panel = LFGListFrame.CategorySelection;
	panel.selectedCategory = 2;

	local baseFilters = panel:GetParent().baseFilters;
	local entryCreation = panel:GetParent().EntryCreation;

	LFGListEntryCreation_Show(
		entryCreation, baseFilters, panel.selectedCategory, panel.selectedFilters
	);
	LFGListEntryCreation_Select(LFGListFrame.EntryCreation, nil, nil, nil, activity);

	--activity = 459;
	----activityID, itemLevel, honorLevel, autoAccept, privateGroup, questID
	--C_LFGList.CreateListing(activity, 0, 0, false, false, nil);
end

-- Helpers

function KeystoneManager:UpdateTable()
	local table = self.ScrollTable;
	if not table then
		return;
	end

	local tableData = {};
	for char, key in pairs(self.db.keystones) do
		local color = self:GetKeystoneColor(key);

		tinsert(tableData, {
			name         = self:NameWithoutRealm(char),
			weeklyBest   = key.weeklyBest,
			mapName      = format('|c%s%s|r', color, key.mapName),
			mapNamePlain = key.mapName,
			class        = key.class,
			level        = key.level,
			mapId        = key.mapId
		});
	end

	table:SetData(tableData, true);
end

function KeystoneManager:NameAndRealm()
	local playerName = UnitName('player');
	return playerName .. '-' .. GetRealmName():gsub('%s+', ''), playerName;
end

function KeystoneManager:NameWithoutRealm(name)
	return gsub(name or '', '%-[^|]+', '');
end

function KeystoneManager:FormatKeystone(info)
	local color = self:GetKeystoneColor(info);
	return format('|c%s%s|r +%d', color, info.mapName, info.level);
end

function KeystoneManager:GetShortInfo(info)
	local color = self:GetKeystoneColor(info);
	return format('|c%s%s|r +%d', color, shortNames[info.mapId] or 'UNKNOWN', info.level);
end

function KeystoneManager:GetKeystoneColor(info)
	local quality = 2;
	local _, _, _, color = GetItemQualityColor(quality);
	return color;
end