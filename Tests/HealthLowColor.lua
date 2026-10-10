-- lua54 Tests/HealthLowColor.lua
-- Actual Health/Colors/Utils and reset boundary; native curves, widgets and APIs are doubles.
-- This proves dispatch/provenance and preservation, not native Midnight secret rendering.
local count = 0
local function Test(name, fn) fn(); count = count + 1; print("PASS: " .. name) end
local function Equal(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function Near(a,b) assert(math.abs(a-b)<0.000001,tostring(a).." ~= "..tostring(b)) end
local function Fixture()
    local f = { current=100, maximum=100, percent=1, exists=true, mode="live", updates=0,
        predictionCalls=0, unitCalls=0, numericCalls=0, curves=0, absorbed=0, healAbsorbed=0 }
    local secrets = {}
    local env = setmetatable({}, {__index=_G})
    env.issecretvalue = function(v) return secrets[v] == true end
    function f.Secret(v) secrets[v]=true; return v end
    env.CreateColor = function(r,g,b,a) return {GetRGBA=function() return r,g,b,a end} end
    local function Evaluate(curve,p)
        local lo,hi=curve.points[1],curve.points[#curve.points]
        for i=2,#curve.points do if p<=curve.points[i].x then lo,hi=curve.points[i-1],curve.points[i]; break end end
        local t=math.max(0,math.min(1,(p-lo.x)/(hi.x-lo.x)))
        local result={}; for i=1,4 do result[i]=lo.c[i]+(hi.c[i]-lo.c[i])*t end
        return env.CreateColor(table.unpack(result))
    end
    env.C_CurveUtil={CreateColorCurve=function()
        f.curves=f.curves+1
        local curve={points={}}
        function curve:SetType() end
        function curve:AddPoint(x,c) self.points[#self.points+1]={x=x,c={c:GetRGBA()}} end
        function curve:Evaluate(p) f.numericCalls=f.numericCalls+1; return Evaluate(self,p) end
        f.curve=curve; return curve
    end}
    env.Enum={LuaCurveType={Linear=1}}
    env.UnitHealth=function()return f.current end
    env.UnitHealthMax=function()return f.maximum end
    env.UnitExists=function()return f.exists end
    env.UnitIsPlayer=function()return not f.npc end
    env.UnitClass=function()return "Mage","MAGE" end
    env.UnitReaction=function()return 5 end
    env.RAID_CLASS_COLORS={MAGE={r=.1,g=.2,b=.9}}
    env.FACTION_BAR_COLORS={[5]={r=.1,g=.9,b=.2}}
    env.UnitHealthPercent=function(unit,includeAbsorbs,curve)
        Equal(unit,f.frame._fpUnit); Equal(includeAbsorbs,false); f.unitCalls=f.unitCalls+1
        if f.unitFails then error("unit curve unavailable") end
        return f.nativeColor or Evaluate(curve,f.percent)
    end
    env.CreateUnitHealPredictionCalculator=function()
        f.created=(f.created or 0)+1
        return {
            GetCurrentHealth=function() if f.getterFails then error("getter") end;return f.current end,
            GetMaximumHealth=function()return f.maximum end,
            GetDamageAbsorbs=function()return 7 end,
            EvaluateCurrentHealthPercent=function(_,curve)
                f.predictionCalls=f.predictionCalls+1
                if f.predictionFails then error("prediction curve unavailable") end
                return f.nativeColor or Evaluate(curve,f.percent)
            end,
        }
    end
    env.UnitGetDetailedHealPrediction=function(unit,healer)
        Equal(unit,f.frame._fpUnit);Equal(healer,"player"); f.updates=f.updates+1
        if f.updateFails or f.updates==f.failAt then error("prediction update failed") end
    end
    env.UnitGetTotalAbsorbs=function()return 9 end
    env.UnitGetTotalHealAbsorbs=function()return 3 end
    env.CreateFrame=function()
        return {RegisterEvent=function()end,RegisterUnitEvent=function()end,
            SetScript=function(self,_,fn)self.event=fn end}
    end
    local ns={UnitFramePresence={DoesUnitSeemPresent=function()return f.exists end,IsPreviewModeEnabled=function()return f.mode=="preview" end},
        UnitFramePreview={GetTestValues=function()return f.sim end,IsPlaceholderPreviewEnabled=function()return f.mode=="placeholder" end},
        EditorVisualPolicy={Resolve=function()return f.mode end,IsSimulatedState=function(s)return s=="simulated" end,
            GetSimulationValues=function()return f.sim end},
        UnitFrameDemoEnvironment={GetUnitValues=function()if f.mode=="demo" then return f.sim end end,
            GetPlaceholderColors=function()return {barR=.3,barG=.2,barB=.1,barA=.6,disabledBarA=.2} end},
        UnitFrameAbsorbBars={UpdateNormalAbsorbBarValue=function()f.absorbed=f.absorbed+1 end,
            UpdateHealingAbsorbBarValue=function()f.healAbsorbed=f.healAbsorbed+1 end},
        UnitFrameState={QueueRefresh=function()f.queued=true end}}
    local function Load(path) assert(loadfile(path,"t",env))("FocalPoint",ns) end
    Load("Engine/UnitFrame/Shared/UnitFrameUtils.lua")
    local utils=ns.UnitFrameUtils
    utils.GetUnitDB=function()return f.config end
    utils.ToSafeNumberValue=function(v) return not env.issecretvalue(v) and type(v)=="number" and v or 0 end
    utils.FormatDisplayNumber=function()return "formatted" end
    utils.ResolveBlizzardAbbreviation=function()return "abbreviated" end
    Load("Engine/UnitFrame/Shared/UnitFrameColors.lua")
    Load("Engine/UnitFrame/Bars/UnitFrameHealth.lua")
    f.config={enabled=true,useClassColorHealth=false,useLowHealthColor=true,
        healthColor={r=.2,g=.7,b=.4,a=.6},healthLowColor={1,.1,.1,.2}}
    local bar={}
    function bar:SetMinMaxValues(a,b)self.minimum,self.maximum=a,b end
    function bar:GetMinMaxValues()return self.minimum,self.maximum end
    function bar:SetValue(v)self.value=v end
    function bar:GetValue()return self.value end
    function bar:SetStatusBarColor(...)self.color={...} end
    function bar:SetAlpha(a)self.alpha=a end
    f.frame={_fpUnit="player",Elements={HealthBar=bar},LiveValues={unrelated="retained"}}
    f.ns,f.env,f.bar,f.Load=ns,env,bar,Load
    function f.Refresh()ns.UnitFrameHealth.RefreshBar(nil,f.frame)end
    function f.Color()ns.UnitFrameHealth.UpdateBarColor(f.frame)end
    function f.Expect(r,g,b,a)Near(bar.color[1],r);Near(bar.color[2],g);Near(bar.color[3],b);Near(bar.alpha,a);Equal(bar.color[4],1)end
    function f.NoPrediction()env.CreateUnitHealPredictionCalculator=nil;env.UnitGetDetailedHealPrediction=nil end
    return f
end

Test("Custom curve endpoints from original values; fills, absorbs and LiveValues retained",function()
    local f=Fixture();f.NoPrediction();f.env.UnitHealthPercent=nil
    for _,case in ipairs({{100,.2,.7,.4,.6},{75,1,.84,.18,.6},{30,1,.1,.1,.2},{0,1,.1,.1,.2}})do
        f.current=case[1];f.Refresh();f.Expect(table.unpack(case,2));Equal(f.bar.value,case[1]);Equal(f.bar.maximum,100)
        Equal(f.frame.LiveValues.healthCurrentRaw,case[1]);Equal(f.frame.LiveValues.healthCurrentSafe,case[1])
        Equal(f.frame.LiveValues.healthCurrentText,"formatted");Equal(f.frame.LiveValues.healthCurrentAbbr,"abbreviated")
        Equal(f.frame.LiveValues.absorbTotalRaw,9);Equal(f.frame.LiveValues.healAbsorbTotalRaw,3)
        Equal(f.frame.LiveValues.unrelated,"retained")
    end
    Equal(f.absorbed,4);Equal(f.healAbsorbed,4);Equal(f.unitCalls,0)
end)
Test("secret current/max use current prediction; mixed secrecy never evaluates fake zero",function()
    for _,which in ipairs({"both","current","maximum"})do
        local f=Fixture();f.current=which~="maximum" and f.Secret(17) or 100
        f.maximum=which~="current" and f.Secret(113) or 100;f.percent=1
        f.Refresh();f.Expect(.2,.7,.4,.6);Equal(f.predictionCalls,1);Equal(f.numericCalls,0)
        f.predictionFails=true;f.Refresh();f.Expect(.2,.7,.4,.6);Equal(f.unitCalls,1);Equal(f.numericCalls,0)
        f.env.UnitHealthPercent=nil;f.Refresh();f.Expect(.2,.7,.4,.6);Equal(f.numericCalls,0)
    end
end)
Test("failed calculator updates, including absorb refresh, cannot reuse stale prediction",function()
    for _,failure in ipairs({"all","second"})do
        local f=Fixture();f.current=f.Secret(17);f.maximum=f.Secret(113);f.percent=.1;f.Refresh();f.Expect(1,.1,.1,.2)
        local prior=f.predictionCalls;f.percent=1
        if failure=="all" then f.updateFails=true else f.failAt=f.updates+2 end
        f.Refresh();f.Expect(.2,.7,.4,.6);Equal(f.predictionCalls,prior);Equal(f.unitCalls,1)
    end
end)
Test("native output channels pass untouched to rendering, including opaque secret doubles",function()
    local f=Fixture();local function Forbidden()error("secret arithmetic/comparison")end
    local channels={};for i=1,4 do channels[i]=f.Secret(setmetatable({},{__lt=Forbidden,__le=Forbidden,__add=Forbidden,__sub=Forbidden,__div=Forbidden})) end
    f.nativeColor={GetRGBA=function()return table.unpack(channels)end};f.Refresh()
    for i=1,3 do assert(rawequal(f.bar.color[i],channels[i]))end
    assert(rawequal(f.bar.alpha,channels[4]));Equal(f.numericCalls,0)
end)
Test("no valid original/native source returns base; malformed originals do not divide",function()
    local f=Fixture();f.NoPrediction();f.env.UnitHealthPercent=nil
    for _,case in ipairs({{false,100},{100,false},{0,0},{0/0,100},{math.huge,100},{100,math.huge}})do
        f.current,f.maximum=case[1],case[2];f.Refresh();f.Expect(.2,.7,.4,.6)
    end
    f.current=nil;f.maximum=100;f.Refresh();f.Expect(.2,.7,.4,.6)
    f.current=10;f.maximum=nil;f.Refresh();f.Expect(.2,.7,.4,.6)
    Equal(f.numericCalls,0)
end)
Test("Low disabled never constructs/evaluates a curve",function()
    local f=Fixture();f.config.useLowHealthColor=false;f.current=f.Secret(17);f.Refresh();f.Expect(.2,.7,.4,.6)
    Equal(f.curves,0);Equal(f.predictionCalls,0);Equal(f.unitCalls,0)
end)
Test("named Custom channels beat stale numeric keys; zero alpha and existing interpolation",function()
    local f=Fixture();f.config.healthColor={r=0,g=.4,b=.6,a=0,[1]=1,[2]=1,[3]=1,[4]=1}
    f.Refresh();f.Expect(0,.4,.6,0)
    f.percent=0;f.config.healthLowColor={1,.1,.1,0};f.Refresh();f.Expect(1,.1,.1,0)
    f.percent=.75;f.Refresh();f.Expect(1,.84,.18,0)
    f.config.healthLowColor[4]=.8;f.Refresh();f.Expect(1,.84,.18,.8)
    f.config.healthColor={0,.4,.6,0};f.percent=1;f.Refresh();f.Expect(0,.4,.6,0)
end)
Test("Class and NPC reaction endpoints retain their existing precedence and configured alpha",function()
    local f=Fixture();f.config.useClassColorHealth=true;f.Refresh();f.Expect(.1,.2,.9,.6)
    f.npc=true;f.frame._fpUnit="target";f.config.useReactionColorNpcHealth=true;f.Refresh();f.Expect(.1,.9,.2,.6)
    f.config.useClassColorHealth=false;f.Refresh();f.Expect(.2,.7,.4,.6)
    f.config.useLowHealthColor=nil;f.percent=0;f.Refresh();f.Expect(1,.1,.1,.2)
end)
Test("Live to Demo/Preview to Live ignores cached calculator and native-unit curves",function()
    for _,mode in ipairs({"demo","preview","simulated"})do
        local f=Fixture();f.percent=0;f.Refresh();local p,u=f.predictionCalls,f.unitCalls
        f.mode=mode;f.sim={healthCurrent=100,healthMax=100};f.Color();f.Expect(.2,.7,.4,.6)
        f.Refresh();f.Expect(.2,.7,.4,.6);Equal(f.predictionCalls,p);Equal(f.unitCalls,u)
        f.mode="live";f.percent=.75;f.Color();f.Expect(1,.84,.18,.6)
        f.Refresh();f.Expect(1,.84,.18,.6)
    end
end)
Test("simulation without values never falls through to live; placeholders remain neutral",function()
    local f=Fixture();f.Refresh();local p,u=f.predictionCalls,f.unitCalls
    f.mode="simulated";f.sim=nil;f.Color();f.Expect(.2,.7,.4,.6);Equal(f.predictionCalls,p);Equal(f.unitCalls,u)
    f.mode="placeholder";f.Color();f.Expect(.3,.2,.1,.6)
    f.config.enabled=false;f.Color();f.Expect(.3,.2,.1,.2)
end)
Test("queued target changes invalidate old source before refresh; no foreign unit or lost-unit color",function()
    local f=Fixture();f.frame._fpUnit="target";f.percent=0;f.Refresh()
    f.ns.UnitFrameHealth.RegisterEvents({},f.frame);local p=f.predictionCalls
    f.percent=1;f.frame.HealthBarEventFrame.event(nil,"PLAYER_TARGET_CHANGED");assert(f.queued)
    f.Color();f.Expect(.2,.7,.4,.6);Equal(f.predictionCalls,p)
    f.frame._fpUnit="focus";f.Color();f.Expect(.2,.7,.4,.6);Equal(f.predictionCalls,p)
    f.exists=false;local u=f.unitCalls;f.Refresh();f.Expect(.2,.7,.4,.6);Equal(f.unitCalls,u)
    f.exists=true;f.Refresh();f.Expect(.2,.7,.4,.6)
end)
Test("real derived-state reset invalidates provenance; layout/combat/reload model",function()
    local f=Fixture();f.Refresh();local calc=f.frame.HealthPredictionValues
    f.Load("Engine/UnitFrame/Runtime/UnitFrameState.lua")
    for i=1,50 do
        f.env.InCombatLockdown=function()return i%2==0 end
        f.ns.UnitFrameState.ResetDerivedFrameState(f.frame)
        local p=f.predictionCalls;f.percent=1;f.Color();Equal(f.predictionCalls,p)
        f.config={enabled=true,useClassColorHealth=false,useLowHealthColor=true,healthColor={0,.5,.8,0},healthLowColor={1,0,0,.3}}
        f.Refresh();f.Expect(0,.5,.8,0);assert(f.frame.HealthPredictionValues==calc)
    end
    Equal(f.created,1)
    local reloaded=Fixture();reloaded.Refresh();reloaded.Expect(.2,.7,.4,.6)
end)
Test("Threshold at 1.0 preserves existing behavior; full range curve from 0 to 100%",function()
    local f=Fixture();f.NoPrediction();f.env.UnitHealthPercent=nil
    f.config.lowHealthColorThreshold=1.0
    for _,case in ipairs({{100,.2,.7,.4,.6},{75,1,.84,.18,.6},{30,1,.1,.1,.2},{0,1,.1,.1,.2}})do
        f.current=case[1];f.Refresh();f.Expect(table.unpack(case,2))
    end
    Equal(f.bar.color[4],1)
end)
Test("Threshold at 0.5 returns normal color above 50%, uses scaled curve at or below",function()
    local f=Fixture();f.NoPrediction();f.env.UnitHealthPercent=nil
    f.config.lowHealthColorThreshold=0.5
    f.current=60;f.Refresh();f.Expect(.2,.7,.4,.6)
    f.current=51;f.Refresh();f.Expect(.2,.7,.4,.6)
    f.current=50;f.Refresh();f.Expect(.2,.7,.4,.6)
    f.current=37.5;f.Refresh();f.Expect(1,.84,.18,.6)
    f.current=15;f.Refresh();f.Expect(1,.1,.1,.2)
    f.current=0;f.Refresh();f.Expect(1,.1,.1,.2)
end)
Test("Threshold at 0.3 scales curve endpoints; health above threshold uses normal color",function()
    local f=Fixture();f.NoPrediction();f.env.UnitHealthPercent=nil
    f.config.lowHealthColorThreshold=0.3
    f.current=100;f.Refresh();f.Expect(.2,.7,.4,.6)
    f.current=50;f.Refresh();f.Expect(.2,.7,.4,.6)
    f.current=31;f.Refresh();f.Expect(.2,.7,.4,.6)
    f.current=30;f.Refresh();f.Expect(.2,.7,.4,.6)
    f.current=22.5;f.Refresh();f.Expect(1,.84,.18,.6)
    f.current=9;f.Refresh();f.Expect(1,.1,.1,.2)
    f.current=0;f.Refresh();f.Expect(1,.1,.1,.2)
end)
Test("Curve point scaling respects threshold multipliers at each breakpoint",function()
    local f=Fixture();f.NoPrediction();f.env.UnitHealthPercent=nil
    f.config.lowHealthColorThreshold=0.4
    f.current=0;f.Refresh();local curve=f.curve
    Near(curve.points[1].x,0);Near(curve.points[2].x,0.12);Near(curve.points[3].x,0.3);Near(curve.points[4].x,0.4)
    Near(curve.points[1].c[1],1);Near(curve.points[1].c[2],.1);Near(curve.points[1].c[3],.1)
    Near(curve.points[4].c[1],.2);Near(curve.points[4].c[2],.7);Near(curve.points[4].c[3],.4)
end)
Test("Missing threshold config falls back to default 1.0 behavior",function()
    local f=Fixture();f.NoPrediction();f.env.UnitHealthPercent=nil
    f.config.lowHealthColorThreshold=nil
    f.current=100;f.Refresh();f.Expect(.2,.7,.4,.6)
    f.current=75;f.Refresh();f.Expect(1,.84,.18,.6)
    f.current=30;f.Refresh();f.Expect(1,.1,.1,.2)
end)
Test("Threshold with class and reaction colors preserves endpoint precedence",function()
    local f=Fixture();f.NoPrediction();f.env.UnitHealthPercent=nil
    f.config.useClassColorHealth=true;f.config.lowHealthColorThreshold=0.5
    f.current=60;f.Refresh();f.Expect(.1,.2,.9,.6)
    f.current=50;f.Refresh();f.Expect(.1,.2,.9,.6)
    f.current=0;f.Refresh();f.Expect(1,.1,.1,.2)
    f.config.useClassColorHealth=false;f.config.useLowHealthColor=false
    f.current=60;f.Refresh();f.Expect(.2,.7,.4,.6)
end)
Test("Threshold respects prediction and unit curve sources with scaled curve range",function()
    local f=Fixture();f.current=f.Secret(60);f.maximum=f.Secret(100);f.config.lowHealthColorThreshold=0.5
    f.percent=.6;f.Refresh();f.Expect(.2,.7,.4,.6);Equal(f.predictionCalls,1);assert(f.curves>0)
    f.percent=.5;f.Refresh();f.Expect(.2,.7,.4,.6)
    f.percent=0;f.Refresh();f.Expect(1,.1,.1,.2)
    local curve=f.curve;Near(curve.points[4].x,0.5)
end)
print("Health Low Color: "..count.." groups PASS")
