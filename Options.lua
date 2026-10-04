-- The options page in the game's settings window.
local ADDON, ns = ...

local category
local variables = {}

-- The page reads every setting again
function ns.profileChanged()
	for _, variable in ipairs(variables) do Settings.NotifyUpdate(variable) end
end

-- Popups

local function popupEditBox(dialog)
	return dialog.GetEditBox and dialog:GetEditBox() or dialog.EditBox or dialog.editBox
end

-- Asks for a name and gives it to run(name), asking again with run's complaint if it returns one
local nameAction
local function askName(prompt, initial, run)
	nameAction = { prompt = prompt, initial = initial, run = run }
	StaticPopup_Show(ADDON .. "_NAME", prompt)
end

local function submitName(text)
	local action = nameAction
	nameAction = nil
	if not action then return end
	local err = action.run(text)
	if err then
		C_Timer.After(0, function()
			nameAction = { prompt = action.prompt, initial = text, run = action.run }
			StaticPopup_Show(ADDON .. "_NAME", "|cffff6060" .. err:gsub("^%l", string.upper) .. ".|r\n" .. action.prompt)
		end)
	end
end

StaticPopupDialogs[ADDON .. "_NAME"] = {
	text = "%s", button1 = ACCEPT, button2 = CANCEL,
	hasEditBox = true, maxLetters = 32,
	OnShow = function(self)
		local e = popupEditBox(self)
		if e then
			e:SetText(nameAction and nameAction.initial or "")
			e:HighlightText()
			e:SetFocus()
		end
	end,
	OnAccept = function(self)
		local e = popupEditBox(self)
		submitName(e and e:GetText() or "")
	end,
	EditBoxOnEnterPressed = function(self)
		submitName(self:GetText())
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs[ADDON .. "_CONFIRM"] = {
	text = "%s", button1 = YES, button2 = NO,
	OnAccept = function(_, run) run() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function confirm(question, run)
	StaticPopup_Show(ADDON .. "_CONFIRM", question, nil, run)
end

-- The export and import window

local share
local function buildShare()
	local f = CreateFrame("Frame", ADDON .. "Share", UIParent, "BackdropTemplate")
	f:SetSize(460, 250)
	f:SetPoint("CENTER")
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetBackdrop(ns.BACKDROP)
	f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
	f:SetBackdropBorderColor(0.85, 0.71, 0.42, 0.9)
	table.insert(UISpecialFrames, f:GetName())

	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.title:SetPoint("TOPLEFT", 14, -12)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
	box:SetBackdrop(ns.BACKDROP)
	box:SetBackdropColor(0, 0, 0, 0.35)
	box:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
	box:SetPoint("TOPLEFT", 12, -40)
	box:SetPoint("BOTTOMRIGHT", -12, 64)
	local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -6)
	scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	local e = CreateFrame("EditBox", nil, scroll)
	e:SetMultiLine(true)
	e:SetAutoFocus(false)
	e:SetFontObject("ChatFontSmall")
	e:SetMaxLetters(0)
	e:SetWidth(460 - 24 - 36)
	e:SetScript("OnEscapePressed", function() f:Hide() end)
	scroll:SetScrollChild(e)
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function() e:SetFocus() end)
	f.edit = e

	f.note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.note:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -8)
	f.note:SetPoint("RIGHT", -12, 0)
	f.note:SetJustifyH("LEFT")

	f.primary = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.primary:SetSize(100, 22)
	f.primary:SetPoint("BOTTOMRIGHT", -12, 12)
	f.secondary = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.secondary:SetSize(100, 22)
	f.secondary:SetPoint("RIGHT", f.primary, "LEFT", -6, 0)
	f.secondary:SetText(CANCEL)
	f.secondary:SetScript("OnClick", function() f:Hide() end)

	e:SetScript("OnTextChanged", function(self, user)
		if f.mode == "export" then
			-- The exported text can't be edited away
			if user then
				self:SetText(f.exported)
				self:HighlightText()
			end
			return
		end
		f.primary:SetEnabled(strtrim(self:GetText()) ~= "")
		if user then
			f.note:SetText("Paste profile text above.")
			f.note:SetTextColor(0.78, 0.74, 0.68)
		end
	end)
	f.primary:SetScript("OnClick", function()
		if f.mode == "export" then return f:Hide() end
		local settings, err = ns.decodeProfile(e:GetText())
		if not settings then
			f.note:SetText(err:gsub("^%l", string.upper) .. ".")
			f.note:SetTextColor(1, 0.38, 0.38)
			return
		end
		f:Hide()
		askName("Name for the imported profile:", "Imported", function(name) return ns.newProfile(name, settings) end)
	end)
	return f
