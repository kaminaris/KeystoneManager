KeystoneManager = LibStub('AceAddon-3.0'):NewAddon('KeystoneManager', 'AceConsole-3.0', 'AceEvent-3.0', 'AceTimer-3.0');
AceGUI = LibStub('AceGUI-3.0');
local icon = LibStub('LibDBIcon-1.0');
local ldb = LibStub:GetLibrary('LibDataBroker-1.1');

local dungeonNames = {
	[1456] = 'Eye of Azshara',
	[1466] = 'Darkheart Thicket',
	[1501] = 'Black Rook Hold',
	[1477] = 'Halls of Valor',
	[1458] = 'Neltharion\'s Lair',
	[1493] = 'Vault of the Wardens',
	[1492] = 'Maw of Souls',
	[1516] = 'The Arcway',
	[1571] = 'Court of Stars',
}

local shortNames = {
	[1456] = 'EOA',
	[1466] = 'DHT',
	[1501] = 'BRH',
	[1477] = 'HOV',
	[1458] = 'NL',
	[1493] = 'VOTW',
	[1492] = 'MOS',
	[1516] = 'ARC',
	[1571] = 'COS',
}

local options = {
	type = 'group',
	name = 'Keystone Manager Options',
	inline = false,
	args = {
		enableIcon = {
			name = 'Enable minimap icon',
			desc = 'Enables / disables minimap icon',
			type = 'toggle',
			width = 'full',
			set = function(info, val)
				KeystoneManager.db.global.ldbStorage.hide = not val;
				if KeystoneManager.db.global.ldbStorage.hide then
					icon:Hide('KeystoneManager');
				else
					icon:Show('KeystoneManager');
				end
			end,
			get = function(info) return not KeystoneManager.db.global.ldbStorage.hide end
		},
		announce = {
			name = 'Announce new key in party channel',
			desc = 'Announce new key in party channel',
			type = 'toggle',
			width = 'full',
			set = function(info, val)
				KeystoneManager.db.global.announce = val;
			end,
			get = function(info) return KeystoneManager.db.global.announce end
		},
		excludeDungeons = {
			type = 'multiselect',
			name = 'Exclude dungeons from report',
			values = function()
				return dungeonNames;
			end,
			get = function(self, key)
				if not KeystoneManager.db.global.excludes then
					KeystoneManager.db.global.excludes = {};
				end
				return KeystoneManager.db.global.excludes[key];
			end,
			set = function(self, key, val)
				KeystoneManager.db.global.excludes[key] = val;
				KeystoneManager:UpdateTable(KeystoneManager.ScrollTable);
				KeystoneManager:RefreshDataText();
			end,
		},
	},
}

local defaults = {
	global = {
		enabled = true,
		announce = true,
		excludes = {},
		keystones = {},
		target = 'GUILD',
		whisper = '',
		nondepleted = false,
		minlevel = 0,
		maxlevel = 20,
		ldbStorage = {
			hide = false
		}
	}
};

local kmldbObject = {
	type = 'launcher',
	text = 'Keystone Manager',
	label = 'Keystone Manager',
	icon = 'Interface\\Icons\\INV_Relics_Hourglass',
	OnClick = function() KeystoneManager:ShowWindow(); end,
	OnTooltipShow = function(tooltip)

		local info = KeystoneManager:GetCurrentKeystoneInfo();
		if info then
			local name = KeystoneManager:NameAndRealm();
			tooltip:AddDoubleLine(
				format("|cffffffff%s|r", KeystoneManager:NameWithoutRealm(name)),
				KeystoneManager:FormatKeystone(info)
			);
			tooltip:AddLine(' ');
		end


		for char, key in pairs(KeystoneManager.db.global.keystones) do
			local info = KeystoneManager:ExtractKeystoneInfo(key);

			tooltip:AddDoubleLine(
				format("|cffffffff%s|r", KeystoneManager:NameWithoutRealm(char)),
				KeystoneManager:FormatKeystone(info)
			);
		end
	end,
};

function KeystoneManager:OnInitialize()
	LibStub('AceConfig-3.0'):RegisterOptionsTable('KeystoneManager', options, {'/kmconfig'});
	self.db = LibStub('AceDB-3.0'):New('KeystoneManagerDb', defaults);
	self.optionsFrame = LibStub('AceConfigDialog-3.0'):AddToBlizOptions('KeystoneManager', 'Keystone Manager');
	self:RegisterChatCommand('keystonemanager', 'ShowWindow');
	self:RegisterChatCommand('keylist', 'ShowWindow');
	self:RegisterChatCommand('keyprint', 'PrintKeystone');
	self:RegisterEvent('BAG_UPDATE');
	self:RegisterEvent('PLAYER_ENTERING_WORLD');
	ldb:NewDataObject('KeystoneManager', kmldbObject);
	icon:Register('KeystoneManager', kmldbObject, self.db.global.ldbStorage);

	self:RefreshDataText();
