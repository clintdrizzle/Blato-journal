-- BlatoLexicon minimap button: the standard round button on the minimap's edge.
-- Left-click opens the journal, right-click writes a quick note, drag moves it around the minimap.
-- It is a child of the minimap, so ForeverImmersion fades it together with the minimap.
local _, ns = ...
local J, UI = ns.J, ns.UI
local DB = J.DB

local button = CreateFrame("Button", "BlatoLexiconMinimapButton", Minimap)
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")
local bg = button:CreateTexture(nil, "BACKGROUND")
bg:SetSize(20, 20)
bg:SetTexture("Interface/Minimap/UI-Minimap-Background")
bg:SetPoint("TOPLEFT", 7, -5)
local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetSize(18, 18)
icon:SetTexture(UI.ICON)
icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
icon:SetPoint("TOPLEFT", 7, -6)
local border = button:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
border:SetPoint("TOPLEFT")

-- Square minimaps (some UIs) keep the button on the square's edge instead of the circle.
local function Place()
    local angle = math.rad(DB.minimapAngle or 200)
    local x, y = math.cos(angle), math.sin(angle)
    local r = (Minimap:GetWidth() / 2) + 5
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        x, y = math.max(-1, math.min(1, x * 1.414)), math.max(-1, math.min(1, y * 1.414))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * r, y * r)
end

local function Drag()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    DB.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
    Place()
end
button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", Drag) end)
button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
button:SetScript("OnClick", function(_, which)
    if which == "RightButton" then UI.NoteDialog() else UI.Toggle() end
end)
button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Blato Lexicon", 1, 1, 1)
    GameTooltip:AddLine("Left-click to open your lexicon.", 0.9, 0.82, 0.6)
    GameTooltip:AddLine("Right-click to write a quick note.", 0.9, 0.82, 0.6)
    GameTooltip:AddLine("Drag to move around the minimap.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
button:SetScript("OnLeave", GameTooltip_Hide)

function UI.UpdateMinimapButton()
    button:SetShown(DB.minimap)
    Place()
end
