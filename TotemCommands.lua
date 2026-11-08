-- Totem Commands
-- Put Call of the Elements on a gamepad crossbar slot: tap the button to cast it, hold it to cast
-- Totemic Recall, keep holding to cast Totemic Call instead.
--
-- All of the decision making is secure. Each crossbar button's OnClick is wrapped (SecureHandlerWrapScript):
-- a press on a Call of the Elements slot is held back, and the release casts the slot's spell or, depending
-- on how long the button was held, Totemic Recall or Totemic Call. The restricted environment has no clock,
-- so a self-resetting state driver provides a secure tick (~0.2 s, sooner when the game fires driver events)
-- and the hold is counted in ticks. Addon code only sets things up out of combat and reads the header's
-- "armed" attribute to give rumble feedback; it never writes to Blizzard's buttons or tables.

local ADDON_NAME = ...;

local RECALL_SPELL_ID = 36936;
local TOTEMIC_CALL_NAME = "Totemic Call";
local CALL_SPELL_IDS = { 66842, 66843, 66844 }; -- Call of the Elements / Ancestors / Spirits
local DEFAULT_HOLD_TICKS, DEFAULT_HOLD2_TICKS = 3, 7;
local MIN_HOLD_TICKS, MAX_HOLD_TICKS = 2, 6;
local MAX_HOLD2_TICKS = 12;
local RUMBLE_INTENSITY, RUMBLE_TIME, DOUBLE_RUMBLE_GAP = 0.5, 0.15, 0.25;

local header = CreateFrame("Frame", "TotemCommandsHeader", UIParent, "SecureHandlerStateTemplate");
header:SetAttribute("enabled", false);
header:SetAttribute("armed", 0);
header:SetAttribute("holdTicks", DEFAULT_HOLD_TICKS);
header:SetAttribute("hold2Ticks", DEFAULT_HOLD2_TICKS);

-- Secure tick: the driver always resolves to "tock"; resetting the attribute to "tick" makes the next
-- driver update count as a change. "armed" is the hold stage: 0 tap, 1 Totemic Recall, 2 Totemic Call
-- (only when the spell was found). A press that is never released is dropped after ~5 s.
header:SetAttribute("_onstate-tick", [[
	if newstate ~= "tock" then
		return;
	end
	self:SetAttribute("state-tick", "tick");
	self:SetAttribute("tickcount", (self:GetAttribute("tickcount") or 0) + 1);

	if pressedSlot then
		ticks = (ticks or 0) + 1;
		local stage = armed or 0;
		if ticks > 25 then
			pressedSlot = nil;
			armed = 0;
			self:SetAttribute("armed", 0);
		elseif stage < 1 and ticks >= (self:GetAttribute("holdTicks") or 3) then
			armed = 1;
			self:SetAttribute("armed", 1);
		elseif stage == 1 and self:GetAttribute("callSpell") and ticks >= (self:GetAttribute("hold2Ticks") or 7) then
			armed = 2;
			self:SetAttribute("armed", 2);
		end
	end
]]);

local function IsCallSpellCondition(var)
	local parts = {};
	for _, spellID in ipairs(CALL_SPELL_IDS) do
		table.insert(parts, ("%s == %d"):format(var, spellID));
	end
	return table.concat(parts, " or ");
end