end

function KeystoneManager:PLAYER_ENTERING_WORLD()
	self.bestTries = 0;
	self.bestTimer = self:ScheduleTimer('GetWeeklyBest', 20);
end

function KeystoneManager:BAG_UPDATE()
	self:GetKeystone();
end

function KeystoneManager:ShowWindow(input)
	if not self.KeystoneWindow then
		self:GetWeeklyBest();

		self.KeystoneWindow = AceGUI:Create('Window');
		self.KeystoneWindow:SetTitle('Keystone Manager');
		self.KeystoneWindow.frame:SetFrameStrata('DIALOG');
		self.KeystoneWindow:SetLayout('Flow');
		self.KeystoneWindow:SetWidth(625);
		self.KeystoneWindow:SetHeight(550);
		self.KeystoneWindow:EnableResize(false);

		local target = AceGUI:Create('Dropdown');
		target:SetLabel('Report to');
		target:SetList({
			['WHISPER'] = 'Whisper',
			['GUILD'] = 'Guild',
			['PARTY'] = 'Party',
			['RAID'] = 'Raid',
			['INSTANCE_CHAT'] = 'Instance',
		});
		target:SetValue(self.db.global.target);
		target:SetCallback('OnValueChanged', function(self, event, key)
			KeystoneManager.db.global.target = key;
		end);
		self.KeystoneWindow:AddChild(target);

		local whisper = AceGUI:Create('EditBox');
		whisper:SetLabel('Whisper target');
		whisper:SetText(self.db.global.whisper);
		whisper:SetCallback('OnTextChanged', function(self, event, text)
			KeystoneManager.db.global.whisper = text;
		end);
		self.KeystoneWindow:AddChild(whisper);

		local nondepleted = AceGUI:Create('CheckBox');
		nondepleted:SetLabel('Exclude depleted');
		nondepleted:SetValue(self.db.global.nondepleted);
		nondepleted:SetCallback('OnValueChanged', function(self, event, val)
			KeystoneManager.db.global.nondepleted = val;
		end);
		self.KeystoneWindow:AddChild(nondepleted);

		local minlevel = AceGUI:Create('Slider');
		minlevel:SetLabel('Min Level');
		minlevel:SetSliderValues(0, 50, 1);
		minlevel:SetValue(self.db.global.minlevel);
		minlevel:SetCallback('OnValueChanged', function(self, event, val)
			KeystoneManager.db.global.minlevel = val;
		end);
		self.KeystoneWindow:AddChild(minlevel);

		local maxlevel = AceGUI:Create('Slider');
		maxlevel:SetLabel('Max Level');
		maxlevel:SetSliderValues(0, 50, 1);
		maxlevel:SetValue(self.db.global.maxlevel);
		maxlevel:SetCallback('OnValueChanged', function(self, event, val)
			KeystoneManager.db.global.maxlevel = val;
		end);
		self.KeystoneWindow:AddChild(maxlevel);


		local btn = AceGUI:Create('Button');
		btn:SetWidth(100);
		btn:SetText('Report');
		btn:SetCallback('OnClick', function()
			self:ReportKeys();
		end);
		self.KeystoneWindow:AddChild(btn);

		local ScrollingTable = LibStub('ScrollingTable');
		local cols = {
			{
				['name'] = 'Character',
				['width'] = 140,
				['align'] = 'LEFT',
			},

			{
				['name'] = 'Weekly Best',
				['width'] = 80,
				['align'] = 'LEFT',
			},

			{
				['name'] = 'Key',
				['width'] = 130,
				['align'] = 'LEFT',
			},

			{
				['name'] = 'Dungeon',
				['width'] = 175,
				['align'] = 'LEFT',
			},

			{
				['name'] = 'Level',
				['width'] = 45,
				['align'] = 'LEFT',
			},
		}
		self.ScrollTable = ScrollingTable:CreateST(cols, 16, 20, nil, self.KeystoneWindow.content);

		self:UpdateTable(self.ScrollTable);

		self.ScrollTable:RegisterEvents({
			['OnClick'] = function(rowFrame, cellFrame, data, cols, row, realrow, column, scrollingTable, ...)
				if data[row] then
					local link = data[row][3];
					if link then
						GameTooltip:SetOwner(UIParent);
						GameTooltip:SetHyperlink(link);
						GameTooltip:Show();
					end
				end
			end,
		});
		local tableWrapper = AceGUI:Create('lib-st'):WrapST(self.ScrollTable);

		tableWrapper.head_offset = 20;
		self.KeystoneWindow:AddChild(tableWrapper);

		-- Clear button
		local clearBtn = AceGUI:Create('Button');
		clearBtn:SetWidth(100);
		clearBtn:SetText('Clear');

		clearBtn:SetCallback('OnClick', function()
			self:ClearKeystones();
		end);
		self.KeystoneWindow:AddChild(clearBtn);

		-- Refresh button
		local refreshbtn = AceGUI:Create('Button');
		refreshbtn:SetWidth(100);
		refreshbtn:SetText('Refresh');

		refreshbtn:SetCallback('OnClick', function()
			self:GetKeystone(true);
			self:GetWeeklyBest();
		end);
		self.KeystoneWindow:AddChild(refreshbtn);

		-- Copy button
		local copybtn = AceGUI:Create('Button');
		copybtn:SetWidth(100);
		copybtn:SetText('Copy Keys');

		copybtn:SetCallback('OnClick', function()
			self:ShowCopyWindow();
		end);
		self.KeystoneWindow:AddChild(copybtn);

		-- Set points manually
		clearBtn:ClearAllPoints();
		clearBtn:SetPoint('BOTTOMLEFT', self.KeystoneWindow.frame, 20, 20);
		refreshbtn:ClearAllPoints();
		refreshbtn:SetPoint('BOTTOMLEFT', self.KeystoneWindow.frame, 130, 20);
		copybtn:ClearAllPoints();
		copybtn:SetPoint('BOTTOMLEFT', self.KeystoneWindow.frame, 240, 20);
	end

	self.KeystoneWindow:Show();
