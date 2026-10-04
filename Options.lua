-- The options window: a nav column and scrolling pages of rows.
local ADDON, ns = ...

local WIDTH, HEIGHT, NAV_W = 700, 560, 170
local LABEL_W, ROW_W = 180, WIDTH - NAV_W - 64
local SLIDER_W, BOX_W = 200, 52
local GOLD = { 0.88, 0.66, 0.29 }

local win, pages, navButtons, current

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


-- Pages: rows stacked down a scrolling column, each with a function that shows its value again

local Page = {}
Page.__index = Page

local function newPage(key, title)
	local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, win, "ScrollFrameTemplate")
	if ok and scroll and scroll.ScrollBar then
		if scroll.ScrollBar.SetHideIfUnscrollable then scroll.ScrollBar:SetHideIfUnscrollable(true) end
		scroll.ScrollBar:ClearAllPoints()
		scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 14, 0)
		scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 14, 0)
	else
		scroll = CreateFrame("ScrollFrame", ADDON .. "OptionsScroll_" .. key, win, "UIPanelScrollFrameTemplate")
	end
	scroll:SetPoint("TOPLEFT", win, "TOPLEFT", NAV_W + 18, -38)
	scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -40, 12)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(ROW_W, 1)
	scroll:SetScrollChild(content)
	scroll:Hide()
	local page = setmetatable({ key = key, title = title, scroll = scroll, content = content, y = 0,
		refreshers = {} }, Page)
	pages[key] = page
	pages[#pages + 1] = page
	return page
end

function Page:add(height, refresh)
	local f = CreateFrame("Frame", nil, self.content)
	f:SetSize(ROW_W, height)
	f:SetPoint("TOPLEFT", 0, -self.y)
	self.y = self.y + height
	self.content:SetHeight(self.y)
	if refresh then self.refreshers[#self.refreshers + 1] = refresh end
	return f
end

function Page:refresh()
	for _, refresh in ipairs(self.refreshers) do refresh() end
end

local function label(f, text)
	local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fs:SetPoint("LEFT", 4, 0)
	fs:SetWidth(LABEL_W - 8)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
end

function Page:section(text)
	local f = self:add(46)
	local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	fs:SetPoint("BOTTOMLEFT", 4, 9)
	fs:SetText(text)
	local line = f:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(0.85, 0.71, 0.42, 0.6)
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT", 0, 3)
	line:SetPoint("BOTTOMRIGHT", 0, 3)
end

function Page:checkbox(text, get, set)
	local cb
	local f = self:add(30, function() cb:SetChecked(get() and true or false) end)
	cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	cb:SetSize(26, 26)
	cb:SetPoint("LEFT", 0, 0)
	cb.Text:SetFontObject("GameFontHighlight")
	cb.Text:SetText(text)
	cb:SetScript("OnClick", function(button) set(button:GetChecked() and true or false) end)
end

-- A slider with a box to type the value in. unit: scale (shown = saved x scale), decimals, suffix
function Page:slider(text, range, unit, get, set)
	local slider, box
	local updating = false
	local function shown(v) return ("%." .. unit.decimals .. "f"):format(v * unit.scale) .. unit.suffix end
	local f = self:add(34, function()
		updating = true
		slider:SetValue(get())
		updating = false
		if not box:HasFocus() then box:SetText(shown(get())) end
	end)
	label(f, text)
	slider = CreateFrame("Frame", nil, f, "MinimalSliderWithSteppersTemplate")
	slider:SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	slider:SetWidth(SLIDER_W)
	slider:Init(get(), range[1], range[2], math.floor((range[2] - range[1]) / range[3] + 0.5))
	box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	box:SetSize(BOX_W, 20)
	box:SetPoint("LEFT", slider, "RIGHT", 10, 0)
	box:SetAutoFocus(false)
	box:SetMaxLetters(8)
	box:SetFontObject("GameFontHighlight")
	box:SetJustifyH("CENTER")
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
		if updating then return end
		set(v)
		box:ClearFocus()
		box:SetText(shown(get()))
	end, slider)
	box:SetScript("OnEditFocusGained", function(b)
		b:SetText((shown(get()):gsub("[^%d%.%-]", "")))
		b:HighlightText()
	end)
	box:SetScript("OnEditFocusLost", function(b)
		b:HighlightText(0, 0)
		b:SetText(shown(get()))
	end)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEnterPressed", function(b)
		local n = tonumber((b:GetText():gsub(",", "."):match("%-?%d*%.?%d+")) or "")
		if n then
			set(n / unit.scale)
			updating = true
			slider:SetValue(get())
			updating = false
		end
		b:ClearFocus()
	end)