end

local function showShare(mode)
	local text, err
	if mode == "export" then
		text, err = ns.exportProfile()
		if not text then return print(err) end
	end
	share = share or buildShare()
	local f = share
	f.mode, f.exported = mode, text
	f.note:SetTextColor(0.78, 0.74, 0.68)
	if mode == "export" then
		f.title:SetText("Export profile: " .. ns.profileName())
		f.note:SetText("Copy this text (Ctrl+C) and share it.")
		f.primary:SetText(CLOSE)
		f.primary:SetEnabled(true)
		f.secondary:Hide()
		f.edit:SetText(text)
	else
		f.title:SetText("Import profile")
		f.note:SetText("Paste profile text above.")
		f.primary:SetText("Import")
		f.primary:SetEnabled(false)
		f.secondary:Show()
		f.edit:SetText("")
	end
	f:Show()
	f.edit:SetFocus()
	if mode == "export" then f.edit:HighlightText() end
end

function ns.openOptions()
	Settings.OpenToCategory(category:GetID())
end

-- Buttons whose text follows the addon's state, by their row's data
local dynamic = {}

function ns.refreshOptions()
	if not SettingsPanel:IsShown() then return end
	SettingsPanel:GetSettingsList().ScrollBox:ForEachFrame(function(frame)
		local text = frame.data and dynamic[frame.data]
		if text and frame.Button then frame.Button:SetText(text()) end
	end)
end

