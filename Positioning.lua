-- Unlock mode's helpers: snapping, the grid, the unlock tray and the preview panel.
local _, ns = ...

local SNAP = 8
local GOLD, BLUE = { 0.85, 0.71, 0.42, 0.9 }, { 0.2, 0.6, 1, 0.9 }

-- Grid and snap guides

local grid = CreateFrame("Frame", nil, UIParent)
grid:SetAllPoints(UIParent)
grid:SetFrameStrata("BACKGROUND")
grid:Hide()
grid.lines = {}

local function drawGrid()
	local w, h = UIParent:GetSize()
	local size = ns.acct.gridSize
	local n = 0
	local function line(vertical, offset)
		n = n + 1
		local t = grid.lines[n]
		if not t then
			t = grid:CreateTexture(nil, "BACKGROUND")
			grid.lines[n] = t
		end
		t:ClearAllPoints()
		if offset == 0 then t:SetColorTexture(0.2, 0.6, 1, 0.5) else t:SetColorTexture(1, 1, 1, 0.1) end
		if vertical then
			t:SetPoint("TOP", grid, "TOP", offset, 0)
			t:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
			t:SetWidth(1)
		else
			t:SetPoint("LEFT", grid, "LEFT", 0, offset)
			t:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
			t:SetHeight(1)
		end
		t:Show()
	end
	for k = 0, math.floor(w / 2 / size) do
		line(true, k * size)
		if k > 0 then line(true, -k * size) end
	end
	for k = 0, math.floor(h / 2 / size) do
		line(false, k * size)
		if k > 0 then line(false, -k * size) end
	end
	for i = n + 1, #grid.lines do grid.lines[i]:Hide() end
end

local guides = CreateFrame("Frame", nil, UIParent)
guides:SetAllPoints(UIParent)
guides:SetFrameStrata("BACKGROUND")
guides:SetFrameLevel(grid:GetFrameLevel() + 5)
guides.x = guides:CreateTexture(nil, "ARTWORK")
guides.x:SetColorTexture(1, 0.82, 0, 0.8)
guides.x:SetWidth(1)
guides.x:Hide()
guides.y = guides:CreateTexture(nil, "ARTWORK")
guides.y:SetColorTexture(1, 0.82, 0, 0.8)
guides.y:SetHeight(1)
guides.y:Hide()

local function showGuides(gx, gy)
	guides.x:SetShown(gx ~= nil)
	guides.y:SetShown(gy ~= nil)
	if gx then
		guides.x:ClearAllPoints()
		guides.x:SetPoint("TOP", guides, "TOPLEFT", gx, 0)
		guides.x:SetPoint("BOTTOM", guides, "BOTTOMLEFT", gx, 0)
	end
	if gy then
		guides.y:ClearAllPoints()
		guides.y:SetPoint("LEFT", guides, "BOTTOMLEFT", 0, gy)
		guides.y:SetPoint("RIGHT", guides, "BOTTOMRIGHT", 0, gy)
	end
end

-- The nearest target within reach of an edge or the centre, else the nearest grid line
local function snapAxis(pos, half, targets, origin, size)
	local best, shift, guide = SNAP, nil, nil
	for _, t in ipairs(targets) do
		for _, e in ipairs({ -half, 0, half }) do
			local d = t - (pos + e)
			if math.abs(d) <= best then best, shift, guide = math.abs(d), d, t end
		end
	end
	if shift then return pos + shift, guide end
	if size then
		for _, e in ipairs({ -half, 0, half }) do
			local p = pos + e
			local d = origin + math.floor((p - origin) / size + 0.5) * size - p
			if not shift or math.abs(d) < math.abs(shift) then shift = d end
		end
		return pos + shift
	end
	return pos
end

local function snap(frame, x, y)
	local gx, gy
	if ns.acct.snap then
		local w, h = UIParent:GetSize()
		local tx, ty = { w / 2 }, { h / 2 }
		for _, f in ipairs(ns.frames) do
			if f ~= frame and f:IsShown() and f:GetLeft() then
				local l, r, b, t = f:GetLeft(), f:GetRight(), f:GetBottom(), f:GetTop()
				table.insert(tx, l); table.insert(tx, (l + r) / 2); table.insert(tx, r)
				table.insert(ty, b); table.insert(ty, (b + t) / 2); table.insert(ty, t)
			end
		end
		local size = ns.acct.grid and ns.acct.gridSize or nil
		x, gx = snapAxis(x, frame:GetWidth() / 2, tx, w / 2, size)
		y, gy = snapAxis(y, frame:GetHeight() / 2, ty, h / 2, size)
	end
	showGuides(gx, gy)
	return x, y
end

-- Dragged by hand rather than with StartMoving, so a box can snap while it moves
local dragger = CreateFrame("Frame", nil, UIParent)
dragger:Hide()
dragger:SetScript("OnUpdate", function(self)
	local f = self.moved
	local scale = UIParent:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local x, y = snap(f, cx / scale + self.dx, cy / scale + self.dy)
	local ux, uy = UIParent:GetCenter()
	f.opts.x, f.opts.y = x - ux, y - uy
	ns.place(f)
end)

function ns.startDrag(f)
	local scale = UIParent:GetEffectiveScale()
	local fx, fy = f:GetCenter()
	local cx, cy = GetCursorPosition()
	dragger.moved, dragger.dx, dragger.dy = f, fx - cx / scale, fy - cy / scale
	dragger:Show()
end