-- Runs before Blizzard's OnClick on every wrapped crossbar button.
local PRE_CLICK = ([[
	if not control:GetAttribute("enabled") then
		return;
	end
	local slot = self:GetID();
	if control:GetAttribute("debug") then
		control:SetAttribute("debugSeq", (control:GetAttribute("debugSeq") or 0) + 1);
		control:SetAttribute("debugLast", format("slot %%d %%s", slot, down and "down" or "up"));
	end

	if down then
		if slot <= 0 then
			return;
		end
		local kind, id = GetActionInfo(slot);
		if kind ~= "spell" or not (%s) then
			return;
		end
		pressedSlot = slot;
		ticks = 0;
		armed = 0;
		control:SetAttribute("armed", 0);
		-- Don't cast on press; the release decides.
		return false;
	end

	if not pressedSlot then
		return;
	end
	local stage = armed or 0;
	armed = 0;
	control:SetAttribute("armed", 0);
	if pressedSlot ~= slot then
		-- The crossbar page changed mid-hold, so this button now holds something else: drop the press.
		pressedSlot = nil;
		return;
	end
	pressedSlot = nil;

	local kind, id = GetActionInfo(slot);
	if kind ~= "spell" or not (%s) then
		return false;
	end

	-- Cast on this release instead of on the (suppressed) press; the post-body puts Blizzard's value back.
	savedUseOnKeyDown = self:GetAttribute("useOnKeyDown");
	self:SetAttribute("useOnKeyDown", false);
	local callSpell = control:GetAttribute("callSpell");
	if stage == 2 and callSpell then
		if self:GetAttribute("*type-TotemicCall") ~= "spell" then
			self:SetAttribute("*type-TotemicCall", "spell");
		end
		if self:GetAttribute("*spell-TotemicCall") ~= callSpell then
			self:SetAttribute("*spell-TotemicCall", callSpell);
		end
		return "TotemicCall", "restore";
	elseif stage >= 1 then
		if self:GetAttribute("*type-TotemRecall") ~= "spell" then
			self:SetAttribute("*type-TotemRecall", "spell");
		end
		if self:GetAttribute("*spell-TotemRecall") ~= %d then
			self:SetAttribute("*spell-TotemRecall", %d);
		end
		return "TotemRecall", "restore";
	end
	return nil, "restore";
]]):format(IsCallSpellCondition("id"), IsCallSpellCondition("id"), RECALL_SPELL_ID, RECALL_SPELL_ID);

local POST_CLICK = [[
	if message == "restore" then
		self:SetAttribute("useOnKeyDown", savedUseOnKeyDown);
		savedUseOnKeyDown = nil;
	end
]];

local function Print(text)
	print("|cff33ff99Totem Commands|r: " .. text);
end

local function GetHoldTicks()
	return (TotemCommandsDB and TotemCommandsDB.holdTicks) or DEFAULT_HOLD_TICKS;
end

local function GetHold2Ticks()
	return math.max((TotemCommandsDB and TotemCommandsDB.hold2Ticks) or DEFAULT_HOLD2_TICKS, GetHoldTicks() + 2);
end

-- Totemic Call's ID isn't a known constant, so find it by name in the spellbook.
local function FindTotemicCall()
	local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(TOTEMIC_CALL_NAME);
	return info and info.spellID or nil;
end

local function GetPageUnit()
	return GamepadMainActionBarFrame and GamepadMainActionBarFrame.PageUnit;
end

-- The crossbar buttons that hold bindable actions: the top bar's left cluster (its right cluster is
-- Interact/Inspect/Back/Jump), all eight buttons of the left, right and bottom bars, and the stance and
-- possess bars that can take over one of those bars' slots.
local function GetCrossbarButtons()
	local pageUnit = GetPageUnit();
	local bars = pageUnit and pageUnit.actionBars;
	if not bars then
		return {};
	end

	local buttons = {};
	local layout = { { "topBar", 4 }, { "leftBar", 8 }, { "rightBar", 8 }, { "bottomBar", 8 }, { "stanceBar", 8 }, { "possessBar", 8 } };
	for _, entry in ipairs(layout) do
		local barKey, count = entry[1], entry[2];
		local bar = bars[barKey];
		for index = 1, count do
			local button = bar and bar.GetActionButtonByIndex and bar:GetActionButtonByIndex(index);
			-- Only standard action buttons; the stance/possess bars may use other button types.
			if button and button.GetAttribute and button:GetAttribute("type") == "action" then
				table.insert(buttons, { button = button, bar = barKey, index = index });
			end
		end
	end
	return buttons;
end

local wrapped = {};
local function WrapCrossbarButtons()
	for _, info in ipairs(GetCrossbarButtons()) do
		if not wrapped[info.button] then
			local ok, err = pcall(SecureHandlerWrapScript, info.button, "OnClick", header, PRE_CLICK, POST_CLICK);
			if ok then
				wrapped[info.button] = true;
			else
				Print(("could not hook %s button %d: %s"):format(info.bar, info.index, tostring(err)));
			end
		end
	end
end