end

function KeystoneManager:GetKeysText()
	local text = '';
	for char, key in pairs(self.db.global.keystones) do
		local info = self:ExtractKeystoneInfo(key);
		if (info.lootEligible or not self.db.global.nondepleted) and
			info.level >= self.db.global.minlevel and
			info.level <= self.db.global.maxlevel and
			not self.db.global.excludes[info.dungeonId]
		then
			text = text .. self:NameWithoutRealm(char) .. ' - ' .. info.dungeonName .. ' +' .. info.level .. "\n";
		end
	end

	return text;
end

function KeystoneManager:ShowCopyWindow()
	if self.KeystoneCopyWindow then
		self:GetWeeklyBest();

		self.KeystoneCopyWindow.copyText:SetText(self:GetKeysText());
		self.KeystoneCopyWindow:Show();
		self.KeystoneCopyWindow.frame:SetToplevel(true);
		return;
	end

	self.KeystoneCopyWindow = AceGUI:Create('Window');
	self.KeystoneCopyWindow :SetTitle('Keystone Manager');
	self.KeystoneCopyWindow:SetLayout('Flow');
	self.KeystoneCopyWindow:SetWidth(400);
	self.KeystoneCopyWindow:SetHeight(350);
	self.KeystoneCopyWindow:EnableResize(false);

	-- Refresh button
	local copyText = AceGUI:Create('MultiLineEditBox');
	copyText:SetFullHeight(true);
	copyText:SetFullWidth(true);
	copyText:SetLabel('Your Keys');
	copyText:DisableButton(true);
	copyText:SetNumLines(14);
	self.KeystoneCopyWindow.copyText = copyText;
	self.KeystoneCopyWindow:AddChild(copyText);

	copyText:SetText(self:GetKeysText());
	self.KeystoneCopyWindow.frame:SetToplevel(true);
end

function KeystoneManager:GetCurrentKeystoneInfo()
	local name = KeystoneManager:NameAndRealm();
	local keystone = KeystoneManager.db.global.keystones[name];
	if keystone then
		return KeystoneManager:ExtractKeystoneInfo(keystone);
	else
		return nil
	end
end

function KeystoneManager:GetKeystone(force)
	force = force or false;
	local name = self:NameAndRealm();
	if not self.db.global.keystones then
		self.db.global.keystones = {};
	end
	local keystone = self.db.global.keystones[name];

	for bag = 0, NUM_BAG_SLOTS do
		local numSlots = GetContainerNumSlots(bag);
		if numSlots ~= 0 then
			for slot = 1, numSlots do
				if (GetContainerItemID(bag, slot) == 138019) then
					local link = GetContainerItemLink(bag, slot);
					local oldKey = self.db.global.keystones[name];

					local info = self:ExtractKeystoneInfo(link);
					local oldInfo = self:ExtractKeystoneInfo(oldKey);

					if force or oldInfo == nil or (info.level ~= 0 and (info.dungeonId ~= oldInfo.dungeonId or
							info.level ~= oldInfo.level)) then --keystone has changed
						if self.db.global.announce then
							SendChatMessage('New Keystone - ' .. info.dungeonName .. ' +' .. info.level,
								'PARTY');
						end

						self.db.global.keystones[name] = link;
						self:GetWeeklyBest();
						self:UpdateTable(self.ScrollTable);
						self:RefreshDataText();
					end
					return link;
				end
			end
		end
	end

	return keystone;
