local _, ns = ...

ns.GUI = ns.GUI or {}
ns.GUI.Editor = ns.GUI.Editor or {}
ns.GUI.Editor.Inspector = ns.GUI.Editor.Inspector or {}

local AceGUI = LibStub("AceGUI-3.0")
local InspectorController = ns.GUI.Editor.Inspector
ns.GUI.Editor.Inspector = InspectorController
local InspectorBinding = InspectorController.InspectorBinding or {}
local InspectorContext = ns.InspectorContext or (ns.GUI.Editor.Inspector and ns.GUI.Editor.Inspector.Context) or {}
local InspectorTextSelection = ns.InspectorTextSelection or (ns.GUI.Editor.Inspector and ns.GUI.Editor.Inspector.TextSelection) or {}
local InspectorIndicatorSelection = ns.InspectorIndicatorSelection or (ns.GUI.Editor.Inspector and ns.GUI.Editor.Inspector.IndicatorSelection) or {}
local InspectorAuraSelection = ns.InspectorAuraSelection or (ns.GUI.Editor.Inspector and ns.GUI.Editor.Inspector.AuraSelection) or {}
local InspectorMutations = ns.InspectorMutations or (ns.GUI.Editor.Inspector and ns.GUI.Editor.Inspector.Mutations) or {}
local InspectorRefreshPolicy = ns.InspectorRefreshPolicy or (ns.GUI.Editor.Inspector and ns.GUI.Editor.Inspector.RefreshPolicy) or {}
local MediaOptionAdapter = ns.GUI.Editor.Inspector and ns.GUI.Editor.Inspector.MediaOptionAdapter or {}
local OptionValues = ns.GUI.Helpers and ns.GUI.Helpers.OptionValues or {}
local EditorStateApi = ns.GUI.Editor and ns.GUI.Editor.State or {}
local ObjectSelection = ns.GUI.Editor and ns.GUI.Editor.ObjectSelection or {}
local CastBar = ns.UnitFrameCastBar or {}

local L = ns.L or {}
local FormWidgets = ns.GUI.Helpers and ns.GUI.Helpers.FormWidgets or {}
local ResolveItemColor = FormWidgets.ResolveItemColor
local Shared = ns.GUI.Editor.SidebarShared or {}

local POINTS = Shared.POINTS or {}
local INDICATOR_META = Shared.INDICATOR_META or {}
local AddSpacer = Shared.AddSpacer
local CreateSection = Shared.CreateSection
local BuildLocalizedList = Shared.BuildLocalizedList
local function LabelledControl(create, slot, disabledRole)
    return function(parent, caption, ...)
        local widget = create(parent, caption, ...)
        if type(caption) == "string" and caption ~= "" then
            FormWidgets.BindLabelTypography(widget, slot, "inspector_label", disabledRole)
        end
        return widget
    end
end
local AddCheckBox = LabelledControl(Shared.AddCheckBox, "text", true)
local AddSlider = LabelledControl(Shared.AddSlider, "label", true)
local AddDropdown = LabelledControl(Shared.AddDropdown, "label", false)

local AddColorPicker = Shared.AddColorPicker
local BuildTextList = Shared.BuildTextList
local BuildIndicatorList = Shared.BuildIndicatorList
local GetFirstIndicatorKey = Shared.GetFirstIndicatorKey
local BuildAuraList = Shared.BuildAuraList
local GetFirstAuraKey = Shared.GetFirstAuraKey
local GetFirstTextId = Shared.GetFirstTextId
local INSPECTOR_SECTION_SPACING = 10
-- Strides include the gap added by the surrounding AceGUI Flow layout.
local INSPECTOR_FLOW_GAP = 3
local INSPECTOR_ROW_STRIDES = {
    COMPACT = 32,
    SLIDER = 48,
    DOUBLE = 64,
    TRIPLE = 96,
}
local activeTextFontSizeControl
local activeCanvasWheelFieldControl
local activeCanvasDirectMoveOffsetControls
local activeCanvasDecorationSizeControls
local activeInspectorDiagnosticHosts = {}

-- TEMP DIAGNOSTIC: Inspector 1px-line investigation.
-- Intentionally kept for 2.0.6; remove after root cause is confirmed.
local function InspectorDiagnosticMessage(message)
    if ns and ns.Info then
        ns:Info("[FP InspectorTexture] " .. tostring(message or ""))
    elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("[FP InspectorTexture] " .. tostring(message or ""))
    end
end

local function InspectorDiagnosticPoints(region)
    if not (region and region.GetNumPoints and region.GetPoint) then
        return "none"
    end

    local points = {}
    for index = 1, region:GetNumPoints() do
        local point, relativeTo, relativePoint, offsetX, offsetY = region:GetPoint(index)
        points[#points + 1] = string.format(
            "%s>%s:%s@%s,%s",
            tostring(point),
            tostring(relativeTo),
            tostring(relativePoint),
            tostring(offsetX),
            tostring(offsetY)
        )
    end
    return #points > 0 and table.concat(points, " | ") or "none"
end

local function InspectorDiagnosticColor(texture)
    local red, green, blue, alpha
    if texture and texture.GetColorTexture then
        red, green, blue, alpha = texture:GetColorTexture()
    end
    if red == nil and texture and texture.GetVertexColor then
        red, green, blue, alpha = texture:GetVertexColor()
    end
    return red, green, blue, alpha
end

function InspectorController.DebugVisibleRowTextures()
    local reportedHosts = 0
    local reportedTextures = 0

    for _, host in ipairs(activeInspectorDiagnosticHosts) do
        local widget = host.widget
        local frame = widget and widget.frame
        if frame and frame.IsVisible and frame:IsVisible() then
            reportedHosts = reportedHosts + 1
            InspectorDiagnosticMessage(string.format(
                "host role=%s label=%s widget=%s type=%s frame=%s parent=%s w=%s h=%s points=%s",
                tostring(host.role),
                tostring(host.label),
                tostring(widget),
                tostring(widget.type),
                tostring(frame),
                tostring(frame:GetParent()),
                tostring(frame:GetWidth()),
                tostring(frame:GetHeight()),
                InspectorDiagnosticPoints(frame)
            ))

            for _, region in ipairs({ frame:GetRegions() }) do
                if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                    local red, green, blue, alpha = InspectorDiagnosticColor(region)
                    local layer = region.GetDrawLayer and region:GetDrawLayer() or nil
                    local isDivider = widget._fpDivider == region
                    local isCandidate = isDivider
                        or (region:GetHeight() >= 0.5 and region:GetHeight() <= 1.5
                            and layer == "ARTWORK"
                            and region:IsShown())
                    reportedTextures = reportedTextures + 1
                    InspectorDiagnosticMessage(string.format(
                        "%s texture=%s host=%s parent=%s w=%s h=%s layer=%s color=%s,%s,%s,%s path=%s atlas=%s shown=%s visible=%s points=%s",
                        isDivider and "CONFIRMED _fpDivider" or (isCandidate and "CANDIDATE" or "texture"),
                        tostring(region),
                        tostring(widget),
                        tostring(region:GetParent()),
                        tostring(region:GetWidth()),
                        tostring(region:GetHeight()),
                        tostring(layer),
                        tostring(red),
                        tostring(green),
                        tostring(blue),
                        tostring(alpha),
                        tostring(region:GetTexture()),
                        tostring(region.GetAtlas and region:GetAtlas() or nil),
                        tostring(region:IsShown()),
                        tostring(region:IsVisible()),
                        InspectorDiagnosticPoints(region)
                    ))
                end
            end

            if widget._fpDivider and widget._fpDivider.GetObjectType then
                InspectorDiagnosticMessage(string.format(
                    "divider host=%s exists=true texture=%s height=%s layer=%s shown=%s visible=%s points=%s",
                    tostring(widget),
                    tostring(widget._fpDivider),
                    tostring(widget._fpDivider:GetHeight()),
                    tostring(widget._fpDivider:GetDrawLayer()),
                    tostring(widget._fpDivider:IsShown()),
                    tostring(widget._fpDivider:IsVisible()),
                    InspectorDiagnosticPoints(widget._fpDivider)
                ))
            end
        end
    end

    InspectorDiagnosticMessage(string.format("summary visibleHosts=%d textureRegions=%d", reportedHosts, reportedTextures))
end
local MEDIA_TYPE_FONT = "font"
local MEDIA_TYPE_STATUSBAR = "statusbar"
local MEDIA_TYPE_DECORATION = "decoration"
local DEFAULT_FONT_REFERENCE = "fp:font:standard"
local DEFAULT_STATUSBAR_REFERENCE = "fp:statusbar:blizzard-default"
local DEFAULT_DECORATION_REFERENCE = "fp:decoration:shadow1"
local deleteTextInstanceDialog
local deleteDecorationDialog
local function NormalizeInspectorUnitKey(unitKey)
    if type(unitKey) ~= "string" or unitKey == "" then
        return nil
    end
    if unitKey:match("^boss%d+$") then
        return "boss"
    end
    return unitKey
end

local function NormalizeInspectorTextFontSize(value)
    value = tonumber(value) or 12
    if value < 6 then
        value = 6
    elseif value > 32 then
        value = 32
    end
    return math.floor(value + 0.5)
end

local function GetInspectorObjectKey(objectRef)
    if type(objectRef) ~= "table" then
        return nil
    end
    return objectRef.objectKey or objectRef.auraKey
end

local function IsSameInspectorObject(left, right)
    return type(left) == "table"
        and type(right) == "table"
        and left.kind == right.kind
        and NormalizeInspectorUnitKey(left.unit) == NormalizeInspectorUnitKey(right.unit)
        and GetInspectorObjectKey(left) == GetInspectorObjectKey(right)
end

local function RegisterActiveCanvasWheelFieldControl(unitKey, objectRef, fieldName, widget)
    local selected = ObjectSelection.GetSelectedObject and ObjectSelection.GetSelectedObject() or nil
    if not IsSameInspectorObject(selected, objectRef) then
        return
    end
    activeCanvasWheelFieldControl = {
        unitKey = NormalizeInspectorUnitKey(unitKey),
        objectRef = objectRef,
        fieldName = fieldName,
        widget = widget,
        suppress = false,
    }
end

local function IsActiveCanvasWheelFieldControlSuppressed(widget)
    local control = activeCanvasWheelFieldControl
    return type(control) == "table" and control.widget == widget and control.suppress == true
end

function InspectorController.SetActiveCanvasWheelFieldValue(unitKey, objectRef, fieldName, value)
    local control = activeCanvasWheelFieldControl
    local selected = ObjectSelection.GetSelectedObject and ObjectSelection.GetSelectedObject() or nil
    if type(control) ~= "table"
        or control.unitKey ~= NormalizeInspectorUnitKey(unitKey)
        or control.fieldName ~= fieldName
        or not IsSameInspectorObject(control.objectRef, objectRef)
        or not IsSameInspectorObject(selected, objectRef)
        or type(control.widget) ~= "table"
    then
        return false
    end

    control.suppress = true
    local ok = pcall(function()
        if control.widget.SetValue then
            control.widget:SetValue(value)
        elseif control.widget.SetText then
            control.widget:SetText(tostring(value))
        end
    end)
    control.suppress = false
    return ok == true
end

local function RegisterActiveCanvasDecorationSizeControls(unitKey, objectRef, widthControl, heightControl)
    local selected = ObjectSelection.GetSelectedObject and ObjectSelection.GetSelectedObject() or nil
    if not IsSameInspectorObject(selected, objectRef) then
        return
    end
    activeCanvasDecorationSizeControls = {
        unitKey = NormalizeInspectorUnitKey(unitKey),
        objectRef = objectRef,
        widthControl = widthControl,
        heightControl = heightControl,
        suppress = false,
    }
end

local function IsActiveCanvasDecorationSizeControlSuppressed(widget)
    local controls = activeCanvasDecorationSizeControls
    return type(controls) == "table" and controls.suppress == true
        and (controls.widthControl == widget or controls.heightControl == widget)
end

function InspectorController.SetActiveCanvasDecorationSizeValues(unitKey, objectRef, width, height)
    local controls = activeCanvasDecorationSizeControls
    local selected = ObjectSelection.GetSelectedObject and ObjectSelection.GetSelectedObject() or nil
    if type(controls) ~= "table"
        or controls.unitKey ~= NormalizeInspectorUnitKey(unitKey)
        or not IsSameInspectorObject(controls.objectRef, objectRef)
        or not IsSameInspectorObject(selected, objectRef)
        or type(controls.widthControl) ~= "table"
        or type(controls.heightControl) ~= "table"
    then
        return false
    end

    controls.suppress = true
    local ok = pcall(function()
        controls.widthControl:SetValue(width)
        controls.heightControl:SetValue(height)
    end)
    controls.suppress = false
    return ok == true
end

local function RegisterActiveCanvasDirectMoveOffsetControls(unitKey, objectRef, offsetXControl, offsetYControl, pointControl, relativePointControl)
    local selected = ObjectSelection.GetSelectedObject and ObjectSelection.GetSelectedObject() or nil
    if not IsSameInspectorObject(selected, objectRef) then
        return
    end
    activeCanvasDirectMoveOffsetControls = {
        unitKey = NormalizeInspectorUnitKey(unitKey),
        objectRef = objectRef,
        offsetXControl = offsetXControl,
        offsetYControl = offsetYControl,
        pointControl = pointControl,
        relativePointControl = relativePointControl,
        suppress = false,
    }
end

local function IsActiveCanvasDirectMoveOffsetControlSuppressed(widget)
    local controls = activeCanvasDirectMoveOffsetControls
    return type(controls) == "table"
        and controls.suppress == true
        and (controls.offsetXControl == widget or controls.offsetYControl == widget or controls.pointControl == widget or controls.relativePointControl == widget)
end

function InspectorController.SetActiveCanvasDirectMoveOffsetValues(unitKey, objectRef, offsetX, offsetY)
    local controls = activeCanvasDirectMoveOffsetControls
    local selected = ObjectSelection.GetSelectedObject and ObjectSelection.GetSelectedObject() or nil
    if type(controls) ~= "table"
        or controls.unitKey ~= NormalizeInspectorUnitKey(unitKey)
        or not IsSameInspectorObject(controls.objectRef, objectRef)
        or not IsSameInspectorObject(selected, objectRef)
        or type(controls.offsetXControl) ~= "table"
        or type(controls.offsetYControl) ~= "table"
    then
        return false
    end

    controls.suppress = true
    local ok = pcall(function()
        if objectRef.kind == "bar" and objectRef.objectKey == "CastBar" then
            local frame = ns.frames and ns.frames[unitKey == "boss" and "boss1" or unitKey]
            local config = ns.UnitFrameUtils.GetUnitDB(unitKey)
            local minX, maxX, minY, maxY = ns.GUI.Editor.AnchorGeometry.ResolveCastBarOffsetRange(frame, config, offsetX, offsetY)
            controls.offsetXControl:SetSliderValues(minX, maxX, 1)
            controls.offsetYControl:SetSliderValues(minY, maxY, 1)
        end
        controls.offsetXControl:SetValue(offsetX)
        controls.offsetYControl:SetValue(offsetY)
    end)
    controls.suppress = false
    return ok == true
end

function InspectorController.SetActiveCanvasDirectMoveAnchorValues(unitKey, objectRef, value)
    local controls = activeCanvasDirectMoveOffsetControls
    local selected = ObjectSelection.GetSelectedObject and ObjectSelection.GetSelectedObject() or nil
    if type(controls) ~= "table"
        or controls.unitKey ~= NormalizeInspectorUnitKey(unitKey)
        or not IsSameInspectorObject(controls.objectRef, objectRef)
        or not IsSameInspectorObject(selected, objectRef)
        or type(controls.pointControl) ~= "table"
        or type(controls.relativePointControl) ~= "table"
        or type(controls.offsetXControl) ~= "table"
        or type(controls.offsetYControl) ~= "table"
        or type(value) ~= "table"
    then
        return false
    end

    controls.suppress = true
    local ok = pcall(function()
        controls.pointControl:SetValue(value.point)
        controls.relativePointControl:SetValue(value.relativePoint)
        controls.offsetXControl:SetValue(value.offsetX)
        controls.offsetYControl:SetValue(value.offsetY)
    end)
    controls.suppress = false
    return ok == true
end

local function RegisterActiveTextFontSizeControl(unitKey, textKey, widget)
    activeTextFontSizeControl = {
        unitKey = NormalizeInspectorUnitKey(unitKey),
        textKey = textKey,
        widget = widget,
        suppress = false,
    }
end

function InspectorController.SetActiveTextFontSizeValue(unitKey, textKey, value)
    local control = activeTextFontSizeControl
    if type(control) ~= "table"
        or control.unitKey ~= NormalizeInspectorUnitKey(unitKey)
        or control.textKey ~= textKey
        or not (control.widget and control.widget.SetValue)
    then
        return false
    end

    control.suppress = true
    local ok = pcall(function()
        control.widget:SetValue(NormalizeInspectorTextFontSize(value))
    end)
    control.suppress = false
    return ok == true
end