-- Secure attributes can only change out of combat: wraps the buttons (once per session), flips the
-- kill switch and publishes the hold lengths and Totemic Call's ID to the secure code.
local function ApplySettings()
	if InCombatLockdown() then
		return false;
	end
	local enabled = TotemCommandsDB.enabled == true;
	if enabled then
		WrapCrossbarButtons();
	end
	header:SetAttribute("holdTicks", GetHoldTicks());
	header:SetAttribute("hold2Ticks", GetHold2Ticks());
	header:SetAttribute("callSpell", FindTotemicCall());
	header:SetAttribute("debug", TotemCommandsDB.debug == true);
	header:SetAttribute("enabled", enabled);
	return true;
end

local function GetBarName(bar)
	local pageUnit = GetPageUnit();
	for key, candidate in pairs(pageUnit and pageUnit.actionBars or {}) do
		if candidate == bar then
			return key;
		end
	end
	return tostring(bar and bar:GetName() or bar);
end

-- Debug: report where each crossbar press went (read-only post-hook on Blizzard's dispatcher).
local function OnPressActionButton(_, index, _, down)
	if not (down and TotemCommandsDB and TotemCommandsDB.debug) then
		return;
	end
	local pageUnit = GetPageUnit();
	local bar = pageUnit and pageUnit:GetActiveBar();
	local button = bar and bar.GetActionButtonByIndex and bar:GetActionButtonByIndex(index);
	local slot = button and button:GetID();
	local kind, id = GetActionInfo(slot or 0);
	Print(("press: button %d on %s, hooked=%s, slot=%s, action=%s %s"):format(index, GetBarName(bar),
		tostring(button and wrapped[button] == true), tostring(slot), tostring(kind), tostring(id)));
end

local function Rumble()
	if C_GamePad and C_GamePad.SetVibration then
		C_GamePad.SetVibration("Low", RUMBLE_INTENSITY);
		C_Timer.After(RUMBLE_TIME, function() C_GamePad.StopVibration(); end);
	end
end

-- Feedback: read-only poll of the secure hold stage (and, in debug mode, of the secure hook's activity).
local lastStage = 0;
local lastDebugSeq = 0;
local feedback = CreateFrame("Frame");
feedback:SetScript("OnUpdate", function()
	local debugSeq = header:GetAttribute("debugSeq") or 0;
	if debugSeq ~= lastDebugSeq then
		lastDebugSeq = debugSeq;
		Print("secure hook ran: " .. tostring(header:GetAttribute("debugLast")));
	end

	local stage = header:GetAttribute("armed") or 0;
	if stage ~= lastStage then
		if stage == 1 then
			Rumble();
			UIErrorsFrame:AddMessage("Release for Totemic Recall", 0.2, 1, 0.6);
		elseif stage == 2 then
			Rumble();
			C_Timer.After(DOUBLE_RUMBLE_GAP, Rumble);
			UIErrorsFrame:AddMessage("Release for Totemic Call", 0.4, 0.8, 1);
		end
	end
	lastStage = stage;
end);

local function SpellLine(spellID, label)
	if not spellID then
		return label .. " = not found in your spellbook";
	end
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID);
	local known = IsPlayerSpell and IsPlayerSpell(spellID);
	return ("%d = %s (%s)"):format(spellID, tostring(name), known and "known" or "not known");
end

local function RunTest()
	Print("spells: " .. SpellLine(CALL_SPELL_IDS[1]) .. ", " .. SpellLine(RECALL_SPELL_ID) .. ", "
		.. SpellLine(FindTotemicCall(), TOTEMIC_CALL_NAME));

	local slots = {};
	for _, info in ipairs(GetCrossbarButtons()) do
		local slot = info.button:GetID();
		local kind, id = GetActionInfo(slot);
		if kind == "spell" and tContains(CALL_SPELL_IDS, id) then
			table.insert(slots, ("%s %d"):format(info.bar, info.index));
		end
	end
	Print(#slots > 0 and ("Call of the Elements found on: " .. table.concat(slots, ", "))
		or "Call of the Elements isn't on a crossbar slot on the current page.");

	local start = header:GetAttribute("tickcount") or 0;
	C_Timer.After(2, function()
		local ticks = (header:GetAttribute("tickcount") or 0) - start;
		Print(("secure ticks: %d in 2 s (%s)"):format(ticks, ticks >= 4 and "working" or "NOT working - tell me"));
	end);
end

local frame = CreateFrame("Frame");
frame:RegisterEvent("ADDON_LOADED");
frame:RegisterEvent("PLAYER_LOGIN");
frame:RegisterEvent("PLAYER_REGEN_ENABLED");
frame:RegisterEvent("SPELLS_CHANGED");
frame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS");
frame:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		if ... == ADDON_NAME then
			TotemCommandsDB = TotemCommandsDB or { enabled = false };
		end
	elseif event == "PLAYER_LOGIN" then
		RegisterStateDriver(header, "tick", "tock");
		if GamepadMainActionBarFrame and GamepadMainActionBarFrame.PressActionButton then
			hooksecurefunc(GamepadMainActionBarFrame, "PressActionButton", OnPressActionButton);
		end
		-- Give Blizzard's gamepad bars a frame to finish their own setup first.
		C_Timer.After(0, function()
			if not ApplySettings() then
				self.pendingApply = true;
			end
		end);
	elseif event == "SPELLS_CHANGED" then
		-- Learning Totemic Call (or the spellbook loading late) updates its ID for the secure code.
		if TotemCommandsDB and FindTotemicCall() ~= header:GetAttribute("callSpell") then
			self.pendingApply = not ApplySettings();
		end
	elseif event == "PLAYER_REGEN_ENABLED" or event == "UPDATE_SHAPESHIFT_FORMS" then
		-- Out of combat, pick up any crossbar buttons that weren't hookable earlier (e.g. a stance bar).
		if TotemCommandsDB and (self.pendingApply or TotemCommandsDB.enabled) then
			self.pendingApply = not ApplySettings();
		end
	end
end);