end

function KeystoneManager:GetWeeklyBest()
	local name = self:NameAndRealm();
	if not self.db.global.weeklyBest then
		self.db.global.weeklyBest = {};
	end

	C_ChallengeMode.RequestMapInfo();
	C_ChallengeMode.RequestRewards();
	local mapTable = C_ChallengeMode.GetMapTable();
	local best = 0;
	for i, mapId in pairs(mapTable) do
		local _, weeklyBestTime, weeklyBestLevel = C_ChallengeMode.GetMapPlayerStats(mapId);

		if weeklyBestLevel and weeklyBestLevel > best then
			best = weeklyBestLevel;
		end
	end
	if best == 0 then
		if self.bestTries < 5 then
			self.bestTries = self.bestTries + 1;
			self.bestTimer = self:ScheduleTimer('GetWeeklyBest', 3);
		end
	end
	self.db.global.weeklyBest[name] = best;
	return best;
end

function KeystoneManager:PrintKeystone()
	local name = self:NameAndRealm();
	local keystone = self.db.global.keystones[name];
	if keystone then
		keystone = self:GetKeystone();
	end
	self:Print(keystone);
end

function KeystoneManager:ReportKeys()
	local target = self.db.global.whisper;
	if self.db.global.target ~= 'WHISPER' then
		target = nil;
	end

	for char, key in pairs(self.db.global.keystones) do
		local info = self:ExtractKeystoneInfo(key);
		if (info.lootEligible or not self.db.global.nondepleted) and
			info.level >= self.db.global.minlevel and
			info.level <= self.db.global.maxlevel and
			not self.db.global.excludes[info.dungeonId]
		then
			SendChatMessage(self:NameWithoutRealm(char) .. ' - ' .. info.dungeonName .. ' +' .. info.level,
				self.db.global.target,
				nil,
				target);
		end
	end
end

function KeystoneManager:ClearKeystones()
	self.db.global.weeklyBest = {};
	self.db.global.keystones = {};
	self:UpdateTable(self.ScrollTable);
	self:RefreshDataText()
end

function KeystoneManager:UpdateTable(table)
	if not table then
		return;
	end

	local tableData = {};
	for char, key in pairs(self.db.global.keystones) do
		local info = self:ExtractKeystoneInfo(key);
		local weeklyBest = self.db.global.weeklyBest[char];

		local color = self:GetKeystoneColor(info);

		tinsert(tableData, {
			self:NameWithoutRealm(char),
			weeklyBest,
			key,
			format('|c%s%s|r', color, info.dungeonName),
			info.level
		});
	end

	table:SetData(tableData, true);
end

function KeystoneManager:RefreshDataText()
	local info = self:GetCurrentKeystoneInfo();
	if info then
		kmldbObject.text = self:GetShortInfo(info);
	else
		kmldbObject.text = 'Keystone Manager';
	end
end

function KeystoneManager:NameAndRealm()
	return UnitName('player') .. '-' .. GetRealmName();
end

function KeystoneManager:NameWithoutRealm(name)
	return gsub(name or '', "%-[^|]+", "");
end

function KeystoneManager:ExtractKeystoneInfo(link)
	if not link then
		return nil;
	end

	local parts = { strsplit(':', link) }

	local dungeonId = tonumber(parts[15]);
	local level = tonumber(parts[16]);
	local numAffixes = ({0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 3, 3, 3})[level];
	local ready = 0x400000;
	local lootEligible = bit.band(parts[12], ready) == ready;
	local dungeonName = C_ChallengeMode.GetMapInfo(dungeonId);

	return {
		dungeonId = dungeonId,
		dungeonName = dungeonName,
		level = level,
		lootEligible = lootEligible,
	}
end

function KeystoneManager:FormatKeystone(info)
	local color = self:GetKeystoneColor(info);
	return format('|c%s%s|r +%d', color, info.dungeonName, info.level);
end

function KeystoneManager:GetShortInfo(info)
	local color = self:GetKeystoneColor(info);
	return format('|c%s%s|r +%d', color, shortNames[info.dungeonId], info.level);
end

function KeystoneManager:GetKeystoneColor(info)
	if self.db.global.excludes[info.dungeonId] then
		return 'ffc41f3b';
	end

	local quality = 2;
	if not info.lootEligible then
		quality = 0;
	end

	local _, _, _, color = GetItemQualityColor(quality);

	return color;
end