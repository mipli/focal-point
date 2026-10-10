local _, FocalPoint = ...

FocalPoint.GUI = FocalPoint.GUI or {}
FocalPoint.GUI.Editor = FocalPoint.GUI.Editor or {}
FocalPoint.GUI.Editor.Inspector = FocalPoint.GUI.Editor.Inspector or {}

local InspectorRefreshPolicy = {}
FocalPoint.InspectorRefreshPolicy = InspectorRefreshPolicy
FocalPoint.GUI.Editor.Inspector.RefreshPolicy = InspectorRefreshPolicy

local FIELD_POLICIES = {
    unit = {
        enabled = { scope = "unitEnabled" },
        useClassColorHealth = { scope = "section", sectionKey = "health" },
        useLowHealthColor = { scope = "section", sectionKey = "health" },
        lowHealthColorThreshold = { scope = "section", sectionKey = "health" },
        useReactionColorNpcHealth = { scope = "section", sectionKey = "health" },
        healthBackground = { scope = "section", sectionKey = "health" },
        showNormalAbsorbBar = { scope = "section", sectionKey = "absorbs" },
        normalAbsorbBarTexture = { scope = "section", sectionKey = "absorbs" },
        normalAbsorbBarSizeMode = { scope = "section", sectionKey = "absorbs" },
        normalAbsorbBarAnchorTo = { scope = "section", sectionKey = "absorbs" },
        normalAbsorbBarPoint = { scope = "section", sectionKey = "absorbs" },
        normalAbsorbBarRelativePoint = { scope = "section", sectionKey = "absorbs" },
        normalAbsorbBarGrowth = { scope = "section", sectionKey = "absorbs" },
        showHealingAbsorbBar = { scope = "section", sectionKey = "absorbs" },
        healingAbsorbBarTexture = { scope = "section", sectionKey = "absorbs" },
        healingAbsorbBarSizeMode = { scope = "section", sectionKey = "absorbs" },
        healingAbsorbBarAnchorTo = { scope = "section", sectionKey = "absorbs" },
        healingAbsorbBarPoint = { scope = "section", sectionKey = "absorbs" },
        healingAbsorbBarRelativePoint = { scope = "section", sectionKey = "absorbs" },
        healingAbsorbBarGrowth = { scope = "section", sectionKey = "absorbs" },
        showPowerBar = { scope = "section", sectionKey = "power" },
        useClassColorPower = { scope = "section", sectionKey = "power" },
        powerBackground = { scope = "section", sectionKey = "power" },
        showAlternativePowerBar = { scope = "section", sectionKey = "alt_power" },
        alternativePowerBackground = { scope = "section", sectionKey = "alt_power" },
        showClassPowerBar = { scope = "section", sectionKey = "class_power" },
        useBlizzardColorClassPower = { scope = "section", sectionKey = "class_power" },
        showCastBar = { scope = "section", sectionKey = "cast" },
        castBarWidthMode = { scope = "section", sectionKey = "cast" },
        castBarWidth = { scope = "live" },
        mouseEnabled = { scope = "section", sectionKey = "visibility" },
    },
    text = {
        enabled = { scope = "section", sectionKey = "texts" },
    },
    indicator = {
        enabled = { scope = "section", sectionKey = "indicators" },
        placement = { scope = "section", sectionKey = "indicators" },
    },
    aura = {
        enabled = { scope = "section", sectionKey = "auras" },
        placement = { scope = "section", sectionKey = "auras" },
        hideLongAuras = { scope = "section", sectionKey = "auras" },
    },
    decoration = {
        __list = { scope = "section", sectionKey = "decoration" },
        enabled = { scope = "section", sectionKey = "decoration" },
    },
}

local function CopyPolicy(policy)
    if type(policy) ~= "table" then
        return { scope = "live" }
    end

    return {
        scope = policy.scope or "live",
        sectionKey = policy.sectionKey,
    }
end

function InspectorRefreshPolicy.Resolve(targetKind, fieldName)
    if type(targetKind) ~= "string" or targetKind == "" then
        return { scope = "none" }
    end
    if type(fieldName) ~= "string" or fieldName == "" then
        return { scope = "none" }
    end

    local targetPolicies = FIELD_POLICIES[targetKind]
    if type(targetPolicies) ~= "table" then
        return { scope = "none" }
    end

    if targetKind == "aura" then
        local AuraDiagnostics = FocalPoint and FocalPoint.AuraDiagnostics or nil
        if AuraDiagnostics and AuraDiagnostics.IncrementManagedCounter then
            AuraDiagnostics.IncrementManagedCounter("inspectorRefresh")
        end
    end

    return CopyPolicy(targetPolicies[fieldName])
end

return InspectorRefreshPolicy