SLASH_TOTEMCOMMANDS1 = "/totemcommands";
SlashCmdList.TOTEMCOMMANDS = function(msg)
	msg = strtrim(msg or ""):lower();
	local holdArg = msg:match("^hold%s+(%d+)$");
	local hold2Arg = msg:match("^hold2%s+(%d+)$");
	if msg == "test" then
		RunTest();
		return;
	end
	if msg == "debug" then
		if InCombatLockdown() then
			Print("can't change this in combat.");
			return;
		end
		TotemCommandsDB.debug = not TotemCommandsDB.debug;
		ApplySettings();
		Print("debug output " .. (TotemCommandsDB.debug and "on - press crossbar buttons to see where they go." or "off."));
		return;
	end
	if msg == "on" or msg == "off" or holdArg or hold2Arg then
		if InCombatLockdown() then
			Print("can't change this in combat.");
			return;
		end
		if holdArg then
			local ticks = tonumber(holdArg);
			if ticks < MIN_HOLD_TICKS or ticks > MAX_HOLD_TICKS then
				Print(("hold must be %d to %d ticks (about 0.2 s each)."):format(MIN_HOLD_TICKS, MAX_HOLD_TICKS));
				return;
			end
			TotemCommandsDB.holdTicks = ticks;
		elseif hold2Arg then
			local ticks = tonumber(hold2Arg);
			if ticks < GetHoldTicks() + 2 or ticks > MAX_HOLD2_TICKS then
				Print(("hold2 must be %d to %d ticks."):format(GetHoldTicks() + 2, MAX_HOLD2_TICKS));
				return;
			end
			TotemCommandsDB.hold2Ticks = ticks;
		else
			TotemCommandsDB.enabled = (msg == "on");
		end
		ApplySettings();
		if TotemCommandsDB.enabled then
			local count = 0;
			for _ in pairs(wrapped) do
				count = count + 1;
			end
			Print(("on - %d crossbar buttons hooked. Tap Call of the Elements to cast it, hold %d ticks for Totemic Recall, %d for Totemic Call%s."):format(
				count, GetHoldTicks(), GetHold2Ticks(), header:GetAttribute("callSpell") and "" or " (not found - Recall only)"));
		else
			Print("off - crossbar buttons behave normally.");
		end
		return;
	end
	Print(("enabled=%s, hold=%d, hold2=%d, Totemic Call=%s, ticks so far=%s. Commands: test, on, off, hold <%d-%d>, hold2 <n>"):format(
		tostring(header:GetAttribute("enabled")), GetHoldTicks(), GetHold2Ticks(), tostring(header:GetAttribute("callSpell")),
		tostring(header:GetAttribute("tickcount")), MIN_HOLD_TICKS, MAX_HOLD_TICKS));
end;