function InspectorController.Build(container, state, options)
    local perf = ns and ns.SelectionPerfDebug
    local perfStart = perf and perf.Begin and perf:Begin("InspectorController.Build")

    options = options or {}
    local buildContextOnly = options.buildContextOnly == true
    local buildPropertiesOnly = options.buildPropertiesOnly == true


    activeTextFontSizeControl = nil
    activeCanvasWheelFieldControl = nil
    activeCanvasDirectMoveOffsetControls = nil
    activeCanvasDecorationSizeControls = nil
    activeInspectorDiagnosticHosts = {}
    container:ReleaseChildren()
    container:SetLayout("Flow")

    local barLayouts = ns.GUI and ns.GUI.Layouts and ns.GUI.Layouts.UnitBars or {}
    local frameLayouts = ns.GUI and ns.GUI.Layouts and ns.GUI.Layouts.UnitFrame or {}
    local textLayouts = ns.GUI and ns.GUI.Layouts and ns.GUI.Layouts.UnitTexts or {}
    local portraitLayouts = ns.GUI and ns.GUI.Layouts and ns.GUI.Layouts.UnitPortrait or {}
    local classificationLayouts = ns.GUI and ns.GUI.Layouts and ns.GUI.Layouts.UnitClassificationIndicator or {}
    local statusIndicatorLayouts = ns.GUI and ns.GUI.Layouts and ns.GUI.Layouts.UnitStatusIndicator or {}
    local auraLayouts = ns.GUI and ns.GUI.Layouts and ns.GUI.Layouts.UnitAuras or {}

    local barAnchorList = BuildLocalizedList(barLayouts.Lists and barLayouts.Lists.anchorPoints)
    local textAnchorTargetList = BuildLocalizedList(textLayouts.Lists and textLayouts.Lists.anchorTo)
    local textAnchorPointList = BuildLocalizedList(textLayouts.Lists and textLayouts.Lists.anchorPoints)
    local fontStyleList = BuildLocalizedList(textLayouts.Lists and textLayouts.Lists.fontStyles)
    local justifyList = BuildLocalizedList(textLayouts.Lists and textLayouts.Lists.justifyH)
    local overflowList = BuildLocalizedList(textLayouts.Lists and textLayouts.Lists.overflowMode)
    local frameStrataList = BuildLocalizedList(frameLayouts.Lists and frameLayouts.Lists.frameStrata)
    local portraitPlacementList = BuildLocalizedList(portraitLayouts.Lists and portraitLayouts.Lists.placement)
    local portraitInsideSideList = BuildLocalizedList(portraitLayouts.Lists and portraitLayouts.Lists.insideSide)
    local portraitAnchorTargetList = BuildLocalizedList(portraitLayouts.Lists and portraitLayouts.Lists.anchorTo)
    local portraitAnchorPointList = BuildLocalizedList(portraitLayouts.Lists and portraitLayouts.Lists.anchorPoints)
    local classificationEffectList = BuildLocalizedList(classificationLayouts.Lists and classificationLayouts.Lists.effect)
    local statusIndicatorEffectList = BuildLocalizedList(statusIndicatorLayouts.Lists and statusIndicatorLayouts.Lists.effect)
    local auraPlacementList = BuildLocalizedList(auraLayouts.Lists and auraLayouts.Lists.placement)
    local auraAnchorPointList = BuildLocalizedList(auraLayouts.Lists and auraLayouts.Lists.anchorPoints)
    local auraInsideSideList = BuildLocalizedList(auraLayouts.Lists and auraLayouts.Lists.insideSide)
    local auraGrowthXList = BuildLocalizedList(auraLayouts.Lists and auraLayouts.Lists.growthX)
    local auraGrowthYList = BuildLocalizedList(auraLayouts.Lists and auraLayouts.Lists.growthY)
    local auraSortModeList = BuildLocalizedList(auraLayouts.Lists and auraLayouts.Lists.sortMode)
    local decorationTargetList = {
        FRAME = L["EDITOR_SECTION_FRAME"] or "Frame",
        PORTRAIT = L["EDITOR_SECTION_PORTRAIT"] or "Portrait",
    }
    local decorationConditionList = {
        ALWAYS = L["OPTION_ALWAYS"] or "Always",
        ELITE = L["CLASSIFICATION_ELITE"] or "Elite",
        RARE = L["CLASSIFICATION_RARE"] or "Rare",
        RAREELITE = L["CLASSIFICATION_RAREELITE"] or "Rare-Elite",
        BOSS = L["CLASSIFICATION_BOSS"] or "Boss",
    }
    local absorbAnchorTargetList = {
        Frame = textAnchorTargetList.Frame or (L["EDITOR_SECTION_FRAME"] or "Frame"),
        HealthBar = textAnchorTargetList.HealthBar or (L["BAR_HEALTH"] or "Health"),
        PowerBar = textAnchorTargetList.PowerBar or (L["BAR_POWER"] or "Power"),
    }
    local absorbSizeModeList = {
        MATCH_TARGET = L["OPTION_MATCH_TARGET"] or "Match Target",
        CUSTOM = L["OPTION_CUSTOM"] or "Custom",
    }
    local castBarWidthModeList = {
        MATCH_FRAME = L["OPTION_MATCH_FRAME"] or "Match Frame",
        CUSTOM = L["OPTION_CUSTOM"] or "Custom",
    }
    local absorbGrowthList = {
        LEFT_TO_RIGHT = L["OPTION_LEFT_TO_RIGHT"] or "Left to Right",
        RIGHT_TO_LEFT = L["OPTION_RIGHT_TO_LEFT"] or "Right to Left",
    }
    local lowHealthThresholdList = {
        ["1.0"] = L["OPTION_LOW_HEALTH_THRESHOLD_100"] or "100%",
        ["0.75"] = L["OPTION_LOW_HEALTH_THRESHOLD_75"] or "75%",
        ["0.5"] = L["OPTION_LOW_HEALTH_THRESHOLD_50"] or "50%",
        ["0.3"] = L["OPTION_LOW_HEALTH_THRESHOLD_30"] or "30%",
    }

    local function BuildDecorationTextureOptions(currentValue)
        if MediaOptionAdapter and MediaOptionAdapter.BuildDecorationDropdown then
            return MediaOptionAdapter.BuildDecorationDropdown(currentValue)
        end

        return {
            values = {},
            order = {},
            value = currentValue,
        }
    end

    local function GetDecorationList(currentInspectorContext, currentUnitConfig)
        if type(InspectorMutations.GetDecorationList) == "function" then
            return InspectorMutations.GetDecorationList(currentInspectorContext) or {}
        end
        return type(currentUnitConfig) == "table" and type(currentUnitConfig.decorations) == "table" and currentUnitConfig.decorations or {}
    end

    local function BuildDecorationLabel(decoration, index)
        local condition = type(decoration) == "table" and decoration.condition or nil
        local target = type(decoration) == "table" and decoration.target or nil
        local conditionLabel = decorationConditionList[condition or "ALWAYS"] or condition or (L["OPTION_ALWAYS"] or "Always")
        local targetLabel = decorationTargetList[target or "FRAME"] or target or (L["EDITOR_SECTION_FRAME"] or "Frame")
        return string.format("%s %d - %s - %s", L["EDITOR_SECTION_DECORATION"] or "Decoration", index or 1, conditionLabel, targetLabel)
    end

    local function ResolveSelectedDecoration(currentInspectorContext, currentUnitConfig)
        local decorations = GetDecorationList(currentInspectorContext, currentUnitConfig)
        if #decorations == 0 then
            state.selectedDecorationId = nil
            return nil, nil, decorations
        end

        local selectedDecorationId = state.selectedDecorationId
        local selectedDecoration = nil
        for _, decoration in ipairs(decorations) do
            if type(decoration) == "table" and decoration.id == selectedDecorationId then
                selectedDecoration = decoration
                break
            end
        end

        if not selectedDecoration then
            selectedDecoration = decorations[1]
            selectedDecorationId = type(selectedDecoration) == "table" and selectedDecoration.id or nil
            state.selectedDecorationId = selectedDecorationId
        end

        return selectedDecorationId, selectedDecoration, decorations
    end

    local function BuildDecorationSelectorOptions(decorations)
        local values = {}
        local order = {}
        for index, decoration in ipairs(decorations or {}) do
            if type(decoration) == "table" and type(decoration.id) == "string" and decoration.id ~= "" then
                values[decoration.id] = BuildDecorationLabel(decoration, index)
                order[#order + 1] = decoration.id
            end
        end
        return {
            values = values,
            order = order,
        }
    end

    local function BuildStatusBarTextureOptions(currentValue)
        if MediaOptionAdapter and MediaOptionAdapter.BuildStatusBarDropdown then
            return MediaOptionAdapter.BuildStatusBarDropdown(currentValue)
        end

        return {
            values = {},
            order = {},
            value = currentValue,
        }
    end

    local function ResolveOptionValueLabel(options, value)
        if type(options) == "table" then
            local values = type(options.values) == "table" and options.values or nil
            if values and type(value) == "string" and values[value] ~= nil then
                return tostring(values[value])
            end
            local selected = options.value
            if values and type(selected) == "string" and values[selected] ~= nil then
                return tostring(values[selected])
            end
        end
        if type(value) == "string" and value ~= "" then
            return value
        end
        return L["OPTION_NONE"] or "None"
    end

    local function BuildFontOptions(currentValue)
        if MediaOptionAdapter and MediaOptionAdapter.BuildFontDropdown then
            return MediaOptionAdapter.BuildFontDropdown(currentValue)
        end

        return {
            values = {},
            order = {},
            value = currentValue,
        }
    end

    local function GetActiveProfileTextTemplates()
        local templates = ns.UnitFrameUtils
            and ns.UnitFrameUtils.GetTextTemplatesDB
            and ns.UnitFrameUtils.GetTextTemplatesDB()
            or nil
        return type(templates) == "table" and templates or {}
    end

    local function GetEditableActivePayload()
        local resolver = ns.ActiveLayoutResolver
        if resolver and resolver.EnsureEditableForMutation then
            local payload = resolver.EnsureEditableForMutation(ns.db)
            return type(payload) == "table" and payload or nil
        end
        return nil
    end

    local function GetEditableUnitConfig(unitKey)
        local payload = GetEditableActivePayload()
        local units = type(payload) == "table" and payload.Units or nil
        local normalizedUnit = ns.UnitFrameUtils
            and ns.UnitFrameUtils.NormalizeConfigUnitKey
            and ns.UnitFrameUtils.NormalizeConfigUnitKey(unitKey)
            or unitKey
        return type(units) == "table" and units[normalizedUnit] or nil
    end

    local function BuildTextStateTemplateOptions(currentValue, entityMode)
        if entityMode == true then
            local values = { __none = L["TEXT_STATE_TEMPLATE_NONE"] or "None" }
            local order = { "__none" }
            local rows = ns.TextTemplateLibrary and ns.TextTemplateLibrary.Entity
                and ns.TextTemplateLibrary.Entity.List and ns.TextTemplateLibrary.Entity.List(ns.db) or {}
            for _, row in ipairs(rows or {}) do
                if type(row) == "table" and type(row.value) == "string" and type(row.label) == "string" then
                    values[row.value] = row.label
                    order[#order + 1] = row.value
                end
            end
            if type(currentValue) == "string" and currentValue ~= "" and values[currentValue] == nil then
                values[currentValue] = string.format("%s: %s", L["MEDIA_LIBRARY_MISSING"] or "Missing", currentValue)
                order[#order + 1] = currentValue
            end
            return {values = values, order = order,
                value = (type(currentValue) == "string" and currentValue ~= "") and currentValue or "__none"}
        end
        local values = {
            __none = L["TEXT_STATE_TEMPLATE_NONE"] or "None",
        }
        local order = { "__none" }
        local templates = GetActiveProfileTextTemplates()
        local templateNames = {}

        for templateName, templateValue in pairs(templates) do
            if type(templateName) == "string" and templateName ~= "" and type(templateValue) == "string" then
                templateNames[#templateNames + 1] = templateName
            end
        end

        table.sort(templateNames)
        for _, templateName in ipairs(templateNames) do
            values[templateName] = templateName
            order[#order + 1] = templateName
        end

        if type(currentValue) == "string" and currentValue ~= "" and values[currentValue] == nil then
            values[currentValue] = string.format("%s: %s", L["MEDIA_LIBRARY_MISSING"] or "Missing", currentValue)
            order[#order + 1] = currentValue
        end

        return {
            values = values,
            order = order,
            value = (type(currentValue) == "string" and currentValue ~= "") and currentValue or "__none",
        }
    end

    local function IsMediaBrowserAvailable()
        return ns.GUI
            and ns.GUI.Editor
            and ns.GUI.Editor.MediaLibrary
            and type(ns.GUI.Editor.MediaLibrary.Open) == "function"
    end

    local function AddMediaBrowseButton(section, disabled, onClick, options)
        if not section or not IsMediaBrowserAvailable() then
            return nil
        end

        options = type(options) == "table" and options or {}
        local button = AceGUI:Create("Button")
        if FormWidgets.ResetInspectorButtonState then
            FormWidgets.ResetInspectorButtonState(button)
        end
        button:SetText(options.label or L["MEDIA_LIBRARY_BROWSE"] or "Browse...")
        button:SetFullWidth(options.fullWidth == true)
        button:SetWidth(options.width or 112)
        button:SetDisabled(disabled and true or false)
        button:SetCallback("OnClick", function()
            if disabled or type(onClick) ~= "function" then
                return
            end
            onClick()
        end)
        if FormWidgets.ApplyModalActionButtonVisual then
            FormWidgets.ApplyModalActionButtonVisual(button, "utility")
        end
        if FormWidgets.SetInspectorButtonTooltip then
            FormWidgets.SetInspectorButtonTooltip(button, nil)
        end

        section:AddChild(button)
        return button
    end

    local function OpenMediaBrowserForField(options)
        options = type(options) == "table" and options or {}
        local MediaLibrary = ns.GUI
            and ns.GUI.Editor
            and ns.GUI.Editor.MediaLibrary
        if not (MediaLibrary and type(MediaLibrary.Open) == "function") then
            return
        end

        MediaLibrary.Open({
            mediaType = options.mediaType,
            currentValue = type(options.currentValue) == "function" and options.currentValue() or options.currentValue,
            defaultReference = options.fallbackReference,
            title = options.title,
            onApply = function(selectedValue, selectedItem)
                if type(options.onApply) == "function" then
                    options.onApply(selectedValue, selectedItem)
                end
            end,
        })
    end

    local function AddMediaBrowserForField(section, mediaType, currentValue, fallbackReference, title, disabled, onApply, buttonOptions)
        return AddMediaBrowseButton(section, disabled, function()
            OpenMediaBrowserForField({
                mediaType = mediaType,
                currentValue = currentValue,
                fallbackReference = fallbackReference,
                title = title,
                onApply = onApply,
            })
        end, buttonOptions)
    end

    local function SyncDropdownToStoredValue(dropdown, value)
        if dropdown and dropdown.SetValue then
            dropdown:SetValue(value)
        end
    end

    textAnchorTargetList.CastBar = textAnchorTargetList.CastBar or (L["BAR_CAST"] or "Cast Bar")
    textAnchorTargetList.AlternativePowerBar = textAnchorTargetList.AlternativePowerBar or (L["BAR_ALT_POWER"] or "Alt Power")
    textAnchorTargetList.ClassPowerBar = textAnchorTargetList.ClassPowerBar or (L["BAR_CLASS_POWER"] or "Class Power")
    local classPowerAnchorTargetList = {
        Frame = textAnchorTargetList.Frame or (L["EDITOR_SECTION_FRAME"] or "Frame"),
        HealthBar = textAnchorTargetList.HealthBar or (L["BAR_HEALTH"] or "Health"),
        PowerBar = textAnchorTargetList.PowerBar or (L["BAR_POWER"] or "Power"),
        AlternativePowerBar = textAnchorTargetList.AlternativePowerBar or (L["BAR_ALT_POWER"] or "Alt Power"),
        CastBar = textAnchorTargetList.CastBar or (L["BAR_CAST"] or "Cast"),
    }

    local inspectorContext = InspectorContext.Create and InspectorContext.Create({
        state = state,
        profile = ns.db and ns.db.profile,
        getUnitConfig = function(unitKey)
            return ns.UnitFrameUtils and ns.UnitFrameUtils.GetUnitDB and ns.UnitFrameUtils.GetUnitDB(unitKey) or nil
        end,
        getEditablePayload = GetEditableActivePayload,
        getEditableUnitConfig = GetEditableUnitConfig,
        buildTextList = function(_, currentUnitConfig)
            return BuildTextList(type(currentUnitConfig) == "table" and currentUnitConfig.Texts or nil)
        end,
        getFirstTextId = GetFirstTextId,
        buildIndicatorList = function(unitKey)
            return BuildIndicatorList(unitKey)
        end,
        getFirstIndicatorKey = GetFirstIndicatorKey,
        indicatorMeta = INDICATOR_META,
        buildAuraList = function(_, currentUnitConfig)
            return BuildAuraList(currentUnitConfig)
        end,
        getFirstAuraKey = GetFirstAuraKey,
    }) or {}

    inspectorContext.entity = true

    local isQuick = inspectorContext.isQuick == true
    local isExpert = inspectorContext.isExpert == true
    local selectedUnit = inspectorContext.unitKey
    local unitConfig = inspectorContext.unitConfig
    if type(unitConfig) ~= "table" then
        local label = AceGUI:Create("Label")
        label:SetFullWidth(true)
        label:SetText("Missing unit config.")
        container:AddChild(label)
        return
    end

    local function ResolveSelectedUnitLabel()
        if ns.GetLabel and ns.KeyMap and ns.KeyMap.Units then
            return ns.GetLabel(ns.KeyMap.Units, selectedUnit) or selectedUnit
        end
        return selectedUnit
    end

    local function ResolveTextContext()
        local currentTextList = BuildTextList(type(unitConfig) == "table" and unitConfig.Texts or nil)
        local visualTextUnit = state and state.selectedTextElementUnit
        local visualTextId = state and state.selectedTextElementId
        if visualTextUnit == selectedUnit
            and type(visualTextId) == "string"
            and visualTextId ~= ""
            and type(unitConfig.Texts) == "table"
            and type(unitConfig.Texts[visualTextId]) == "table"
            and currentTextList[visualTextId] == nil
        then
            currentTextList[visualTextId] = visualTextId
        end
        if type(InspectorTextSelection.Resolve) == "function" and InspectorContext.GetTextSelection then
            local result = InspectorTextSelection.Resolve({
                state = state,
                textList = currentTextList,
                unitConfig = unitConfig,
                getFirstTextId = GetFirstTextId,
            })
            local selectedTextId, textConfig, linkedTemplateName = InspectorContext.GetTextSelection({
                textSelection = result,
            })
            return selectedTextId, textConfig, linkedTemplateName, result, currentTextList
        end

        return nil, nil, nil, nil, currentTextList
    end

    local function BuildMissingTemplateMessages(textId)
        local payload = ns.ActiveLayoutResolver.GetActivePayloadRoot(ns.db)
        if not payload or not textId then return {} end
        local messages = {}
        for _, ref in ipairs(ns.TextTemplateUsage.ScanEntities({active={payload=payload}})) do
            if ref.unitKey == selectedUnit and ref.textKey == textId
                and not ns.TextTemplateLibrary.ResolveTemplateEntity(ref.templateId, ns.db) then
                messages[#messages+1] = "Missing template: " .. ref.templateId
                    .. (ref.stateKey and (" (" .. ref.stateKey .. ")") or "")
            end
        end
        return messages
    end

    local function ResolveIndicatorContext()
        local currentIndicatorList = type(BuildIndicatorList) == "function" and BuildIndicatorList(selectedUnit) or {}
        if type(InspectorIndicatorSelection.Resolve) == "function" and InspectorContext.GetIndicatorSelection then
            local result = InspectorIndicatorSelection.Resolve({
                state = state,
                indicatorList = currentIndicatorList,
                indicatorMeta = INDICATOR_META,
                unitConfig = unitConfig,
                unitKey = selectedUnit,
                getFirstIndicatorKey = GetFirstIndicatorKey,
            })
            local selectedIndicatorKey, indicatorMeta, indicatorConfig = InspectorContext.GetIndicatorSelection({
                indicatorSelection = result,
            })
            return selectedIndicatorKey, indicatorMeta, indicatorConfig, result, currentIndicatorList
        end

        return nil, nil, nil, nil, currentIndicatorList
    end

    local function ResolveAuraContext()
        local currentAuraList = type(BuildAuraList) == "function" and BuildAuraList(unitConfig) or {}
        if type(InspectorAuraSelection.Resolve) == "function" and InspectorContext.GetAuraSelection then
            local result = InspectorAuraSelection.Resolve({
                state = state,
                auraList = currentAuraList,
                unitConfig = unitConfig,
                getFirstAuraKey = GetFirstAuraKey,
            })
            local selectedAuraKey, auraConfig = InspectorContext.GetAuraSelection({
                auraSelection = result,
            })
            return selectedAuraKey, auraConfig, result, currentAuraList
        end

        return nil, nil, nil, currentAuraList
    end

    local function NotifyConfigChanged()
        if options.onConfigChanged then
            options.onConfigChanged()
        end
    end

    local function NotifyUnitEnabledChanged()
        if options.onUnitEnabledChanged then
            options.onUnitEnabledChanged()
        else
            NotifyConfigChanged()
        end
    end

    local function NotifySidebarChanged(sectionKey)
        if options.onSidebarChanged then
            options.onSidebarChanged(sectionKey)
        else
            NotifyConfigChanged()
        end
    end

    local function NotifySelectionChanged(changeKind)
        if options.onSelectionChanged then
            options.onSelectionChanged(changeKind)
            return
        end
        NotifySidebarChanged()
    end

    local function NotifyCompositionTreeChanged()
        if options.onCompositionTreeChanged then
            options.onCompositionTreeChanged()
        end
    end

    local function AffectsCompositionTreeProjection(targetKind, fieldName)
        if targetKind == "text" then
            return fieldName == "enabled" or fieldName == "anchorTo"
        end
        if targetKind == "indicator" then
            return fieldName == "enabled" or fieldName == "present"
        end
        if targetKind == "aura" or targetKind == "decoration" then
            return fieldName == "enabled"
        end
        return targetKind == "unit"
            and (
                fieldName == "showPowerBar"
                or fieldName == "powerBarPresent"
                or fieldName == "showCastBar"
                or fieldName == "castBarPresent"
                or fieldName == "showClassPowerBar"
                or fieldName == "showAlternativePowerBar"
                or fieldName == "showNormalAbsorbBar"
                or fieldName == "normalAbsorbBarPresent"
                or fieldName == "showHealingAbsorbBar"
                or fieldName == "healingAbsorbBarPresent"
            )
    end

    local function RebuildLocalSection(section)
        if section and section._focalPointRequestRebuild then
            section._focalPointRequestRebuild()
            return true
        end
        return false
    end

    local function NotifyConfigChangedAndRebuildSection(section, fallbackSectionKey)
        NotifyConfigChanged()
        if not RebuildLocalSection(section) and fallbackSectionKey then
            NotifySidebarChanged(fallbackSectionKey)
        end
    end

    local function ApplyRefreshPolicy(policy, section)
        local scope = type(policy) == "table" and policy.scope or "live"
        if scope == "none" then
            return
        end
        if scope == "section" then
            NotifyConfigChangedAndRebuildSection(section, policy and policy.sectionKey)
            return
        end
        if scope == "unitEnabled" then
            NotifyUnitEnabledChanged()
            return
        end
        if scope == "sidebar" then
            NotifySidebarChanged(policy and policy.sectionKey)
            return
        end

        NotifyConfigChanged()
    end

    local function ResolveMutationErrorMessage(result)
        local errorCode = type(result) == "table" and result.errorCode or nil
        if errorCode == "unit_config_not_found" then
            return L["EDITOR_INSPECTOR_ERROR_UNIT_CONFIG_NOT_FOUND"] or L["EDITOR_INSPECTOR_ERROR_CHANGE_FAILED"]
        elseif errorCode == "text_config_not_found" then
            return L["EDITOR_INSPECTOR_ERROR_TEXT_CONFIG_NOT_FOUND"] or L["EDITOR_INSPECTOR_ERROR_CHANGE_FAILED"]
        elseif errorCode == "unit_not_found" then
            return L["EDITOR_INSPECTOR_ERROR_UNIT_CONFIG_NOT_FOUND"] or L["EDITOR_INSPECTOR_ERROR_CHANGE_FAILED"]
        elseif errorCode == "text_element_not_found" then
            return L["EDITOR_INSPECTOR_ERROR_TEXT_CONFIG_NOT_FOUND"] or L["EDITOR_INSPECTOR_ERROR_CHANGE_FAILED"]
        elseif errorCode == "indicator_config_not_found" then
            return L["EDITOR_INSPECTOR_ERROR_INDICATOR_CONFIG_NOT_FOUND"] or L["EDITOR_INSPECTOR_ERROR_CHANGE_FAILED"]
        elseif errorCode == "aura_config_not_found" then
            return L["EDITOR_INSPECTOR_ERROR_AURA_CONFIG_NOT_FOUND"] or L["EDITOR_INSPECTOR_ERROR_CHANGE_FAILED"]
        elseif errorCode == "template_not_found" then
            return L["INFO_TEXT_BUILDER_STATUS_SELECT_TEMPLATE"] or L["EDITOR_INSPECTOR_ERROR_CHANGE_FAILED"]
        elseif errorCode == "invalid_template_name" or errorCode == "state_key_invalid" then
            return L["EDITOR_INSPECTOR_ERROR_CHANGE_FAILED"]
        end

        return L["EDITOR_INSPECTOR_ERROR_CHANGE_FAILED"]
    end

    local function ReportMutationError(result)
        if ns.GUI and type(ns.GUI.SetStatusText) == "function" then
            ns.GUI:SetStatusText(ResolveMutationErrorMessage(result))
        end
    end

    local function ApplyMutation(targetKind, fieldName, result, section, fallbackNotify)
        if result and result.ok == false then
            ReportMutationError(result)
            return result
        end

        if not (result and result.ok and result.changed) then
            return result
        end

        if type(fallbackNotify) == "function" then
            fallbackNotify()
            return result
        end

        local policy = type(InspectorRefreshPolicy.Resolve) == "function"
            and InspectorRefreshPolicy.Resolve(targetKind, fieldName)
            or { scope = "live" }
        ApplyRefreshPolicy(policy, section)
        if AffectsCompositionTreeProjection(targetKind, fieldName) then
            NotifyCompositionTreeChanged()
        end
        return result
    end

    local function RequestEditableMutation(action)
        local workflow = ns.LayoutEditWorkflow
        if not (workflow and workflow.RequestEditableLayoutForMutation) then
            return nil
        end
        local result = nil
        local ready = workflow.RequestEditableLayoutForMutation(function()
            result = action()
        end)
        if result then
            return result
        end
        if ready == false then
            return { ok = true, changed = false, pending = true }
        end
        return nil
    end
    local function SetUnitField(fieldName, value, section, fallbackNotify)
        if type(InspectorMutations.SetUnitField) ~= "function" then
            return nil
        end
        return RequestEditableMutation(function() return ApplyMutation("unit", fieldName, InspectorMutations.SetUnitField(inspectorContext, fieldName, value), section, fallbackNotify) end)
    end

    local function SetUnitPresence(present)
        if type(InspectorMutations.SetUnitPresence) ~= "function" then
            return nil
        end
        return RequestEditableMutation(function() return InspectorMutations.SetUnitPresence(inspectorContext, present == true) end)
    end

    local function SetComponentPresence(componentKey, present)
        if type(InspectorMutations.SetComponentPresence) ~= "function" then
            return nil
        end
        return RequestEditableMutation(function() return InspectorMutations.SetComponentPresence(inspectorContext, componentKey, present == true) end)
    end

    local function SetTextField(textKey, fieldName, value, section, fallbackNotify)
        if type(InspectorMutations.SetTextField) ~= "function" then
            return nil
        end
        return RequestEditableMutation(function() return ApplyMutation("text", fieldName, InspectorMutations.SetTextField(inspectorContext, textKey, fieldName, value), section, fallbackNotify) end)
    end

    local function SetTextStateTemplate(textKey, stateKey, value, section, dropdown)
        local function SyncStoredTemplateValue()
            local textConfig = type(unitConfig.Texts) == "table" and unitConfig.Texts[textKey] or nil
            local stateTemplates = type(textConfig) == "table" and (inspectorContext.entity and textConfig.stateTemplateIds or textConfig.stateTemplates) or nil
            SyncDropdownToStoredValue(dropdown, type(stateTemplates) == "table" and stateTemplates[stateKey] or "__none")
        end
        local entitySelectionValid = value == "__none"
        if inspectorContext.entity and value ~= "__none" then
            local entity = ns.TextTemplateLibrary and ns.TextTemplateLibrary.ResolveTemplateEntity
                and ns.TextTemplateLibrary.ResolveTemplateEntity(value, ns.db)
            entitySelectionValid = entity ~= nil
        end
        if value ~= "__none" and ((not inspectorContext.entity and type(GetActiveProfileTextTemplates()[value]) ~= "string") or (inspectorContext.entity and not entitySelectionValid)) then
            SyncStoredTemplateValue()
            return { ok = true, changed = false }
        end

        local result = RequestEditableMutation(function()
            local mutationResult
            if value == "__none" then
                mutationResult = type(InspectorMutations.UnassignTextStateTemplate) == "function"
                    and InspectorMutations.UnassignTextStateTemplate(inspectorContext, textKey, stateKey)
                    or nil
            else
                mutationResult = type(InspectorMutations.AssignTextStateTemplate) == "function"
                    and InspectorMutations.AssignTextStateTemplate(inspectorContext, textKey, stateKey, value)
                    or nil
            end

            if mutationResult and mutationResult.ok == false then
                ReportMutationError(mutationResult)
                SyncStoredTemplateValue()
                return mutationResult
            end

            if mutationResult and mutationResult.ok and mutationResult.changed then
                NotifyConfigChangedAndRebuildSection(section, "texts")
                return mutationResult
            end

            SyncStoredTemplateValue()
            return mutationResult
        end)
        if result and result.pending then
            SyncStoredTemplateValue()
        end
        return result
    end

    local function RefreshTextFontSizeLocally(textKey, newValue)
        local overlay = ns.GUI
            and ns.GUI.Editor
            and ns.GUI.Editor.TextEditorOverlay
        local refreshed = overlay
            and overlay.RefreshTextElementByUnit
            and overlay.RefreshTextElementByUnit(state and state.selectedUnit, textKey)
            or false

        InspectorController.SetActiveTextFontSizeValue(state and state.selectedUnit, textKey, newValue)
        if not refreshed then
            NotifyConfigChanged()
        end
    end

    local function SetTextFontSize(textKey, value)
        if type(InspectorMutations.SetTextFontSize) ~= "function" then
            return nil
        end

        local requestedValue = value
        local textConfig = type(unitConfig.Texts) == "table" and unitConfig.Texts[textKey] or nil
        local storedValue = type(textConfig) == "table" and textConfig.fontSize or nil
        local result = RequestEditableMutation(function()
            local mutationResult = InspectorMutations.SetTextFontSize(inspectorContext, textKey, requestedValue)
            if mutationResult and mutationResult.ok == false then
                ReportMutationError(mutationResult)
                return mutationResult
            end
            if mutationResult and mutationResult.ok and mutationResult.changed then
                RefreshTextFontSizeLocally(textKey, mutationResult.newValue)
            end
            return mutationResult
        end)
        if result and result.pending then
            InspectorController.SetActiveTextFontSizeValue(state and state.selectedUnit, textKey, storedValue)
        end
        return result
    end

    local function IsSelectedTextObject(unitKey, textKey)
        local selected = type(ObjectSelection.GetSelectedObject) == "function"
            and ObjectSelection.GetSelectedObject()
            or nil
        return type(selected) == "table"
            and selected.kind == "text"
            and selected.unit == NormalizeInspectorUnitKey(unitKey)
            and selected.textKey == textKey
    end

    local function IsSelectedIndicatorObject(unitKey, indicatorKey)
        local selected = type(ObjectSelection.GetSelectedObject) == "function"
            and ObjectSelection.GetSelectedObject()
            or nil
        return type(selected) == "table"
            and selected.kind == "indicator"
            and selected.unit == NormalizeInspectorUnitKey(unitKey)
            and selected.indicatorKey == indicatorKey
    end

    local function IsSelectedAuraObject(unitKey, auraKey)
        local selected = type(ObjectSelection.GetSelectedObject) == "function"
            and ObjectSelection.GetSelectedObject()
            or nil
        return type(selected) == "table"
            and selected.kind == "aura"
            and selected.unit == NormalizeInspectorUnitKey(unitKey)
            and selected.auraKey == auraKey
    end

    local function IsSelectedDecorationObject(unitKey, decorationId)
        local selected = type(ObjectSelection.GetSelectedObject) == "function"
            and ObjectSelection.GetSelectedObject()
            or nil
        return type(selected) == "table"
            and selected.kind == "decoration"
            and selected.unit == NormalizeInspectorUnitKey(unitKey)
            and selected.decorationId == decorationId
    end

    local function IsSelectedUnitRootObject(unitKey)
        local selected = type(ObjectSelection.GetSelectedObject) == "function"
            and ObjectSelection.GetSelectedObject()
            or nil
        return type(selected) == "table"
            and selected.kind == "unit"
            and selected.unit == NormalizeInspectorUnitKey(unitKey)
    end

    local function CloseDeleteTextInstanceDialog()
        if deleteTextInstanceDialog and deleteTextInstanceDialog.Close then
            deleteTextInstanceDialog:Close()
        elseif deleteTextInstanceDialog and deleteTextInstanceDialog.window and deleteTextInstanceDialog.window.Hide then
            deleteTextInstanceDialog.window:Hide()
        end
        deleteTextInstanceDialog = nil
    end

    local function CloseDeleteDecorationDialog()
        if deleteDecorationDialog and deleteDecorationDialog.Close then
            deleteDecorationDialog:Close()
        elseif deleteDecorationDialog and deleteDecorationDialog.window and deleteDecorationDialog.window.Hide then
            deleteDecorationDialog.window:Hide()
        end
        deleteDecorationDialog = nil
    end

    local function SelectUnitRootAfterTextDelete(unitKey)
        local ok = false
        if type(ObjectSelection.SelectObject) == "function" then
            ok = ObjectSelection.SelectObject({
                kind = "unit",
                unit = unitKey,
            }) == true
        end
        if not ok then
            if EditorStateApi and type(EditorStateApi.SetSingleSelection) == "function" then
                EditorStateApi.SetSingleSelection(unitKey)
            end
            if EditorStateApi and type(EditorStateApi.ClearSelectedTextElement) == "function" then
                EditorStateApi.ClearSelectedTextElement()
            end
            if EditorStateApi and type(EditorStateApi.ClearPropertyScope) == "function" then
                EditorStateApi.ClearPropertyScope()
            end
        end
    end

    local function SelectUnitRoot(unitKey)
        local ok = false
        local changeKind
        if type(ObjectSelection.SelectObject) == "function" then
            ok, changeKind = ObjectSelection.SelectObject({
                kind = "unit",
                unit = unitKey,
            })
            ok = ok == true
        end
        if not ok then
            if EditorStateApi and type(EditorStateApi.SetSingleSelection) == "function" then
                EditorStateApi.SetSingleSelection(unitKey)
            end
            if EditorStateApi and type(EditorStateApi.ClearPropertyScope) == "function" then
                EditorStateApi.ClearPropertyScope()
            end
        end
        return ok, changeKind
    end

    local function SelectBar(unitKey, objectKey)
        if type(ObjectSelection.SelectObject) ~= "function" then
            return false
        end
        return ObjectSelection.SelectObject({
            kind = "bar",
            unit = unitKey,
            objectKey = objectKey,
        })
    end

    local function SelectIndicator(unitKey, indicatorKey)
        if type(ObjectSelection.SelectObject) ~= "function" then
            return false
        end
        return ObjectSelection.SelectObject({
            kind = "indicator",
            unit = unitKey,
            indicatorKey = indicatorKey,
            objectKey = indicatorKey,
        })
    end

    local function SelectAura(unitKey, auraKey)
        if type(ObjectSelection.SelectObject) ~= "function" then
            return false
        end
        return ObjectSelection.SelectObject({
            kind = "aura",
            unit = unitKey,
            auraKey = auraKey,
            objectKey = auraKey,
        })
    end

    local function ApplySingletonComponentPresence(componentKey, present, sectionKey, kind)
        local result = SetComponentPresence(componentKey, present == true)
        if result and result.ok == false then
            ReportMutationError(result)
            return result
        end
        if not (result and result.ok and result.changed) then
            return result
        end

        if type(ns.RefreshUnitFrame) == "function" and type(selectedUnit) == "string" and selectedUnit ~= "" then
            ns:RefreshUnitFrame(selectedUnit == "boss" and "boss" or selectedUnit)
        end
        NotifyCompositionTreeChanged()

        local ok, changeKind
        if present == true then
            if kind == "indicator" then
                ok, changeKind = SelectIndicator(selectedUnit, componentKey)
            elseif kind == "aura" then
                ok, changeKind = SelectAura(selectedUnit, componentKey)
            else
                ok, changeKind = SelectBar(selectedUnit, componentKey)
            end
        else
            ok, changeKind = SelectUnitRoot(selectedUnit)
        end
        if ok then
            NotifySelectionChanged(changeKind)
        else
            NotifySidebarChanged(present == true and (sectionKey or "frame") or "frame")
        end
        return result
    end

    local function ApplySingletonBarPresence(componentKey, present, sectionKey)
        return ApplySingletonComponentPresence(componentKey, present == true, sectionKey, "bar")
    end

    local function ApplySingletonIndicatorPresence(componentKey, present)
        return ApplySingletonComponentPresence(componentKey, present == true, "indicators", "indicator")
    end

    local function ApplySingletonAuraPresence(componentKey, present)
        return ApplySingletonComponentPresence(componentKey, present == true, "auras", "aura")
    end

    local function ApplyCastBarPresence(present)
        return ApplySingletonBarPresence("CastBar", present == true, "cast")
    end

    local function IsRemovableUnitRoot(unitKey)
        return unitKey == "pet"
            or unitKey == "targettarget"
            or unitKey == "focus"
            or unitKey == "focustarget"
            or unitKey == "boss"
    end

    local function ResolveRemoveUnitLabel(unitKey)
        if unitKey == "boss" then
            return L["EDITOR_REMOVE_BOSS_FRAMES_BUTTON"] or "Remove Boss Frames"
        end
        local template = L["EDITOR_REMOVE_UNIT_FRAME_BUTTON"] or "Remove %s"
        return string.format(template, ResolveSelectedUnitLabel())
    end

    local function RemoveSelectedUnitFrame()
        if not IsRemovableUnitRoot(selectedUnit) then
            return nil
        end
        local result = SetUnitPresence(false)
        if result and result.ok == false then
            ReportMutationError(result)
            return result
        end
        if not (result and result.ok and result.changed) then
            return result
        end

        if type(ns.ResyncActiveLayout) == "function" then
            ns:ResyncActiveLayout("Inspector.RemoveUnitFrame")
        else
            NotifySidebarChanged("frame")
        end
        NotifyCompositionTreeChanged()
        NotifySelectionChanged("unitChanged")
        return result
    end

    local function OpenDeleteTextInstanceConfirmDialog(unitKey, textKey)
        if not IsSelectedTextObject(unitKey, textKey) then
            return
        end
        if type(InspectorMutations.DeleteTextInstance) ~= "function" then
            return
        end
        if not (FormWidgets and type(FormWidgets.CreateCompactConfirmation) == "function") then
            return
        end

        CloseDeleteTextInstanceDialog()
        local dialog = FormWidgets.CreateCompactConfirmation({
            title = L["EDITOR_DELETE_TEXT_CONFIRM_TITLE"] or "Delete Text?",
            message = L["EDITOR_DELETE_TEXT_CONFIRM_DESCRIPTION"] or "This permanently removes this text from the selected unit.",
            hint = L["EDITOR_DELETE_TEXT_CONFIRM_TEMPLATE_NOTE"] or "The text template is not deleted.",
            messageHeight = 32,
            primary = {
                text = L["EDITOR_DELETE_TEXT_CONFIRM_BUTTON"] or "Delete",
                role = "danger",
                width = 104,
                onClick = function(activeDialog)
                    local overlay = ns.GUI and ns.GUI.Editor and ns.GUI.Editor.TextEditorOverlay or nil
                    if overlay and type(overlay.CancelActiveDrag) == "function" then
                        overlay.CancelActiveDrag()
                    end

                    local result = RequestEditableMutation(function()
                        local mutationResult = InspectorMutations.DeleteTextInstance(inspectorContext, textKey)
                        if mutationResult and mutationResult.ok == false then
                            return mutationResult
                        end

                        if mutationResult and mutationResult.ok and mutationResult.changed then
                            NotifyCompositionTreeChanged()
                        end
                        SelectUnitRootAfterTextDelete(unitKey)
                        NotifySidebarChanged("texts")
                        return mutationResult
                    end)
                    if result and result.ok == false then
                        if activeDialog and activeDialog.SetStatus then
                            activeDialog:SetStatus(ResolveMutationErrorMessage(result), "error", activeDialog.confirmationStatus)
                        end
                        return
                    end

                    CloseDeleteTextInstanceDialog()
                end,
            },
            cancel = {
                text = L["INFO_COMMON_CANCEL"] or "Cancel",
                role = "utility",
                width = 104,
                onClick = function()
                    CloseDeleteTextInstanceDialog()
                end,
            },
        })
        if not dialog then
            return
        end

        dialog.window:SetCallback("OnClose", function()
            if deleteTextInstanceDialog == dialog then
                deleteTextInstanceDialog = nil
            end
        end)
        deleteTextInstanceDialog = dialog
        dialog:Show()
    end

    local function SetIndicatorField(indicatorKey, fieldName, value, section, fallbackNotify)
        if type(InspectorMutations.SetIndicatorField) ~= "function" then
            return nil
        end
        return RequestEditableMutation(function() return ApplyMutation("indicator", fieldName, InspectorMutations.SetIndicatorField(inspectorContext, indicatorKey, fieldName, value), section, fallbackNotify) end)
    end

    local function SetAuraField(auraKey, fieldName, value, section, fallbackNotify)
        if type(InspectorMutations.SetAuraField) ~= "function" then
            return nil
        end
        return RequestEditableMutation(function() return ApplyMutation("aura", fieldName, InspectorMutations.SetAuraField(inspectorContext, auraKey, fieldName, value), section, fallbackNotify) end)
    end

    local function SetDecorationField(fieldName, value, section, fallbackNotify)
        if type(InspectorMutations.SetDecorationField) ~= "function" then
            return nil
        end
        local decorationId = state and state.selectedDecorationId
        if type(decorationId) ~= "string" or decorationId == "" then
            return nil
        end
        return RequestEditableMutation(function() return ApplyMutation("decoration", fieldName, InspectorMutations.SetDecorationField(inspectorContext, decorationId, fieldName, value), section, fallbackNotify) end)
    end

    local function RefreshInspectorLayout()
        if container and container.DoLayout then
            container:DoLayout()
        end
        if container and container.FixScroll then
            container:FixScroll()
        end
        local parent = container and container.parent or nil
        if parent and parent.DoLayout then
            parent:DoLayout()
        end
        if parent and parent.FixScroll then
            parent:FixScroll()
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if container and container.DoLayout then
                    container:DoLayout()
                end
                if container and container.FixScroll then
                    container:FixScroll()
                end
                local delayedParent = container and container.parent or nil
                if delayedParent and delayedParent.DoLayout then
                    delayedParent:DoLayout()
                end
                if delayedParent and delayedParent.FixScroll then
                    delayedParent:FixScroll()
                end
            end)
        end
    end

    local function CreateInspectorSection(sectionKey, title, defaultCollapsed, sectionOptions)
        return InspectorBinding.CreateInspectorSection(container, CreateSection, state, sectionKey, title, defaultCollapsed, NotifySidebarChanged, sectionOptions)
    end

    local function ResolvePropertyScope()
        if not buildPropertiesOnly then
            return nil
        end
        if type(state) ~= "table" then
            return nil
        end
        local scope = state.propertyScope
        if type(scope) ~= "table" or type(scope.sectionKey) ~= "string" or scope.sectionKey == "" then
            return nil
        end
        return scope
    end

    local function ShouldBuildSection(sectionKey)
        local scope = ResolvePropertyScope()
        if not scope then
            return true
        end
        return sectionKey == scope.sectionKey
    end

    local function AddScopedInspectorSection(sectionKey, title, defaultCollapsed, sectionOptions)
        if not ShouldBuildSection(sectionKey) then
            return nil
        end
        local scopedOptions = sectionOptions
        if ResolvePropertyScope() then
            scopedOptions = {}
            for key, value in pairs(sectionOptions or {}) do
                scopedOptions[key] = value
            end
            scopedOptions.forceExpanded = true
            scopedOptions.persistCollapse = false
        end
        AddSpacer(container, INSPECTOR_SECTION_SPACING)
        return CreateInspectorSection(sectionKey, title, defaultCollapsed, scopedOptions)
    end

    local function IsScopedPowerBarObjectMode()
        local scope = ResolvePropertyScope()
        return type(scope) == "table"
            and scope.kind == "unit"
            and scope.sectionKey == "power"
    end

    local function IsScopedAlternativePowerBarObjectMode()
        local scope = ResolvePropertyScope()
        return type(scope) == "table"
            and scope.kind == "unit"
            and scope.sectionKey == "alt_power"
    end

    local function IsScopedClassPowerBarObjectMode()
        local scope = ResolvePropertyScope()
        return type(scope) == "table"
            and scope.kind == "unit"
            and scope.sectionKey == "class_power"
    end

    local function IsScopedHealthBarObjectMode()
        local scope = ResolvePropertyScope()
        return type(scope) == "table"
            and scope.kind == "unit"
            and scope.sectionKey == "health"
    end

    local function IsScopedCastBarObjectMode()
        local scope = ResolvePropertyScope()
        return type(scope) == "table"
            and scope.kind == "unit"
            and scope.sectionKey == "cast"
    end

    local function ResolveScopedAbsorbObject()
        local scope = ResolvePropertyScope()
        if not (type(scope) == "table" and scope.kind == "unit" and scope.sectionKey == "absorbs") then
            return nil
        end
        if scope.objectKey == "NormalAbsorbBar" then
            return {
                objectKey = "NormalAbsorbBar",
                prefix = "normalAbsorbBar",
                showField = "showNormalAbsorbBar",
                title = L["OPTION_NORMAL_ABSORB"] or "Normal Absorb",
                headerTitle = L["OPTION_NORMAL_ABSORB"] or "Normal Absorb Bar",
                fallbackColor = { 0.66, 0.86, 1.0, 0.62 },
                fallbackGrowth = "LEFT_TO_RIGHT",
            }
        elseif scope.objectKey == "HealingAbsorbBar" then
            return {
                objectKey = "HealingAbsorbBar",
                prefix = "healingAbsorbBar",
                showField = "showHealingAbsorbBar",
                title = L["OPTION_HEALING_ABSORB"] or "Healing Absorb",
                headerTitle = L["OPTION_HEALING_ABSORB"] or "Healing Absorb Bar",
                fallbackColor = { 0.75, 0.20, 1.0, 0.62 },
                fallbackGrowth = "RIGHT_TO_LEFT",
            }
        end
        return nil
    end

    local function AddObjectInspectorHeader(parent, title, subtitle)
        local headerTitle = title or ""
        if type(subtitle) == "string" and subtitle ~= "" then
            headerTitle = subtitle .. " / " .. headerTitle
        end

        local titleLabel
        if FormWidgets.CreateBodyText then
            titleLabel = FormWidgets.CreateBodyText(headerTitle, "identity", 13, nil, nil, true)
        else
            titleLabel = AceGUI:Create("Label")
            titleLabel:SetFullWidth(true)
            titleLabel:SetText(headerTitle)
        end
        parent:AddChild(titleLabel)
    end

    local function AddScopedObjectInspectorBody(sectionKey, title, localContentBuilder)
        if not ShouldBuildSection(sectionKey) then
            return nil
        end

        AddSpacer(container, INSPECTOR_SECTION_SPACING)

        local root = AceGUI:Create("SimpleGroup")
        root:SetFullWidth(true)
        root:SetLayout("Flow")
        container:AddChild(root)

        AddObjectInspectorHeader(root, title, ResolveSelectedUnitLabel())
        AddSpacer(root, 6)

        local body = AceGUI:Create("SimpleGroup")
        body:SetFullWidth(true)
        body:SetLayout("Flow")
        root:AddChild(body)

        local function BuildBodyContent()
            body:ReleaseChildren()
            if type(localContentBuilder) == "function" then
                localContentBuilder(body)
            end
        end

        local function RebuildBody()
            BuildBodyContent()
            RefreshInspectorLayout()
        end

        body._focalPointRequestRebuild = RebuildBody
        if body.SetUserData then
            body:SetUserData("focalPointSectionKey", sectionKey)
            body:SetUserData("focalPointSectionRole", "content")
        end
        if body.frame then
            body.frame._focalPointSectionKey = sectionKey
            body.frame._focalPointSectionRole = "content"
        end

        BuildBodyContent()
        return body
    end

    local function AddObjectPropertyGroup(parent, title, addTopSpacing)
        if addTopSpacing then
            AddSpacer(parent, 10)
        end

        local group = AceGUI:Create("SimpleGroup")
        group:SetFullWidth(true)
        group:SetLayout("Flow")
        parent:AddChild(group)

        local header = AceGUI:Create("SimpleGroup")
        header:SetFullWidth(true)
        header:SetLayout("Table")
        header:SetUserData("table", {
            columns = {
                { width = 96 },
                { weight = 1 },
            },
            spaceH = 8,
            spaceV = 0,
            align = "TOPLEFT",
            alignV = "center",
            alignH = "start",
        })
        group:AddChild(header)

        local titleLabel
        if FormWidgets.CreateSectionTitle then
            titleLabel = FormWidgets.CreateSectionTitle(title or "", 12)
        else
            titleLabel = AceGUI:Create("Label")
            titleLabel:SetText(title or "")
        end
        titleLabel:SetFullWidth(false)
        titleLabel:SetWidth(96)
        header:AddChild(titleLabel)

        local separator = AceGUI:Create("SimpleGroup")
        separator:SetFullWidth(true)
        separator:SetHeight(12)
        header:AddChild(separator)
        if separator.frame and separator.frame.CreateTexture then
            local line = separator.frame:CreateTexture(nil, "ARTWORK")
            local color = ResolveItemColor and ResolveItemColor("sectionBorder") or { 0.16, 0.19, 0.24, 0.75 }
            line:SetPoint("LEFT", separator.frame, "LEFT", 0, 0)
            line:SetPoint("RIGHT", separator.frame, "RIGHT", 0, 0)
            line:SetHeight(1)
            line:SetColorTexture(color[1] or 0.16, color[2] or 0.19, color[3] or 0.24, color[4] or 0.75)
        end

        AddSpacer(group, 4)

        local content = AceGUI:Create("SimpleGroup")
        content:SetFullWidth(true)
        content:SetLayout("Flow")
        group:AddChild(content)

        return content
    end

    local function AddFramedObjectPropertyGroup(parent, title, addTopSpacing)
        if addTopSpacing then
            AddSpacer(parent, 8)
        end

        local group = CreateSection(parent, title, {
            collapsible = false,
            style = "default",
            titleTextRole = "strongHeading",
        })
        if group and InspectorBinding.ApplyInspectorSectionStructure then
            InspectorBinding.ApplyInspectorSectionStructure(group, "muted")
        end
        return group
    end

    local function AddPropertyLabel(parent, text)
        if not parent then
            return nil
        end

        local label
        if FormWidgets.CreateBodyText then
            label = FormWidgets.CreateBodyText(text or "", "label", 12, nil, nil, true)
        else
            label = AceGUI:Create("Label")
            label:SetFullWidth(true)
            label:SetText(text or "")
        end
        parent:AddChild(label)
        return label
    end

    local PROPERTY_LABEL_WIDTH = 108

    local function AddPropertyRow(parent, labelText, valueBuilder, options)
        if not parent then
            return nil, nil
        end

        options = type(options) == "table" and options or {}

        -- Unclassified text/specialized rows retain their content-driven layout.
        local stride = options.rowType and assert(INSPECTOR_ROW_STRIDES[options.rowType], "Unknown Inspector row type")
        local rowHeight = stride and (stride - INSPECTOR_FLOW_GAP)

        local row = AceGUI:Create("SimpleGroup")
        row:SetAutoAdjustHeight(rowHeight == nil)
        if rowHeight then row:SetHeight(rowHeight) end
        row:SetFullWidth(true)
        row:SetLayout("Table")
        row:SetUserData("table", {
            columns = {
                { width = options.labelWidth or PROPERTY_LABEL_WIDTH },
                { weight = 1 },
            },
            spaceH = options.spaceH or 8,
            spaceV = 0,
            align = "TOPLEFT",
            alignV = options.alignV or "center",
            alignH = "start",
        })
        parent:AddChild(row)

        local label
        if FormWidgets.CreateBodyText then
            label = FormWidgets.CreateBodyText(labelText or "", "label", 12, nil, options.labelWidth or PROPERTY_LABEL_WIDTH, false)
        else
            label = AceGUI:Create("Label")
            label:SetText(labelText or "")
            label:SetFullWidth(false)
            label:SetWidth(options.labelWidth or PROPERTY_LABEL_WIDTH)
        end
        row:AddChild(label)
        FormWidgets.BindLabelTypography(label, "label", "inspector_label")

        local value = AceGUI:Create("SimpleGroup")
        value:SetFullWidth(true)
        value:SetAutoAdjustHeight(rowHeight == nil)
        if rowHeight then
            value:SetHeight(rowHeight)
            -- A Flow value host adds a 3px top inset, overflowing a 44px slider
            -- in a 45px row. The existing Table layout has no such inset.
            value:SetLayout("Table")
            value:SetUserData("table", {
                columns = { { weight = 1 } },
                spaceH = 0,
                spaceV = 0,
                alignV = "start",
                alignH = "start",
            })
        else
            value:SetLayout(options.valueLayout or "Flow")
        end
        row:AddChild(value)

        activeInspectorDiagnosticHosts[#activeInspectorDiagnosticHosts + 1] = {
            widget = row,
            role = "row",
            label = labelText,
        }
        activeInspectorDiagnosticHosts[#activeInspectorDiagnosticHosts + 1] = {
            widget = value,
            role = "value",
            label = labelText,
        }

        if type(valueBuilder) == "function" then
            valueBuilder(value, row, label)
        end

        return row, value
    end

    local function CreateTwoControlTableRow(parent, rightColumnWidth)
        if not parent then
            return nil
        end

        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetLayout("Table")
        row:SetUserData("table", {
            columns = {
                { weight = 1 },
                { width = rightColumnWidth or 96 },
            },
            spaceH = 8,
            spaceV = 0,
            align = "TOPLEFT",
            alignV = "start",
            alignH = "start",
        })
        parent:AddChild(row)
        return row
    end

    local function CreateEvenTwoControlTableRow(parent)
        if not parent then
            return nil
        end

        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetLayout("Table")
        row:SetUserData("table", {
            columns = {
                { weight = 1 },
                { weight = 1 },
            },
            spaceH = 8,
            spaceV = 0,
            align = "TOPLEFT",
            alignV = "start",
            alignH = "start",
        })
        parent:AddChild(row)
        return row
    end

    local function AddDropdownBrowseRow(parent, dropdownOptions, browseCallback, disabled)
        local row = CreateTwoControlTableRow(parent, 80)
        if not row then
            return nil, nil
        end

        dropdownOptions = type(dropdownOptions) == "table" and dropdownOptions or {}
        local dropdown = AddDropdown(
            row,
            "",
            dropdownOptions.list,
            dropdownOptions.value,
            dropdownOptions.onChanged,
            disabled,
            dropdownOptions.anchorKey
        )

        local browse = AddMediaBrowseButton(row, disabled, browseCallback, {
            width = 80,
        })
        return dropdown, browse
    end

    local function AddPropertyDropdownBrowseRow(parent, labelText, dropdownOptions, browseCallback, disabled)
        local dropdown
        local browse

        AddPropertyRow(parent, labelText, function(valueGroup)
            valueGroup:SetLayout("Table")
            valueGroup:SetUserData("table", {
                columns = {
                    { weight = 1 },
                    { width = 80 },
                },
                spaceH = 8,
                spaceV = 0,
                align = "TOPLEFT",
                alignV = "start",
                alignH = "start",
            })

            dropdownOptions = type(dropdownOptions) == "table" and dropdownOptions or {}
            dropdown = AddDropdown(
                valueGroup,
                "",
                dropdownOptions.list,
                dropdownOptions.value,
                dropdownOptions.onChanged,
                disabled,
                dropdownOptions.anchorKey
            )

            browse = AddMediaBrowseButton(valueGroup, disabled, browseCallback, {
                width = 80,
            })
        end, { rowType = "COMPACT" })

        return dropdown, browse
    end

    local function AddPropertyDropdownRow(parent, labelText, dropdownOptions, disabled)
        local dropdown

        AddPropertyRow(parent, labelText, function(valueGroup)
            dropdownOptions = type(dropdownOptions) == "table" and dropdownOptions or {}
            dropdown = AddDropdown(
                valueGroup,
                "",
                dropdownOptions.list,
                dropdownOptions.value,
                dropdownOptions.onChanged,
                disabled,
                dropdownOptions.anchorKey
            )
        end, {
            rowType = "COMPACT",
        })


        return dropdown
    end

    local function AddPropertySliderRow(parent, labelText, minValue, maxValue, step, value, onChanged, disabled, anchorKey)
        local slider

        AddPropertyRow(parent, labelText, function(valueGroup)
            slider = AddSlider(valueGroup, "", minValue, maxValue, step, value, onChanged, disabled, anchorKey)
        end, {
            rowType = "SLIDER",
        })

        return slider
    end

    local function AddPropertyCompactSliderRow(parent, labelText, minValue, maxValue, step, value, onChanged, disabled, anchorKey)
        local slider
        AddPropertyRow(parent, labelText, function(valueGroup)
            slider = AceGUI:Create("FPCompactSlider")
            slider:SetFullWidth(true)
            slider:SetSliderValues(minValue, maxValue, step)
            slider:SetValue(value)
            slider:SetDisabled(disabled == true)
            slider:SetInspectorPresentation()
            slider:SetCallback("OnValueChanged", function(_, _, newValue)
                if onChanged then onChanged(newValue) end
            end)
            if anchorKey then
                slider:SetUserData("focalPointAnchorKey", anchorKey)
                slider.frame._focalPointAnchorKey = anchorKey
            end
            valueGroup:AddChild(slider)
        end, { rowType = "COMPACT" })
        return slider
    end

    local function AddPropertyNumericInputRow(parent, labelText, minValue, maxValue, value, onChanged, disabled, anchorKey)
        local editBox
        local currentValue = math.floor((tonumber(value) or tonumber(minValue) or 0) + 0.5)

        local function NormalizeValue(rawValue)
            local numericValue = tonumber(rawValue)
            if type(numericValue) ~= "number" then
                return nil
            end
            numericValue = math.floor(numericValue + 0.5)
            if type(minValue) == "number" and numericValue < minValue then
                numericValue = minValue
            end
            if type(maxValue) == "number" and numericValue > maxValue then
                numericValue = maxValue
            end
            return numericValue
        end

        local function SetEditBoxValue(nextValue)
            currentValue = NormalizeValue(nextValue) or currentValue
            if editBox and editBox.SetText then
                editBox:SetText(tostring(currentValue))
            end
        end

        local function CommitValue(rawValue, widget)
            local nextValue = NormalizeValue(rawValue)
            if nextValue == nil then
                SetEditBoxValue(currentValue)
                return
            end
            SetEditBoxValue(nextValue)
            if type(onChanged) == "function" then
                onChanged(nextValue)
            end
            if widget and widget.ClearFocus then
                widget:ClearFocus()
            end
        end

        AddPropertyRow(parent, labelText, function(valueGroup)
            editBox = AceGUI:Create("EditBox")
            editBox:SetLabel("")
            editBox:SetWidth(72)
            editBox:SetText(tostring(currentValue))
            if editBox.SetDisabled then
                editBox:SetDisabled(disabled == true)
            end
            if editBox.SetUserData and anchorKey then
                editBox:SetUserData("focalPointAnchorKey", anchorKey)
            end
            if FormWidgets.StyleEditBox then
                FormWidgets.StyleEditBox(editBox, "editor_inset", "value")
            end
            editBox:SetCallback("OnEnterPressed", function(widget, _, rawValue)
                CommitValue(rawValue, widget)
            end)
            editBox:SetCallback("OnFocusLost", function(widget)
                CommitValue(widget and widget.GetText and widget:GetText() or currentValue, nil)
            end)
            valueGroup:AddChild(editBox)
        end, { rowType = "COMPACT" })

        return editBox
    end

    local function AddPropertyValueTextRow(parent, labelText, valueText, options)
        local label

        AddPropertyRow(parent, labelText, function(valueGroup)
            options = type(options) == "table" and options or {}
            if FormWidgets.CreateBodyText then
                label = FormWidgets.CreateBodyText(valueText or "", options.variant or "label", 12, nil, nil, true)
            else
                label = AceGUI:Create("Label")
                label:SetFullWidth(true)
                label:SetText(valueText or "")
            end
            valueGroup:AddChild(label)
        end)

        return label
    end

    local function AddPropertyActionButtonRow(parent, labelText, buttonText, component, width, onClick, disabled)
        local button

        AddPropertyRow(parent, labelText, function(valueGroup)
            button = FormWidgets.CreateActionButton
                and FormWidgets.CreateActionButton(buttonText or labelText or "", component or "InspectorAction", width or 128, disabled and true or false)
                or AceGUI:Create("Button")
            button:SetText(buttonText or labelText or "")
            button:SetWidth(width or 128)
            button:SetFullWidth(false)
            button:SetDisabled(disabled and true or false)
            if FormWidgets.ApplyModalActionButtonVisual then
                FormWidgets.ApplyModalActionButtonVisual(button, component or "InspectorAction")
            end
            button:SetCallback("OnClick", function()
                if disabled or type(onClick) ~= "function" then
                    return
                end
                onClick()
            end)
            valueGroup:AddChild(button)
        end, { rowType = "COMPACT" })

        return button
    end

    local function AddPropertyPickerValueRow(parent, labelText, valueText, onClick, disabled, options)
        local button
        AddPropertyRow(parent, labelText, function(valueGroup)
            options = type(options) == "table" and options or {}
            button = AceGUI:Create("Button")
            if FormWidgets.ResetInspectorButtonState then
                FormWidgets.ResetInspectorButtonState(button)
            end
            button:SetFullWidth(true)
            button:SetText(string.format("%s %s", valueText or (L["OPTION_NONE"] or "None"), options.glyph or "v"))
            if button.text and button.text.SetJustifyH then
                button.text:SetJustifyH("LEFT")
            end
            button:SetDisabled(disabled and true or false)
            button:SetCallback("OnClick", function()
                if disabled or type(onClick) ~= "function" then
                    return
                end
                onClick()
            end)
            if FormWidgets.ApplyModalActionButtonVisual then
                FormWidgets.ApplyModalActionButtonVisual(button, "utility")
            elseif FormWidgets.StyleActionButton then
                FormWidgets.StyleActionButton(button, "utility")
            end
            if FormWidgets.SetInspectorButtonTooltip then
                FormWidgets.SetInspectorButtonTooltip(button, options.tooltip)
            end
            button._fpSetPropertyValueText = function(newText)
                button:SetText(string.format("%s %s", newText or (L["OPTION_NONE"] or "None"), options.glyph or "v"))
            end
            valueGroup:AddChild(button)
        end)
        return button
    end

    local function AddPropertyCheckBoxRow(parent, labelText, value, onChanged, disabled, anchorKey)
        local checkbox
        AddPropertyRow(parent, labelText, function(valueGroup)
            local function ResolveValueLabel(currentValue)
                return currentValue and (L["OPTION_ON"] or "On") or (L["OPTION_OFF"] or "Off")
            end

            checkbox = Shared.AddCheckBox(valueGroup, ResolveValueLabel(value), value, function(newValue)
                if checkbox and checkbox.SetLabel then
                    checkbox:SetLabel(ResolveValueLabel(newValue))
                end
                if onChanged then
                    onChanged(newValue)
                end
            end, disabled, anchorKey)
        end, {
            rowType = "COMPACT",
        })

        return checkbox
    end

    local function AddPropertyColorRow(parent, labelText, color, hasAlpha, onChanged, disabled, anchorKey)
        local colorPicker
        AddPropertyRow(parent, labelText, function(valueGroup)
            colorPicker = AddColorPicker(valueGroup, "", color, hasAlpha, onChanged, disabled, anchorKey)
        end, {
            rowType = "COMPACT",
        })
        return colorPicker
    end

    local function AddPropertyToggleColorRow(parent, labelText, toggleOptions, colorOptions)
        local toggle
        local color
        AddPropertyRow(parent, labelText, function(valueGroup)
            valueGroup:SetLayout("Table")
            valueGroup:SetUserData("table", {
                columns = {
                    { width = 72 },
                    { weight = 1 },
                },
                spaceH = 8,
                spaceV = 0,
                align = "TOPLEFT",
                alignV = "start",
                alignH = "start",
            })

            toggleOptions = type(toggleOptions) == "table" and toggleOptions or {}
            colorOptions = type(colorOptions) == "table" and colorOptions or {}
            local function ResolveValueLabel(currentValue)
                return currentValue and (L["OPTION_ON"] or "On") or (L["OPTION_OFF"] or "Off")
            end
            toggle = Shared.AddCheckBox(valueGroup, ResolveValueLabel(toggleOptions.value), toggleOptions.value, function(newValue)
                if toggle and toggle.SetLabel then
                    toggle:SetLabel(ResolveValueLabel(newValue))
                end
                if toggleOptions.onChanged then
                    toggleOptions.onChanged(newValue)
                end
            end, toggleOptions.disabled, toggleOptions.anchorKey)
            color = AddColorPicker(
                valueGroup,
                "",
                colorOptions.color,
                colorOptions.hasAlpha ~= false,
                colorOptions.onChanged,
                colorOptions.disabled,
                colorOptions.anchorKey
            )
        end, { rowType = "COMPACT" })

        return toggle, color
    end

    local function AddToggleColorRow(parent, toggleOptions, colorOptions)
        local row = CreateTwoControlTableRow(parent, 96)
        if not row then
            return nil, nil
        end

        toggleOptions = type(toggleOptions) == "table" and toggleOptions or {}
        colorOptions = type(colorOptions) == "table" and colorOptions or {}

        local toggle = AddCheckBox(
            row,
            toggleOptions.label or L["OPTION_ENABLED"] or "Enabled",
            toggleOptions.value,
            toggleOptions.onChanged,
            toggleOptions.disabled,
            toggleOptions.anchorKey
        )
        local color = AddColorPicker(
            row,
            "",
            colorOptions.color,
            colorOptions.hasAlpha ~= false,
            colorOptions.onChanged,
            colorOptions.disabled,
            colorOptions.anchorKey
        )
        return toggle, color
    end


    local function AddPointPairRow(parent, pointOptions, relativePointOptions)
        AddPropertyLabel(parent, L["OPTION_ANCHOR_POINTS"] or "Anchor Points")
        local row = CreateEvenTwoControlTableRow(parent)
        if not row then
            return nil, nil
        end

        pointOptions = type(pointOptions) == "table" and pointOptions or {}
        relativePointOptions = type(relativePointOptions) == "table" and relativePointOptions or {}
        local point = AddDropdown(row, pointOptions.label or L["OPTION_FROM_POINT"] or "From Point", pointOptions.list, pointOptions.value, pointOptions.onChanged, pointOptions.disabled, pointOptions.anchorKey)
        local relativePoint = AddDropdown(row, relativePointOptions.label or L["OPTION_TO_POINT"] or "To Point", relativePointOptions.list, relativePointOptions.value, relativePointOptions.onChanged, relativePointOptions.disabled, relativePointOptions.anchorKey)
        return point, relativePoint
    end


    if buildContextOnly then
        return
    end

    local function BuildUnitRootSectionContent(rootSection)
        if not rootSection then
            return
        end

        local generalSection = AddFramedObjectPropertyGroup(rootSection, L["SECTION_GENERAL"] or "General", false)
        local appearanceSection = AddFramedObjectPropertyGroup(rootSection, L["SECTION_APPEARANCE"] or "Appearance", true)
        local geometrySection = AddFramedObjectPropertyGroup(rootSection, L["SECTION_GEOMETRY"] or "Geometry", true)
        local positionSection = AddFramedObjectPropertyGroup(rootSection, L["SECTION_POSITION"] or "Position", true)
        local visibilitySection = AddFramedObjectPropertyGroup(rootSection, L["EDITOR_SECTION_VISIBILITY"] or "Visibility", true)
        local behaviorSection = isExpert and AddFramedObjectPropertyGroup(rootSection, L["SECTION_BEHAVIOR"] or "Behavior", true) or nil
        local advancedSection = isExpert and AddFramedObjectPropertyGroup(rootSection, L["SECTION_ADVANCED"] or "Advanced", true) or nil
        local hasAbsentSingleton =
            unitConfig.powerBarPresent == false
            or unitConfig.castBarPresent == false
            or unitConfig.normalAbsorbBarPresent == false
            or unitConfig.healingAbsorbBarPresent == false
        local hasUnitRemoveAction = IsRemovableUnitRoot(selectedUnit)
        local actionsSection = (hasAbsentSingleton or hasUnitRemoveAction) and AddFramedObjectPropertyGroup(rootSection, L["SECTION_ACTIONS"] or "Actions", true) or nil

        AddPropertyCheckBoxRow(generalSection, L["EDITOR_OPTION_ENABLED"] or "Enabled", unitConfig.enabled ~= false, function(value)
            SetUnitField("enabled", value and true or false, rootSection)
        end)

        AddPropertyCompactSliderRow(appearanceSection, L["EDITOR_OPTION_ALPHA"] or "Transparency", 0.1, 1.0, 0.01, tonumber(unitConfig.alpha) or 1, function(value)
            SetUnitField("alpha", tonumber(string.format("%.2f", value or 1)) or 1)
        end)
        AddPropertyColorRow(appearanceSection, L["OPTION_BACKGROUND_COLOR"] or "Background Color", unitConfig.backgroundColor, true, function(value)
            SetUnitField("backgroundColor", value)
        end)
        if isExpert then
            AddPropertyColorRow(appearanceSection, L["OPTION_BORDER_COLOR"] or "Border Color", unitConfig.borderColor, true, function(value)
                SetUnitField("borderColor", value)
            end)
        end

        AddPropertyCompactSliderRow(geometrySection, L["EDITOR_OPTION_WIDTH"] or "Width", 120, 420, 1, tonumber(unitConfig.width) or 260, function(value)
            SetUnitField("width", math.floor((value or 0) + 0.5))
        end)
        AddPropertyCompactSliderRow(geometrySection, L["EDITOR_OPTION_HEIGHT"] or "Height", 24, 120, 1, tonumber(unitConfig.height) or 65, function(value)
            SetUnitField("height", math.floor((value or 0) + 0.5))
        end)
        if selectedUnit == "boss" then
            AddPropertyCompactSliderRow(geometrySection, L["OPTION_BOSS_FRAME_SPACING"] or "Boss Frame Spacing", 0, 40, 1, tonumber(unitConfig.bossSpacing) or 10, function(value)
                SetUnitField("bossSpacing", math.floor((value or 0) + 0.5))
            end)
        end
        AddPropertyCompactSliderRow(geometrySection, L["EDITOR_OPTION_SCALE"] or "Scale", 0.5, 1.5, 0.01, tonumber(unitConfig.scale) or 1, function(value)
            SetUnitField("scale", tonumber(string.format("%.2f", value or 1)) or 1)
        end)

        AddPropertyDropdownRow(positionSection, L["EDITOR_OPTION_POINT"] or "Anchor From", {
            list = POINTS,
            value = unitConfig.point or "CENTER",
            onChanged = function(value)
                SetUnitField("point", value)
            end,
        })
        AddPropertyDropdownRow(positionSection, L["EDITOR_OPTION_RELATIVE_POINT"] or "Anchor To", {
            list = POINTS,
            value = unitConfig.relativePoint or "CENTER",
            onChanged = function(value)
                SetUnitField("relativePoint", value)
            end,
        })
        AddPropertyCompactSliderRow(positionSection, L["EDITOR_OPTION_X"] or "X Offset", -800, 800, 1, tonumber(unitConfig.x) or 0, function(value)
            SetUnitField("x", math.floor((value or 0) + 0.5))
        end)
        AddPropertyCompactSliderRow(positionSection, L["EDITOR_OPTION_Y"] or "Y Offset", -800, 800, 1, tonumber(unitConfig.y) or 0, function(value)
            SetUnitField("y", math.floor((value or 0) + 0.5))
        end)

        AddPropertyCheckBoxRow(visibilitySection, L["OPTION_SHOW_IN_SOLO"] or "Show in Solo", unitConfig.showInSolo ~= false, function(value)
            SetUnitField("showInSolo", value and true or false)
        end)
        AddPropertyCheckBoxRow(visibilitySection, L["OPTION_SHOW_IN_PARTY"] or "Show in Party", unitConfig.showInParty ~= false, function(value)
            SetUnitField("showInParty", value and true or false)
        end)
        AddPropertyCheckBoxRow(visibilitySection, L["OPTION_SHOW_IN_RAID"] or "Show in Raid", unitConfig.showInRaid ~= false, function(value)
            SetUnitField("showInRaid", value and true or false)
        end)
        AddPropertyCheckBoxRow(visibilitySection, L["OPTION_SHOW_IN_ARENA"] or "Show in Arena", unitConfig.showInArena ~= false, function(value)
            SetUnitField("showInArena", value and true or false)
        end)
        AddPropertyCheckBoxRow(visibilitySection, L["OPTION_SHOW_IN_PVP"] or "Show in PvP", unitConfig.showInPvp ~= false, function(value)
            SetUnitField("showInPvp", value and true or false)
        end)

        if behaviorSection then
            AddPropertyCheckBoxRow(behaviorSection, L["OPTION_MOUSE_ENABLED"] or "Mouse Enabled", unitConfig.mouseEnabled ~= false, function(value)
                SetUnitField("mouseEnabled", value and true or false, behaviorSection)
            end)
            AddPropertyCheckBoxRow(behaviorSection, L["OPTION_CLICK_THROUGH"] or "Click Through", unitConfig.clickThrough == true, function(value)
                SetUnitField("clickThrough", value and true or false)
            end, unitConfig.mouseEnabled == false)
        end

        if advancedSection then
            AddPropertyDropdownRow(advancedSection, L["OPTION_FRAME_STRATA"] or "Frame Strata", {
                list = frameStrataList,
                value = unitConfig.frameStrata or "MEDIUM",
                onChanged = function(value)
                    SetUnitField("frameStrata", value)
                end,
            })
            AddPropertyNumericInputRow(advancedSection, L["OPTION_FRAME_LEVEL"] or "Frame Level", 0, 50, tonumber(unitConfig.frameLevel) or 1, function(value)
                SetUnitField("frameLevel", math.floor((value or 0) + 0.5))
            end)
        end

        if actionsSection then
            if unitConfig.powerBarPresent == false then
                AddPropertyActionButtonRow(actionsSection, L["EDITOR_ADD_POWER_BAR_BUTTON"] or "Add Power Bar", L["EDITOR_ADD_POWER_BAR_BUTTON"] or "Add Power Bar", "PrimaryAction", 132, function()
                    ApplySingletonBarPresence("PowerBar", true, "power")
                end)
            end
            if unitConfig.castBarPresent == false then
                AddPropertyActionButtonRow(actionsSection, L["EDITOR_ADD_CAST_BAR_BUTTON"] or "Add Cast Bar", L["EDITOR_ADD_CAST_BAR_BUTTON"] or "Add Cast Bar", "PrimaryAction", 132, function()
                    ApplyCastBarPresence(true)
                end)
            end
            if unitConfig.normalAbsorbBarPresent == false then
                AddPropertyActionButtonRow(actionsSection, L["EDITOR_ADD_NORMAL_ABSORB_BAR_BUTTON"] or "Add Normal Absorb", L["EDITOR_ADD_NORMAL_ABSORB_BAR_BUTTON"] or "Add Normal Absorb", "PrimaryAction", 160, function()
                    ApplySingletonBarPresence("NormalAbsorbBar", true, "absorbs")
                end)
            end
            if unitConfig.healingAbsorbBarPresent == false then
                AddPropertyActionButtonRow(actionsSection, L["EDITOR_ADD_HEALING_ABSORB_BAR_BUTTON"] or "Add Healing Absorb", L["EDITOR_ADD_HEALING_ABSORB_BAR_BUTTON"] or "Add Healing Absorb", "PrimaryAction", 160, function()
                    ApplySingletonBarPresence("HealingAbsorbBar", true, "absorbs")
                end)
            end
            if hasUnitRemoveAction then
                local removeLabel = ResolveRemoveUnitLabel(selectedUnit)
                AddPropertyActionButtonRow(actionsSection, removeLabel, removeLabel, "DestructiveAction", 172, RemoveSelectedUnitFrame)
            end
        end
    end

    if buildPropertiesOnly and IsSelectedUnitRootObject(selectedUnit) then
        AddScopedObjectInspectorBody("frame", L["EDITOR_SECTION_UNIT_FRAME"] or L["EDITOR_SECTION_FRAME"] or "Unit Frame", BuildUnitRootSectionContent)
        return
    end

    local function BuildFrameSectionContent(frameSection)
        if not frameSection then
            return
        end

        AddCheckBox(frameSection, L["EDITOR_OPTION_ENABLED"] or "Enabled", unitConfig.enabled ~= false, function(value)
            SetUnitField("enabled", value and true or false)
        end)

        AddSlider(frameSection, L["EDITOR_OPTION_WIDTH"] or "Width", 120, 420, 1, tonumber(unitConfig.width) or 260, function(value)
            SetUnitField("width", math.floor((value or 0) + 0.5))
        end)

        AddSlider(frameSection, L["EDITOR_OPTION_HEIGHT"] or "Height", 24, 120, 1, tonumber(unitConfig.height) or 65, function(value)
            SetUnitField("height", math.floor((value or 0) + 0.5))
        end)

        if selectedUnit == "boss" then
            AddSlider(frameSection, L["OPTION_BOSS_FRAME_SPACING"] or "Boss Frame Spacing", 0, 40, 1, tonumber(unitConfig.bossSpacing) or 10, function(value)
                SetUnitField("bossSpacing", math.floor((value or 0) + 0.5))
            end)
        end

        AddSlider(frameSection, L["EDITOR_OPTION_SCALE"] or "Scale", 0.5, 1.5, 0.01, tonumber(unitConfig.scale) or 1, function(value)
            SetUnitField("scale", tonumber(string.format("%.2f", value or 1)) or 1)
        end)

        AddSlider(frameSection, L["EDITOR_OPTION_ALPHA"] or "Transparency", 0.1, 1.0, 0.01, tonumber(unitConfig.alpha) or 1, function(value)
            SetUnitField("alpha", tonumber(string.format("%.2f", value or 1)) or 1)
        end)

        AddColorPicker(frameSection, L["OPTION_BACKGROUND_COLOR"] or "Background Color", unitConfig.backgroundColor, true, function(value)
            SetUnitField("backgroundColor", value)
        end)

        if isExpert then
            AddColorPicker(frameSection, L["OPTION_BORDER_COLOR"] or "Border Color", unitConfig.borderColor, true, function(value)
                SetUnitField("borderColor", value)
            end)

            AddDropdown(frameSection, L["OPTION_FRAME_STRATA"] or "Frame Strata", frameStrataList, unitConfig.frameStrata or "MEDIUM", function(value)
                SetUnitField("frameStrata", value)
            end)

            AddSlider(frameSection, L["OPTION_FRAME_LEVEL"] or "Frame Level", 0, 50, 1, tonumber(unitConfig.frameLevel) or 1, function(value)
                SetUnitField("frameLevel", math.floor((value or 0) + 0.5))
            end)
        end
    end

    AddScopedInspectorSection("frame", L["EDITOR_SECTION_FRAME"] or "Frame", false, {
        localContentBuilder = BuildFrameSectionContent,
        layoutRefresh = RefreshInspectorLayout,
    })

    local function BuildHealthSectionContent(healthSection)
        if not healthSection then
            return
        end

        local usePropertyGroups = IsScopedHealthBarObjectMode()
        local appearanceSection = healthSection
        local backgroundSection = healthSection
        local behaviorSection = healthSection
        if usePropertyGroups then
            appearanceSection = AddFramedObjectPropertyGroup(healthSection, L["SECTION_APPEARANCE"] or "Appearance", false)
            backgroundSection = AddFramedObjectPropertyGroup(healthSection, L["SECTION_BACKGROUND"] or L["OPTION_BACKGROUND"] or "Background", true)
            if isExpert then
                behaviorSection = AddFramedObjectPropertyGroup(healthSection, L["SECTION_BEHAVIOR"] or "Behavior", true)
            end
        end

        local healthTextureOptions = BuildStatusBarTextureOptions(unitConfig.healthBarTexture)
        local healthTextureDropdown
        local function SetHealthBarTexture(value)
            local result = SetUnitField("healthBarTexture", value)
            if not (result and result.ok == false) then
                if healthTextureDropdown and type(healthTextureDropdown._fpSetPropertyValueText) == "function" then
                    local storedValue = result and result.newValue or unitConfig.healthBarTexture or value
                    healthTextureDropdown._fpSetPropertyValueText(ResolveOptionValueLabel(BuildStatusBarTextureOptions(storedValue), storedValue))
                else
                    SyncDropdownToStoredValue(healthTextureDropdown, unitConfig.healthBarTexture)
                end
            end
            return result
        end
        if usePropertyGroups then
            healthTextureDropdown = AddPropertyPickerValueRow(appearanceSection, L["OPTION_TEXTURE"] or L["OPTION_BAR_TEXTURE"] or "Texture", ResolveOptionValueLabel(healthTextureOptions, healthTextureOptions.value or unitConfig.healthBarTexture), function()
                OpenMediaBrowserForField({
                    mediaType = MEDIA_TYPE_STATUSBAR,
                    currentValue = function()
                        return unitConfig.healthBarTexture
                    end,
                    fallbackReference = DEFAULT_STATUSBAR_REFERENCE,
                    title = L["MEDIA_LIBRARY_BROWSE_STATUSBAR_TITLE"] or "Choose Bar Texture",
                    onApply = SetHealthBarTexture,
                })
            end, not IsMediaBrowserAvailable(), {
                tooltip = L["MEDIA_LIBRARY_BROWSE_STATUSBAR_TITLE"] or L["MEDIA_LIBRARY_BROWSE"] or "Browse textures",
            })
        else
            healthTextureDropdown = AddDropdown(appearanceSection, L["OPTION_BAR_TEXTURE"] or "Bar Texture", healthTextureOptions, healthTextureOptions.value, SetHealthBarTexture)
            AddMediaBrowserForField(appearanceSection, MEDIA_TYPE_STATUSBAR, function()
                return unitConfig.healthBarTexture
            end, DEFAULT_STATUSBAR_REFERENCE, L["MEDIA_LIBRARY_BROWSE_STATUSBAR_TITLE"] or "Choose Bar Texture", false, SetHealthBarTexture)
        end

        if isQuick or unitConfig.useClassColorHealth ~= true then
            if usePropertyGroups then
                AddPropertyColorRow(appearanceSection, L["OPTION_COLOR"] or "Color", unitConfig.healthColor, true, function(value)
                    SetUnitField("healthColor", value)
                end, unitConfig.useClassColorHealth == true or unitConfig.useReactionColorNpcHealth == true)
            else
                AddColorPicker(appearanceSection, L["OPTION_COLOR"] or "Color", unitConfig.healthColor, true, function(value)
                    SetUnitField("healthColor", value)
                end, unitConfig.useClassColorHealth == true or unitConfig.useReactionColorNpcHealth == true)
            end
        end

        if usePropertyGroups then
            AddPropertyCheckBoxRow(appearanceSection, L["OPTION_CLASS_COLOR"] or L["OPTION_USE_CLASS_COLORS"] or "Class Color", unitConfig.useClassColorHealth == true, function(value)
                SetUnitField("useClassColorHealth", value and true or false, healthSection)
            end)
        else
            AddCheckBox(appearanceSection, L["OPTION_USE_CLASS_COLORS"] or "Use Class Colors", unitConfig.useClassColorHealth == true, function(value)
                SetUnitField("useClassColorHealth", value and true or false, healthSection)
            end)
        end

        if isExpert then
            if usePropertyGroups then
                AddPropertyCheckBoxRow(appearanceSection, L["OPTION_REACTION_COLOR"] or L["OPTION_USE_REACTION_COLORS_NPC_HEALTH"] or "Reaction Color", unitConfig.useReactionColorNpcHealth == true, function(value)
                    SetUnitField("useReactionColorNpcHealth", value and true or false, healthSection)
                end)
            else
                AddCheckBox(appearanceSection, L["OPTION_USE_REACTION_COLORS_NPC_HEALTH"] or "Use NPC Reaction Colors", unitConfig.useReactionColorNpcHealth == true, function(value)
                    SetUnitField("useReactionColorNpcHealth", value and true or false, healthSection)
                end)
            end

            if usePropertyGroups then
                AddPropertyCheckBoxRow(behaviorSection, L["OPTION_REVERSE_FILL"] or "Reverse Fill", unitConfig.healthBarReverseFill == true, function(value)
                    SetUnitField("healthBarReverseFill", value and true or false)
                end)
            else
                AddCheckBox(behaviorSection, L["OPTION_REVERSE_FILL"] or "Reverse Fill", unitConfig.healthBarReverseFill == true, function(value)
                    SetUnitField("healthBarReverseFill", value and true or false)
                end)
            end
        end

        if usePropertyGroups then
            AddPropertyToggleColorRow(appearanceSection, L["OPTION_LOW_HEALTH_COLOR"] or "Low Health Color", {
                value = unitConfig.useLowHealthColor ~= false,
                onChanged = function(value)
                    SetUnitField("useLowHealthColor", value and true or false, healthSection)
                end,
            }, {
                color = unitConfig.healthLowColor,
                hasAlpha = true,
                onChanged = function(value)
                    SetUnitField("healthLowColor", value)
                end,
                disabled = unitConfig.useLowHealthColor == false,
            })

            if isExpert then
                AddPropertyDropdownRow(appearanceSection, L["OPTION_LOW_HEALTH_THRESHOLD"] or "Low Health Threshold", {
                    list = lowHealthThresholdList,
                    value = tostring(unitConfig.lowHealthColorThreshold or 1.0),
                    onChanged = function(value)
                        SetUnitField("lowHealthColorThreshold", tonumber(value))
                    end,
                }, unitConfig.useLowHealthColor == false)
            end
        else
            AddCheckBox(appearanceSection, L["OPTION_USE_LOW_HEALTH_COLOR"] or "Use Low Health Color", unitConfig.useLowHealthColor ~= false, function(value)
                SetUnitField("useLowHealthColor", value and true or false, healthSection)
            end)

            AddColorPicker(appearanceSection, L["OPTION_LOW_HEALTH_COLOR"] or "Low Health Color", unitConfig.healthLowColor, true, function(value)
                SetUnitField("healthLowColor", value)
            end, unitConfig.useLowHealthColor == false)

            if isExpert then
                AddDropdown(appearanceSection, L["OPTION_LOW_HEALTH_THRESHOLD"] or "Low Health Threshold", lowHealthThresholdList, tostring(unitConfig.lowHealthColorThreshold or 1.0), function(value)
                    SetUnitField("lowHealthColorThreshold", tonumber(value))
                end, unitConfig.useLowHealthColor == false)
            end
        end

        if isQuick or isExpert then
            if usePropertyGroups then
                AddPropertyCheckBoxRow(backgroundSection, L["OPTION_ENABLED"] or "Enabled", unitConfig.healthBackground ~= false, function(value)
                    SetUnitField("healthBackground", value and true or false, healthSection)
                end)

                AddPropertyColorRow(backgroundSection, L["OPTION_COLOR"] or "Color", unitConfig.healthBackgroundColor, true, function(value)
                    SetUnitField("healthBackgroundColor", value)
                end, unitConfig.healthBackground == false)
            else
                AddCheckBox(appearanceSection, L["OPTION_SHOW_BACKGROUND"] or "Show Background", unitConfig.healthBackground ~= false, function(value)
                    SetUnitField("healthBackground", value and true or false, healthSection)
                end)

                AddColorPicker(appearanceSection, L["OPTION_BACKGROUND_COLOR"] or "Background Color", unitConfig.healthBackgroundColor, true, function(value)
                    SetUnitField("healthBackgroundColor", value)
                end, unitConfig.healthBackground == false)
            end
        end
    end

    if IsScopedHealthBarObjectMode() then
        AddScopedObjectInspectorBody("health", L["VALUE_ANCHOR_TARGET_HEALTH_BAR"] or L["BAR_HEALTH"] or "Health Bar", BuildHealthSectionContent)
    else
        AddScopedInspectorSection("health", L["BAR_HEALTH"] or "Health", false, {
            localContentBuilder = BuildHealthSectionContent,
            layoutRefresh = RefreshInspectorLayout,
        })
    end

    local function BuildAbsorbsSectionContent(absorbsSection)
        if not absorbsSection then
            return
        end

        local scopedAbsorbObject = ResolveScopedAbsorbObject()

        local function AddAbsorbSubheading(text)
            local label = AceGUI:Create("Label")
            label:SetFullWidth(true)
            label:SetText(text)
            absorbsSection:AddChild(label)
        end

        local function BuildAbsorbBar(prefix, showField, title, fallbackColor, fallbackGrowth, options)
            options = type(options) == "table" and options or {}
            local isScopedObject = options.scopedObject == true
            local rootSection = options.rootSection or absorbsSection
            local generalSection = absorbsSection
            local appearanceSection = absorbsSection
            local backgroundSection = absorbsSection
            local geometrySection = absorbsSection
            local positionSection = absorbsSection
            local behaviorSection = absorbsSection
            local actionsSection

            if isScopedObject then
                generalSection = AddFramedObjectPropertyGroup(absorbsSection, L["SECTION_GENERAL"] or "General", false)
                appearanceSection = AddFramedObjectPropertyGroup(absorbsSection, L["SECTION_APPEARANCE"] or "Appearance", true)
                backgroundSection = AddFramedObjectPropertyGroup(absorbsSection, L["SECTION_BACKGROUND"] or L["OPTION_BACKGROUND"] or "Background", true)
                geometrySection = AddFramedObjectPropertyGroup(absorbsSection, L["SECTION_GEOMETRY"] or "Geometry", true)
                positionSection = AddFramedObjectPropertyGroup(absorbsSection, L["SECTION_POSITION"] or "Position", true)
                behaviorSection = AddFramedObjectPropertyGroup(absorbsSection, L["SECTION_BEHAVIOR"] or "Behavior", true)
                actionsSection = AddFramedObjectPropertyGroup(absorbsSection, L["SECTION_ACTIONS"] or "Actions", true)
            else
                AddAbsorbSubheading(title)
            end

            local showValue = unitConfig[showField] ~= false
            if isScopedObject then
                AddPropertyCheckBoxRow(generalSection, L["OPTION_SHOW"] or "Show", showValue, function(value)
                    SetUnitField(showField, value and true or false, rootSection)
                end)
            else
                AddCheckBox(generalSection, L["OPTION_SHOW"] or "Show", showValue, function(value)
                    SetUnitField(showField, value and true or false, rootSection)
                end)
            end

            local textureField = prefix .. "Texture"
            local textureOptions = BuildStatusBarTextureOptions(unitConfig[textureField])
            local textureDropdown
            local function SetAbsorbTexture(value)
                local result = SetUnitField(textureField, value, rootSection)
                if not (result and result.ok == false) then
                    if textureDropdown and type(textureDropdown._fpSetPropertyValueText) == "function" then
                        local storedValue = result and result.newValue or unitConfig[textureField] or value
                        textureDropdown._fpSetPropertyValueText(ResolveOptionValueLabel(BuildStatusBarTextureOptions(storedValue), storedValue))
                    else
                        SyncDropdownToStoredValue(textureDropdown, unitConfig[textureField])
                    end
                end
                return result
            end
            if isScopedObject then
                textureDropdown = AddPropertyPickerValueRow(appearanceSection, L["OPTION_TEXTURE"] or L["OPTION_BAR_TEXTURE"] or "Texture", ResolveOptionValueLabel(textureOptions, textureOptions.value or unitConfig[textureField]), function()
                    OpenMediaBrowserForField({
                        mediaType = MEDIA_TYPE_STATUSBAR,
                        currentValue = function()
                            return unitConfig[textureField]
                        end,
                        fallbackReference = DEFAULT_STATUSBAR_REFERENCE,
                        title = L["MEDIA_LIBRARY_BROWSE_STATUSBAR_TITLE"] or "Choose Bar Texture",
                        onApply = SetAbsorbTexture,
                    })
                end, not IsMediaBrowserAvailable(), {
                    tooltip = L["MEDIA_LIBRARY_BROWSE_STATUSBAR_TITLE"] or L["MEDIA_LIBRARY_BROWSE"] or "Browse textures",
                })
            else
                textureDropdown = AddDropdown(absorbsSection, L["OPTION_BAR_TEXTURE"] or "Bar Texture", textureOptions, textureOptions.value, SetAbsorbTexture)
                AddMediaBrowserForField(absorbsSection, MEDIA_TYPE_STATUSBAR, function()
                    return unitConfig[textureField]
                end, DEFAULT_STATUSBAR_REFERENCE, L["MEDIA_LIBRARY_BROWSE_STATUSBAR_TITLE"] or "Choose Bar Texture", false, SetAbsorbTexture)
            end

            if isScopedObject then
                AddPropertyColorRow(appearanceSection, L["OPTION_COLOR"] or "Color", unitConfig[prefix .. "Color"] or fallbackColor, true, function(value)
                    SetUnitField(prefix .. "Color", value, rootSection)
                end)
            else
                AddColorPicker(appearanceSection, L["OPTION_COLOR"] or "Color", unitConfig[prefix .. "Color"] or fallbackColor, true, function(value)
                    SetUnitField(prefix .. "Color", value, rootSection)
                end)
            end

            if actionsSection and options.objectKey == "NormalAbsorbBar" then
                AddPropertyActionButtonRow(actionsSection, L["EDITOR_REMOVE_NORMAL_ABSORB_BAR_BUTTON"] or "Remove Normal Absorb", L["EDITOR_REMOVE_NORMAL_ABSORB_BAR_BUTTON"] or "Remove Normal Absorb", "DestructiveAction", 176, function()
                    ApplySingletonBarPresence("NormalAbsorbBar", false, "absorbs")
                end)
            elseif actionsSection and options.objectKey == "HealingAbsorbBar" then
                AddPropertyActionButtonRow(actionsSection, L["EDITOR_REMOVE_HEALING_ABSORB_BAR_BUTTON"] or "Remove Healing Absorb", L["EDITOR_REMOVE_HEALING_ABSORB_BAR_BUTTON"] or "Remove Healing Absorb", "DestructiveAction", 176, function()
                    ApplySingletonBarPresence("HealingAbsorbBar", false, "absorbs")
                end)
            end

            if isScopedObject then
                AddPropertyColorRow(backgroundSection, L["OPTION_COLOR"] or "Color", unitConfig[prefix .. "BackgroundColor"] or { 0, 0, 0, 0 }, true, function(value)
                    SetUnitField(prefix .. "BackgroundColor", value, rootSection)
                end)
            else
                AddColorPicker(appearanceSection, L["OPTION_BACKGROUND_COLOR"] or "Background Color", unitConfig[prefix .. "BackgroundColor"] or { 0, 0, 0, 0 }, true, function(value)
                    SetUnitField(prefix .. "BackgroundColor", value, rootSection)
                end)
            end

            local sizeMode = unitConfig[prefix .. "SizeMode"] or "MATCH_TARGET"
            local isCustom = sizeMode == "CUSTOM"
            if isScopedObject then
                AddPropertyDropdownRow(geometrySection, L["OPTION_SIZE_MODE"] or "Size Mode", {
                    list = absorbSizeModeList,
                    value = sizeMode,
                    onChanged = function(value)
                        SetUnitField(prefix .. "SizeMode", value, rootSection)
                    end,
                })
            else
                AddDropdown(geometrySection, L["OPTION_SIZE_MODE"] or "Size Mode", absorbSizeModeList, sizeMode, function(value)
                    SetUnitField(prefix .. "SizeMode", value, rootSection)
                end)
            end
            local anchorTargetLabel = isScopedObject
                and (L["OPTION_ANCHOR_TARGET"] or "Anchor Target")
                or (L["OPTION_ANCHOR_TO_TARGET"] or "Anchor To Element")
            local anchorParent = isScopedObject and positionSection or geometrySection
            if isScopedObject then
                AddPropertyDropdownRow(anchorParent, anchorTargetLabel, {
                    list = absorbAnchorTargetList,
                    value = unitConfig[prefix .. "AnchorTo"] or "HealthBar",
                    onChanged = function(value)
                        SetUnitField(prefix .. "AnchorTo", value, rootSection)
                    end,
                })
            else
                AddDropdown(anchorParent, anchorTargetLabel, absorbAnchorTargetList, unitConfig[prefix .. "AnchorTo"] or "HealthBar", function(value)
                    SetUnitField(prefix .. "AnchorTo", value, rootSection)
                end)
            end
            if isScopedObject then
                AddPropertyCompactSliderRow(geometrySection, L["OPTION_WIDTH"] or "Width", 1, 512, 1, tonumber(unitConfig[prefix .. "Width"]) or 120, function(value)
                    SetUnitField(prefix .. "Width", math.floor((value or 0) + 0.5), rootSection)
                end, not isCustom)
                AddPropertyCompactSliderRow(geometrySection, L["OPTION_HEIGHT"] or "Height", 1, 128, 1, tonumber(unitConfig[prefix .. "Height"]) or 8, function(value)
                    SetUnitField(prefix .. "Height", math.floor((value or 0) + 0.5), rootSection)
                end, not isCustom)
                local pointControl
                local relativePointControl
                if isExpert then
                    pointControl, relativePointControl = AddPointPairRow(positionSection, {
                    list = barAnchorList,
                    value = unitConfig[prefix .. "Point"] or "LEFT",
                    onChanged = function(value)
                        if IsActiveCanvasDirectMoveOffsetControlSuppressed(pointControl) then
                            return
                        end
                        SetUnitField(prefix .. "Point", value, rootSection)
                    end,
                    disabled = not isCustom,
                }, {
                    list = barAnchorList,
                    value = unitConfig[prefix .. "RelativePoint"] or "LEFT",
                    onChanged = function(value)
                        if IsActiveCanvasDirectMoveOffsetControlSuppressed(relativePointControl) then
                            return
                        end
                        SetUnitField(prefix .. "RelativePoint", value, rootSection)
                    end,
                    disabled = not isCustom,
                    })
                end
                local offsetXControl = AddPropertyCompactSliderRow(positionSection, L["OPTION_OFFSET_X"] or "Offset X", -500, 500, 1, tonumber(unitConfig[prefix .. "OffsetX"]) or 0, function(value)
                    if IsActiveCanvasDirectMoveOffsetControlSuppressed(offsetXControl) then
                        return
                    end
                    SetUnitField(prefix .. "OffsetX", math.floor((value or 0) + 0.5), rootSection)
                end, not isCustom)
                local offsetYControl = AddPropertyCompactSliderRow(positionSection, L["OPTION_OFFSET_Y"] or "Offset Y", -500, 500, 1, tonumber(unitConfig[prefix .. "OffsetY"]) or 0, function(value)
                    if IsActiveCanvasDirectMoveOffsetControlSuppressed(offsetYControl) then
                        return
                    end
                    SetUnitField(prefix .. "OffsetY", math.floor((value or 0) + 0.5), rootSection)
                end, not isCustom)
                local objectKey = prefix == "normalAbsorbBar" and "NormalAbsorbBar" or "HealingAbsorbBar"
                RegisterActiveCanvasDirectMoveOffsetControls(state and state.selectedUnit, {
                    kind = "bar",
                    unit = state and state.selectedUnit,
                    objectKey = objectKey,
                }, offsetXControl, offsetYControl, pointControl, relativePointControl)
            else
                AddSlider(geometrySection, L["OPTION_WIDTH"] or "Width", 1, 512, 1, tonumber(unitConfig[prefix .. "Width"]) or 120, function(value)
                    SetUnitField(prefix .. "Width", math.floor((value or 0) + 0.5), rootSection)
                end, not isCustom)
                AddSlider(geometrySection, L["OPTION_HEIGHT"] or "Height", 1, 128, 1, tonumber(unitConfig[prefix .. "Height"]) or 8, function(value)
                    SetUnitField(prefix .. "Height", math.floor((value or 0) + 0.5), rootSection)
                end, not isCustom)
                if isExpert then
                    AddDropdown(geometrySection, L["OPTION_ANCHOR_FROM"] or "Anchor From", barAnchorList, unitConfig[prefix .. "Point"] or "LEFT", function(value)
                        SetUnitField(prefix .. "Point", value, rootSection)
                    end, not isCustom)
                    AddDropdown(geometrySection, L["OPTION_ANCHOR_TO"] or "Anchor To", barAnchorList, unitConfig[prefix .. "RelativePoint"] or "LEFT", function(value)
                        SetUnitField(prefix .. "RelativePoint", value, rootSection)
                    end, not isCustom)
                end
                AddSlider(geometrySection, L["OPTION_X_OFFSET"] or "X Offset", -500, 500, 1, tonumber(unitConfig[prefix .. "OffsetX"]) or 0, function(value)
                    SetUnitField(prefix .. "OffsetX", math.floor((value or 0) + 0.5), rootSection)
                end, not isCustom)
                AddSlider(geometrySection, L["OPTION_Y_OFFSET"] or "Y Offset", -500, 500, 1, tonumber(unitConfig[prefix .. "OffsetY"]) or 0, function(value)
                    SetUnitField(prefix .. "OffsetY", math.floor((value or 0) + 0.5), rootSection)
                end, not isCustom)
            end
            if isScopedObject then
                AddPropertyDropdownRow(behaviorSection, L["OPTION_GROWTH_DIRECTION"] or "Growth Direction", {
                    list = absorbGrowthList,
                    value = unitConfig[prefix .. "Growth"] or fallbackGrowth,
                    onChanged = function(value)
                        SetUnitField(prefix .. "Growth", value, rootSection)
                    end,
                })
            else
                AddDropdown(behaviorSection, L["OPTION_GROWTH_DIRECTION"] or "Growth Direction", absorbGrowthList, unitConfig[prefix .. "Growth"] or fallbackGrowth, function(value)
                    SetUnitField(prefix .. "Growth", value, rootSection)
                end)
            end

        end

        if scopedAbsorbObject then
            BuildAbsorbBar(
                scopedAbsorbObject.prefix,
                scopedAbsorbObject.showField,
                scopedAbsorbObject.title,
                scopedAbsorbObject.fallbackColor,
                scopedAbsorbObject.fallbackGrowth,
                { scopedObject = true, rootSection = absorbsSection, objectKey = scopedAbsorbObject.objectKey }
            )
            return
        end

        BuildAbsorbBar("normalAbsorbBar", "showNormalAbsorbBar", L["OPTION_NORMAL_ABSORB"] or "Normal Absorb", { 0.66, 0.86, 1.0, 0.62 }, "LEFT_TO_RIGHT")
        AddSpacer(absorbsSection, 6)
        BuildAbsorbBar("healingAbsorbBar", "showHealingAbsorbBar", L["OPTION_HEALING_ABSORB"] or "Healing Absorb", { 0.75, 0.20, 1.0, 0.62 }, "RIGHT_TO_LEFT")
    end

    do
        local scopedAbsorbObject = ResolveScopedAbsorbObject()
        if scopedAbsorbObject then
            AddScopedObjectInspectorBody("absorbs", scopedAbsorbObject.headerTitle, BuildAbsorbsSectionContent)
        else
            AddScopedInspectorSection("absorbs", L["OPTION_ABSORBS"] or "Absorbs", true, {
                localContentBuilder = BuildAbsorbsSectionContent,
                layoutRefresh = RefreshInspectorLayout,
            })
        end
    end

    local function BuildPowerSectionContent(powerSection)
        if not powerSection then
            return
        end

        local usePropertyGroups = IsScopedPowerBarObjectMode()
        local generalSection = powerSection
        local appearanceSection = powerSection
        local backgroundSection = powerSection
        local geometrySection = powerSection
        local behaviorSection = powerSection
        local actionsSection
        if usePropertyGroups then
            generalSection = AddFramedObjectPropertyGroup(powerSection, L["SECTION_GENERAL"] or "General", false)
            appearanceSection = AddFramedObjectPropertyGroup(powerSection, L["SECTION_APPEARANCE"] or "Appearance", true)
            backgroundSection = AddFramedObjectPropertyGroup(powerSection, L["SECTION_BACKGROUND"] or L["OPTION_BACKGROUND"] or "Background", true)
            geometrySection = AddFramedObjectPropertyGroup(powerSection, L["SECTION_GEOMETRY"] or "Geometry", true)
            behaviorSection = AddFramedObjectPropertyGroup(powerSection, L["SECTION_BEHAVIOR"] or "Behavior", true)
            actionsSection = AddFramedObjectPropertyGroup(powerSection, L["SECTION_ACTIONS"] or "Actions", true)
        end

        if usePropertyGroups then
            AddPropertyCheckBoxRow(generalSection, L["OPTION_SHOW"] or "Show", unitConfig.showPowerBar ~= false, function(value)
                SetUnitField("showPowerBar", value and true or false, powerSection)
            end)
        else
            AddCheckBox(generalSection, L["EDITOR_OPTION_SHOW_POWER"] or "Show Power Bar", unitConfig.showPowerBar ~= false, function(value)
                SetUnitField("showPowerBar", value and true or false, powerSection)
            end)
        end

        local powerTextureOptions = BuildStatusBarTextureOptions(unitConfig.powerBarTexture)
        local powerTextureDropdown
        local function SetPowerBarTexture(value)
            local result = SetUnitField("powerBarTexture", value)
            if not (result and result.ok == false) then
                if powerTextureDropdown and type(powerTextureDropdown._fpSetPropertyValueText) == "function" then
                    local storedValue = result and result.newValue or unitConfig.powerBarTexture or value
                    powerTextureDropdown._fpSetPropertyValueText(ResolveOptionValueLabel(BuildStatusBarTextureOptions(storedValue), storedValue))
                else
                    SyncDropdownToStoredValue(powerTextureDropdown, unitConfig.powerBarTexture)
                end
            end
            return result
        end
        if usePropertyGroups then
            powerTextureDropdown = AddPropertyPickerValueRow(appearanceSection, L["OPTION_TEXTURE"] or L["OPTION_BAR_TEXTURE"] or "Texture", ResolveOptionValueLabel(powerTextureOptions, powerTextureOptions.value or unitConfig.powerBarTexture), function()
                OpenMediaBrowserForField({
                    mediaType = MEDIA_TYPE_STATUSBAR,
                    currentValue = function()
                        return unitConfig.powerBarTexture
                    end,
                    fallbackReference = DEFAULT_STATUSBAR_REFERENCE,
                    title = L["MEDIA_LIBRARY_BROWSE_STATUSBAR_TITLE"] or "Choose Bar Texture",
                    onApply = SetPowerBarTexture,
                })
            end, unitConfig.showPowerBar == false or not IsMediaBrowserAvailable(), {
                tooltip = L["MEDIA_LIBRARY_BROWSE_STATUSBAR_TITLE"] or L["MEDIA_LIBRARY_BROWSE"] or "Browse textures",
            })
        else
            powerTextureDropdown = AddDropdown(appearanceSection, L["OPTION_BAR_TEXTURE"] or "Bar Texture", powerTextureOptions, powerTextureOptions.value, SetPowerBarTexture, unitConfig.showPowerBar == false)
            AddMediaBrowserForField(appearanceSection, MEDIA_TYPE_STATUSBAR, function()
                return unitConfig.powerBarTexture
            end, DEFAULT_STATUSBAR_REFERENCE, L["MEDIA_LIBRARY_BROWSE_STATUSBAR_TITLE"] or "Choose Bar Texture", unitConfig.showPowerBar == false, SetPowerBarTexture)
        end

        if isQuick or isExpert then
            local powerBarHeightControl
            if usePropertyGroups then
                powerBarHeightControl = AddPropertyCompactSliderRow(geometrySection, L["OPTION_HEIGHT"] or L["OPTION_POWER_BAR_HEIGHT"] or "Height", 4, 30, 1, tonumber(unitConfig.powerBarHeight) or 20, function(value)
                    if IsActiveCanvasWheelFieldControlSuppressed(powerBarHeightControl) then
                        return
                    end
                    SetUnitField("powerBarHeight", math.floor((value or 0) + 0.5))
                end, unitConfig.showPowerBar == false)
            else
                powerBarHeightControl = AddSlider(geometrySection, L["OPTION_POWER_BAR_HEIGHT"] or "Power Bar Height", 4, 30, 1, tonumber(unitConfig.powerBarHeight) or 20, function(value)
                    if IsActiveCanvasWheelFieldControlSuppressed(powerBarHeightControl) then
                        return
                    end
                    SetUnitField("powerBarHeight", math.floor((value or 0) + 0.5))
                end, unitConfig.showPowerBar == false)
            end
            RegisterActiveCanvasWheelFieldControl(state and state.selectedUnit, { kind = "bar", unit = state and state.selectedUnit, objectKey = "PowerBar" }, "powerBarHeight", powerBarHeightControl)
        end

        if usePropertyGroups then
            AddPropertyColorRow(appearanceSection, L["OPTION_COLOR"] or "Color", unitConfig.powerColor, true, function(value)
                SetUnitField("powerColor", value)
            end, unitConfig.showPowerBar == false or unitConfig.useClassColorPower == true)
        else
            AddColorPicker(appearanceSection, L["OPTION_COLOR"] or "Color", unitConfig.powerColor, true, function(value)
                SetUnitField("powerColor", value)
            end, unitConfig.showPowerBar == false or unitConfig.useClassColorPower == true)
        end

        if usePropertyGroups then
            AddPropertyCheckBoxRow(appearanceSection, L["OPTION_CLASS_COLOR"] or L["OPTION_USE_CLASS_COLORS"] or "Class Color", unitConfig.useClassColorPower == true, function(value)
                SetUnitField("useClassColorPower", value and true or false, powerSection)
            end, unitConfig.showPowerBar == false)
        else
            AddCheckBox(appearanceSection, L["OPTION_USE_CLASS_COLORS"] or "Use Class Colors", unitConfig.useClassColorPower == true, function(value)
                SetUnitField("useClassColorPower", value and true or false, powerSection)
            end, unitConfig.showPowerBar == false)
        end

        if isExpert then
            if usePropertyGroups then
                AddPropertyCheckBoxRow(behaviorSection, L["OPTION_REVERSE_FILL"] or "Reverse Fill", unitConfig.powerBarReverseFill == true, function(value)
                    SetUnitField("powerBarReverseFill", value and true or false)
                end, unitConfig.showPowerBar == false)
            else
                AddCheckBox(behaviorSection, L["OPTION_REVERSE_FILL"] or "Reverse Fill", unitConfig.powerBarReverseFill == true, function(value)
                    SetUnitField("powerBarReverseFill", value and true or false)
                end, unitConfig.showPowerBar == false)
            end
        end

        if isQuick or isExpert then
            if usePropertyGroups then
                AddPropertyCheckBoxRow(backgroundSection, L["OPTION_ENABLED"] or "Enabled", unitConfig.powerBackground ~= false, function(value)
                    SetUnitField("powerBackground", value and true or false, powerSection)
                end, unitConfig.showPowerBar == false)

                AddPropertyColorRow(backgroundSection, L["OPTION_COLOR"] or "Color", unitConfig.powerBackgroundColor, true, function(value)
                    SetUnitField("powerBackgroundColor", value)
                end, unitConfig.showPowerBar == false or unitConfig.powerBackground == false)
            else
                AddCheckBox(appearanceSection, L["OPTION_SHOW_BACKGROUND"] or "Show Background", unitConfig.powerBackground ~= false, function(value)
                    SetUnitField("powerBackground", value and true or false, powerSection)
                end, unitConfig.showPowerBar == false)

                AddColorPicker(appearanceSection, L["OPTION_BACKGROUND_COLOR"] or "Background Color", unitConfig.powerBackgroundColor, true, function(value)
                    SetUnitField("powerBackgroundColor", value)
                end, unitConfig.showPowerBar == false or unitConfig.powerBackground == false)
            end
        end

        if actionsSection then
            AddPropertyActionButtonRow(actionsSection, L["EDITOR_REMOVE_POWER_BAR_BUTTON"] or "Remove Power Bar", L["EDITOR_REMOVE_POWER_BAR_BUTTON"] or "Remove Power Bar", "DestructiveAction", 148, function()
                ApplySingletonBarPresence("PowerBar", false, "power")
            end)
        end
    end

    if IsScopedPowerBarObjectMode() then
        AddScopedObjectInspectorBody("power", L["VALUE_ANCHOR_TARGET_POWER_BAR"] or L["BAR_POWER"] or "Power Bar", BuildPowerSectionContent)
    else
        AddScopedInspectorSection("power", L["BAR_POWER"] or "Power", true, {
            localContentBuilder = BuildPowerSectionContent,
            layoutRefresh = RefreshInspectorLayout,
        })
    end

    local function BuildAltPowerSectionContent(altPowerSection)
        if not altPowerSection or selectedUnit ~= "player" then
            return
        end

        local usePropertyGroups = IsScopedAlternativePowerBarObjectMode()
        local rootSection = altPowerSection
        local generalSection = altPowerSection
        local appearanceSection = altPowerSection
        local backgroundSection = altPowerSection
        local geometrySection = altPowerSection
        local behaviorSection = altPowerSection
        local actionsSection
        if usePropertyGroups then
            generalSection = AddFramedObjectPropertyGroup(altPowerSection, L["SECTION_GENERAL"] or "General", false)
            appearanceSection = AddFramedObjectPropertyGroup(altPowerSection, L["SECTION_APPEARANCE"] or "Appearance", true)
            backgroundSection = AddFramedObjectPropertyGroup(altPowerSection, L["SECTION_BACKGROUND"] or L["OPTION_BACKGROUND"] or "Background", true)
            geometrySection = AddFramedObjectPropertyGroup(altPowerSection, L["SECTION_GEOMETRY"] or "Geometry", true)
            if isExpert then
                behaviorSection = AddFramedObjectPropertyGroup(altPowerSection, L["SECTION_BEHAVIOR"] or "Behavior", true)
            end
            actionsSection = AddFramedObjectPropertyGroup(altPowerSection, L["SECTION_ACTIONS"] or "Actions", true)
        end

        if usePropertyGroups then
            AddPropertyCheckBoxRow(generalSection, L["OPTION_SHOW"] or "Show", unitConfig.showAlternativePowerBar == true, function(value)
                SetUnitField("showAlternativePowerBar", value and true or false, rootSection)
            end)
        else
            AddCheckBox(generalSection, L["OPTION_SHOW_ALTERNATIVE_POWER_BAR"] or "Show Alternative Power Bar", unitConfig.showAlternativePowerBar == true, function(value)
                SetUnitField("showAlternativePowerBar", value and true or false, rootSection)
            end)
        end

        local alternativePowerTextureValue = unitConfig.alternativePowerBarTexture or unitConfig.powerBarTexture
        local alternativePowerTextureOptions = BuildStatusBarTextureOptions(alternativePowerTextureValue)
        local alternativePowerTextureDropdown
        local function SetAlternativePowerBarTexture(value)
            local result = SetUnitField("alternativePowerBarTexture", value)
            if not (result and result.ok == false) then
                if alternativePowerTextureDropdown and type(alternativePowerTextureDropdown._fpSetPropertyValueText) == "function" then
                    local storedValue = result and result.newValue or unitConfig.alternativePowerBarTexture or unitConfig.powerBarTexture or value
                    alternativePowerTextureDropdown._fpSetPropertyValueText(ResolveOptionValueLabel(BuildStatusBarTextureOptions(storedValue), storedValue))
                else
                    SyncDropdownToStoredValue(alternativePowerTextureDropdown, unitConfig.alternativePowerBarTexture or unitConfig.powerBarTexture)
                end
            end
            return result
        end
        if usePropertyGroups then
            alternativePowerTextureDropdown = AddPropertyPickerValueRow(appearanceSection, L["OPTION_TEXTURE"] or L["OPTION_BAR_TEXTURE"] or "Texture", ResolveOptionValueLabel(alternativePowerTextureOptions, alternativePowerTextureOptions.value or alternativePowerTextureValue), function()
                OpenMediaBrowserForField({
                    mediaType = MEDIA_TYPE_STATUSBAR,
                    currentValue = function()
                        return unitConfig.alternativePowerBarTexture or unitConfig.powerBarTexture
                    end,
                    fallbackReference = DEFAULT_STATUSBAR_REFERENCE,
                    title = L["MEDIA_LIBRARY_BROWSE_STATUSBAR_TITLE"] or "Choose Bar Texture",
                    onApply = SetAlternativePowerBarTexture,
                })
            end, unitConfig.showAlternativePowerBar ~= true or not IsMediaBrowserAvailable(), {
                tooltip = L["MEDIA_LIBRARY_BROWSE_STATUSBAR_TITLE"] or L["MEDIA_LIBRARY_BROWSE"] or "Browse textures",
            })
        else
            alternativePowerTextureDropdown = AddDropdown(altPowerSection, L["OPTION_BAR_TEXTURE"] or "Bar Texture", alternativePowerTextureOptions, alternativePowerTextureOptions.value, SetAlternativePowerBarTexture, unitConfig.showAlternativePowerBar ~= true)
            AddMediaBrowserForField(altPowerSection, MEDIA_TYPE_STATUSBAR, function()
                return unitConfig.alternativePowerBarTexture or unitConfig.powerBarTexture
            end, DEFAULT_STATUSBAR_REFERENCE, L["MEDIA_LIBRARY_BROWSE_STATUSBAR_TITLE"] or "Choose Bar Texture", unitConfig.showAlternativePowerBar ~= true, SetAlternativePowerBarTexture)
        end

        local alternativePowerBarHeightControl
        if usePropertyGroups then
            alternativePowerBarHeightControl = AddPropertyCompactSliderRow(geometrySection, L["OPTION_HEIGHT"] or L["OPTION_ALTERNATIVE_POWER_BAR_HEIGHT"] or "Height", 4, 30, 1, tonumber(unitConfig.alternativePowerBarHeight) or 20, function(value)
                if IsActiveCanvasWheelFieldControlSuppressed(alternativePowerBarHeightControl) then
                    return
                end
                SetUnitField("alternativePowerBarHeight", math.floor((value or 0) + 0.5))
            end, unitConfig.showAlternativePowerBar ~= true)
        else
            alternativePowerBarHeightControl = AddSlider(geometrySection, L["OPTION_ALTERNATIVE_POWER_BAR_HEIGHT"] or "Alternative Power Height", 4, 30, 1, tonumber(unitConfig.alternativePowerBarHeight) or 20, function(value)
                if IsActiveCanvasWheelFieldControlSuppressed(alternativePowerBarHeightControl) then
                    return
                end
                SetUnitField("alternativePowerBarHeight", math.floor((value or 0) + 0.5))
            end, unitConfig.showAlternativePowerBar ~= true)
        end
        RegisterActiveCanvasWheelFieldControl(state and state.selectedUnit, { kind = "bar", unit = state and state.selectedUnit, objectKey = "AlternativePowerBar" }, "alternativePowerBarHeight", alternativePowerBarHeightControl)

        if isQuick or isExpert then
            if usePropertyGroups then
                AddPropertyColorRow(appearanceSection, L["OPTION_COLOR"] or "Color", unitConfig.alternativePowerColor, true, function(value)
                    SetUnitField("alternativePowerColor", value)
                end, unitConfig.showAlternativePowerBar ~= true)
            else
                AddColorPicker(appearanceSection, L["OPTION_COLOR"] or "Color", unitConfig.alternativePowerColor, true, function(value)
                    SetUnitField("alternativePowerColor", value)
                end, unitConfig.showAlternativePowerBar ~= true)
            end

            local altPowerBackgroundEnabled = unitConfig.alternativePowerBackground
            if altPowerBackgroundEnabled == nil then
                altPowerBackgroundEnabled = unitConfig.powerBackground ~= false
            else
                altPowerBackgroundEnabled = altPowerBackgroundEnabled ~= false
            end

            if usePropertyGroups then
                AddPropertyCheckBoxRow(backgroundSection, L["OPTION_ENABLED"] or "Enabled", altPowerBackgroundEnabled, function(value)
                    SetUnitField("alternativePowerBackground", value and true or false, rootSection)
                end, unitConfig.showAlternativePowerBar ~= true)

                AddPropertyColorRow(backgroundSection, L["OPTION_COLOR"] or "Color", unitConfig.alternativePowerBackgroundColor or unitConfig.powerBackgroundColor, true, function(value)
                    SetUnitField("alternativePowerBackgroundColor", value)
                end, unitConfig.showAlternativePowerBar ~= true or altPowerBackgroundEnabled == false)
            else
                AddCheckBox(altPowerSection, L["OPTION_SHOW_BACKGROUND"] or "Show Background", altPowerBackgroundEnabled, function(value)
                    SetUnitField("alternativePowerBackground", value and true or false, altPowerSection)
                end, unitConfig.showAlternativePowerBar ~= true)

                AddColorPicker(altPowerSection, L["OPTION_BACKGROUND_COLOR"] or "Background Color", unitConfig.alternativePowerBackgroundColor or unitConfig.powerBackgroundColor, true, function(value)
                    SetUnitField("alternativePowerBackgroundColor", value)
                end, unitConfig.showAlternativePowerBar ~= true or altPowerBackgroundEnabled == false)
            end
        end

        if isExpert then
            local altPowerReverseFillEnabled = unitConfig.alternativePowerBarReverseFill
            if altPowerReverseFillEnabled == nil then
                altPowerReverseFillEnabled = unitConfig.powerBarReverseFill == true
            else
                altPowerReverseFillEnabled = altPowerReverseFillEnabled == true
            end

            if usePropertyGroups then
                AddPropertyCheckBoxRow(behaviorSection, L["OPTION_REVERSE_FILL"] or "Reverse Fill", altPowerReverseFillEnabled, function(value)
                    SetUnitField("alternativePowerBarReverseFill", value and true or false)
                end, unitConfig.showAlternativePowerBar ~= true)
            else
                AddCheckBox(behaviorSection, L["OPTION_REVERSE_FILL"] or "Reverse Fill", altPowerReverseFillEnabled, function(value)
                    SetUnitField("alternativePowerBarReverseFill", value and true or false)
                end, unitConfig.showAlternativePowerBar ~= true)
            end

        end

        if actionsSection then
            local label = L["EDITOR_REMOVE_ALTERNATIVE_POWER_BAR_BUTTON"] or "Remove Secondary Resource Bar"
            AddPropertyActionButtonRow(actionsSection, label, label, "DestructiveAction", 180, function()
                ApplySingletonBarPresence("AlternativePowerBar", false, "alt_power")
            end)
        end
    end
    local function BuildClassPowerSectionContent(classPowerSection)
        if not classPowerSection or selectedUnit ~= "player" then
            return
        end

        local usePropertyGroups = IsScopedClassPowerBarObjectMode()
        local rootSection = classPowerSection
        local generalSection = classPowerSection
        local appearanceSection = classPowerSection
        local backgroundSection = classPowerSection
        local geometrySection = classPowerSection
        local positionSection = classPowerSection
        local actionsSection
        if usePropertyGroups then
            generalSection = AddFramedObjectPropertyGroup(classPowerSection, L["SECTION_GENERAL"] or "General", false)
            appearanceSection = AddFramedObjectPropertyGroup(classPowerSection, L["SECTION_APPEARANCE"] or "Appearance", true)
            backgroundSection = AddFramedObjectPropertyGroup(classPowerSection, L["SECTION_BACKGROUND"] or L["OPTION_BACKGROUND"] or "Background", true)
            geometrySection = AddFramedObjectPropertyGroup(classPowerSection, L["SECTION_GEOMETRY"] or "Geometry", true)
            if isExpert then
                positionSection = AddFramedObjectPropertyGroup(classPowerSection, L["SECTION_POSITION"] or "Position", true)
            end
            actionsSection = AddFramedObjectPropertyGroup(classPowerSection, L["SECTION_ACTIONS"] or "Actions", true)
        end

        if usePropertyGroups then
            AddPropertyCheckBoxRow(generalSection, L["OPTION_SHOW"] or "Show", unitConfig.showClassPowerBar == true, function(value)
                SetUnitField("showClassPowerBar", value and true or false, rootSection)
            end)
        else
            AddCheckBox(generalSection, L["OPTION_SHOW_CLASS_POWER_BAR"] or "Show Class Power Bar", unitConfig.showClassPowerBar == true, function(value)
                SetUnitField("showClassPowerBar", value and true or false, rootSection)
            end)
        end

        local classPowerTextureValue = unitConfig.classPowerBarTexture or unitConfig.powerBarTexture
        local classPowerTextureOptions = BuildStatusBarTextureOptions(classPowerTextureValue)
        local classPowerTextureDropdown
        local function SetClassPowerBarTexture(value)
            local result = SetUnitField("classPowerBarTexture", value)
            if not (result and result.ok == false) then
                if classPowerTextureDropdown and type(classPowerTextureDropdown._fpSetPropertyValueText) == "function" then
                    local storedValue = result and result.newValue or unitConfig.classPowerBarTexture or unitConfig.powerBarTexture or value
                    classPowerTextureDropdown._fpSetPropertyValueText(ResolveOptionValueLabel(BuildStatusBarTextureOptions(storedValue), storedValue))
                else
                    SyncDropdownToStoredValue(classPowerTextureDropdown, unitConfig.classPowerBarTexture or unitConfig.powerBarTexture)
                end
            end
            return result
        end
        if usePropertyGroups then
            classPowerTextureDropdown = AddPropertyPickerValueRow(appearanceSection, L["OPTION_TEXTURE"] or L["OPTION_BAR_TEXTURE"] or "Texture", ResolveOptionValueLabel(classPowerTextureOptions, classPowerTextureOptions.value or classPowerTextureValue), function()
                OpenMediaBrowserForField({
                    mediaType = MEDIA_TYPE_STATUSBAR,
                    currentValue = function()
                        return unitConfig.classPowerBarTexture or unitConfig.powerBarTexture
                    end,
                    fallbackReference = DEFAULT_STATUSBAR_REFERENCE,
                    title = L["MEDIA_LIBRARY_BROWSE_STATUSBAR_TITLE"] or "Choose Bar Texture",
                    onApply = SetClassPowerBarTexture,
                })
            end, unitConfig.showClassPowerBar ~= true or not IsMediaBrowserAvailable(), {
                tooltip = L["MEDIA_LIBRARY_BROWSE_STATUSBAR_TITLE"] or L["MEDIA_LIBRARY_BROWSE"] or "Browse textures",
            })
        else
            classPowerTextureDropdown = AddDropdown(classPowerSection, L["OPTION_BAR_TEXTURE"] or "Bar Texture", classPowerTextureOptions, classPowerTextureOptions.value, SetClassPowerBarTexture, unitConfig.showClassPowerBar ~= true)
            AddMediaBrowserForField(classPowerSection, MEDIA_TYPE_STATUSBAR, function()
                return unitConfig.classPowerBarTexture or unitConfig.powerBarTexture
            end, DEFAULT_STATUSBAR_REFERENCE, L["MEDIA_LIBRARY_BROWSE_STATUSBAR_TITLE"] or "Choose Bar Texture", unitConfig.showClassPowerBar ~= true, SetClassPowerBarTexture)
        end

        if usePropertyGroups then
            AddPropertyColorRow(appearanceSection, L["OPTION_COLOR"] or "Color", unitConfig.classPowerColor or unitConfig.powerColor, true, function(value)
                SetUnitField("classPowerColor", value)
            end, unitConfig.showClassPowerBar ~= true or unitConfig.useBlizzardColorClassPower ~= false)
        else
            AddColorPicker(appearanceSection, L["OPTION_COLOR"] or "Color", unitConfig.classPowerColor or unitConfig.powerColor, true, function(value)
                SetUnitField("classPowerColor", value)
            end, unitConfig.showClassPowerBar ~= true or unitConfig.useBlizzardColorClassPower ~= false)
        end

        if usePropertyGroups then
            AddPropertyCheckBoxRow(appearanceSection, L["OPTION_BLIZZARD_STANDARD"] or "Blizzard Standard", unitConfig.useBlizzardColorClassPower ~= false, function(value)
                SetUnitField("useBlizzardColorClassPower", value and true or false, rootSection)
            end, unitConfig.showClassPowerBar ~= true)
        else
            AddCheckBox(appearanceSection, L["OPTION_BLIZZARD_STANDARD"] or "Blizzard Standard", unitConfig.useBlizzardColorClassPower ~= false, function(value)
                SetUnitField("useBlizzardColorClassPower", value and true or false, rootSection)
            end, unitConfig.showClassPowerBar ~= true)
        end

        if usePropertyGroups then
            AddPropertyColorRow(backgroundSection, L["OPTION_COLOR"] or "Color", unitConfig.classPowerBackgroundColor or unitConfig.powerBackgroundColor, true, function(value)
                SetUnitField("classPowerBackgroundColor", value)
            end, unitConfig.showClassPowerBar ~= true)
        else
            AddColorPicker(appearanceSection, L["OPTION_BACKGROUND_COLOR"] or "Background Color", unitConfig.classPowerBackgroundColor or unitConfig.powerBackgroundColor, true, function(value)
                SetUnitField("classPowerBackgroundColor", value)
            end, unitConfig.showClassPowerBar ~= true)
        end

        local classPowerBarHeightControl
        if usePropertyGroups then
            classPowerBarHeightControl = AddPropertyCompactSliderRow(geometrySection, L["OPTION_HEIGHT"] or L["OPTION_CLASS_POWER_BAR_HEIGHT"] or "Height", 4, 30, 1, tonumber(unitConfig.classPowerBarHeight) or 12, function(value)
                if IsActiveCanvasWheelFieldControlSuppressed(classPowerBarHeightControl) then
                    return
                end
                SetUnitField("classPowerBarHeight", math.floor((value or 0) + 0.5))
            end, unitConfig.showClassPowerBar ~= true)
        else
            classPowerBarHeightControl = AddSlider(geometrySection, L["OPTION_CLASS_POWER_BAR_HEIGHT"] or "Class Power Height", 4, 30, 1, tonumber(unitConfig.classPowerBarHeight) or 12, function(value)
                if IsActiveCanvasWheelFieldControlSuppressed(classPowerBarHeightControl) then
                    return
                end
                SetUnitField("classPowerBarHeight", math.floor((value or 0) + 0.5))
            end, unitConfig.showClassPowerBar ~= true)
        end
        RegisterActiveCanvasWheelFieldControl(state and state.selectedUnit, { kind = "bar", unit = state and state.selectedUnit, objectKey = "ClassPowerBar" }, "classPowerBarHeight", classPowerBarHeightControl)

        local classPowerGrowth = unitConfig.classPowerBarGrowth == "RIGHT_TO_LEFT" and "RIGHT_TO_LEFT" or "LEFT_TO_RIGHT"
        if usePropertyGroups then
            AddPropertyDropdownRow(geometrySection, L["OPTION_CLASS_POWER_SEGMENT_GROWTH"] or "Segment Growth", {
                list = absorbGrowthList,
                value = classPowerGrowth,
                onChanged = function(value)
                    SetUnitField("classPowerBarGrowth", value)
                end,
            }, unitConfig.showClassPowerBar ~= true)
        else
            AddDropdown(geometrySection, L["OPTION_CLASS_POWER_SEGMENT_GROWTH"] or "Segment Growth", absorbGrowthList, classPowerGrowth, function(value)
                SetUnitField("classPowerBarGrowth", value)
            end, unitConfig.showClassPowerBar ~= true)
        end

        if isExpert then
            if usePropertyGroups then
                AddPropertyCompactSliderRow(geometrySection, L["OPTION_WIDTH"] or L["OPTION_CLASS_POWER_BAR_WIDTH"] or "Width", 40, 260, 1, tonumber(unitConfig.classPowerBarWidth) or 100, function(value)
                    SetUnitField("classPowerBarWidth", math.floor((value or 0) + 0.5))
                end, unitConfig.showClassPowerBar ~= true)
            else
                AddSlider(geometrySection, L["OPTION_CLASS_POWER_BAR_WIDTH"] or "Class Power Width", 40, 260, 1, tonumber(unitConfig.classPowerBarWidth) or 100, function(value)
                    SetUnitField("classPowerBarWidth", math.floor((value or 0) + 0.5))
                end, unitConfig.showClassPowerBar ~= true)
            end

            if usePropertyGroups then
                AddPropertyCompactSliderRow(geometrySection, L["OPTION_CLASS_POWER_BAR_SPACING"] or "Class Power Spacing", 0, 20, 1, tonumber(unitConfig.classPowerBarSpacing) or 2, function(value)
                    SetUnitField("classPowerBarSpacing", math.floor((value or 0) + 0.5))
                end, unitConfig.showClassPowerBar ~= true)
            else
                AddSlider(geometrySection, L["OPTION_CLASS_POWER_BAR_SPACING"] or "Class Power Spacing", 0, 20, 1, tonumber(unitConfig.classPowerBarSpacing) or 2, function(value)
                    SetUnitField("classPowerBarSpacing", math.floor((value or 0) + 0.5))
                end, unitConfig.showClassPowerBar ~= true)
            end

            local classPowerAnchorTargetLabel = usePropertyGroups
                and (L["OPTION_ANCHOR_TARGET"] or "Anchor Target")
                or (L["OPTION_ANCHOR_TO_TARGET"] or "Anchor To Element")
            local anchorParent = usePropertyGroups and positionSection or geometrySection
            if usePropertyGroups then
                AddPropertyDropdownRow(anchorParent, classPowerAnchorTargetLabel, {
                    list = classPowerAnchorTargetList,
                    value = unitConfig.classPowerBarAnchorTo or "HealthBar",
                    onChanged = function(value)
                        SetUnitField("classPowerBarAnchorTo", value)
                    end,
                    anchorKey = "class_power_anchor_to",
                }, unitConfig.showClassPowerBar ~= true)
            else
                AddDropdown(anchorParent, classPowerAnchorTargetLabel, classPowerAnchorTargetList, unitConfig.classPowerBarAnchorTo or "HealthBar", function(value)
                    SetUnitField("classPowerBarAnchorTo", value)
                end, unitConfig.showClassPowerBar ~= true)
            end

            local pointControl
            local relativePointControl
            if usePropertyGroups then
                pointControl, relativePointControl = AddPointPairRow(positionSection, {
                    list = barAnchorList,
                    value = unitConfig.classPowerBarPoint or "BOTTOMRIGHT",
                    onChanged = function(value)
                        if IsActiveCanvasDirectMoveOffsetControlSuppressed(pointControl) then
                            return
                        end
                        SetUnitField("classPowerBarPoint", value)
                    end,
                    disabled = unitConfig.showClassPowerBar ~= true,
                }, {
                    list = barAnchorList,
                    value = unitConfig.classPowerBarRelativePoint or "BOTTOMRIGHT",
                    onChanged = function(value)
                        if IsActiveCanvasDirectMoveOffsetControlSuppressed(relativePointControl) then
                            return
                        end
                        SetUnitField("classPowerBarRelativePoint", value)
                    end,
                    disabled = unitConfig.showClassPowerBar ~= true,
                })
            else
                AddDropdown(classPowerSection, L["OPTION_ANCHOR_FROM"] or "Anchor From", barAnchorList, unitConfig.classPowerBarPoint or "BOTTOMRIGHT", function(value)
                    SetUnitField("classPowerBarPoint", value)
                end, unitConfig.showClassPowerBar ~= true)

                AddDropdown(classPowerSection, L["OPTION_ANCHOR_TO"] or "Anchor To", barAnchorList, unitConfig.classPowerBarRelativePoint or "BOTTOMRIGHT", function(value)
                    SetUnitField("classPowerBarRelativePoint", value)
                end, unitConfig.showClassPowerBar ~= true)
            end

            local offsetXLabel = usePropertyGroups and (L["OPTION_OFFSET_X"] or "Offset X") or (L["OPTION_X_OFFSET"] or "X Offset")
            local offsetYLabel = usePropertyGroups and (L["OPTION_OFFSET_Y"] or "Offset Y") or (L["OPTION_Y_OFFSET"] or "Y Offset")
            local offsetXControl
            local offsetYControl
            if usePropertyGroups then
                offsetXControl = AddPropertyCompactSliderRow(positionSection, offsetXLabel, -200, 200, 1, tonumber(unitConfig.classPowerBarOffsetX) or -5, function(value)
                    if IsActiveCanvasDirectMoveOffsetControlSuppressed(offsetXControl) then
                        return
                    end
                    SetUnitField("classPowerBarOffsetX", math.floor((value or 0) + 0.5))
                end, unitConfig.showClassPowerBar ~= true)
            else
                offsetXControl = AddSlider(geometrySection, offsetXLabel, -200, 200, 1, tonumber(unitConfig.classPowerBarOffsetX) or -5, function(value)
                    if IsActiveCanvasDirectMoveOffsetControlSuppressed(offsetXControl) then
                        return
                    end
                    SetUnitField("classPowerBarOffsetX", math.floor((value or 0) + 0.5))
                end, unitConfig.showClassPowerBar ~= true)
            end

            if usePropertyGroups then
                offsetYControl = AddPropertyCompactSliderRow(positionSection, offsetYLabel, -200, 200, 1, tonumber(unitConfig.classPowerBarOffsetY) or 5, function(value)
                    if IsActiveCanvasDirectMoveOffsetControlSuppressed(offsetYControl) then
                        return
                    end
                    SetUnitField("classPowerBarOffsetY", math.floor((value or 0) + 0.5))
                end, unitConfig.showClassPowerBar ~= true)
            else
                offsetYControl = AddSlider(geometrySection, offsetYLabel, -200, 200, 1, tonumber(unitConfig.classPowerBarOffsetY) or 5, function(value)
                    if IsActiveCanvasDirectMoveOffsetControlSuppressed(offsetYControl) then
                        return
                    end
                    SetUnitField("classPowerBarOffsetY", math.floor((value or 0) + 0.5))
                end, unitConfig.showClassPowerBar ~= true)
            end
            RegisterActiveCanvasDirectMoveOffsetControls(state and state.selectedUnit, {
                kind = "bar",
                unit = state and state.selectedUnit,
                objectKey = "ClassPowerBar",
            }, offsetXControl, offsetYControl, pointControl, relativePointControl)
        end

        if actionsSection then
            local label = L["EDITOR_REMOVE_CLASS_POWER_BAR_BUTTON"] or "Remove Class Power Bar"
            AddPropertyActionButtonRow(actionsSection, label, label, "DestructiveAction", 160, function()
                ApplySingletonBarPresence("ClassPowerBar", false, "class_power")
            end)
        end
    end

    if selectedUnit == "player" then
        if IsScopedAlternativePowerBarObjectMode() then
            AddScopedObjectInspectorBody("alt_power", L["BAR_ALT_POWER"] or "Alternative Power Bar", BuildAltPowerSectionContent)
        else
            AddScopedInspectorSection("alt_power", L["BAR_ALT_POWER"] or "Alt Power", true, {
                localContentBuilder = BuildAltPowerSectionContent,
                layoutRefresh = RefreshInspectorLayout,
            })
        end

        if IsScopedClassPowerBarObjectMode() then
            AddScopedObjectInspectorBody("class_power", L["BAR_CLASS_POWER"] or "Class Power Bar", BuildClassPowerSectionContent)
        else
            AddScopedInspectorSection("class_power", L["BAR_CLASS_POWER"] or "Class Power", true, {
                localContentBuilder = BuildClassPowerSectionContent,
                layoutRefresh = RefreshInspectorLayout,
            })
        end
    end

    local function BuildCastSectionContent(castSection)
        if not castSection then
            return
        end

        local usePropertyGroups = IsScopedCastBarObjectMode()
        local generalSection = castSection
        local appearanceSection = castSection
        local geometrySection = castSection
        local actionsSection
        if usePropertyGroups then
            generalSection = AddFramedObjectPropertyGroup(castSection, L["SECTION_GENERAL"] or "General", false)
            appearanceSection = AddFramedObjectPropertyGroup(castSection, L["SECTION_APPEARANCE"] or "Appearance", true)
            geometrySection = AddFramedObjectPropertyGroup(castSection, L["SECTION_GEOMETRY"] or "Geometry", true)
            actionsSection = AddFramedObjectPropertyGroup(castSection, L["SECTION_ACTIONS"] or "Actions", true)
        end

        if usePropertyGroups then
            AddPropertyCheckBoxRow(generalSection, L["OPTION_SHOW"] or "Show", unitConfig.showCastBar ~= false, function(value)
                SetUnitField("showCastBar", value and true or false, castSection)
            end)
        else
            AddCheckBox(generalSection, L["OPTION_SHOW_CAST_BAR"] or "Show Cast Bar", unitConfig.showCastBar ~= false, function(value)
                SetUnitField("showCastBar", value and true or false, castSection)
            end)
        end

        if usePropertyGroups then
            AddPropertyCheckBoxRow(generalSection, L["OPTION_SHOW_CAST_BAR_ICON"] or "Show Cast Bar Icon", unitConfig.showCastBarIcon ~= false, function(value)
                SetUnitField("showCastBarIcon", value and true or false)
            end, unitConfig.showCastBar == false)
        else
            AddCheckBox(generalSection, L["OPTION_SHOW_CAST_BAR_ICON"] or "Show Cast Bar Icon", unitConfig.showCastBarIcon ~= false, function(value)
                SetUnitField("showCastBarIcon", value and true or false)
            end, unitConfig.showCastBar == false)
        end

        if isQuick or isExpert then
            local castTextureOptions = BuildStatusBarTextureOptions(unitConfig.castBarTexture)
            local castTextureDropdown
            local function SetCastBarTexture(value)
                local result = SetUnitField("castBarTexture", value)
                if not (result and result.ok == false) then
                    if castTextureDropdown and type(castTextureDropdown._fpSetPropertyValueText) == "function" then
                        local storedValue = result and result.newValue or unitConfig.castBarTexture or value
                        castTextureDropdown._fpSetPropertyValueText(ResolveOptionValueLabel(BuildStatusBarTextureOptions(storedValue), storedValue))
                    else
                        SyncDropdownToStoredValue(castTextureDropdown, unitConfig.castBarTexture)
                    end
                end
                return result
            end
            if usePropertyGroups then
                castTextureDropdown = AddPropertyPickerValueRow(appearanceSection, L["OPTION_TEXTURE"] or L["OPTION_BAR_TEXTURE"] or "Texture", ResolveOptionValueLabel(castTextureOptions, castTextureOptions.value or unitConfig.castBarTexture), function()
                    OpenMediaBrowserForField({
                        mediaType = MEDIA_TYPE_STATUSBAR,
                        currentValue = function()
                            return unitConfig.castBarTexture
                        end,
                        fallbackReference = DEFAULT_STATUSBAR_REFERENCE,
                        title = L["MEDIA_LIBRARY_BROWSE_STATUSBAR_TITLE"] or "Choose Bar Texture",
                        onApply = SetCastBarTexture,
                    })
                end, unitConfig.showCastBar == false or not IsMediaBrowserAvailable(), {
                    tooltip = L["MEDIA_LIBRARY_BROWSE_STATUSBAR_TITLE"] or L["MEDIA_LIBRARY_BROWSE"] or "Browse textures",
                })
            else
                castTextureDropdown = AddDropdown(castSection, L["OPTION_BAR_TEXTURE"] or "Bar Texture", castTextureOptions, castTextureOptions.value, SetCastBarTexture, unitConfig.showCastBar == false)
                AddMediaBrowserForField(castSection, MEDIA_TYPE_STATUSBAR, function()
                    return unitConfig.castBarTexture
                end, DEFAULT_STATUSBAR_REFERENCE, L["MEDIA_LIBRARY_BROWSE_STATUSBAR_TITLE"] or "Choose Bar Texture", unitConfig.showCastBar == false, SetCastBarTexture)
            end

            local castBarWidthMode = unitConfig.castBarWidthMode or "MATCH_FRAME"
            local castBarWidthMin, castBarWidthMax, castBarWidthDefault = 20, 600, 120
            if CastBar.GetWidthLimits then
                castBarWidthMin, castBarWidthMax, castBarWidthDefault = CastBar.GetWidthLimits()
            end
            local castBarWidthControl
            if usePropertyGroups then
                AddPropertyDropdownRow(geometrySection, L["OPTION_WIDTH_MODE"] or "Width Mode", {
                    list = castBarWidthModeList,
                    value = castBarWidthMode,
                    onChanged = function(value)
                        SetUnitField("castBarWidthMode", value)
                    end,
                })
            else
                AddDropdown(geometrySection, L["OPTION_WIDTH_MODE"] or "Width Mode", castBarWidthModeList, castBarWidthMode, function(value)
                    SetUnitField("castBarWidthMode", value)
                end)
            end
            if usePropertyGroups then
                castBarWidthControl = AddPropertyCompactSliderRow(geometrySection, L["OPTION_WIDTH"] or "Width", castBarWidthMin, castBarWidthMax, 1, tonumber(unitConfig.castBarWidth) or castBarWidthDefault, function(value)
                    SetUnitField("castBarWidth", math.floor((value or 0) + 0.5))
                end, castBarWidthMode ~= "CUSTOM")
            else
                castBarWidthControl = AddSlider(geometrySection, L["OPTION_WIDTH"] or "Width", castBarWidthMin, castBarWidthMax, 1, tonumber(unitConfig.castBarWidth) or castBarWidthDefault, function(value)
                    SetUnitField("castBarWidth", math.floor((value or 0) + 0.5))
                end, castBarWidthMode ~= "CUSTOM")
            end

            local castBarHeightControl
            if usePropertyGroups then
                castBarHeightControl = AddPropertyCompactSliderRow(geometrySection, L["OPTION_HEIGHT"] or L["OPTION_CAST_BAR_HEIGHT"] or "Height", 4, 30, 1, tonumber(unitConfig.castBarHeight) or 20, function(value)
                    if IsActiveCanvasWheelFieldControlSuppressed(castBarHeightControl) then
                        return
                    end
                    SetUnitField("castBarHeight", math.floor((value or 0) + 0.5))
                end, unitConfig.showCastBar == false)
            else
                castBarHeightControl = AddSlider(geometrySection, L["OPTION_CAST_BAR_HEIGHT"] or "Cast Bar Height", 4, 30, 1, tonumber(unitConfig.castBarHeight) or 20, function(value)
                    if IsActiveCanvasWheelFieldControlSuppressed(castBarHeightControl) then
                        return
                    end
                    SetUnitField("castBarHeight", math.floor((value or 0) + 0.5))
                end, unitConfig.showCastBar == false)
            end
            RegisterActiveCanvasWheelFieldControl(state and state.selectedUnit, { kind = "bar", unit = state and state.selectedUnit, objectKey = "CastBar" }, "castBarHeight", castBarHeightControl)
        end

        if usePropertyGroups then
            AddPropertyColorRow(appearanceSection, L["OPTION_COLOR"] or L["OPTION_CAST_BAR_COLOR"] or "Color", unitConfig.castBarColor, true, function(value)
                SetUnitField("castBarColor", value)
            end, unitConfig.showCastBar == false)
        else
            AddColorPicker(appearanceSection, L["OPTION_CAST_BAR_COLOR"] or "Cast Bar Color", unitConfig.castBarColor, true, function(value)
                SetUnitField("castBarColor", value)
            end, unitConfig.showCastBar == false)
        end

        local defaultCastBarInterruptibleColor = OptionValues.GetDefault({"Units", state and state.selectedUnit, "castBarInterruptibleColor"}, {0.6, 0.6, 0.6, 1.0})
        local castBarInterruptibleColor = unitConfig.castBarInterruptibleColor or unitConfig.castBarUninterruptibleColor or defaultCastBarInterruptibleColor
        if usePropertyGroups then
            AddPropertyColorRow(appearanceSection, L["OPTION_INTERRUPTIBLE_COLOR"] or L["OPTION_CAST_BAR_INTERRUPTIBLE_COLOR"] or "Interruptible Color", castBarInterruptibleColor, true, function(value)
                SetUnitField("castBarInterruptibleColor", value)
            end, unitConfig.showCastBar == false)
        else
            AddColorPicker(appearanceSection, L["OPTION_CAST_BAR_INTERRUPTIBLE_COLOR"] or "Cast Bar Interruptible Color", castBarInterruptibleColor, true, function(value)
                SetUnitField("castBarInterruptibleColor", value)
            end, unitConfig.showCastBar == false)
        end

        if actionsSection then
            AddPropertyActionButtonRow(actionsSection, L["EDITOR_REMOVE_CAST_BAR_BUTTON"] or "Remove Cast Bar", L["EDITOR_REMOVE_CAST_BAR_BUTTON"] or "Remove Cast Bar", "DestructiveAction", 148, function()
                ApplyCastBarPresence(false)
            end)
        end
    end

    if IsScopedCastBarObjectMode() then
        AddScopedObjectInspectorBody("cast", L["BAR_CAST"] or "Cast Bar", BuildCastSectionContent)
    else
        AddScopedInspectorSection("cast", L["BAR_CAST"] or "Cast Bar", true, {
            localContentBuilder = BuildCastSectionContent,
            layoutRefresh = RefreshInspectorLayout,
        })
    end

    local function BuildVisibilitySectionContent(visibilitySection)
        if not visibilitySection then
            return
        end

        AddCheckBox(visibilitySection, L["OPTION_SHOW_IN_SOLO"] or "Show in Solo", unitConfig.showInSolo ~= false, function(value)
            SetUnitField("showInSolo", value and true or false)
        end)

        AddCheckBox(visibilitySection, L["OPTION_SHOW_IN_PARTY"] or "Show in Party", unitConfig.showInParty ~= false, function(value)
            SetUnitField("showInParty", value and true or false)
        end)

        AddCheckBox(visibilitySection, L["OPTION_SHOW_IN_RAID"] or "Show in Raid", unitConfig.showInRaid ~= false, function(value)
            SetUnitField("showInRaid", value and true or false)
        end)

        AddCheckBox(visibilitySection, L["OPTION_SHOW_IN_ARENA"] or "Show in Arena", unitConfig.showInArena ~= false, function(value)
            SetUnitField("showInArena", value and true or false)
        end)

        AddCheckBox(visibilitySection, L["OPTION_SHOW_IN_PVP"] or "Show in PvP", unitConfig.showInPvp ~= false, function(value)
            SetUnitField("showInPvp", value and true or false)
        end)

        if isExpert then
            AddCheckBox(visibilitySection, L["OPTION_MOUSE_ENABLED"] or "Mouse Enabled", unitConfig.mouseEnabled ~= false, function(value)
                SetUnitField("mouseEnabled", value and true or false, visibilitySection)
            end)

            AddCheckBox(visibilitySection, L["OPTION_CLICK_THROUGH"] or "Click Through", unitConfig.clickThrough == true, function(value)
                SetUnitField("clickThrough", value and true or false)
            end, unitConfig.mouseEnabled == false)
        end
    end

    AddScopedInspectorSection("visibility", L["EDITOR_SECTION_VISIBILITY"] or "Visibility", true, {
        localContentBuilder = BuildVisibilitySectionContent,
        layoutRefresh = RefreshInspectorLayout,
    })

    local function BuildPositioningSectionContent(positioning)
        if not positioning or not isExpert then
            return
        end

        AddDropdown(positioning, L["EDITOR_OPTION_POINT"] or "Anchor From", POINTS, unitConfig.point or "CENTER", function(value)
            SetUnitField("point", value)
        end)

        AddDropdown(positioning, L["EDITOR_OPTION_RELATIVE_POINT"] or "Anchor To", POINTS, unitConfig.relativePoint or "CENTER", function(value)
            SetUnitField("relativePoint", value)
        end)

        AddSlider(positioning, L["EDITOR_OPTION_X"] or "X Offset", -800, 800, 1, tonumber(unitConfig.x) or 0, function(value)
            SetUnitField("x", math.floor((value or 0) + 0.5))
        end)

        AddSlider(positioning, L["EDITOR_OPTION_Y"] or "Y Offset", -800, 800, 1, tonumber(unitConfig.y) or 0, function(value)
            SetUnitField("y", math.floor((value or 0) + 0.5))
        end)
    end

    local function BuildCastPositionSectionContent(castPosition)
        if not castPosition or not isExpert then
            return
        end

        AddDropdown(castPosition, L["OPTION_ANCHOR_FROM"] or "Anchor From", barAnchorList, unitConfig.castBarPoint or "BOTTOMLEFT", function(value)
            SetUnitField("castBarPoint", value)
        end)

        AddDropdown(castPosition, L["OPTION_ANCHOR_TO"] or "Anchor To", barAnchorList, unitConfig.castBarRelativePoint or "TOPLEFT", function(value)
            SetUnitField("castBarRelativePoint", value)
        end)

        local frame = ns.frames and ns.frames[state.selectedUnit == "boss" and "boss1" or state.selectedUnit]
        local minX, maxX, minY, maxY = ns.GUI.Editor.AnchorGeometry.ResolveCastBarOffsetRange(frame, unitConfig)
        local offsetXControl = AddSlider(castPosition, L["OPTION_X_OFFSET"] or "X Offset", minX, maxX, 1, tonumber(unitConfig.castBarOffsetX) or 0, function(value)
            if IsActiveCanvasDirectMoveOffsetControlSuppressed(offsetXControl) then
                return
            end
            SetUnitField("castBarOffsetX", math.floor((value or 0) + 0.5))
        end)

        local offsetYControl = AddSlider(castPosition, L["OPTION_Y_OFFSET"] or "Y Offset", minY, maxY, 1, tonumber(unitConfig.castBarOffsetY) or 4, function(value)
            if IsActiveCanvasDirectMoveOffsetControlSuppressed(offsetYControl) then
                return
            end
            SetUnitField("castBarOffsetY", math.floor((value or 0) + 0.5))
        end)
        RegisterActiveCanvasDirectMoveOffsetControls(state and state.selectedUnit, {
            kind = "bar",
            unit = state and state.selectedUnit,
            objectKey = "CastBar",
        }, offsetXControl, offsetYControl)
    end

    if isExpert then
        AddScopedInspectorSection("positioning", L["EDITOR_POSITIONING"] or "Positioning", true, {
            localContentBuilder = BuildPositioningSectionContent,
            layoutRefresh = RefreshInspectorLayout,
        })

        AddScopedInspectorSection("cast_position", L["EDITOR_SECTION_CAST_POSITION"] or "Cast Bar Position", true, {
            localContentBuilder = BuildCastPositionSectionContent,
            layoutRefresh = RefreshInspectorLayout,
        })
    end

    local function BuildTextSectionContent(textSection)
        local selectedTextId, textConfig, linkedTemplateName, _, currentTextList = ResolveTextContext()
        if not textSection or not textConfig then
            return
        end

        local isScopedObject = IsSelectedTextObject(selectedUnit, selectedTextId)
        local contentSection = textSection
        local appearanceSection = textSection
        local positionSection = textSection
        local advancedSection = textSection
        local actionsSection = textSection

        if isScopedObject then
            contentSection = AddFramedObjectPropertyGroup(textSection, L["SECTION_CONTENT"] or "Content", false)
            appearanceSection = AddFramedObjectPropertyGroup(textSection, L["SECTION_APPEARANCE"] or "Appearance", true)
            positionSection = AddFramedObjectPropertyGroup(textSection, L["SECTION_POSITION"] or "Position", true)
            if not isQuick and type(InspectorMutations.AssignTextStateTemplate) == "function"
                and type(InspectorMutations.UnassignTextStateTemplate) == "function"
            then
                advancedSection = AddFramedObjectPropertyGroup(textSection, L["SECTION_ADVANCED"] or "Advanced", true)
            end
            actionsSection = AddFramedObjectPropertyGroup(textSection, L["SECTION_ACTIONS"] or "Actions", true)
        else
            AddDropdown(textSection, L["EDITOR_OPTION_TEXT_ELEMENT"] or "Text Element", currentTextList, selectedTextId, function(value)
                local ok = type(ObjectSelection.SelectObject) == "function"
                    and ObjectSelection.SelectObject({
                        kind = "text",
                        unit = selectedUnit,
                        textKey = value,
                    })
                if ok == true then
                    RebuildLocalSection(textSection)
                    return
                end
                local result = type(InspectorTextSelection.Set) == "function"
                    and InspectorTextSelection.Set(state, value, currentTextList)
                    or nil
                if result and result.ok and result.changed then
                    RebuildLocalSection(textSection)
                end
            end, nil, "text_element")
        end

        local templateLabel = ((type(linkedTemplateName) == "string" and linkedTemplateName ~= "") and linkedTemplateName or (L["EDITOR_TEXT_DIRECT_TEMPLATE"] or "Direct Template"))
        if inspectorContext.entity and textConfig.templateId ~= nil then
            local entity = textConfig.templateId and ns.TextTemplateLibrary and ns.TextTemplateLibrary.ResolveTemplateEntity
                and ns.TextTemplateLibrary.ResolveTemplateEntity(textConfig.templateId, ns.db)
            if entity then
                local typeLabel = entity.readOnly
                    and (L["INFO_TEXT_BUILDER_BUILTIN_READ_ONLY"] or "Built-in · Read-only")
                    or (L["INFO_TEXT_BUILDER_USER_TEMPLATE"] or "User Template")
                templateLabel = entity.name .. " · " .. typeLabel
            else
                templateLabel = L["MEDIA_LIBRARY_MISSING"] or "Missing"
            end
        elseif inspectorContext.entity then
            templateLabel = L["EDITOR_TEMPLATE_LOCAL"] or "Local"
        end
        if isScopedObject then
            if inspectorContext.entity and textConfig.templateId == nil then
                AddPropertyValueTextRow(contentSection, L["EDITOR_OPTION_TEXT"] or "Text", L["INFO_TEXT_BUILDER_LOCAL_TEXT"] or "Local Text")
                AddPropertyActionButtonRow(contentSection, L["EDITOR_EDIT_TEXT"] or "Edit Text...", L["EDITOR_EDIT_TEXT"] or "Edit Text...", "InspectorAction", 142, function()
                    local controller = ns.GUIController or {}
                    local char = ns.db and ns.db.char
                    local layoutId = type(char) == "table" and char.activeLayoutId or nil
                    if type(controller.OpenTextBuilderWindow) == "function" then
                        controller.OpenTextBuilderWindow({
                            entity = true,
                            kind = "object",
                            layoutId = layoutId,
                            unitKey = selectedUnit,
                            textKey = selectedTextId,
                            returnContext = {pickerMode = "change", layoutId = layoutId,
                                unitKey = selectedUnit, textKey = selectedTextId, originToken = {}},
                        })
                    end
                end)
            end
            AddPropertyValueTextRow(contentSection, L["EDITOR_OPTION_TEMPLATE"] or "Template", templateLabel)
            AddPropertyActionButtonRow(contentSection, L["EDITOR_CHOOSE_TEMPLATE"] or "Choose Template...", L["EDITOR_CHOOSE_TEMPLATE"] or "Choose Template...", "InspectorAction", 142, function()
                local library = ns.GUI and ns.GUI.Editor and ns.GUI.Editor.TextTemplateLibraryWindow or nil
                if library and type(library.Open) == "function" then
                    library.Open({
                        mode = "change",
                        unit = selectedUnit,
                        textKey = selectedTextId,
                        entity = inspectorContext.entity == true,
                        initialTemplateName = type(textConfig.templateName) == "string" and textConfig.templateName or nil,
                        initialTemplateId = textConfig.templateId,
                    })
                end
            end)
        else
            local templateSummary = AceGUI:Create("Label")
            templateSummary:SetFullWidth(true)
            templateSummary:SetText(
                (L["EDITOR_TEMPLATE_LINKED"] or "Linked Template") .. ": " .. templateLabel
            )
            if templateSummary.label and templateSummary.label.SetFont then
                templateSummary.label:SetFont(STANDARD_TEXT_FONT, 10, "")
                templateSummary.label:SetTextColor(0.55, 0.59, 0.64, 1)
            end
            textSection:AddChild(templateSummary)

            local changeTemplateButton = AceGUI:Create("Button")
            if FormWidgets.ResetInspectorButtonState then
                FormWidgets.ResetInspectorButtonState(changeTemplateButton)
            end
            changeTemplateButton:SetText(L["EDITOR_CHANGE_TEXT_TEMPLATE"] or "Change Text...")
            changeTemplateButton:SetFullWidth(false)
            changeTemplateButton:SetWidth(142)
            changeTemplateButton:SetCallback("OnClick", function()
                local library = ns.GUI and ns.GUI.Editor and ns.GUI.Editor.TextTemplateLibraryWindow or nil
                if library and type(library.Open) == "function" then
                    library.Open({
                        mode = "change",
                        unit = selectedUnit,
                        textKey = selectedTextId,
                        entity = inspectorContext.entity == true,
                        initialTemplateName = type(textConfig.templateName) == "string" and textConfig.templateName or nil,
                        initialTemplateId = textConfig.templateId,
                    })
                end
            end)
            if FormWidgets.ApplyModalActionButtonVisual then
                FormWidgets.ApplyModalActionButtonVisual(changeTemplateButton, "InspectorAction")
            end
            textSection:AddChild(changeTemplateButton)
        end

        local missingTemplateMessages = BuildMissingTemplateMessages(selectedTextId)
        if #missingTemplateMessages > 0 then
            local missingTemplateWarning = AceGUI:Create("Label")
            missingTemplateWarning:SetFullWidth(true)
            missingTemplateWarning:SetText(table.concat(missingTemplateMessages, "\n"))
            if missingTemplateWarning.label and missingTemplateWarning.label.SetFont then
                missingTemplateWarning.label:SetFont(STANDARD_TEXT_FONT, 10, "")
                missingTemplateWarning.label:SetTextColor(1.00, 0.72, 0.28, 1)
            end
            contentSection:AddChild(missingTemplateWarning)
        end

        if isScopedObject then
            AddPropertyCheckBoxRow(contentSection, L["OPTION_ENABLED"] or "Enabled", textConfig.enabled ~= false, function(value)
                SetTextField(selectedTextId, "enabled", value and true or false, textSection)
            end, nil, "text_enabled")
        else
            AddCheckBox(textSection, L["OPTION_ENABLED"] or "Enabled", textConfig.enabled ~= false, function(value)
                SetTextField(selectedTextId, "enabled", value and true or false, textSection)
            end, nil, "text_enabled")
        end

        local function AddFontSizeControl(parent)
            local fontSizeSlider
            if isScopedObject then
                fontSizeSlider = AddPropertyCompactSliderRow(parent, L["OPTION_FONT_SIZE"] or "Font Size", 6, 32, 1, tonumber(textConfig.fontSize) or 12, function(value)
                    if activeTextFontSizeControl
                        and activeTextFontSizeControl.widget == fontSizeSlider
                        and activeTextFontSizeControl.suppress == true
                    then
                        return
                    end
                    SetTextFontSize(selectedTextId, value)
                end, textConfig.enabled == false, "text_font_size")
            else
                fontSizeSlider = AddSlider(parent, L["OPTION_FONT_SIZE"] or "Font Size", 6, 32, 1, tonumber(textConfig.fontSize) or 12, function(value)
                    if activeTextFontSizeControl
                        and activeTextFontSizeControl.widget == fontSizeSlider
                        and activeTextFontSizeControl.suppress == true
                    then
                        return
                    end
                    SetTextFontSize(selectedTextId, value)
                end, textConfig.enabled == false, "text_font_size")
            end
            RegisterActiveTextFontSizeControl(state and state.selectedUnit, selectedTextId, fontSizeSlider)
        end

        local fontOptions = BuildFontOptions(textConfig.font)
        local fontDropdown
        local function SetTextFont(value)
            local result = SetTextField(selectedTextId, "font", value)
            if not (result and result.ok == false) then
                if fontDropdown and type(fontDropdown._fpSetPropertyValueText) == "function" then
                    local storedValue = result and result.newValue or textConfig.font or value
                    fontDropdown._fpSetPropertyValueText(ResolveOptionValueLabel(BuildFontOptions(storedValue), storedValue))
                else
                    SyncDropdownToStoredValue(fontDropdown, textConfig.font)
                end
            end
            return result
        end

        if isQuick then
            if isScopedObject then
                fontDropdown = AddPropertyPickerValueRow(appearanceSection, L["OPTION_FONT"] or "Font", ResolveOptionValueLabel(fontOptions, fontOptions.value or textConfig.font), function()
                    OpenMediaBrowserForField({
                        mediaType = MEDIA_TYPE_FONT,
                        currentValue = function()
                            return textConfig.font
                        end,
                        fallbackReference = DEFAULT_FONT_REFERENCE,
                        title = L["MEDIA_LIBRARY_BROWSE_FONT_TITLE"] or "Choose Font",
                        onApply = SetTextFont,
                    })
                end, textConfig.enabled == false or not IsMediaBrowserAvailable(), {
                    tooltip = L["MEDIA_LIBRARY_BROWSE_FONT_TITLE"] or L["MEDIA_LIBRARY_BROWSE"] or "Browse fonts",
                })
                AddPropertyDropdownRow(appearanceSection, L["OPTION_FONT_STYLE"] or "Font Style", {
                    list = fontStyleList,
                    value = textConfig.fontStyle or "NONE",
                    onChanged = function(value)
                        SetTextField(selectedTextId, "fontStyle", value)
                    end,
                    anchorKey = "text_font_style",
                }, textConfig.enabled == false)
            end
            AddFontSizeControl(appearanceSection)
            if isScopedObject then
                AddPropertyColorRow(appearanceSection, L["OPTION_COLOR"] or "Color", textConfig.color, true, function(value)
                    SetTextField(selectedTextId, "color", value)
                end, textConfig.enabled == false, "text_color")
            else
                AddColorPicker(textSection, L["OPTION_COLOR"] or "Color", textConfig.color, true, function(value)
                    SetTextField(selectedTextId, "color", value)
                end, textConfig.enabled == false, "text_color")
            end
            if isScopedObject then
                AddPropertyDropdownRow(appearanceSection, L["OPTION_JUSTIFY_H"] or "Justify", {
                    list = justifyList,
                    value = textConfig.justifyH or "CENTER",
                    onChanged = function(value)
                        SetTextField(selectedTextId, "justifyH", value)
                    end,
                    anchorKey = "text_justify",
                }, textConfig.enabled == false)
                AddPropertyDropdownRow(positionSection, L["OPTION_ANCHOR_TO_TARGET"] or "Anchor To Element", {
                    list = textAnchorTargetList,
                    value = textConfig.anchorTo or "Frame",
                    onChanged = function(value)
                        SetTextField(selectedTextId, "anchorTo", value)
                    end,
                    anchorKey = "text_anchor_to",
                }, textConfig.enabled == false)
                AddPropertyCompactSliderRow(positionSection, L["OPTION_X_OFFSET"] or "X Offset", -100, 100, 1, tonumber(textConfig.offsetX) or 0, function(value)
                    SetTextField(selectedTextId, "offsetX", math.floor((value or 0) + 0.5))
                end, textConfig.enabled == false, "text_offset_x")
                AddPropertyCompactSliderRow(positionSection, L["OPTION_Y_OFFSET"] or "Y Offset", -100, 100, 1, tonumber(textConfig.offsetY) or 0, function(value)
                    SetTextField(selectedTextId, "offsetY", math.floor((value or 0) + 0.5))
                end, textConfig.enabled == false, "text_offset_y")
            end
        else
            if isScopedObject then
                fontDropdown = AddPropertyPickerValueRow(appearanceSection, L["OPTION_FONT"] or "Font", ResolveOptionValueLabel(fontOptions, fontOptions.value or textConfig.font), function()
                    OpenMediaBrowserForField({
                        mediaType = MEDIA_TYPE_FONT,
                        currentValue = function()
                            return textConfig.font
                        end,
                        fallbackReference = DEFAULT_FONT_REFERENCE,
                        title = L["MEDIA_LIBRARY_BROWSE_FONT_TITLE"] or "Choose Font",
                        onApply = SetTextFont,
                    })
                end, textConfig.enabled == false or not IsMediaBrowserAvailable(), {
                    tooltip = L["MEDIA_LIBRARY_BROWSE_FONT_TITLE"] or L["MEDIA_LIBRARY_BROWSE"] or "Browse fonts",
                })
                AddPropertyDropdownRow(appearanceSection, L["OPTION_FONT_STYLE"] or "Font Style", {
                    list = fontStyleList,
                    value = textConfig.fontStyle or "NONE",
                    onChanged = function(value)
                        SetTextField(selectedTextId, "fontStyle", value)
                    end,
                    anchorKey = "text_font_style",
                }, textConfig.enabled == false)
                local fontSizeSlider
                fontSizeSlider = AddPropertyCompactSliderRow(appearanceSection, L["OPTION_FONT_SIZE"] or "Font Size", 6, 32, 1, tonumber(textConfig.fontSize) or 12, function(value)
                    if activeTextFontSizeControl
                        and activeTextFontSizeControl.widget == fontSizeSlider
                        and activeTextFontSizeControl.suppress == true
                    then
                        return
                    end
                    SetTextFontSize(selectedTextId, value)
                end, textConfig.enabled == false, "text_font_size")
                RegisterActiveTextFontSizeControl(state and state.selectedUnit, selectedTextId, fontSizeSlider)
                AddPropertyColorRow(appearanceSection, L["OPTION_COLOR"] or "Color", textConfig.color, true, function(value)
                    SetTextField(selectedTextId, "color", value)
                end, textConfig.enabled == false, "text_color")
                AddPropertyDropdownRow(appearanceSection, L["OPTION_JUSTIFY_H"] or "Justify", {
                    list = justifyList,
                    value = textConfig.justifyH or "CENTER",
                    onChanged = function(value)
                        SetTextField(selectedTextId, "justifyH", value)
                    end,
                    anchorKey = "text_justify",
                }, textConfig.enabled == false)
            else
                fontDropdown = AddDropdown(textSection, L["OPTION_FONT"] or "Font", fontOptions, fontOptions.value, SetTextFont, textConfig.enabled == false, "text_font")
                AddMediaBrowserForField(textSection, MEDIA_TYPE_FONT, function()
                    return textConfig.font
                end, DEFAULT_FONT_REFERENCE, L["MEDIA_LIBRARY_BROWSE_FONT_TITLE"] or "Choose Font", textConfig.enabled == false, SetTextFont)

                AddDropdown(textSection, L["OPTION_FONT_STYLE"] or "Font Style", fontStyleList, textConfig.fontStyle or "NONE", function(value)
                    SetTextField(selectedTextId, "fontStyle", value)
                end, textConfig.enabled == false, "text_font_style")

                AddFontSizeControl(textSection)

                AddDropdown(textSection, L["OPTION_JUSTIFY_H"] or "Justify", justifyList, textConfig.justifyH or "CENTER", function(value)
                    SetTextField(selectedTextId, "justifyH", value)
                end, textConfig.enabled == false, "text_justify")
            end

            if isScopedObject then
                AddPropertyDropdownRow(positionSection, L["OPTION_ANCHOR_TO_TARGET"] or "Anchor To Element", {
                    list = textAnchorTargetList,
                    value = textConfig.anchorTo or "Frame",
                    onChanged = function(value)
                        SetTextField(selectedTextId, "anchorTo", value)
                    end,
                    anchorKey = "text_anchor_to",
                }, textConfig.enabled == false)
                AddPropertyDropdownRow(positionSection, L["OPTION_ANCHOR_FROM"] or "Anchor From", {
                    list = textAnchorPointList,
                    value = textConfig.point or "CENTER",
                    onChanged = function(value)
                        SetTextField(selectedTextId, "point", value)
                    end,
                    anchorKey = "text_point",
                }, textConfig.enabled == false)
                AddPropertyDropdownRow(positionSection, L["OPTION_ANCHOR_TO"] or "Anchor To", {
                    list = textAnchorPointList,
                    value = textConfig.relativePoint or "CENTER",
                    onChanged = function(value)
                        SetTextField(selectedTextId, "relativePoint", value)
                    end,
                    anchorKey = "text_relative_point",
                }, textConfig.enabled == false)
                AddPropertyCompactSliderRow(positionSection, L["OPTION_X_OFFSET"] or "X Offset", -100, 100, 1, tonumber(textConfig.offsetX) or 0, function(value)
                    SetTextField(selectedTextId, "offsetX", math.floor((value or 0) + 0.5))
                end, textConfig.enabled == false, "text_offset_x")
                AddPropertyCompactSliderRow(positionSection, L["OPTION_Y_OFFSET"] or "Y Offset", -100, 100, 1, tonumber(textConfig.offsetY) or 0, function(value)
                    SetTextField(selectedTextId, "offsetY", math.floor((value or 0) + 0.5))
                end, textConfig.enabled == false, "text_offset_y")
                AddPropertyDropdownRow(positionSection, L["OPTION_TEXT_OVERFLOW"] or "Text Overflow", {
                    list = overflowList,
                    value = textConfig.overflowMode or "NONE",
                    onChanged = function(value)
                        SetTextField(selectedTextId, "overflowMode", value)
                    end,
                    anchorKey = "text_overflow",
                }, textConfig.enabled == false)
                AddPropertyCheckBoxRow(appearanceSection, L["OPTION_FONT_SHADOW"] or "Shadow", textConfig.shadowEnabled ~= false, function(value)
                    SetTextField(selectedTextId, "shadowEnabled", value and true or false)
                end, textConfig.enabled == false, "text_shadow")
                AddPropertyColorRow(appearanceSection, L["OPTION_SHADOW_COLOR"] or "Shadow Color", textConfig.shadowColor, true, function(value)
                    SetTextField(selectedTextId, "shadowColor", value)
                end, textConfig.enabled == false or textConfig.shadowEnabled == false, "text_shadow_color")
            else
                AddDropdown(textSection, L["OPTION_ANCHOR_TO_TARGET"] or "Anchor To Element", textAnchorTargetList, textConfig.anchorTo or "Frame", function(value)
                    SetTextField(selectedTextId, "anchorTo", value)
                end, textConfig.enabled == false, "text_anchor_to")

                AddDropdown(textSection, L["OPTION_ANCHOR_FROM"] or "Anchor From", textAnchorPointList, textConfig.point or "CENTER", function(value)
                    SetTextField(selectedTextId, "point", value)
                end, textConfig.enabled == false, "text_point")

                AddDropdown(textSection, L["OPTION_ANCHOR_TO"] or "Anchor To", textAnchorPointList, textConfig.relativePoint or "CENTER", function(value)
                    SetTextField(selectedTextId, "relativePoint", value)
                end, textConfig.enabled == false, "text_relative_point")

                AddSlider(textSection, L["OPTION_X_OFFSET"] or "X Offset", -100, 100, 1, tonumber(textConfig.offsetX) or 0, function(value)
                    SetTextField(selectedTextId, "offsetX", math.floor((value or 0) + 0.5))
                end, textConfig.enabled == false, "text_offset_x")

                AddSlider(textSection, L["OPTION_Y_OFFSET"] or "Y Offset", -100, 100, 1, tonumber(textConfig.offsetY) or 0, function(value)
                    SetTextField(selectedTextId, "offsetY", math.floor((value or 0) + 0.5))
                end, textConfig.enabled == false, "text_offset_y")

                AddDropdown(textSection, L["OPTION_TEXT_OVERFLOW"] or "Text Overflow", overflowList, textConfig.overflowMode or "NONE", function(value)
                    SetTextField(selectedTextId, "overflowMode", value)
                end, textConfig.enabled == false, "text_overflow")

                AddCheckBox(textSection, L["OPTION_FONT_SHADOW"] or "Shadow", textConfig.shadowEnabled ~= false, function(value)
                    SetTextField(selectedTextId, "shadowEnabled", value and true or false)
                end, textConfig.enabled == false, "text_shadow")

                AddColorPicker(textSection, L["OPTION_SHADOW_COLOR"] or "Shadow Color", textConfig.shadowColor, true, function(value)
                    SetTextField(selectedTextId, "shadowColor", value)
                end, textConfig.enabled == false or textConfig.shadowEnabled == false, "text_shadow_color")
            end

            if type(InspectorMutations.AssignTextStateTemplate) == "function"
                and type(InspectorMutations.UnassignTextStateTemplate) == "function"
            then
                if not isScopedObject then
                    AddSpacer(textSection, 6)
                    local stateTemplateTitle = AceGUI:Create("Label")
                    stateTemplateTitle:SetFullWidth(true)
                    stateTemplateTitle:SetText(L["TEXT_STATE_TEMPLATES"] or "State Templates")
                    if stateTemplateTitle.label and stateTemplateTitle.label.SetFont then
                        stateTemplateTitle.label:SetFont(STANDARD_TEXT_FONT, 11, "")
                        stateTemplateTitle.label:SetTextColor(0.68, 0.70, 0.75, 1)
                    end
                    textSection:AddChild(stateTemplateTitle)
                end

                local stateTemplates = type(textConfig) == "table" and (inspectorContext.entity and textConfig.stateTemplateIds or textConfig.stateTemplates) or nil
                local deadTemplateOptions = BuildTextStateTemplateOptions(stateTemplates and stateTemplates.dead or nil, inspectorContext.entity)
                local deadTemplateDropdown
                if isScopedObject then
                    deadTemplateDropdown = AddPropertyDropdownRow(advancedSection, L["TEXT_DEAD_TEMPLATE"] or "Dead Template", {
                        list = deadTemplateOptions,
                        value = deadTemplateOptions.value,
                        onChanged = function(value)
                            SetTextStateTemplate(selectedTextId, "dead", value, textSection, deadTemplateDropdown)
                        end,
                        anchorKey = "text_dead_template",
                    }, textConfig.enabled == false)
                else
                    deadTemplateDropdown = AddDropdown(textSection, L["TEXT_DEAD_TEMPLATE"] or "Dead Template", deadTemplateOptions, deadTemplateOptions.value, function(value)
                        SetTextStateTemplate(selectedTextId, "dead", value, textSection, deadTemplateDropdown)
                    end, textConfig.enabled == false, "text_dead_template")
                end

                local ghostTemplateOptions = BuildTextStateTemplateOptions(stateTemplates and stateTemplates.ghost or nil, inspectorContext.entity)
                local ghostTemplateDropdown
                if isScopedObject then
                    ghostTemplateDropdown = AddPropertyDropdownRow(advancedSection, L["TEXT_GHOST_TEMPLATE"] or "Ghost Template", {
                        list = ghostTemplateOptions,
                        value = ghostTemplateOptions.value,
                        onChanged = function(value)
                            SetTextStateTemplate(selectedTextId, "ghost", value, textSection, ghostTemplateDropdown)
                        end,
                        anchorKey = "text_ghost_template",
                    }, textConfig.enabled == false)
                else
                    ghostTemplateDropdown = AddDropdown(textSection, L["TEXT_GHOST_TEMPLATE"] or "Ghost Template", ghostTemplateOptions, ghostTemplateOptions.value, function(value)
                        SetTextStateTemplate(selectedTextId, "ghost", value, textSection, ghostTemplateDropdown)
                    end, textConfig.enabled == false, "text_ghost_template")
                end
            end
        end

        if IsSelectedTextObject(selectedUnit, selectedTextId) then
            if isScopedObject then
                AddPropertyActionButtonRow(actionsSection, L["EDITOR_DELETE_TEXT_BUTTON"] or "Delete Text", L["EDITOR_DELETE_TEXT_BUTTON"] or "Delete Text", "DestructiveAction", 128, function()
                    OpenDeleteTextInstanceConfirmDialog(selectedUnit, selectedTextId)
                end)
            else
                AddSpacer(textSection, 10)
                local deleteTextButton = FormWidgets.CreateActionButton
                    and FormWidgets.CreateActionButton(L["EDITOR_DELETE_TEXT_BUTTON"] or "Delete Text", "DestructiveAction", 128, false)
                    or AceGUI:Create("Button")
                deleteTextButton:SetText(L["EDITOR_DELETE_TEXT_BUTTON"] or "Delete Text")
                deleteTextButton:SetWidth(128)
                deleteTextButton:SetFullWidth(false)
                if FormWidgets.ApplyModalActionButtonVisual then
                    FormWidgets.ApplyModalActionButtonVisual(deleteTextButton, "DestructiveAction")
                end
                deleteTextButton:SetCallback("OnClick", function()
                    OpenDeleteTextInstanceConfirmDialog(selectedUnit, selectedTextId)
                end)
                textSection:AddChild(deleteTextButton)
            end
        end
    end

    local function ResolveSelectedTextInspectorTitle()
        local selectedTextId, textConfig = ResolveTextContext()
        if not textConfig then
            return L["EDITOR_SECTION_TEXT_ELEMENTS"] or "Text Elements"
        end
        local textLabel = selectedTextId
        if type(textConfig.templateName) == "string" and textConfig.templateName ~= "" then
            textLabel = textConfig.templateName
        end
        return string.format("%s: %s", L["EDITOR_OPTION_TEXT"] or "Text", textLabel or selectedTextId or "")
    end

    if select(2, ResolveTextContext()) then
        local selectedTextId = ResolveTextContext()
        if IsSelectedTextObject(selectedUnit, selectedTextId) then
            AddScopedObjectInspectorBody("texts", ResolveSelectedTextInspectorTitle(), BuildTextSectionContent)
        else
            AddScopedInspectorSection("texts", L["EDITOR_SECTION_TEXT_ELEMENTS"] or "Text Elements", true, {
                localContentBuilder = BuildTextSectionContent,
                layoutRefresh = RefreshInspectorLayout,
            })
        end
    end
    local function BuildIndicatorSectionContent(indicatorSection)
        local selectedIndicatorKey, indicatorMeta, indicatorConfig, _, currentIndicatorList = ResolveIndicatorContext()
        if not indicatorSection or type(indicatorConfig) ~= "table" or type(indicatorMeta) ~= "table" then
            return
        end

        local isScopedObject = IsSelectedIndicatorObject(selectedUnit, selectedIndicatorKey)
        local appearanceSection = indicatorSection
        local geometrySection = indicatorSection
        local positionSection = indicatorSection
        local behaviorSection = indicatorSection
        local actionsSection = indicatorSection
        local disabled = indicatorConfig.enabled == false

        if isScopedObject then
            appearanceSection = AddFramedObjectPropertyGroup(indicatorSection, L["SECTION_APPEARANCE"] or "Appearance", false)
            geometrySection = AddFramedObjectPropertyGroup(indicatorSection, L["SECTION_GEOMETRY"] or "Geometry", true)
            behaviorSection = AddFramedObjectPropertyGroup(indicatorSection, L["SECTION_BEHAVIOR"] or "Behavior", true)
            if isExpert then
                positionSection = AddFramedObjectPropertyGroup(indicatorSection, L["SECTION_POSITION"] or "Position", true)
            end
            actionsSection = AddFramedObjectPropertyGroup(indicatorSection, L["SECTION_ACTIONS"] or "Actions", true)
        end

        local removeActionAdded = false
        local function RemoveSelectedIndicator()
            local result = ApplySingletonIndicatorPresence(selectedIndicatorKey, false)
            if result and result.ok == false then
                return result
            end
            return result
        end

        local function AddRemoveIndicatorAction()
            if removeActionAdded or not IsSelectedIndicatorObject(selectedUnit, selectedIndicatorKey) then
                return
            end
            removeActionAdded = true
            if isScopedObject then
                AddPropertyActionButtonRow(actionsSection, L["EDITOR_REMOVE_INDICATOR_BUTTON"] or "Remove Indicator", L["EDITOR_REMOVE_INDICATOR_BUTTON"] or "Remove Indicator", "DestructiveAction", 148, RemoveSelectedIndicator)
            else
                AddSpacer(indicatorSection, 8)
                local removeButton = FormWidgets.CreateActionButton
                    and FormWidgets.CreateActionButton(L["EDITOR_REMOVE_INDICATOR_BUTTON"] or "Remove Indicator", "DestructiveAction", 148, false)
                    or AceGUI:Create("Button")
                removeButton:SetText(L["EDITOR_REMOVE_INDICATOR_BUTTON"] or "Remove Indicator")
                removeButton:SetWidth(148)
                removeButton:SetFullWidth(false)
                removeButton:SetCallback("OnClick", RemoveSelectedIndicator)
                if FormWidgets.ApplyModalActionButtonVisual then
                    FormWidgets.ApplyModalActionButtonVisual(removeButton, "DestructiveAction")
                elseif FormWidgets.StyleActionButton then
                    FormWidgets.StyleActionButton(removeButton, "DestructiveAction")
                end
                indicatorSection:AddChild(removeButton)
            end
        end

        if not isScopedObject then
            AddDropdown(indicatorSection, L["EDITOR_OPTION_INDICATOR"] or "Indicator", currentIndicatorList, selectedIndicatorKey, function(value)
                local ok = type(ObjectSelection.SelectObject) == "function"
                    and ObjectSelection.SelectObject({
                        kind = "indicator",
                        unit = selectedUnit,
                        indicatorKey = value,
                    })
                if ok == true then
                    RebuildLocalSection(indicatorSection)
                    return
                end
                local result = type(InspectorIndicatorSelection.Set) == "function"
                    and InspectorIndicatorSelection.Set(state, value, currentIndicatorList)
                    or nil
                if result and result.ok and result.changed then
                    RebuildLocalSection(indicatorSection)
                end
            end)
        end

        if isScopedObject then
            AddPropertyCheckBoxRow(appearanceSection, L["OPTION_ENABLED"] or "Enabled", indicatorConfig.enabled ~= false, function(value)
                SetIndicatorField(selectedIndicatorKey, "enabled", value and true or false, indicatorSection)
            end)
        else
            AddCheckBox(indicatorSection, L[indicatorMeta.labelKey] or "Enabled", indicatorConfig.enabled ~= false, function(value)
                SetIndicatorField(selectedIndicatorKey, "enabled", value and true or false, indicatorSection)
            end)
        end

        if indicatorMeta.classification then
            if isScopedObject then
                AddPropertyDropdownRow(appearanceSection, L[indicatorMeta.effectLabel] or "Effect", {
                    list = classificationEffectList,
                    value = indicatorConfig.effect or "PORTRAIT_OVERLAY",
                    onChanged = function(value)
                        SetIndicatorField(selectedIndicatorKey, "effect", value)
                    end,
                }, disabled)
            else
                AddDropdown(indicatorSection, L[indicatorMeta.effectLabel] or "Effect", classificationEffectList, indicatorConfig.effect or "PORTRAIT_OVERLAY", function(value)
                    SetIndicatorField(selectedIndicatorKey, "effect", value)
                end, disabled)
            end
            AddRemoveIndicatorAction()
            return
        end

        local effect = indicatorConfig.effect or "ICON"
        if indicatorMeta.effectListKey == "status" then
            if isScopedObject then
                AddPropertyDropdownRow(appearanceSection, L[indicatorMeta.effectLabel] or "Effect", {
                    list = statusIndicatorEffectList,
                    value = effect,
                    onChanged = function(value)
                        SetIndicatorField(selectedIndicatorKey, "effect", value, nil, function()
                            NotifyConfigChangedAndRebuildSection(indicatorSection, "indicators")
                        end)
                    end,
                }, disabled)
            else
                AddDropdown(indicatorSection, L[indicatorMeta.effectLabel] or "Effect", statusIndicatorEffectList, effect, function(value)
                    SetIndicatorField(selectedIndicatorKey, "effect", value, nil, function()
                        NotifyConfigChangedAndRebuildSection(indicatorSection, "indicators")
                    end)
                end, disabled)
            end
        end

        local useOverlayEffect = indicatorMeta.effectListKey == "status" and effect == "FRAME_OVERLAY"
        if useOverlayEffect then
            AddRemoveIndicatorAction()
            return
        end

        if isScopedObject then
            AddPropertyDropdownRow(behaviorSection, L[indicatorMeta.placementLabel] or "Placement", {
                list = portraitPlacementList,
                value = indicatorConfig.placement or "ATTACHED",
                onChanged = function(value)
                    SetIndicatorField(selectedIndicatorKey, "placement", value, indicatorSection)
                end,
            }, disabled)
        else
            AddDropdown(indicatorSection, L[indicatorMeta.placementLabel] or "Placement", portraitPlacementList, indicatorConfig.placement or "ATTACHED", function(value)
                SetIndicatorField(selectedIndicatorKey, "placement", value, indicatorSection)
            end, disabled)
        end

        if isScopedObject then
            AddPropertyCompactSliderRow(geometrySection, L[indicatorMeta.sizeLabel] or "Size", 8, 128, 1, tonumber(indicatorConfig.size) or 16, function(value)
                SetIndicatorField(selectedIndicatorKey, "size", math.floor((value or 0) + 0.5))
            end, disabled)
        else
            AddSlider(indicatorSection, L[indicatorMeta.sizeLabel] or "Size", 8, 128, 1, tonumber(indicatorConfig.size) or 16, function(value)
                SetIndicatorField(selectedIndicatorKey, "size", math.floor((value or 0) + 0.5))
            end, disabled)
        end

        if not isExpert then
            AddRemoveIndicatorAction()
            return
        end

        local indicatorScaleControl
        if isScopedObject then
            indicatorScaleControl = AddPropertyCompactSliderRow(geometrySection, L[indicatorMeta.scaleLabel] or "Scale", 0.25, 3.0, 0.01, tonumber(indicatorConfig.scale) or 1, function(value)
                if IsActiveCanvasWheelFieldControlSuppressed(indicatorScaleControl) then
                    return
                end
                SetIndicatorField(selectedIndicatorKey, "scale", tonumber(string.format("%.2f", value or 1)) or 1)
            end, disabled)
        else
            indicatorScaleControl = AddSlider(indicatorSection, L[indicatorMeta.scaleLabel] or "Scale", 0.25, 3.0, 0.01, tonumber(indicatorConfig.scale) or 1, function(value)
                if IsActiveCanvasWheelFieldControlSuppressed(indicatorScaleControl) then
                    return
                end
                SetIndicatorField(selectedIndicatorKey, "scale", tonumber(string.format("%.2f", value or 1)) or 1)
            end, disabled)
        end
        RegisterActiveCanvasWheelFieldControl(state and state.selectedUnit, {
            kind = "indicator",
            unit = state and state.selectedUnit,
            indicatorKey = selectedIndicatorKey,
            objectKey = selectedIndicatorKey,
        }, "scale", indicatorScaleControl)

        local placement = indicatorConfig.placement or "ATTACHED"
        local inside = placement == "INSIDE"

        if inside then
            if isScopedObject then
                AddPropertyDropdownRow(positionSection, L["OPTION_ANCHOR_TO_TARGET"] or "Anchor To Element", {
                    list = portraitAnchorTargetList,
                    value = indicatorConfig.insideAnchorTo or "Frame",
                    onChanged = function(value)
                        SetIndicatorField(selectedIndicatorKey, "insideAnchorTo", value)
                    end,
                }, disabled)
                AddPropertyDropdownRow(positionSection, L[indicatorMeta.insideSideLabel] or (L["OPTION_INSIDE_SIDE"] or "Inside Side"), {
                    list = portraitInsideSideList,
                    value = indicatorConfig.insideSide or "LEFT",
                    onChanged = function(value)
                        SetIndicatorField(selectedIndicatorKey, "insideSide", value)
                    end,
                }, disabled)
                AddPropertyCompactSliderRow(positionSection, L["OPTION_PADDING"] or "Padding", 0, 64, 1, tonumber(indicatorConfig.padding) or 2, function(value)
                    SetIndicatorField(selectedIndicatorKey, "padding", math.floor((value or 0) + 0.5))
                end, disabled)
            else
                AddDropdown(indicatorSection, L["OPTION_ANCHOR_TO_TARGET"] or "Anchor To Element", portraitAnchorTargetList, indicatorConfig.insideAnchorTo or "Frame", function(value)
                    SetIndicatorField(selectedIndicatorKey, "insideAnchorTo", value)
                end, disabled)

                AddDropdown(indicatorSection, L[indicatorMeta.insideSideLabel] or (L["OPTION_INSIDE_SIDE"] or "Inside Side"), portraitInsideSideList, indicatorConfig.insideSide or "LEFT", function(value)
                    SetIndicatorField(selectedIndicatorKey, "insideSide", value)
                end, disabled)

                AddSlider(indicatorSection, L["OPTION_PADDING"] or "Padding", 0, 64, 1, tonumber(indicatorConfig.padding) or 2, function(value)
                    SetIndicatorField(selectedIndicatorKey, "padding", math.floor((value or 0) + 0.5))
                end, disabled)
            end
            AddRemoveIndicatorAction()
            return
        end

        if isScopedObject then
            AddPropertyDropdownRow(positionSection, L["OPTION_ANCHOR_TO_TARGET"] or "Anchor To Element", {
                list = portraitAnchorTargetList,
                value = indicatorConfig.anchorTo or "Frame",
                onChanged = function(value)
                    SetIndicatorField(selectedIndicatorKey, "anchorTo", value)
                end,
            }, disabled)
            local pointControl = AddPropertyDropdownRow(positionSection, L["OPTION_ANCHOR_FROM"] or "Anchor From", {
                list = portraitAnchorPointList,
                value = indicatorConfig.point or "TOP",
                onChanged = function(value)
                    if IsActiveCanvasDirectMoveOffsetControlSuppressed(pointControl) then
                        return
                    end
                    SetIndicatorField(selectedIndicatorKey, "point", value)
                end,
            }, disabled)
            local relativePointControl = AddPropertyDropdownRow(positionSection, L["OPTION_ANCHOR_TO"] or "Anchor To", {
                list = portraitAnchorPointList,
                value = indicatorConfig.relativePoint or "TOP",
                onChanged = function(value)
                    if IsActiveCanvasDirectMoveOffsetControlSuppressed(relativePointControl) then
                        return
                    end
                    SetIndicatorField(selectedIndicatorKey, "relativePoint", value)
                end,
            }, disabled)
            local offsetXControl = AddPropertyCompactSliderRow(positionSection, L["OPTION_X_OFFSET"] or "X Offset", -500, 500, 1, tonumber(indicatorConfig.offsetX) or 0, function(value)
                if IsActiveCanvasDirectMoveOffsetControlSuppressed(offsetXControl) then
                    return
                end
                SetIndicatorField(selectedIndicatorKey, "offsetX", math.floor((value or 0) + 0.5))
            end, disabled)
            local offsetYControl = AddPropertyCompactSliderRow(positionSection, L["OPTION_Y_OFFSET"] or "Y Offset", -500, 500, 1, tonumber(indicatorConfig.offsetY) or 0, function(value)
                if IsActiveCanvasDirectMoveOffsetControlSuppressed(offsetYControl) then
                    return
                end
                SetIndicatorField(selectedIndicatorKey, "offsetY", math.floor((value or 0) + 0.5))
            end, disabled)
            RegisterActiveCanvasDirectMoveOffsetControls(state and state.selectedUnit, {
                kind = "indicator",
                unit = state and state.selectedUnit,
                indicatorKey = selectedIndicatorKey,
                objectKey = selectedIndicatorKey,
            }, offsetXControl, offsetYControl, pointControl, relativePointControl)
        else
            AddDropdown(indicatorSection, L["OPTION_ANCHOR_TO_TARGET"] or "Anchor To Element", portraitAnchorTargetList, indicatorConfig.anchorTo or "Frame", function(value)
                SetIndicatorField(selectedIndicatorKey, "anchorTo", value)
            end, disabled)

            AddDropdown(indicatorSection, L["OPTION_ANCHOR_FROM"] or "Anchor From", portraitAnchorPointList, indicatorConfig.point or "TOP", function(value)
                SetIndicatorField(selectedIndicatorKey, "point", value)
            end, disabled)

            AddDropdown(indicatorSection, L["OPTION_ANCHOR_TO"] or "Anchor To", portraitAnchorPointList, indicatorConfig.relativePoint or "TOP", function(value)
                SetIndicatorField(selectedIndicatorKey, "relativePoint", value)
            end, disabled)

            AddSlider(indicatorSection, L["OPTION_X_OFFSET"] or "X Offset", -500, 500, 1, tonumber(indicatorConfig.offsetX) or 0, function(value)
                SetIndicatorField(selectedIndicatorKey, "offsetX", math.floor((value or 0) + 0.5))
            end, disabled)

            AddSlider(indicatorSection, L["OPTION_Y_OFFSET"] or "Y Offset", -500, 500, 1, tonumber(indicatorConfig.offsetY) or 0, function(value)
                SetIndicatorField(selectedIndicatorKey, "offsetY", math.floor((value or 0) + 0.5))
            end, disabled)
        end

        AddRemoveIndicatorAction()
    end

    local function ResolveSelectedIndicatorInspectorTitle()
        local selectedIndicatorKey, indicatorMeta = ResolveIndicatorContext()
        if type(indicatorMeta) == "table" and type(indicatorMeta.labelKey) == "string" then
            return L[indicatorMeta.labelKey] or selectedIndicatorKey or (L["EDITOR_SECTION_INDICATORS"] or "Indicators")
        end
        return selectedIndicatorKey or (L["EDITOR_SECTION_INDICATORS"] or "Indicators")
    end

    do
        local selectedIndicatorKey, indicatorMeta, indicatorConfig = ResolveIndicatorContext()
        if indicatorConfig and indicatorMeta then
            if IsSelectedIndicatorObject(selectedUnit, selectedIndicatorKey) then
                AddScopedObjectInspectorBody("indicators", ResolveSelectedIndicatorInspectorTitle(), BuildIndicatorSectionContent)
            else
                AddScopedInspectorSection("indicators", L["EDITOR_SECTION_INDICATORS"] or "Indicators", true, {
                    localContentBuilder = BuildIndicatorSectionContent,
                    layoutRefresh = RefreshInspectorLayout,
                })
            end
        end
    end

    local function BuildDecorationSectionContent(decorationSection)
        if not decorationSection then
            return
        end

        local selectedDecorationId, decorationConfig, decorations = ResolveSelectedDecoration(inspectorContext, unitConfig)
        local decorationSelectorOptions = BuildDecorationSelectorOptions(decorations)
        local isScopedObject = IsSelectedDecorationObject(selectedUnit, selectedDecorationId)
        local appearanceSection = decorationSection
        local geometrySection = decorationSection
        local positionSection = decorationSection
        local behaviorSection = decorationSection
        local actionsSection = decorationSection
        local function RebuildDecorationSection()
            NotifyConfigChangedAndRebuildSection(decorationSection, "decoration")
        end

        local function DeleteDecoration()
            if type(InspectorMutations.DeleteDecoration) ~= "function" or not selectedDecorationId then
                return nil
            end
            return RequestEditableMutation(function()
                local result = InspectorMutations.DeleteDecoration(inspectorContext, selectedDecorationId)
                if result and result.ok == false then
                    ReportMutationError(result)
                    return result
                end
                if result and result.ok and result.changed then
                    state.selectedDecorationId = nil
                    SelectUnitRoot(selectedUnit)
                    NotifySidebarChanged("decoration")
                end
                return result
            end)
        end

        local function OpenDeleteDecorationConfirmDialog()
            if not selectedDecorationId or type(InspectorMutations.DeleteDecoration) ~= "function" then
                return
            end
            if not (FormWidgets and type(FormWidgets.CreateCompactConfirmation) == "function") then
                DeleteDecoration()
                return
            end

            CloseDeleteDecorationDialog()
            local dialog = FormWidgets.CreateCompactConfirmation({
                title = L["EDITOR_DELETE_DECORATION_CONFIRM_TITLE"] or "Delete Decoration?",
                message = L["EDITOR_DELETE_DECORATION_CONFIRM_DESCRIPTION"] or "This removes the selected decoration from this unit frame.",
                primary = {
                    text = L["EDITOR_DELETE_DECORATION_CONFIRM_BUTTON"] or "Delete",
                    role = "danger",
                    width = 104,
                    onClick = function(activeDialog)
                        local result = DeleteDecoration()
                        if result and result.ok == false then
                            if activeDialog and activeDialog.SetStatus then
                                activeDialog:SetStatus(ResolveMutationErrorMessage(result), "error", activeDialog.confirmationStatus)
                            end
                            return
                        end
                        CloseDeleteDecorationDialog()
                    end,
                },
                cancel = {
                    text = L["INFO_COMMON_CANCEL"] or "Cancel",
                    role = "utility",
                    width = 104,
                    onClick = function()
                        CloseDeleteDecorationDialog()
                    end,
                },
            })
            if not dialog then
                return
            end

            dialog.window:SetCallback("OnClose", function()
                if deleteDecorationDialog == dialog then
                    deleteDecorationDialog = nil
                end
            end)
            deleteDecorationDialog = dialog
            dialog:Show()
        end

        if isScopedObject then
            appearanceSection = AddFramedObjectPropertyGroup(decorationSection, L["SECTION_APPEARANCE"] or "Appearance", false)
            geometrySection = AddFramedObjectPropertyGroup(decorationSection, L["SECTION_GEOMETRY"] or "Geometry", true)
            positionSection = AddFramedObjectPropertyGroup(decorationSection, L["SECTION_POSITION"] or "Position", true)
            behaviorSection = AddFramedObjectPropertyGroup(decorationSection, L["SECTION_BEHAVIOR"] or "Behavior", true)
            actionsSection = AddFramedObjectPropertyGroup(decorationSection, L["SECTION_ACTIONS"] or "Actions", true)
        elseif #decorations > 0 then
            local selectorRow = AceGUI:Create("SimpleGroup")
            selectorRow:SetFullWidth(true)
            selectorRow:SetLayout("Flow")
            decorationSection:AddChild(selectorRow)

            local decorationSelector = AceGUI:Create("Dropdown")
            decorationSelector:SetFullWidth(true)
            decorationSelector:SetLabel("")
            decorationSelector:SetList(decorationSelectorOptions.values, decorationSelectorOptions.order)
            decorationSelector:SetValue(selectedDecorationId)
            decorationSelector:SetCallback("OnValueChanged", function(_, _, value)
                local ok = type(ObjectSelection.SelectObject) == "function"
                    and ObjectSelection.SelectObject({
                        kind = "decoration",
                        unit = selectedUnit,
                        decorationId = value,
                    })
                if ok ~= true then
                    state.selectedDecorationId = value
                end
                RebuildDecorationSection()
            end)
            if FormWidgets and FormWidgets.StyleDropdown then
                FormWidgets.StyleDropdown(decorationSelector, "editor_inset", "value")
            end
            selectorRow:AddChild(decorationSelector)
        else
            local emptyLabel = AceGUI:Create("Label")
            emptyLabel:SetFullWidth(true)
            emptyLabel:SetText(L["OPTION_DECORATION_EMPTY"] or "No decorations yet.")
            decorationSection:AddChild(emptyLabel)
            return
        end

        if type(decorationConfig) ~= "table" then
            local emptyLabel = AceGUI:Create("Label")
            emptyLabel:SetFullWidth(true)
            emptyLabel:SetText(L["OPTION_DECORATION_EMPTY"] or "No decorations yet.")
            decorationSection:AddChild(emptyLabel)
            return
        end

        local disabled = decorationConfig.enabled == false
        local textureOptions = BuildDecorationTextureOptions(decorationConfig.texture)
        local decorationTextureDropdown
        local decorationTexturePicker

        if isScopedObject then
            AddPropertyCheckBoxRow(appearanceSection, L["OPTION_ENABLED"] or "Enabled", decorationConfig.enabled == true, function(value)
                SetDecorationField("enabled", value and true or false, decorationSection)
            end, nil, "decoration_enabled")
        else
            AddCheckBox(decorationSection, L["OPTION_DECORATION_ENABLED"] or "Enable Decoration", decorationConfig.enabled == true, function(value)
                SetDecorationField("enabled", value and true or false, decorationSection)
            end, nil, "decoration_enabled")
        end

        local function SetDecorationTexture(value)
            local result = SetDecorationField("texture", value or "")
            if not (result and result.ok == false) then
                local nextValue = result and result.newValue or value or ""
                if decorationTexturePicker and type(decorationTexturePicker._fpSetPropertyValueText) == "function" then
                    decorationTexturePicker._fpSetPropertyValueText(ResolveOptionValueLabel(BuildDecorationTextureOptions(nextValue), nextValue))
                else
                    SyncDropdownToStoredValue(decorationTextureDropdown, nextValue)
                end
            end
            return result
        end

        if isScopedObject then
            decorationTexturePicker = AddPropertyPickerValueRow(appearanceSection, L["OPTION_TEXTURE"] or "Texture", ResolveOptionValueLabel(textureOptions, textureOptions.value or decorationConfig.texture), function()
                OpenMediaBrowserForField({
                    mediaType = MEDIA_TYPE_DECORATION,
                    currentValue = function()
                        return decorationConfig.texture
                    end,
                    fallbackReference = DEFAULT_DECORATION_REFERENCE,
                    title = L["MEDIA_LIBRARY_BROWSE_DECORATION_TITLE"] or "Choose Decoration Texture",
                    onApply = SetDecorationTexture,
                })
            end, disabled or not IsMediaBrowserAvailable(), {
                tooltip = L["MEDIA_LIBRARY_BROWSE_DECORATION_TITLE"] or L["MEDIA_LIBRARY_BROWSE"] or "Choose Decoration Texture",
            })
            AddPropertyCompactSliderRow(appearanceSection, L["OPTION_ALPHA"] or "Alpha", 0, 1, 0.01, tonumber(decorationConfig.alpha) or 1, function(value)
                SetDecorationField("alpha", tonumber(string.format("%.2f", value or 1)) or 1)
            end, disabled, "decoration_alpha")
            local widthControl
            widthControl = AddPropertyCompactSliderRow(geometrySection, L["OPTION_WIDTH"] or "Width", 1, 512, 1, tonumber(decorationConfig.width) or 64, function(value)
                if IsActiveCanvasDecorationSizeControlSuppressed(widthControl) then
                    return
                end
                SetDecorationField("width", math.floor((value or 0) + 0.5))
            end, disabled, "decoration_width")
            local heightControl
            heightControl = AddPropertyCompactSliderRow(geometrySection, L["OPTION_HEIGHT"] or "Height", 1, 512, 1, tonumber(decorationConfig.height) or 64, function(value)
                if IsActiveCanvasDecorationSizeControlSuppressed(heightControl) then
                    return
                end
                SetDecorationField("height", math.floor((value or 0) + 0.5))
            end, disabled, "decoration_height")
            RegisterActiveCanvasDecorationSizeControls(state and state.selectedUnit, {
                kind = "decoration",
                unit = state and state.selectedUnit,
                decorationId = selectedDecorationId,
                objectKey = selectedDecorationId,
            }, widthControl, heightControl)
            AddPropertyDropdownRow(positionSection, L["OPTION_ANCHOR_TO_TARGET"] or "Anchor To Element", {
                list = decorationTargetList,
                value = decorationConfig.target or "FRAME",
                onChanged = function(value)
                    SetDecorationField("target", value)
                end,
                anchorKey = "decoration_target",
            }, disabled)
            local pointControl
            local relativePointControl
            if isExpert then
                pointControl = AddPropertyDropdownRow(positionSection, L["OPTION_ANCHOR_FROM"] or "Anchor From", {
                list = portraitAnchorPointList,
                value = decorationConfig.point or "CENTER",
                onChanged = function(value)
                    if IsActiveCanvasDirectMoveOffsetControlSuppressed(pointControl) then
                        return
                    end
                    SetDecorationField("point", value)
                end,
                anchorKey = "decoration_point",
                }, disabled)
                relativePointControl = AddPropertyDropdownRow(positionSection, L["OPTION_ANCHOR_TO"] or "Anchor To", {
                list = portraitAnchorPointList,
                value = decorationConfig.relativePoint or "CENTER",
                onChanged = function(value)
                    if IsActiveCanvasDirectMoveOffsetControlSuppressed(relativePointControl) then
                        return
                    end
                    SetDecorationField("relativePoint", value)
                end,
                anchorKey = "decoration_relative_point",
                }, disabled)
            end
            local offsetXControl = AddPropertyCompactSliderRow(positionSection, L["OPTION_X_OFFSET"] or "X Offset", -500, 500, 1, tonumber(decorationConfig.offsetX) or 0, function(value)
                if IsActiveCanvasDirectMoveOffsetControlSuppressed(offsetXControl) then
                    return
                end
                SetDecorationField("offsetX", math.floor((value or 0) + 0.5))
            end, disabled, "decoration_offset_x")
            local offsetYControl = AddPropertyCompactSliderRow(positionSection, L["OPTION_Y_OFFSET"] or "Y Offset", -500, 500, 1, tonumber(decorationConfig.offsetY) or 0, function(value)
                if IsActiveCanvasDirectMoveOffsetControlSuppressed(offsetYControl) then
                    return
                end
                SetDecorationField("offsetY", math.floor((value or 0) + 0.5))
            end, disabled, "decoration_offset_y")
            RegisterActiveCanvasDirectMoveOffsetControls(state and state.selectedUnit, {
                kind = "decoration",
                unit = state and state.selectedUnit,
                decorationId = selectedDecorationId,
                objectKey = selectedDecorationId,
            }, offsetXControl, offsetYControl, pointControl, relativePointControl)
            if isExpert then
                AddPropertyDropdownRow(behaviorSection, L["OPTION_CONDITION"] or "Condition", {
                    list = decorationConditionList,
                    value = decorationConfig.condition or "ALWAYS",
                    onChanged = function(value)
                        SetDecorationField("condition", value)
                    end,
                    anchorKey = "decoration_condition",
                }, disabled)
            end
            AddPropertyActionButtonRow(actionsSection, L["OPTION_DECORATION_DELETE"] or "Delete Decoration", L["OPTION_DECORATION_DELETE"] or "Delete Decoration", "DestructiveAction", 148, OpenDeleteDecorationConfirmDialog, not decorationConfig)
        else
            decorationTextureDropdown = AddDropdown(decorationSection, L["OPTION_TEXTURE"] or "Texture", textureOptions, textureOptions.value, SetDecorationTexture, disabled, "decoration_texture")
            AddMediaBrowserForField(decorationSection, MEDIA_TYPE_DECORATION, function()
                return decorationConfig.texture
            end, DEFAULT_DECORATION_REFERENCE, L["MEDIA_LIBRARY_BROWSE_DECORATION_TITLE"] or "Choose Decoration Texture", disabled, SetDecorationTexture)

            AddDropdown(decorationSection, L["OPTION_ANCHOR_TO_TARGET"] or "Anchor To Element", decorationTargetList, decorationConfig.target or "FRAME", function(value)
                SetDecorationField("target", value)
            end, disabled, "decoration_target")

            local widthControl
            widthControl = AddSlider(decorationSection, L["OPTION_WIDTH"] or "Width", 1, 512, 1, tonumber(decorationConfig.width) or 64, function(value)
                if IsActiveCanvasDecorationSizeControlSuppressed(widthControl) then
                    return
                end
                SetDecorationField("width", math.floor((value or 0) + 0.5))
            end, disabled, "decoration_width")

            local heightControl
            heightControl = AddSlider(decorationSection, L["OPTION_HEIGHT"] or "Height", 1, 512, 1, tonumber(decorationConfig.height) or 64, function(value)
                if IsActiveCanvasDecorationSizeControlSuppressed(heightControl) then
                    return
                end
                SetDecorationField("height", math.floor((value or 0) + 0.5))
            end, disabled, "decoration_height")
            RegisterActiveCanvasDecorationSizeControls(state and state.selectedUnit, {
                kind = "decoration",
                unit = state and state.selectedUnit,
                decorationId = selectedDecorationId,
                objectKey = selectedDecorationId,
            }, widthControl, heightControl)

            if isExpert then
                AddDropdown(decorationSection, L["OPTION_ANCHOR_FROM"] or "Anchor From", portraitAnchorPointList, decorationConfig.point or "CENTER", function(value)
                    SetDecorationField("point", value)
                end, disabled, "decoration_point")

                AddDropdown(decorationSection, L["OPTION_ANCHOR_TO"] or "Anchor To", portraitAnchorPointList, decorationConfig.relativePoint or "CENTER", function(value)
                    SetDecorationField("relativePoint", value)
                end, disabled, "decoration_relative_point")
            end

            AddSlider(decorationSection, L["OPTION_X_OFFSET"] or "X Offset", -500, 500, 1, tonumber(decorationConfig.offsetX) or 0, function(value)
                SetDecorationField("offsetX", math.floor((value or 0) + 0.5))
            end, disabled, "decoration_offset_x")

            AddSlider(decorationSection, L["OPTION_Y_OFFSET"] or "Y Offset", -500, 500, 1, tonumber(decorationConfig.offsetY) or 0, function(value)
                SetDecorationField("offsetY", math.floor((value or 0) + 0.5))
            end, disabled, "decoration_offset_y")

            AddSlider(decorationSection, L["OPTION_ALPHA"] or "Alpha", 0, 1, 0.01, tonumber(decorationConfig.alpha) or 1, function(value)
                SetDecorationField("alpha", tonumber(string.format("%.2f", value or 1)) or 1)
            end, disabled, "decoration_alpha")

            if isExpert then
                AddDropdown(decorationSection, L["OPTION_CONDITION"] or "Condition", decorationConditionList, decorationConfig.condition or "ALWAYS", function(value)
                    SetDecorationField("condition", value)
                end, disabled, "decoration_condition")
            end

            AddSpacer(decorationSection, 8)
            local deleteButton = AceGUI:Create("Button")
            if FormWidgets and FormWidgets.ResetInspectorButtonState then
                FormWidgets.ResetInspectorButtonState(deleteButton)
            end
            deleteButton:SetText(L["OPTION_DECORATION_DELETE"] or "Delete Decoration")
            deleteButton:SetFullWidth(true)
            deleteButton:SetDisabled(not decorationConfig)
            deleteButton:SetCallback("OnClick", OpenDeleteDecorationConfirmDialog)
            if FormWidgets and FormWidgets.ApplyModalActionButtonVisual then
                FormWidgets.ApplyModalActionButtonVisual(deleteButton, "DestructiveAction")
            elseif FormWidgets and FormWidgets.StyleActionButton then
                FormWidgets.StyleActionButton(deleteButton, "DestructiveAction")
            end
            decorationSection:AddChild(deleteButton)
        end
    end

    local function ResolveSelectedDecorationInspectorTitle()
        local selectedDecorationId, _, decorations = ResolveSelectedDecoration(inspectorContext, unitConfig)
        for index, decoration in ipairs(decorations or {}) do
            if type(decoration) == "table" and decoration.id == selectedDecorationId then
                return BuildDecorationLabel(decoration, index)
            end
        end
        return L["EDITOR_SECTION_DECORATION"] or "Decoration"
    end

    do
        local selectedDecorationId, decorationConfig = ResolveSelectedDecoration(inspectorContext, unitConfig)
        if IsSelectedDecorationObject(selectedUnit, selectedDecorationId) and type(decorationConfig) == "table" then
            AddScopedObjectInspectorBody("decoration", ResolveSelectedDecorationInspectorTitle(), BuildDecorationSectionContent)
        else
            AddScopedInspectorSection("decoration", L["EDITOR_SECTION_DECORATION"] or "Decoration", true, {
                localContentBuilder = BuildDecorationSectionContent,
                layoutRefresh = RefreshInspectorLayout,
            })
        end
    end

    local function BuildAuraSectionContent(auraSection)
        local selectedAuraKey, auraConfig, _, currentAuraList = ResolveAuraContext()
        if not auraSection or type(auraConfig) ~= "table" then
            return
        end

        local isScopedObject = IsSelectedAuraObject(selectedUnit, selectedAuraKey)
        local displaySection = auraSection
        local layoutSection = auraSection
        local behaviorSection = auraSection
        local positionSection = auraSection
        local advancedSection = auraSection
        local actionsSection = auraSection
        local disabled = auraConfig.enabled == false

        if isScopedObject then
            displaySection = AddFramedObjectPropertyGroup(auraSection, L["SECTION_DISPLAY"] or "Display", false)
            actionsSection = AddFramedObjectPropertyGroup(auraSection, L["SECTION_ACTIONS"] or "Actions", true)
            layoutSection = AddFramedObjectPropertyGroup(auraSection, L["SECTION_LAYOUT"] or "Layout", true)
            behaviorSection = AddFramedObjectPropertyGroup(auraSection, L["SECTION_BEHAVIOR"] or "Behavior", true)
            positionSection = AddFramedObjectPropertyGroup(auraSection, L["SECTION_POSITION"] or "Position", true)
            if not isQuick then
                advancedSection = AddFramedObjectPropertyGroup(auraSection, L["SECTION_ADVANCED"] or "Advanced", true)
            end
        else
            AddDropdown(auraSection, L["EDITOR_OPTION_AURA_BLOCK"] or "Aura Block", currentAuraList, selectedAuraKey, function(value)
                local ok = type(ObjectSelection.SelectObject) == "function"
                    and ObjectSelection.SelectObject({
                        kind = "aura",
                        unit = selectedUnit,
                        auraKey = value,
                    })
                if ok == true then
                    RebuildLocalSection(auraSection)
                    return
                end
                local result = type(InspectorAuraSelection.Set) == "function"
                    and InspectorAuraSelection.Set(state, value, currentAuraList)
                    or nil
                if result and result.ok and result.changed then
                    RebuildLocalSection(auraSection)
                end
            end, nil, "aura_block")
        end

        if isScopedObject then
            AddPropertyCheckBoxRow(displaySection, L["OPTION_AURA_ENABLED"] or "Enable Aura Block", auraConfig.enabled ~= false, function(value)
                SetAuraField(selectedAuraKey, "enabled", value and true or false, auraSection)
            end, nil, "aura_enabled")
            AddPropertyCompactSliderRow(displaySection, L["OPTION_AURA_ICON_SIZE"] or "Icon Size", 12, 64, 1, tonumber(auraConfig.iconSize) or 30, function(value)
                SetAuraField(selectedAuraKey, "iconSize", math.floor((value or 0) + 0.5))
            end, disabled, "aura_icon_size")
            AddPropertyCheckBoxRow(displaySection, L["OPTION_AURA_SHOW_STACKS"] or "Show Stacks", auraConfig.showStackText ~= false, function(value)
                SetAuraField(selectedAuraKey, "showStackText", value and true or false)
            end, disabled, "aura_show_stacks")
            AddPropertyCheckBoxRow(displaySection, L["OPTION_AURA_SHOW_TIMER"] or "Show Timer", auraConfig.showTimerText ~= false, function(value)
                SetAuraField(selectedAuraKey, "showTimerText", value and true or false)
            end, disabled, "aura_show_timer")
        else
            AddCheckBox(auraSection, L["OPTION_AURA_ENABLED"] or "Enable Aura Block", auraConfig.enabled ~= false, function(value)
                SetAuraField(selectedAuraKey, "enabled", value and true or false, auraSection)
            end, nil, "aura_enabled")
            AddSlider(auraSection, L["OPTION_AURA_ICON_SIZE"] or "Icon Size", 12, 64, 1, tonumber(auraConfig.iconSize) or 30, function(value)
                SetAuraField(selectedAuraKey, "iconSize", math.floor((value or 0) + 0.5))
            end, disabled, "aura_icon_size")
        end

        if selectedAuraKey == "Buffs" then
            local addWeaponOption = isScopedObject and AddPropertyCheckBoxRow or AddCheckBox
            local label = L["OPTION_AURA_WEAPON_ENHANCEMENTS"] or "Weapon Enhancements"
            if selectedUnit ~= "player" then
                label = label .. " (" .. (L["OPTION_PLAYER_ONLY"] or "Player only") .. ")"
            end
            addWeaponOption(displaySection, label, auraConfig.showWeaponEnhancements == true, function(value)
                if selectedUnit == "player" then
                    SetAuraField(selectedAuraKey, "showWeaponEnhancements", value == true)
                end
            end, disabled or selectedUnit ~= "player", "aura_weapon_enhancements")
        end

        local auraIconsPerRowControl
        if isScopedObject then
            auraIconsPerRowControl = AddPropertyNumericInputRow(layoutSection, L["OPTION_AURA_ICONS_PER_ROW"] or "Icons Per Row", 1, 20, tonumber(auraConfig.iconsPerRow) or 5, function(value)
                if IsActiveCanvasWheelFieldControlSuppressed(auraIconsPerRowControl) then
                    return
                end
                SetAuraField(selectedAuraKey, "iconsPerRow", math.floor((value or 0) + 0.5))
            end, disabled, "aura_icons_per_row")
            AddPropertyNumericInputRow(layoutSection, L["OPTION_AURA_MAX_ROWS"] or "Maximum Rows", 0, 10, tonumber(auraConfig.maxRows) or 0, function(value)
                SetAuraField(selectedAuraKey, "maxRows", math.floor((value or 0) + 0.5))
            end, disabled, "aura_max_rows")
        else
            auraIconsPerRowControl = AddSlider(auraSection, L["OPTION_AURA_ICONS_PER_ROW"] or "Icons Per Row", 1, 20, 1, tonumber(auraConfig.iconsPerRow) or 5, function(value)
                if IsActiveCanvasWheelFieldControlSuppressed(auraIconsPerRowControl) then
                    return
                end
                SetAuraField(selectedAuraKey, "iconsPerRow", math.floor((value or 0) + 0.5))
            end, disabled, "aura_icons_per_row")
            AddSlider(auraSection, L["OPTION_AURA_MAX_ROWS"] or "Maximum Rows", 0, 10, 1, tonumber(auraConfig.maxRows) or 0, function(value)
                SetAuraField(selectedAuraKey, "maxRows", math.floor((value or 0) + 0.5))
            end, disabled, "aura_max_rows")
        end
        RegisterActiveCanvasWheelFieldControl(state and state.selectedUnit, { kind = "aura", unit = state and state.selectedUnit, auraKey = selectedAuraKey, objectKey = selectedAuraKey }, "iconsPerRow", auraIconsPerRowControl)

        if isQuick then
            if isScopedObject then
                AddPropertyNumericInputRow(layoutSection, L["OPTION_AURA_SPACING_X"] or "Spacing X", 0, 20, tonumber(auraConfig.spacingX) or 3, function(value)
                    SetAuraField(selectedAuraKey, "spacingX", math.floor((value or 0) + 0.5))
                end, disabled, "aura_spacing_x")
                AddPropertyNumericInputRow(layoutSection, L["OPTION_AURA_SPACING_Y"] or "Spacing Y", 0, 20, tonumber(auraConfig.spacingY) or 3, function(value)
                    SetAuraField(selectedAuraKey, "spacingY", math.floor((value or 0) + 0.5))
                end, disabled, "aura_spacing_y")
                AddPropertyDropdownRow(behaviorSection, L["OPTION_AURA_GROWTH_X"] or "Growth X", {
                    list = auraGrowthXList,
                    value = auraConfig.growthX or "RIGHT",
                    onChanged = function(value)
                        SetAuraField(selectedAuraKey, "growthX", value)
                    end,
                    anchorKey = "aura_growth_x",
                }, disabled)
                AddPropertyDropdownRow(behaviorSection, L["OPTION_AURA_GROWTH_Y"] or "Growth Y", {
                    list = auraGrowthYList,
                    value = auraConfig.growthY or "DOWN",
                    onChanged = function(value)
                        SetAuraField(selectedAuraKey, "growthY", value)
                    end,
                    anchorKey = "aura_growth_y",
                }, disabled)
            else
                AddCheckBox(auraSection, L["OPTION_AURA_SHOW_STACKS"] or "Show Stacks", auraConfig.showStackText ~= false, function(value)
                    SetAuraField(selectedAuraKey, "showStackText", value and true or false)
                end, disabled, "aura_show_stacks")

                AddCheckBox(auraSection, L["OPTION_AURA_SHOW_TIMER"] or "Show Timer", auraConfig.showTimerText ~= false, function(value)
                    SetAuraField(selectedAuraKey, "showTimerText", value and true or false)
                end, disabled, "aura_show_timer")
            end
        else
            if isScopedObject then
                AddPropertyNumericInputRow(layoutSection, L["OPTION_AURA_SPACING_X"] or "Spacing X", 0, 20, tonumber(auraConfig.spacingX) or 3, function(value)
                    SetAuraField(selectedAuraKey, "spacingX", math.floor((value or 0) + 0.5))
                end, disabled, "aura_spacing_x")
                AddPropertyNumericInputRow(layoutSection, L["OPTION_AURA_SPACING_Y"] or "Spacing Y", 0, 20, tonumber(auraConfig.spacingY) or 3, function(value)
                    SetAuraField(selectedAuraKey, "spacingY", math.floor((value or 0) + 0.5))
                end, disabled, "aura_spacing_y")
                AddPropertyDropdownRow(behaviorSection, L["OPTION_AURA_GROWTH_X"] or "Growth X", {
                    list = auraGrowthXList,
                    value = auraConfig.growthX or "RIGHT",
                    onChanged = function(value)
                        SetAuraField(selectedAuraKey, "growthX", value)
                    end,
                    anchorKey = "aura_growth_x",
                }, disabled)
                AddPropertyDropdownRow(behaviorSection, L["OPTION_AURA_GROWTH_Y"] or "Growth Y", {
                    list = auraGrowthYList,
                    value = auraConfig.growthY or "DOWN",
                    onChanged = function(value)
                        SetAuraField(selectedAuraKey, "growthY", value)
                    end,
                    anchorKey = "aura_growth_y",
                }, disabled)
                AddPropertyDropdownRow(behaviorSection, L["OPTION_AURA_SORT_MODE"] or "Sort Mode", {
                    list = auraSortModeList,
                    value = auraConfig.sortMode or "NEWEST_FIRST",
                    onChanged = function(value)
                        SetAuraField(selectedAuraKey, "sortMode", value)
                    end,
                    anchorKey = "aura_sort_mode",
                }, disabled)
                AddPropertyCompactSliderRow(displaySection, L["OPTION_AURA_STACK_FONT_SCALE"] or "Stack Font Scale", 0.5, 2.0, 0.05, tonumber(auraConfig.stackFontScale) or 1, function(value)
                    SetAuraField(selectedAuraKey, "stackFontScale", tonumber(string.format("%.2f", value or 1)) or 1)
                end, disabled, "aura_stack_font_scale")
                AddPropertyCompactSliderRow(displaySection, L["OPTION_AURA_TIMER_FONT_SCALE"] or "Timer Font Scale", 0.5, 2.0, 0.05, tonumber(auraConfig.timerFontScale) or 1, function(value)
                    SetAuraField(selectedAuraKey, "timerFontScale", tonumber(string.format("%.2f", value or 1)) or 1)
                end, disabled, "aura_timer_font_scale")
                AddPropertyCheckBoxRow(advancedSection, L["OPTION_AURA_SHOW_ONLY_MINE"] or "Only My Auras", auraConfig.showOnlyMine == true, function(value)
                    SetAuraField(selectedAuraKey, "showOnlyMine", value and true or false)
                end, disabled, "aura_show_only_mine")
                AddPropertyCheckBoxRow(advancedSection, L["OPTION_AURA_SHOW_BOSS"] or "Force Boss Auras", auraConfig.showBossAuras ~= false, function(value)
                    SetAuraField(selectedAuraKey, "showBossAuras", value and true or false)
                end, disabled, "aura_show_boss")
                AddPropertyCheckBoxRow(advancedSection, L["OPTION_AURA_HIDE_PERMANENT"] or "Hide Permanent Auras", auraConfig.hidePermanentAuras == true, function(value)
                    SetAuraField(selectedAuraKey, "hidePermanentAuras", value and true or false)
                end, disabled, "aura_hide_permanent")
                AddPropertyCheckBoxRow(advancedSection, L["OPTION_AURA_HIDE_LONG"] or "Hide Long Auras", auraConfig.hideLongAuras == true, function(value)
                    SetAuraField(selectedAuraKey, "hideLongAuras", value and true or false, auraSection)
                end, disabled, "aura_hide_long")
                AddPropertyCompactSliderRow(advancedSection, L["OPTION_AURA_LONG_THRESHOLD"] or "Hide Above Duration", 0, 3600, 5, tonumber(auraConfig.longAuraThreshold) or 300, function(value)
                    SetAuraField(selectedAuraKey, "longAuraThreshold", math.floor((value or 0) + 0.5))
                end, disabled or auraConfig.hideLongAuras ~= true, "aura_long_threshold")
                if selectedAuraKey == "Buffs" then
                    AddPropertyCheckBoxRow(advancedSection, L["OPTION_AURA_SHOW_STEALABLE_ONLY"] or "Only Stealable Buffs", auraConfig.showStealableOnly == true, function(value)
                        SetAuraField(selectedAuraKey, "showStealableOnly", value and true or false)
                    end, disabled, "aura_show_stealable_only")
                else
                    AddPropertyCheckBoxRow(advancedSection, L["OPTION_AURA_SHOW_DISPELLABLE_ONLY"] or "Only Dispellable Debuffs", auraConfig.showDispellableOnly == true, function(value)
                        SetAuraField(selectedAuraKey, "showDispellableOnly", value and true or false)
                    end, disabled, "aura_show_dispellable_only")
                end
            else
                AddSlider(auraSection, L["OPTION_AURA_SPACING_X"] or "Spacing X", 0, 20, 1, tonumber(auraConfig.spacingX) or 3, function(value)
                    SetAuraField(selectedAuraKey, "spacingX", math.floor((value or 0) + 0.5))
                end, disabled, "aura_spacing_x")

                AddSlider(auraSection, L["OPTION_AURA_SPACING_Y"] or "Spacing Y", 0, 20, 1, tonumber(auraConfig.spacingY) or 3, function(value)
                    SetAuraField(selectedAuraKey, "spacingY", math.floor((value or 0) + 0.5))
                end, disabled, "aura_spacing_y")

                AddDropdown(auraSection, L["OPTION_AURA_GROWTH_X"] or "Growth X", auraGrowthXList, auraConfig.growthX or "RIGHT", function(value)
                    SetAuraField(selectedAuraKey, "growthX", value)
                end, disabled, "aura_growth_x")

                AddDropdown(auraSection, L["OPTION_AURA_GROWTH_Y"] or "Growth Y", auraGrowthYList, auraConfig.growthY or "DOWN", function(value)
                    SetAuraField(selectedAuraKey, "growthY", value)
                end, disabled, "aura_growth_y")

                AddDropdown(auraSection, L["OPTION_AURA_SORT_MODE"] or "Sort Mode", auraSortModeList, auraConfig.sortMode or "NEWEST_FIRST", function(value)
                    SetAuraField(selectedAuraKey, "sortMode", value)
                end, disabled, "aura_sort_mode")

                AddSlider(auraSection, L["OPTION_AURA_STACK_FONT_SCALE"] or "Stack Font Scale", 0.5, 2.0, 0.05, tonumber(auraConfig.stackFontScale) or 1, function(value)
                    SetAuraField(selectedAuraKey, "stackFontScale", tonumber(string.format("%.2f", value or 1)) or 1)
                end, disabled, "aura_stack_font_scale")

                AddSlider(auraSection, L["OPTION_AURA_TIMER_FONT_SCALE"] or "Timer Font Scale", 0.5, 2.0, 0.05, tonumber(auraConfig.timerFontScale) or 1, function(value)
                    SetAuraField(selectedAuraKey, "timerFontScale", tonumber(string.format("%.2f", value or 1)) or 1)
                end, disabled, "aura_timer_font_scale")

                AddCheckBox(auraSection, L["OPTION_AURA_SHOW_ONLY_MINE"] or "Only My Auras", auraConfig.showOnlyMine == true, function(value)
                    SetAuraField(selectedAuraKey, "showOnlyMine", value and true or false)
                end, disabled, "aura_show_only_mine")

                AddCheckBox(auraSection, L["OPTION_AURA_SHOW_BOSS"] or "Force Boss Auras", auraConfig.showBossAuras ~= false, function(value)
                    SetAuraField(selectedAuraKey, "showBossAuras", value and true or false)
                end, disabled, "aura_show_boss")

                AddCheckBox(auraSection, L["OPTION_AURA_HIDE_PERMANENT"] or "Hide Permanent Auras", auraConfig.hidePermanentAuras == true, function(value)
                    SetAuraField(selectedAuraKey, "hidePermanentAuras", value and true or false)
                end, disabled, "aura_hide_permanent")

                AddCheckBox(auraSection, L["OPTION_AURA_HIDE_LONG"] or "Hide Long Auras", auraConfig.hideLongAuras == true, function(value)
                    SetAuraField(selectedAuraKey, "hideLongAuras", value and true or false, auraSection)
                end, disabled, "aura_hide_long")

                AddSlider(auraSection, L["OPTION_AURA_LONG_THRESHOLD"] or "Hide Above Duration", 0, 3600, 5, tonumber(auraConfig.longAuraThreshold) or 300, function(value)
                    SetAuraField(selectedAuraKey, "longAuraThreshold", math.floor((value or 0) + 0.5))
                end, disabled or auraConfig.hideLongAuras ~= true, "aura_long_threshold")

                if selectedAuraKey == "Buffs" then
                    AddCheckBox(auraSection, L["OPTION_AURA_SHOW_STEALABLE_ONLY"] or "Only Stealable Buffs", auraConfig.showStealableOnly == true, function(value)
                        SetAuraField(selectedAuraKey, "showStealableOnly", value and true or false)
                    end, disabled, "aura_show_stealable_only")
                else
                    AddCheckBox(auraSection, L["OPTION_AURA_SHOW_DISPELLABLE_ONLY"] or "Only Dispellable Debuffs", auraConfig.showDispellableOnly == true, function(value)
                        SetAuraField(selectedAuraKey, "showDispellableOnly", value and true or false)
                    end, disabled, "aura_show_dispellable_only")
                end

                AddCheckBox(auraSection, L["OPTION_AURA_SHOW_STACKS"] or "Show Stacks", auraConfig.showStackText ~= false, function(value)
                    SetAuraField(selectedAuraKey, "showStackText", value and true or false)
                end, disabled, "aura_show_stacks")

                AddCheckBox(auraSection, L["OPTION_AURA_SHOW_TIMER"] or "Show Timer", auraConfig.showTimerText ~= false, function(value)
                    SetAuraField(selectedAuraKey, "showTimerText", value and true or false)
                end, disabled, "aura_show_timer")
            end
        end

        if isScopedObject then
            AddPropertyDropdownRow(positionSection, L["OPTION_AURA_PLACEMENT"] or "Aura Block Placement", {
                list = auraPlacementList,
                value = auraConfig.placement or "ATTACHED",
                onChanged = function(value)
                    SetAuraField(selectedAuraKey, "placement", value, auraSection)
                end,
                anchorKey = "aura_placement",
            }, disabled)
        else
            AddDropdown(auraSection, L["OPTION_AURA_PLACEMENT"] or "Aura Block Placement", auraPlacementList, auraConfig.placement or "ATTACHED", function(value)
                SetAuraField(selectedAuraKey, "placement", value, auraSection)
            end, disabled, "aura_placement")
        end

        if isScopedObject then
            local removeLabel = selectedAuraKey == "Debuffs"
                and (L["EDITOR_REMOVE_DEBUFFS_BUTTON"] or "Remove Debuffs")
                or (L["EDITOR_REMOVE_BUFFS_BUTTON"] or "Remove Buffs")
            AddPropertyActionButtonRow(actionsSection, removeLabel, removeLabel, "DestructiveAction", 148, function()
                ApplySingletonAuraPresence(selectedAuraKey, false)
            end, false)
        end

        if not isQuick then
            local inside = (auraConfig.placement or "ATTACHED") == "INSIDE"
            if inside then
                if isScopedObject then
                    AddPropertyDropdownRow(positionSection, L["OPTION_INSIDE_SIDE"] or "Inside Side", {
                        list = auraInsideSideList,
                        value = auraConfig.insideSide or "LEFT",
                        onChanged = function(value)
                            SetAuraField(selectedAuraKey, "insideSide", value)
                        end,
                        anchorKey = "aura_inside_side",
                    }, disabled)
                else
                    AddDropdown(auraSection, L["OPTION_INSIDE_SIDE"] or "Inside Side", auraInsideSideList, auraConfig.insideSide or "LEFT", function(value)
                        SetAuraField(selectedAuraKey, "insideSide", value)
                    end, disabled, "aura_inside_side")
                end
            end
            -- Aura groups always use Frame; position controls apply to both placements.
            if isScopedObject then
                AddPropertyDropdownRow(positionSection, L["OPTION_ANCHOR_FROM"] or "Anchor From", {
                    list = auraAnchorPointList,
                    value = auraConfig.point or "TOPLEFT",
                    onChanged = function(value)
                        SetAuraField(selectedAuraKey, "point", value)
                    end,
                    anchorKey = "aura_point",
                }, disabled)
                AddPropertyDropdownRow(positionSection, L["OPTION_ANCHOR_TO"] or "Anchor To", {
                    list = auraAnchorPointList,
                    value = auraConfig.relativePoint or auraConfig.point or "TOPLEFT",
                    onChanged = function(value)
                        SetAuraField(selectedAuraKey, "relativePoint", value)
                    end,
                    anchorKey = "aura_relative_point",
                }, disabled)
                local offsetXControl = AddPropertyCompactSliderRow(positionSection, L["OPTION_X_OFFSET"] or "X Offset", -500, 500, 1, tonumber(auraConfig.offsetX) or 0, function(value)
                    if IsActiveCanvasDirectMoveOffsetControlSuppressed(offsetXControl) then
                        return
                    end
                    SetAuraField(selectedAuraKey, "offsetX", math.floor((value or 0) + 0.5))
                end, disabled, "aura_offset_x")
                local offsetYControl = AddPropertyCompactSliderRow(positionSection, L["OPTION_Y_OFFSET"] or "Y Offset", -500, 500, 1, tonumber(auraConfig.offsetY) or 0, function(value)
                    if IsActiveCanvasDirectMoveOffsetControlSuppressed(offsetYControl) then
                        return
                    end
                    SetAuraField(selectedAuraKey, "offsetY", math.floor((value or 0) + 0.5))
                end, disabled, "aura_offset_y")
                RegisterActiveCanvasDirectMoveOffsetControls(state and state.selectedUnit, {
                    kind = "aura",
                    unit = state and state.selectedUnit,
                    auraKey = selectedAuraKey,
                    objectKey = selectedAuraKey,
                }, offsetXControl, offsetYControl)
            else
                AddDropdown(auraSection, L["OPTION_ANCHOR_FROM"] or "Anchor From", auraAnchorPointList, auraConfig.point or "TOPLEFT", function(value)
                    SetAuraField(selectedAuraKey, "point", value)
                end, disabled, "aura_point")

                AddDropdown(auraSection, L["OPTION_ANCHOR_TO"] or "Anchor To", auraAnchorPointList, auraConfig.relativePoint or auraConfig.point or "TOPLEFT", function(value)
                    SetAuraField(selectedAuraKey, "relativePoint", value)
                end, disabled, "aura_relative_point")

                AddSlider(auraSection, L["OPTION_X_OFFSET"] or "X Offset", -500, 500, 1, tonumber(auraConfig.offsetX) or 0, function(value)
                    SetAuraField(selectedAuraKey, "offsetX", math.floor((value or 0) + 0.5))
                end, disabled, "aura_offset_x")

                AddSlider(auraSection, L["OPTION_Y_OFFSET"] or "Y Offset", -500, 500, 1, tonumber(auraConfig.offsetY) or 0, function(value)
                    SetAuraField(selectedAuraKey, "offsetY", math.floor((value or 0) + 0.5))
                end, disabled, "aura_offset_y")
            end
        end
    end

    local function ResolveSelectedAuraInspectorTitle()
        local selectedAuraKey = ResolveAuraContext()
        if selectedAuraKey == "Buffs" then
            return L["AURA_BUFFS"] or "Buffs"
        end
        if selectedAuraKey == "Debuffs" then
            return L["AURA_DEBUFFS"] or "Debuffs"
        end
        return selectedAuraKey or (L["EDITOR_SECTION_AURAS"] or "Auras")
    end

    if type(select(2, ResolveAuraContext())) == "table" then
        local selectedAuraKey = ResolveAuraContext()
        if IsSelectedAuraObject(selectedUnit, selectedAuraKey) then
            AddScopedObjectInspectorBody("auras", ResolveSelectedAuraInspectorTitle(), BuildAuraSectionContent)
        else
            AddScopedInspectorSection("auras", L["EDITOR_SECTION_AURAS"] or "Auras", true, {
                localContentBuilder = BuildAuraSectionContent,
                layoutRefresh = RefreshInspectorLayout,
            })
        end
    end

    if perf and perf.End then
        perf:End("InspectorController.Build", perfStart)
    end
end

function InspectorController.BuildContext(container, state, options)
    local contextOptions = {}
    for key, value in pairs(options or {}) do
        contextOptions[key] = value
    end
    contextOptions.buildContextOnly = true
    return InspectorController.Build(container, state, contextOptions)
end

function InspectorController.BuildProperties(container, state, options)
    local propertyOptions = {}
    for key, value in pairs(options or {}) do
        propertyOptions[key] = value
    end
    propertyOptions.buildPropertiesOnly = true
    return InspectorController.Build(container, state, propertyOptions)
end

return InspectorController
