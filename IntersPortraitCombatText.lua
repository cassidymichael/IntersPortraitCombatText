-- Combat feedback text (damage, heals, misses) on anchors the player places.
local ADDON, ns = ...

local FADE_IN, FADE_OUT = 0.2, 0.3
local PHYSICAL = 1
local WHEEL_STEP = 2
local UNITS = {
	{ unit = "player", label = "PLAYER", on = true, x = -220, y = -80, size = 30 },
	{ unit = "target", label = "TARGET", on = false, x = 220, y = -80, size = 30 },
	{ unit = "pet", label = "PET", on = false, x = -220, y = -170, size = 30 },
}
local DEFAULTS = {
	font = "", outline = "OUTLINE", shadow = false, alpha = 1, hold = 0.7, crit = 1.5,
	damage = true, heals = true, avoids = true, gains = true, minDamage = 0, minHeal = 0, minGain = 0,
	numbers = "FULL", signs = false, schools = false,
	colorPhysical = "ffffffff", colorSpell = "ffffff00", colorHeal = "ff00ff00", colorGain = "ff69ccf0",
	colorAvoid = "ffffffff",
}
-- Saved for the account, outside profiles
local ACCOUNT = { snap = true, grid = false, gridSize = 32 }
local DEFAULT_PROFILE = "Default"
local SHARE_PREFIX, SHARE_VERSION = "!IPCT1!", 1
-- { least, most, step }: a slider's step is also the finest value that can be typed
local RANGES = {
	x = { -10000, 10000, 1 }, y = { -10000, 10000, 1 },
	size = { 12, 72, 1 }, alpha = { 0.2, 1, 0.01 }, hold = { 0.2, 3, 0.05 }, crit = { 1, 2.5, 0.05 },
	minDamage = { 0, 1000, 1 }, minHeal = { 0, 1000, 1 }, minGain = { 0, 1000, 1 }, gridSize = { 8, 128, 4 },
}
local CHOICES = {
	outline = { [""] = true, OUTLINE = true, THICKOUTLINE = true },
	numbers = { FULL = true, PLAIN = true, SHORT = true },
}
-- A preview's events: what happened, its flag, the amount and the spell school
local SAMPLES = {
	{ "WOUND", "", 87, 1 }, { "WOUND", "CRITICAL", 1412, 1 }, { "WOUND", "", 0, 1 }, { "DODGE", "", 0, 1 },
	{ "PARRY", "", 0, 1 }, { "WOUND", "", 156, 4 }, { "WOUND", "CRITICAL", 503, 16 }, { "BLOCK", "", 0, 1 },
	{ "WOUND", "RESIST", 0, 32 }, { "WOUND", "GLANCING", 45, 1 }, { "HEAL", "", 240, 2 },
	{ "HEAL", "CRITICAL", 1731, 8 }, { "ENERGIZE", "", 64, 0 }, { "WOUND", "ABSORB", 0, 1 },
	{ "IMMUNE", "", 0, 1 },
}
local FONTS = {
	["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
	["Arial Narrow"] = "Fonts\\ARIALN.TTF",
	["Morpheus"] = "Fonts\\MORPHEUS.TTF",
	["Skurri"] = "Fonts\\SKURRI.TTF",
}
local SCHOOLS = {
	[2] = { 1, 0.9, 0.5 }, [4] = { 1, 0.5, 0 }, [8] = { 0.3, 1, 0.3 }, [16] = { 0.5, 1, 1 },
	[32] = { 0.5, 0.5, 1 }, [64] = { 1, 0.5, 1 },
}
ns.UNITS, ns.DEFAULTS, ns.RANGES = UNITS, DEFAULTS, RANGES

local WORDS = {}
for _, key in ipairs({ "INTERRUPT", "MISS", "RESIST", "DODGE", "PARRY", "BLOCK", "EVADE", "IMMUNE", "DEFLECT",
	"ABSORB", "REFLECT" }) do
	WORDS[key] = _G[key]
end
local BLOCK_REDUCED = _G.COMBAT_TEXT_BLOCK_REDUCED or "%s"

local acct, db, current
local frames = {}
ns.frames = frames
local colors = {}
local TITLE = "Inter's Portrait Combat Text"
ns.TITLE = TITLE
local unlocked = false
local selected
local preview = 0
local defaultFont = NumberFontNormalHuge:GetFont()
local secret = issecretvalue or function() return false end

local function say(text)
	print("|cffffd100Portrait Combat Text:|r " .. text)
end

ns.BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }

local function clamp(value, range)
	return math.min(range[2], math.max(range[1], value))
end
ns.clamp = clamp

-- Fonts

local function sharedMedia()
	local LibStub = _G.LibStub
	return LibStub and LibStub("LibSharedMedia-3.0", true)
end

function ns.fonts()
	local seen, list = {}, {}
	for name in pairs(FONTS) do
		seen[name] = true
		list[#list + 1] = name
	end
	local media = sharedMedia()
	for _, name in ipairs(media and media:List("font") or {}) do
		if not seen[name] then list[#list + 1] = name end
	end
	table.sort(list)
	return list
end

local function fontFile()
	if db.font == "" then return defaultFont end
	local media = sharedMedia()
	return media and media:Fetch("font", db.font, true) or FONTS[db.font] or defaultFont
end

-- SetFont fails on a file the client lacks
local function setFont(text, height)
	local ok = pcall(text.SetFont, text, fontFile(), height, db.outline)
	if not ok or not text:GetFont() then text:SetFont(defaultFont, height, db.outline) end
	if db.shadow then
		text:SetShadowColor(0, 0, 0, 1)
		text:SetShadowOffset(1, -1)
	else
		text:SetShadowOffset(0, 0)
	end
end

-- Feedback text

local function number(amount, sign)
	local text
	if db.numbers == "SHORT" and amount >= 1000 then
		local value, unit = amount / 1000, "k"
		if amount >= 1000000 then value, unit = amount / 1000000, "m" end
		text = ("%.1f"):format(value):gsub("%.0$", "") .. unit
	elseif db.numbers == "PLAIN" then
		text = ("%d"):format(amount)
	else
		text = BreakUpLargeNumbers(amount)
	end
	return db.signs and sign .. text or text
end

local function damageColor(school)
	if school == PHYSICAL then return colors.colorPhysical end
	return db.schools and SCHOOLS[school] or colors.colorSpell
end

-- Returns the text, its size factor and colour, or nothing for an event that shows no text.
local function feedback(event, flags, amount, school)
	if secret(event) or secret(flags) or secret(amount) or secret(school) then return end
	if event == "WOUND" and amount ~= 0 then
		if not db.damage or amount < db.minDamage then return end
		local text, scale = number(amount, "-"), 1
		if flags == "CRITICAL" or flags == "CRUSHING" then
			scale = db.crit
		elseif flags == "GLANCING" then
			scale = 0.75
		elseif flags == "BLOCK_REDUCED" then
			text = BLOCK_REDUCED:format(text)
		end
		return text, scale, damageColor(school)
	elseif event == "HEAL" then
		if not db.heals or amount < db.minHeal then return end
		return number(amount, "+"), flags == "CRITICAL" and db.crit or 1, colors.colorHeal
	elseif event == "ENERGIZE" then
		if not db.gains or amount < db.minGain then return end
		return number(amount, "+"), flags == "CRITICAL" and db.crit or 1, colors.colorGain
	elseif not db.avoids then
		return
	elseif event == "WOUND" then
		if flags == "ABSORB" or flags == "BLOCK" or flags == "RESIST" then
			return WORDS[flags], 0.75, colors.colorAvoid
		end
		return WORDS.MISS, 1, colors.colorAvoid
	elseif event == "IMMUNE" then
		return WORDS.IMMUNE, 0.5, colors.colorAvoid
	elseif event == "BLOCK" then
		return WORDS.BLOCK, 0.75, colors.colorAvoid
	end
	return WORDS[event], 1, colors.colorAvoid
end

local function fade(f)
	local t = GetTime() - f.started
	if t < FADE_IN then
		f.text:SetAlpha(db.alpha * t / FADE_IN)
	elseif t < FADE_IN + db.hold then
		f.text:SetAlpha(db.alpha)
	elseif t < FADE_IN + db.hold + FADE_OUT then
		f.text:SetAlpha(db.alpha * (1 - (t - FADE_IN - db.hold) / FADE_OUT))
	else
		f.text:Hide()
		f:SetScript("OnUpdate", nil)
	end
end

local function show(f, text, scale, color)
	if not text then return end
	setFont(f.text, f.opts.size * scale)
	f.text:SetText(text)
	f.text:SetTextColor(color[1], color[2], color[3])
	f.text:SetAlpha(0)
	f.text:Show()
	f.started = GetTime()
	f:SetScript("OnUpdate", fade)
end

local function onEvent(f, event, _, ...)
	if event == "UNIT_COMBAT" then
		show(f, feedback(...))
	else
		f.text:Hide()
		f:SetScript("OnUpdate", nil)
	end
end

-- Anchors

local function place(f)
	local o = f.opts
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER", o.x, o.y)
	f:SetSize(o.size * 2, o.size * 2)
end
ns.place = place

local function describe(f)
	f.label:SetText(("%s: text size %d"):format(f.name, f.opts.size))
end

-- Arrow keys move the selected box by 1 (Shift: 10). Keyboard capture is restricted in combat, so
-- only the arrows and Escape are kept, for the press itself, and the frame hides when combat starts.
local NUDGE_KEYS = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }
local nudger = CreateFrame("Frame", nil, UIParent)
nudger:Hide()

local function nudge(key)
	local d, o = NUDGE_KEYS[key], selected.opts
	local step = IsShiftKeyDown() and 10 or 1
	o.x, o.y = o.x + d[1] * step, o.y + d[2] * step
	place(selected)
end

local function syncNudger()
	local on = unlocked and selected ~= nil and selected.opts.on and not InCombatLockdown()
	if on and not nudger.keys then
		nudger:EnableKeyboard(true)
		nudger:SetPropagateKeyboardInput(true)
		nudger.keys = true
	end
	nudger:SetShown(on)
end

nudger:SetScript("OnKeyDown", function(self, key)
	if InCombatLockdown() then return self:Hide() end
	if NUDGE_KEYS[key] or key == "ESCAPE" then
		self:SetPropagateKeyboardInput(false)
		C_Timer.After(0, function()
			if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
		end)
		if key == "ESCAPE" then return ns.select(nil) end
		nudge(key)
		self.held, self.wait = key, 0.4
	end
end)
nudger:SetScript("OnKeyUp", function(self, key)
	if key == self.held then self.held = nil end
end)
nudger:SetScript("OnUpdate", function(self, elapsed)
	if not self.held then return end
	self.wait = self.wait - elapsed
	if self.wait <= 0 then
		nudge(self.held)
		self.wait = 0.04
	end
end)
nudger:SetScript("OnHide", function(self) self.held = nil end)

local function refresh(f)
	local o = f.opts
	place(f)
	f:SetBackdropColor(0, 0, 0, unlocked and 0.4 or 0)
	if unlocked and f == selected then
		f:SetBackdropBorderColor(1, 0.82, 0, 1)
	else
		f:SetBackdropBorderColor(0.2, 0.6, 1, unlocked and 0.9 or 0)
	end
	describe(f)
	f:SetShown(o.on)
	if o.on then
		f:RegisterUnitEvent("UNIT_COMBAT", f.unit)
	else
		f:UnregisterEvent("UNIT_COMBAT")
	end
	f:EnableMouse(unlocked)
	f:EnableMouseWheel(unlocked)
	f.label:SetShown(unlocked)
end

-- Previews

local function play(sample)
	for _, f in ipairs(frames) do
		show(f, feedback(sample[1], sample[2], sample[3], sample[4]))
	end
end

local function step(run, mode, i)
	if run ~= preview then return end
	local delay
	if mode == "fight" then
		play(SAMPLES[math.random(#SAMPLES)])
		delay = 0.3 + math.random() * 1.2
	else
		play(SAMPLES[i])
		i = i % #SAMPLES + 1
		delay = FADE_IN + db.hold + FADE_OUT + 0.1
	end
	C_Timer.After(delay, function() step(run, mode, i) end)
end

-- mode: "each" plays each sample in turn, "fight" plays them at random, until stopped; nil stops
function ns.preview(mode)
	preview = preview + 1
	ns.previewing = mode
	if mode then step(preview, mode, 1) end
	ns.updateHelpers()
end

-- One sample, for a setting just changed
function ns.sample()
	if ns.previewing then return end
	preview = preview + 1
	for _, f in ipairs(frames) do
		show(f, number(1412, "-"), db.crit, colors.colorPhysical)
	end
end

function ns.apply()
	for key in pairs(DEFAULTS) do
		if key:find("^color") then
			local hex = db[key]
			colors[key] = { tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255,
				tonumber(hex:sub(7, 8), 16) / 255 }
		end
	end
	for _, f in ipairs(frames) do refresh(f) end
	syncNudger()
end

-- The box the arrow keys move
function ns.select(f)
	selected = f
	ns.apply()
end

function ns.setUnlocked(state)
	unlocked = state
	ns.unlocked = state
	if unlocked and not (selected and selected.opts.on) then
		selected = nil
		for _, f in ipairs(frames) do
			if f.opts.on then
				selected = f
				break
			end
		end
	end
	ns.apply()
	ns.updateHelpers()
end

local function onDragStart(f)
	ns.select(f)
	ns.startDrag(f)
end

local function onMouseWheel(f, delta)
	local o = f.opts
	o.size = clamp(o.size + delta * WHEEL_STEP, RANGES.size)
	place(f)
	describe(f)
	show(f, number(1234, "-"), 1, colors.colorPhysical)
end

local function onMouseUp(_, button)
	if button == "RightButton" then ns.setUnlocked(false) end
end

local function build(spec)
	local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	f.unit, f.name = spec.unit, _G[spec.label]
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", onDragStart)
	f:SetScript("OnMouseDown", ns.select)
	f:SetScript("OnDragStop", function() ns.stopDrag() end)
	f:SetScript("OnMouseWheel", onMouseWheel)
	f:SetScript("OnMouseUp", onMouseUp)
	f:SetScript("OnEvent", onEvent)
	if spec.unit == "target" then f:RegisterEvent("PLAYER_TARGET_CHANGED") end

	f:SetBackdrop(ns.BACKDROP)
	f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.label:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 2)
	f.text = f:CreateFontString(nil, "OVERLAY")
	f.text:SetPoint("CENTER")
	f.text:SetFont(defaultFont, spec.size, "OUTLINE")
	f.text:Hide()
	return f
end

-- Settings

local function finite(v) return v == v and v ~= math.huge and v ~= -math.huge end

local function numeric(v, default, range)
	if type(v) ~= "number" or not finite(v) then v = default end
	return range and clamp(v, range) or v
end

-- A profile's settings made whole: a missing, mistyped or unknown value takes its default
local function clean(p)
	for key, default in pairs(DEFAULTS) do
		if type(p[key]) ~= type(default) then p[key] = default end
		if type(default) == "number" then p[key] = numeric(p[key], default, RANGES[key]) end
		if key:find("^color") and not p[key]:find("^%x%x%x%x%x%x%x%x$") then p[key] = default end
	end
	for key, choices in pairs(CHOICES) do
		if not choices[p[key]] then p[key] = DEFAULTS[key] end
	end
	for _, spec in ipairs(UNITS) do
		local o = type(p[spec.unit]) == "table" and p[spec.unit] or {}
		p[spec.unit] = o
		if type(o.on) ~= "boolean" then o.on = spec.on end
		o.x, o.y = numeric(o.x, spec.x, RANGES.x), numeric(o.y, spec.y, RANGES.y)
		o.size = numeric(o.size, spec.size, RANGES.size)
	end
	return p
end

local function loadSaved()
	acct = type(_G[ADDON .. "DB"]) == "table" and _G[ADDON .. "DB"] or {}
	_G[ADDON .. "DB"] = acct
	ns.acct = acct
	if type(acct.profiles) ~= "table" then
		wipe(acct)
		acct.profiles = {}
	end
	if type(acct.chars) ~= "table" then acct.chars = {} end
	if type(acct.minimap) ~= "table" then acct.minimap = {} end
	for key, default in pairs(ACCOUNT) do
		if type(acct[key]) ~= type(default) then acct[key] = default end
	end
	acct.gridSize = numeric(acct.gridSize, ACCOUNT.gridSize, RANGES.gridSize)
	for name, profile in pairs(acct.profiles) do
		if type(name) == "string" and type(profile) == "table" then
			clean(profile)
		else
			acct.profiles[name] = nil
		end
	end
	if not acct.profiles[DEFAULT_PROFILE] then acct.profiles[DEFAULT_PROFILE] = clean({}) end
end

-- Profiles

local function charKey()
	return UnitName("player") .. "-" .. GetRealmName()
end

function ns.profileName() return current end

function ns.profileNames()
	local names = {}
	for name in pairs(acct.profiles) do names[#names + 1] = name end
	table.sort(names, function(a, b) return a:lower() < b:lower() end)
	return names
end

-- Each character remembers its profile
function ns.useProfile(name)
	if not acct.profiles[name] then name = DEFAULT_PROFILE end
	acct.chars[charKey()] = { profile = name }
	current = name
	db = acct.profiles[name]
	ns.db = db
	for _, f in ipairs(frames) do f.opts = db[f.unit] end
	if selected and not selected.opts.on then selected = nil end
	ns.apply()
	ns.profileChanged()
end

local function checkNewName(name)
	if name == "" then return "a profile needs a name" end
	if acct.profiles[name] then return "there is already a profile called " .. name end
end

-- A new profile from source's settings, or a copy of the one in use. Returns why not, if it can't.
function ns.newProfile(name, source)
	name = strtrim(name or "")
	local err = checkNewName(name)
	if err then return err end
	acct.profiles[name] = clean(CopyTable(source or db))
	ns.useProfile(name)
end

function ns.renameProfile(name)
	local old = current
	if old == DEFAULT_PROFILE then return "the Default profile keeps its name" end
	name = strtrim(name or "")
	local err = checkNewName(name)
	if err then return err end
	acct.profiles[name], acct.profiles[old] = acct.profiles[old], nil
	for _, char in pairs(acct.chars) do
		if char.profile == old then char.profile = name end
	end
	ns.useProfile(name)
end

function ns.deleteProfile()
	if current == DEFAULT_PROFILE then return end
	acct.profiles[current] = nil
	ns.useProfile(DEFAULT_PROFILE)
end

function ns.resetProfile()
	acct.profiles[current] = clean({})
	ns.useProfile(current)
end

-- Sharing

function ns.exportProfile()
	local codec = C_EncodingUtil
	local ok, text = pcall(function()
		local method = Enum.CompressionMethod and Enum.CompressionMethod.Deflate
		local packed = codec.CompressString(codec.SerializeCBOR({ v = SHARE_VERSION, profile = db }), method)
		return SHARE_PREFIX .. codec.EncodeBase64(packed)
	end)
	if not ok then return nil, "export failed: " .. tostring(text) end
	return text
end

-- The settings in a share string, cleaned (the text is untrusted), or nil and why not
function ns.decodeProfile(text)
	local codec = C_EncodingUtil
	text = (text or ""):gsub("%s", "")
	if text:sub(1, #SHARE_PREFIX) ~= SHARE_PREFIX then return nil, "that isn't a profile of this addon" end
	local ok, data = pcall(function()
		local method = Enum.CompressionMethod and Enum.CompressionMethod.Deflate
		return codec.DeserializeCBOR(codec.DecompressString(codec.DecodeBase64(text:sub(#SHARE_PREFIX + 1)), method))
	end)
	if not ok or type(data) ~= "table" or type(data.profile) ~= "table" then
		return nil, "that profile text is damaged or incomplete"
	end
	if type(data.v) == "number" and data.v > SHARE_VERSION then
		return nil, "that profile needs a newer version of this addon"
	end
	local profile = {}
	for key in pairs(DEFAULTS) do profile[key] = data.profile[key] end
	for _, spec in ipairs(UNITS) do
		local o = data.profile[spec.unit]
		if type(o) == "table" then profile[spec.unit] = { on = o.on, x = o.x, y = o.y, size = o.size } end
	end
	return clean(profile)
end

-- Minimap button

local minimapIcon
function ns.applyMinimap()
	local LibStub = _G.LibStub
	local broker = LibStub and LibStub("LibDataBroker-1.1", true)
	local icon = LibStub and LibStub("LibDBIcon-1.0", true)
	if not (broker and icon) then return end
	if not minimapIcon then
		local launcher = broker:NewDataObject(ADDON, {
			type = "launcher", text = TITLE, icon = "Interface\\AddOns\\" .. ADDON .. "\\Art\\Minimap",
			OnClick = function(_, button)
				if button == "RightButton" then
					ns.setUnlocked(not unlocked)
				else
					ns.openOptions()
				end
			end,
			OnTooltipShow = function(tip)
				tip:AddLine(TITLE)
				tip:AddLine("Click: options", 1, 0.82, 0)
				tip:AddLine(unlocked and "Right-click: lock" or "Right-click: unlock to move and resize", 1, 0.82, 0)
			end,
		})
		icon:Register(ADDON, launcher, acct.minimap)
		minimapIcon = icon
	end
	if acct.minimap.hide then minimapIcon:Hide(ADDON) else minimapIcon:Show(ADDON) end
end

local function command(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "" then
		ns.openOptions()
	elseif msg == "move" or msg == "lock" then
		ns.setUnlocked(not unlocked)
	elseif msg == "unlock" then
		ns.setUnlocked(true)
	elseif msg == "preview" then
		ns.preview(not ns.previewing and "each" or nil)
	elseif msg == "test" then
		ns.preview("each")
	elseif msg == "test fight" then
		ns.preview("fight")
	elseif msg == "stop" then
		ns.preview()
	elseif msg == "reset" then
		for _, spec in ipairs(UNITS) do
			local o = db[spec.unit]
			o.x, o.y, o.size = spec.x, spec.y, spec.size
		end
		ns.apply()
		say("positions and sizes reset.")
	else
		say("/pct: options. /pct lock: unlock or lock. /pct preview: preview on or off. /pct reset: positions and "
			.. "sizes back.")
	end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_REGEN_DISABLED")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		nudger:Hide()
		return ns.preview()
	elseif event == "PLAYER_REGEN_ENABLED" then
		return syncNudger()
	end
	loadSaved()
	for i, spec in ipairs(UNITS) do frames[i] = build(spec) end
	local saved = acct.chars[charKey()]
	ns.useProfile(saved and saved.profile or DEFAULT_PROFILE)
	ns.applyMinimap()
	ns.buildOptions()
	_G["SLASH_" .. ADDON:upper() .. "1"] = "/pct"
	_G["SLASH_" .. ADDON:upper() .. "2"] = "/ipct"
	SlashCmdList[ADDON:upper()] = command
end)
