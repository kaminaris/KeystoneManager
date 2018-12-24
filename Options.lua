local _, KeystoneManager = ...;

---@type StdUi
local StdUi = LibStub('StdUi');
local Icon = LibStub('LibDBIcon-1.0');
local ldb = LibStub:GetLibrary('LibDataBroker-1.1');

local defaults = {
	enabled    = true,
	announce   = true,
	keystones  = {},
	target     = 'GUILD',
	whisper    = '',
	minLevel   = 0,
	maxLevel   = 20,
	ldbStorage = {
		hide = false
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
		local name, shortName = KeystoneManager:NameAndRealm();

		if info then
			tooltip:AddLine('Current:');
			tooltip:AddDoubleLine(
				format('|cffffffff%s|r', shortName),
				KeystoneManager:FormatKeystone(info)
			);
			tooltip:AddLine(' ');
		end

		tooltip:AddLine('Other Keys:');
		for char, keyInfo in pairs(KeystoneManager.db.keystones) do
			if name ~= char then
				tooltip:AddDoubleLine(
					format('|cffffffff%s|r', keyInfo.shortName),
					KeystoneManager:FormatKeystone(keyInfo)
				);
			end
		end
	end,
};

function KeystoneManager:InitializeDatabase()
	if not KeystoneManagerDb or type(KeystoneManagerDb) ~= 'table' or KeystoneManagerDb.global then
		KeystoneManagerDb = defaults;
	end

	self.db = KeystoneManagerDb;

	if not ldb:GetDataObjectByName('KeystoneManager') then
		ldb:NewDataObject('KeystoneManager', kmldbObject);
		Icon:Register('KeystoneManager', kmldbObject, self.db.ldbStorage);
	end
end

function KeystoneManager:RefreshDataText()
	local info = self:GetCurrentKeystoneInfo();
	if info then
		kmldbObject.text = self:GetShortInfo(info);
	else
		kmldbObject.text = 'Keystone Manager';
	end
end

function KeystoneManager:InitializeOptionsTable()
	local config = {
		layoutConfig = { padding = { top = 30 } },
		database     = self.db,
		rows         = {
			[1] = {
				enabled = {
					type   = 'checkbox',
					label  = 'Enable Addon',
					column = 6
				},
				announce = {
					type   = 'checkbox',
					label  = 'Announce new key in party channel',
					column = 6
				},
			},
			[2] = {
				hideIcon = {
					type   = 'checkbox',
					label  = 'Hide MiniMap Icon',
					column = 6,
					key    = 'ldbStorage.hide',
					onChange = function(_, isHidden)
						if isHidden then
							Icon:Hide('KeystoneManager');
						else
							Icon:Show('KeystoneManager');
						end
					end
				},
			}
		},
	};

	return config;
end

function KeystoneManager:RegisterOptionWindow()
	if self.optionsFrame then
		return;
	end

	self.optionsFrame = StdUi:PanelWithTitle(nil, 100, 100, 'Keystone Manager');
	self.optionsFrame.name = 'Keystone Manager';
	self.optionsFrame:Hide();

	StdUi:BuildWindow(self.optionsFrame, self:InitializeOptionsTable());

	self.optionsFrame:SetScript('OnShow', function(of)
		of:DoLayout();
	end);

	InterfaceOptions_AddCategory(self.optionsFrame);
end