end

-- choices: a list of { value, text }, or a function giving one
function Page:dropdown(text, choices, get, set)
	local dd
	local f = self:add(34, function()
		if not dd:IsMenuOpen() then dd:GenerateMenu() end
	end)
	label(f, text)
	dd = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
	dd:SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	dd:SetWidth(200)
	dd:SetupMenu(function(_, root)
		root:SetScrollMode(400)
		for _, c in ipairs(type(choices) == "function" and choices() or choices) do
			root:CreateRadio(c[2], function() return get() == c[1] end, function() set(c[1]) end)
		end
	end)
end

-- A colour saved as "ffrrggbb"
function Page:color(text, key)
	local swatch
	local function rgb()
		local hex = ns.db[key]
		return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
	end
	local function set(r, g, b)
		local function byte(v) return math.floor(v * 255 + 0.5) end
		ns.set(nil, key, ("ff%02x%02x%02x"):format(byte(r), byte(g), byte(b)))
		swatch:SetColorTexture(r, g, b, 1)
	end
	local f = self:add(30, function() swatch:SetColorTexture(rgb()) end)
	label(f, text)
	local b = CreateFrame("Button", nil, f, "BackdropTemplate")
	b:SetSize(22, 22)
	b:SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	b:SetBackdrop(ns.BACKDROP)
	b:SetBackdropColor(0.5, 0.5, 0.5, 1)
	b:SetBackdropBorderColor(1, 1, 1, 0.6)
	swatch = b:CreateTexture(nil, "ARTWORK")
	swatch:SetPoint("TOPLEFT", 2, -2)
	swatch:SetPoint("BOTTOMRIGHT", -2, 2)
	b:SetScript("OnClick", function()
		local r, g, bl = rgb()
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = bl, hasOpacity = false,
			swatchFunc = function() set(ColorPickerFrame:GetColorRGB()) end,
			cancelFunc = function(prev) set(prev.r, prev.g, prev.b) end,
		})
	end)
end

-- list: { text, onClick, width } each
function Page:buttons(list)
	local f = self:add(32)
	local x = 0
	for _, b in ipairs(list) do
		local button = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		button:SetSize(b[3] or 110, 22)
		button:SetPoint("LEFT", x, 0)
		button:SetText(b[1])
		button:SetScript("OnClick", b[2])
		x = x + (b[3] or 110) + 6
	end
end

-- The pages

local WHOLE = { scale = 1, decimals = 0, suffix = "" }
local PERCENT = { scale = 100, decimals = 0, suffix = "%" }
local SECONDS = { scale = 1, decimals = 2, suffix = " s" }
local TIMES = { scale = 1, decimals = 2, suffix = "x" }

-- A profile setting's row. unit: a box's own setting. look: the change shows on a sample
local function getter(key, unit)
	return function() return (unit and ns.db[unit] or ns.db)[key] end
end
local function setter(key, unit, look)
	return function(value) ns.set(unit, key, value, look) end
end