function ns.stopDrag()
	dragger:Hide()
	showGuides()
end

-- Panels

local function panel(width, height, border)
	local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	f:SetSize(width, height)
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetScript("OnHide", f.StopMovingOrSizing)
	f:SetBackdrop(ns.BACKDROP)
	f:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
	f:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
	f:Hide()
	return f
end

local function button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local function check(parent, label, key)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb.Text:SetFontObject("GameFontHighlightSmall")
	cb.Text:SetText(label)
	cb:SetScript("OnClick", function(self)
		ns.acct[key] = self:GetChecked() and true or false
		ns.updateHelpers()
	end)
	return cb
end

-- The tray while unlocked
local tray = panel(640, 138, BLUE)
tray:SetPoint("TOP", UIParent, "TOP", 0, -120)
do
	local title = tray:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -10)
	title:SetText(ns.TITLE .. ": positioning unlocked")
	local HELP = {
		{ "Drag", "Move a box" },
		{ "Click, then arrow keys", "Nudge it (Shift: 10x)" },
		{ "Mouse wheel", "Text size" },
		{ "Right-click", "Lock" },
	}
	local LINE_H, KEY_W = 16, 150
	for i, h in ipairs(HELP) do
		local key = tray:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		key:SetPoint("TOPLEFT", 10, -30 - (i - 1) * LINE_H)
		key:SetText(h[1])
		local what = tray:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		what:SetPoint("TOPLEFT", 10 + KEY_W, -30 - (i - 1) * LINE_H)
		what:SetText(h[2])
	end
	local row = CreateFrame("Frame", nil, tray)
	row:SetPoint("BOTTOMLEFT", 10, 8)
	row:SetPoint("BOTTOMRIGHT", -10, 8)
	row:SetHeight(26)
	tray.snap = check(row, "Snapping", "snap")
	tray.snap:SetPoint("LEFT", -4, 0)
	tray.grid = check(row, "Show grid", "grid")
	tray.grid:SetPoint("LEFT", tray.snap.Text, "RIGHT", 16, 0)
	local gridLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	gridLabel:SetPoint("LEFT", tray.grid.Text, "RIGHT", 16, 0)
	gridLabel:SetText("Grid size")
	local function stepper(text, delta)
		local b = button(row, text, 22, function()
			ns.acct.gridSize = ns.clamp(ns.acct.gridSize + delta, ns.RANGES.gridSize)
			ns.updateHelpers()
		end)
		b:SetHeight(20)
		return b
	end
	local down = stepper("-", -ns.RANGES.gridSize[3])
	down:SetPoint("LEFT", gridLabel, "RIGHT", 6, 0)
	tray.gridValue = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	tray.gridValue:SetPoint("LEFT", down, "RIGHT", 4, 0)
	tray.gridValue:SetWidth(26)
	local up = stepper("+", ns.RANGES.gridSize[3])
	up:SetPoint("LEFT", tray.gridValue, "RIGHT", 4, 0)
	local lock = button(row, "Lock", 70, function() ns.setUnlocked(false) end)
	lock:SetPoint("RIGHT", 0, 0)
	local options = button(row, "Options", 80, function() ns.openOptions() end)
	options:SetPoint("RIGHT", lock, "LEFT", -6, 0)
	tray.preview = button(row, "Show preview", 110, function()
		ns.preview(not ns.previewing and "each" or nil)
	end)
	tray.preview:SetPoint("RIGHT", options, "LEFT", -6, 0)
end

-- The panel while a preview plays
local MODES = { { "each", "Each kind" }, { "fight", "Fight" } }
local previewPanel = panel(600, 66, GOLD)
previewPanel:SetPoint("TOP", UIParent, "TOP", 0, -12)
do
	local title = previewPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -13)
	title:SetText(ns.TITLE .. ": preview")
	previewPanel.modes = {}
	for i, mode in ipairs(MODES) do
		local b = button(previewPanel, mode[2], 90, function() ns.preview(mode[1]) end)
		b:SetPoint("TOPLEFT", 10 + (i - 1) * 94, -36)
		previewPanel.modes[mode[1]] = b
	end
	local stop = button(previewPanel, "Stop preview", 110, function() ns.preview() end)
	stop:SetPoint("TOPRIGHT", -10, -8)
	local options = button(previewPanel, "Options", 80, function() ns.openOptions() end)
	options:SetPoint("RIGHT", stop, "LEFT", -6, 0)
	previewPanel.lock = button(previewPanel, "Unlock positioning", 140, function()
		ns.setUnlocked(not ns.unlocked)
	end)
	previewPanel.lock:SetPoint("RIGHT", options, "LEFT", -6, 0)
end

function ns.updateHelpers()
	local db, unlocked = ns.acct, ns.unlocked and true or false
	tray:SetShown(unlocked)
	tray.snap:SetChecked(db.snap)
	tray.grid:SetChecked(db.grid)
	tray.gridValue:SetText(db.gridSize)
	tray.preview:SetText(ns.previewing and "Stop preview" or "Show preview")
	grid:SetShown(unlocked and db.grid)
	if unlocked and db.grid then drawGrid() end
	if not unlocked then ns.stopDrag() end
	previewPanel:SetShown(ns.previewing ~= nil)
	previewPanel.lock:SetText(unlocked and "Lock positioning" or "Unlock positioning")
	-- The mode playing is the one that can't be pressed
	for key, b in pairs(previewPanel.modes) do b:SetEnabled(key ~= ns.previewing) end
	ns.refreshOptions()
end
