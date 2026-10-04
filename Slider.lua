-- The settings slider with a box to type the value in.
local ADDON = ...

local Base = _G.SettingsSliderControlMixin
local Slider = CreateFromMixins(Base)
_G[ADDON .. "SliderMixin"] = Slider

function Slider:OnLoad()
	Base.OnLoad(self)
	local box = CreateFrame("EditBox", nil, self, "InputBoxTemplate")
	box:SetSize(44, 20)
	box:SetPoint("LEFT", self.SliderWithSteppers.Slider, "RIGHT", 32, 0)
	box:SetAutoFocus(false)
	box:SetJustifyH("CENTER")
	box:SetScript("OnEnterPressed", function() self:Typed() end)
	box:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
	box:SetScript("OnEditFocusLost", function() self:ShowValue() end)
	self.Box = box
	self.Unit = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	self.Unit:SetPoint("LEFT", box, "RIGHT", 4, 0)
end

-- options.typed: scale (shown value = saved value x scale), decimals, unit
function Slider:Init(initializer)
	Base.Init(self, initializer)
	self.typed = initializer:GetOptions().typed
	self.Unit:SetText(self.typed.unit)
	self:ShowValue()
end

function Slider:ShowValue()
	local typed = self.typed
	self.Box:SetText(("%." .. typed.decimals .. "f"):format(self:GetSetting():GetValue() * typed.scale))
	self.Box:SetCursorPosition(0)
end

-- The setting keeps a typed value within its range
function Slider:Typed()
	local value = tonumber((self.Box:GetText():gsub(",", ".")))
	if value then self:GetSetting():SetValue(value / self.typed.scale) end
	self.Box:ClearFocus()
end

function Slider:SetValue(value)
	Base.SetValue(self, value)
	self:ShowValue()
end