local function buildGeneral(p)
	p:section("Show on")
	local shown = { player = "Player", target = "Target (hits from anyone)", pet = "Pet" }
	local sized = { player = "Player text size", target = "Target text size", pet = "Pet text size" }
	for _, spec in ipairs(ns.UNITS) do
		local unit = spec.unit
		p:checkbox(shown[unit], getter("on", unit), setter("on", unit))
		p:slider(sized[unit], ns.RANGES.size, WHOLE, getter("size", unit), setter("size", unit, true))
	end

	p:section("Text")
	p:dropdown("Font", function()
		local choices = { { "", "Original" } }
		for _, name in ipairs(ns.fonts()) do choices[#choices + 1] = { name, name } end
		return choices
	end, getter("font"), setter("font", nil, true))
	p:dropdown("Outline", { { "", "None" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick outline" } },
		getter("outline"), setter("outline", nil, true))
	p:checkbox("Shadow", getter("shadow"), setter("shadow", nil, true))
	p:slider("Opacity", ns.RANGES.alpha, PERCENT, getter("alpha"), setter("alpha", nil, true))
	p:slider("Time shown", ns.RANGES.hold, SECONDS, getter("hold"), setter("hold"))
	p:slider("Critical hit and heal size", ns.RANGES.crit, TIMES, getter("crit"), setter("crit", nil, true))
	p:dropdown("Number format", { { "FULL", "1,412" }, { "PLAIN", "1412" }, { "SHORT", "1.4k" } },
		getter("numbers"), setter("numbers", nil, true))
	p:checkbox("Plus and minus signs", getter("signs"), setter("signs", nil, true))

	p:section("Other")
	p:checkbox("Hide the game's own portrait text", getter("hideDefault"), setter("hideDefault"))
	p:checkbox("Minimap button", function() return not ns.acct.minimap.hide end, function(value)
		ns.acct.minimap.hide = not value
		ns.applyMinimap()
	end)
end

local function buildEvents(p)
	p:section("Damage")
	p:checkbox("Show damage", getter("damage"), setter("damage"))
	p:slider("Hide damage under", ns.RANGES.minDamage, WHOLE, getter("minDamage"), setter("minDamage"))
	p:color("Physical damage colour", "colorPhysical")
	p:color("Spell damage colour", "colorSpell")
	p:checkbox("Colour spell damage by school", getter("schools"), setter("schools"))

	p:section("Heals")
	p:checkbox("Show heals", getter("heals"), setter("heals"))
	p:slider("Hide heals under", ns.RANGES.minHeal, WHOLE, getter("minHeal"), setter("minHeal"))
	p:color("Heal colour", "colorHeal")

	p:section("Misses, dodges, blocks and resists")
	p:checkbox("Show them", getter("avoids"), setter("avoids"))
	p:color("Their colour", "colorAvoid")

	p:section("Mana, rage and energy gains")
	p:checkbox("Show gains", getter("gains"), setter("gains"))
	p:slider("Hide gains under", ns.RANGES.minGain, WHOLE, getter("minGain"), setter("minGain"))
	p:color("Gain colour", "colorGain")
end

local function buildProfiles(p)
	p:section("Profile")
	p:dropdown("Profile", function()
		local choices = {}
		for _, name in ipairs(ns.profileNames()) do choices[#choices + 1] = { name, name } end
		return choices
	end, ns.profileName, ns.useProfile)
	p:buttons({
		{ "New (a copy)", function() askName("Name for the new profile:", "", ns.newProfile) end },
		{ "Rename", function()
			if ns.profileName() == "Default" then return print("The Default profile keeps its name.") end
			askName("New name for " .. ns.profileName() .. ":", ns.profileName(), ns.renameProfile)
		end },
		{ "Reset to defaults", function()
			confirm("Reset the profile " .. ns.profileName() .. " to defaults?", ns.resetProfile)
		end, 130 },
		{ "Delete", function()
			if ns.profileName() == "Default" then return print("The Default profile can't be deleted.") end
			confirm("Delete the profile " .. ns.profileName() .. "?", ns.deleteProfile)
		end },
	})
	p:section("Share")
	p:buttons({
		{ "Export", function() showShare("export") end },
		{ "Import", function() showShare("import") end },
	})
end

-- The window

local function showPage(key)
	current = key
	for _, p in ipairs(pages) do p.scroll:SetShown(p.key == key) end
	ns.refreshOptions()
end

local function navButton(text, y, onClick)
	local b = CreateFrame("Button", nil, win)
	b:SetSize(NAV_W - 20, 28)
	b:SetPoint("TOPLEFT", 12, y)
	b.sel = b:CreateTexture(nil, "BACKGROUND")
	b.sel:SetAllPoints()
	b.sel:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.16)
	b.accent = b:CreateTexture(nil, "ARTWORK")
	b.accent:SetPoint("TOPLEFT", -8, -4)
	b.accent:SetPoint("BOTTOMLEFT", -8, 4)
	b.accent:SetWidth(3)
	b.accent:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	local hover = b:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.05)
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	b.label:SetPoint("LEFT", 8, 0)
	b.label:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local function build()
	win = CreateFrame("Frame", ADDON .. "Options", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HideButtonBar(win)
	ButtonFrameTemplate_HidePortrait(win)
	if win.Inset then win.Inset:Hide() end
	if win.SetTitle then win:SetTitle(ns.TITLE) end
	win:SetSize(WIDTH, HEIGHT)
	local acct = ns.acct
	if acct.optionsLeft and acct.optionsTop then
		win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", acct.optionsLeft, acct.optionsTop)
	else
		win:SetPoint("CENTER")
	end
	win:SetFrameStrata("DIALOG")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:SetMovable(true)
	win:EnableMouse(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", function()
		win:StopMovingOrSizing()
		acct.optionsLeft, acct.optionsTop = math.floor(win:GetLeft() + 0.5), math.floor(win:GetTop() + 0.5)
	end)
	table.insert(UISpecialFrames, win:GetName())

	local bg = win:CreateTexture(nil, "BACKGROUND", nil, 2)
	bg:SetPoint("TOPLEFT", 2, -22)
	bg:SetPoint("BOTTOMRIGHT", -2, 2)
	bg:SetColorTexture(23 / 255, 19 / 255, 15 / 255, 0.97)
	local navBg = win:CreateTexture(nil, "BACKGROUND", nil, 3)
	navBg:SetPoint("TOPLEFT", bg, "TOPLEFT")
	navBg:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT")
	navBg:SetWidth(NAV_W)
	navBg:SetColorTexture(0, 0, 0, 0.25)
	local navEdge = win:CreateTexture(nil, "BACKGROUND", nil, 4)
	navEdge:SetPoint("TOPLEFT", navBg, "TOPRIGHT")
	navEdge:SetPoint("BOTTOMLEFT", navBg, "BOTTOMRIGHT")
	navEdge:SetWidth(1)
	navEdge:SetColorTexture(0.23, 0.17, 0.10, 1)
	local logo = win:CreateTexture(nil, "OVERLAY")
	logo:SetSize(64, 64)
	logo:SetPoint("TOPLEFT", -12, 14)
	logo:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Art\\Logo")

	pages, navButtons = {}, {}
	for i, spec in ipairs({ { "general", "General", buildGeneral }, { "events", "Events", buildEvents },
		{ "profiles", "Profiles", buildProfiles } }) do
		spec[3](newPage(spec[1], spec[2]))
		local b = navButton(spec[2], -52 - (i - 1) * 30, function() showPage(spec[1]) end)
		b.page = spec[1]
		navButtons[i] = b
	end

	-- The two modes, under the pages
	local function mode(y, text, onClick)
		local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
		b:SetSize(NAV_W - 24, 22)
		b:SetPoint("BOTTOMLEFT", 14, y)
		b:SetScript("OnClick", onClick)
		b.text = text
		return b
	end
	win.modes = {
		mode(40, function() return ns.unlocked and "Lock positioning" or "Unlock positioning" end, function()
			ns.setUnlocked(not ns.unlocked)
		end),
		mode(14, function() return ns.previewing and "Stop preview" or "Show preview" end, function()
			ns.preview(not ns.previewing and "each" or nil)
		end),
	}
	win:Hide()
	showPage("general")
end

-- The page in view shows every value again
function ns.refreshOptions()
	if not win then return end
	for _, b in ipairs(navButtons) do
		local on = b.page == current
		b.sel:SetShown(on)
		b.accent:SetShown(on)
	end
	for _, b in ipairs(win.modes) do b:SetText(b.text()) end
	pages[current]:refresh()
end
ns.profileChanged = ns.refreshOptions

function ns.openOptions()
	if not win then build() end
	win:SetShown(not win:IsShown())
	ns.refreshOptions()
end

-- A page in the game's addon settings list, with one button that opens the window
function ns.registerOptionsEntry()
	local category = Settings.RegisterVerticalLayoutCategory(ns.TITLE)
	local initializer = CreateSettingsButtonInitializer("", "Open the options", function()
		HideUIPanel(SettingsPanel)
		if not (win and win:IsShown()) then ns.openOptions() end
	end, nil, false)
	initializer:AddSearchTags(ns.TITLE)
	SettingsPanel:GetLayout(category):AddInitializer(initializer)
	Settings.RegisterAddOnCategory(category)
end