function ns.buildOptions()
	local DEFAULTS, RANGES = ns.DEFAULTS, ns.RANGES
	category = Settings.RegisterVerticalLayoutCategory(ns.TITLE)
	local main = { category = category, layout = SettingsPanel:GetLayout(category) }

	local function subpage(name)
		local sub = Settings.RegisterVerticalLayoutSubcategory(category, name)
		return { category = sub, layout = SettingsPanel:GetLayout(sub) }
	end

	local function header(page, text)
		page.layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
	end

	-- A button with no label beside it. text: its words, or a function giving them as the state changes
	local function button(page, text, click)
		local initializer = CreateSettingsButtonInitializer("", text, click, nil, false)
		if type(text) == "function" then
			dynamic[initializer.data] = text
		else
			initializer:AddSearchTags(text)
		end
		page.layout:AddInitializer(initializer)
	end

	-- owner(): the table holding the setting now. look: the change shows on a sample
	local function setting(page, owner, key, id, default, label, look)
		local range = RANGES[key]
		variables[#variables + 1] = ADDON .. "_" .. id
		return Settings.RegisterProxySetting(page.category, ADDON .. "_" .. id, type(default), label, default,
			function() return owner()[key] end,
			function(value)
				if range then
					value = math.floor(value / range[3] + 0.5) * range[3]
					value = ns.clamp(tonumber(("%.2f"):format(value)), range)
				end
				owner()[key] = value
				ns.apply()
				if look then ns.sample() end
			end)
	end

	local function profile() return ns.db end
	local function global(page, key, label, look)
		return setting(page, profile, key, key, DEFAULTS[key], label, look)
	end

	local function check(page, option)
		Settings.CreateCheckbox(page.category, option)
	end

	local function swatch(page, key, label)
		Settings.CreateColorSwatch(page.category, global(page, key, label))
	end

	local function dropdown(page, option, choices)
		Settings.CreateDropdown(page.category, option, function()
			local container = Settings.CreateControlTextContainer()
			for _, choice in ipairs(choices()) do container:Add(choice[1], choice[2]) end
			return container:GetData()
		end)
	end

	-- typed: how the value reads in the slider's box
	local function slider(page, option, key, typed)
		local range = RANGES[key]
		local options = Settings.CreateSliderOptions(range[1], range[2], range[3])
		options.typed = typed
		page.layout:AddInitializer(Settings.CreateControlInitializer(ADDON .. "SliderTemplate", option, options))
	end

	local whole = { scale = 1, decimals = 0, unit = "" }
	local percent = { scale = 100, decimals = 0, unit = "%" }
	local seconds = { scale = 1, decimals = 2, unit = "s" }
	local times = { scale = 1, decimals = 2, unit = "x" }

	-- The main page
	button(main, function() return ns.unlocked and "Lock positioning" or "Unlock positioning" end, function()
		ns.setUnlocked(not ns.unlocked)
	end)
	button(main, function() return ns.previewing and "Stop preview" or "Show preview" end, function()
		ns.preview(not ns.previewing and "each" or nil)
	end)

	header(main, "Show on")
	local shown = { player = "Player", target = "Target (hits from anyone)", pet = "Pet" }
	local sized = { player = "Player text size", target = "Target text size", pet = "Pet text size" }
	for _, spec in ipairs(ns.UNITS) do
		local unit = spec.unit
		local function owner() return ns.db[unit] end
		check(main, setting(main, owner, "on", unit .. "_on", spec.on, shown[unit]))
		slider(main, setting(main, owner, "size", unit .. "_size", spec.size, sized[unit], true), "size", whole)
	end

	header(main, "Text")
	dropdown(main, global(main, "font", "Font", true), function()
		local choices = { { "", "Original" } }
		for _, name in ipairs(ns.fonts()) do choices[#choices + 1] = { name, name } end
		return choices
	end)
	dropdown(main, global(main, "outline", "Outline", true), function()
		return { { "", "None" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick outline" } }
	end)
	check(main, global(main, "shadow", "Shadow", true))
	slider(main, global(main, "alpha", "Opacity", true), "alpha", percent)
	slider(main, global(main, "hold", "Time shown"), "hold", seconds)
	slider(main, global(main, "crit", "Critical hit and heal size", true), "crit", times)
	dropdown(main, global(main, "numbers", "Number format", true), function()
		return { { "FULL", "1,412" }, { "PLAIN", "1412" }, { "SHORT", "1.4k" } }
	end)
	check(main, global(main, "signs", "Plus and minus signs", true))

	header(main, "Minimap")
	variables[#variables + 1] = ADDON .. "_minimap"
	check(main, Settings.RegisterProxySetting(category, ADDON .. "_minimap", "boolean", "Minimap button", true,
		function() return not ns.acct.minimap.hide end,
		function(value)
			ns.acct.minimap.hide = not value
			ns.applyMinimap()
		end))

	-- Events: each kind of text with its own settings
	local events = subpage("Events")
	header(events, "Damage")
	check(events, global(events, "damage", "Show damage"))
	slider(events, global(events, "minDamage", "Hide damage under"), "minDamage", whole)
	swatch(events, "colorPhysical", "Physical damage colour")
	swatch(events, "colorSpell", "Spell damage colour")
	check(events, global(events, "schools", "Colour spell damage by school"))

	header(events, "Heals")
	check(events, global(events, "heals", "Show heals"))
	slider(events, global(events, "minHeal", "Hide heals under"), "minHeal", whole)
	swatch(events, "colorHeal", "Heal colour")

	header(events, "Misses, dodges, blocks and resists")
	check(events, global(events, "avoids", "Show them"))
	swatch(events, "colorAvoid", "Their colour")

	header(events, "Mana, rage and energy gains")
	check(events, global(events, "gains", "Show gains"))
	slider(events, global(events, "minGain", "Hide gains under"), "minGain", whole)
	swatch(events, "colorGain", "Gain colour")

	-- Profiles
	local profiles = subpage("Profiles")
	variables[#variables + 1] = ADDON .. "_profile"
	dropdown(profiles, Settings.RegisterProxySetting(profiles.category, ADDON .. "_profile", "string", "Profile",
		"Default", ns.profileName, ns.useProfile), function()
		local choices = {}
		for _, name in ipairs(ns.profileNames()) do choices[#choices + 1] = { name, name } end
		return choices
	end)
	button(profiles, "New profile (a copy)", function()
		askName("Name for the new profile:", "", ns.newProfile)
	end)
	button(profiles, "Rename profile", function()
		if ns.profileName() == "Default" then return print("The Default profile keeps its name.") end
		askName("New name for " .. ns.profileName() .. ":", ns.profileName(), ns.renameProfile)
	end)
	button(profiles, "Reset profile", function()
		confirm("Reset the profile " .. ns.profileName() .. "?", ns.resetProfile)
	end)
	button(profiles, "Delete profile", function()
		if ns.profileName() == "Default" then return print("The Default profile can't be deleted.") end
		confirm("Delete the profile " .. ns.profileName() .. "?", ns.deleteProfile)
	end)
	button(profiles, "Export profile", function() showShare("export") end)
	button(profiles, "Import profile", function() showShare("import") end)

	Settings.RegisterAddOnCategory(category)
end
