-------------------------------------------------------------------------------
-- Hookups into other addons, behind a safety switch
--
-- Bagnon and Auctionator have no plugin API for what Mother's Purse
-- does, so it reaches into their code, which can change with any update.
-- Baganator has an API, but it gets the same treatment. Each hookup:
--
--   * can be turned off on the settings page (Other addons),
--   * checks on load that everything it reaches for exists, and
--   * runs its callbacks through Safely, so any error turns it off.
--
-- When a hookup turns itself off it says so in chat, along with what stops
-- working, and stays off until that addon or Mother's Purse updates. /purse
-- retry, or ticking it again on the settings page, turns it back on after a
-- /reload.
-------------------------------------------------------------------------------

local ADDON_NAME, ns = ...

ns.hookups = {}   -- in the order they're made

local Hookup = {}
Hookup.__index = Hookup

-- label is the other addon's name as players know it. lostText says what
-- stops working while the hookup is off, finishing "Until this is fixed, ...".
function ns.NewHookup(id, label, lostText)
  local hookup = setmetatable({ id = id, label = label, lostText = lostText, off = true }, Hookup)
  table.insert(ns.hookups, hookup)
  return hookup
end

local function Version(addon)
  return C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addon, "Version") or "?"
end

function Hookup:State()
  local db = ns.Settings()
  db.hookups[self.id] = db.hookups[self.id] or {}
  return db.hookups[self.id]
end

-- Call once the other addon is known to be loaded. Returns true when the
-- hookup should go ahead and install itself.
function Hookup:Start(otherAddon)
  self.present = true
  self.versions = Version(otherAddon) .. "/" .. Version(ADDON_NAME)
  local state = self:State()
  if state.disabled then
    self.reason = "turned off in settings"
    return false
  end
  if state.offFor == self.versions then
    self.reason = state.reason
    ns.Print("the %s hookup is still off (%s). Until this is fixed, %s. /purse retry tries again.",
      self.label, state.reason or "?", self.lostText)
    return false
  end
  state.offFor, state.reason = nil, nil
  self.off = false
  return true
end

-- needs is a list of { description, found } pairs. A list rather than a map,
-- since a map entry whose value is nil vanishes and would never be checked.
-- Anything missing turns the hookup off before it installs. Returns true when
-- everything is there.
function Hookup:Require(needs)
  for _, need in ipairs(needs) do
    if not need[2] then
      self:TurnOff(need[1] .. " is missing")
      return false
    end
  end
  return true
end

-- Runs when the hookup turns off, to clear what it drew or set up.
function Hookup:OnTurnOff(fn)
  self.cleanup = fn
end

local function RunCleanup(hookup)
  if hookup.cleanup then pcall(hookup.cleanup) end
end

-- Something went wrong: turn off and say so.
function Hookup:TurnOff(reason)
  if self.off and self.reason then return end
  self.off = true
  self.reason = tostring(reason)
  local state = self:State()
  state.offFor, state.reason = self.versions, self.reason
  RunCleanup(self)
  ns.Print("|cffff4040turned off its %s hookup|r because %s didn't work the way Mother's Purse expects (it may have updated). "
    .. "Until this is fixed, %s. Error: %s. /purse retry tries again.",
    self.label, self.label, self.lostText, self.reason)
end

-- From the settings page.
function Hookup:SetEnabled(enabled)
  local state = self:State()
  state.disabled = not enabled or nil
  if enabled then
    state.offFor, state.reason = nil, nil
    if self.off and self.present then
      ns.Print("the %s hookup turns back on after a /reload.", self.label)
    end
  elseif not self.off then
    self.off = true
    self.reason = "turned off in settings"
    RunCleanup(self)
  end
end

function Hookup:IsEnabled()
  return not self:State().disabled
end

-- Runs fn, turning the hookup off if it errors. Returns false when off or on
-- an error, otherwise true and fn's first result.
function Hookup:Safely(fn, ...)
  if self.off then return false end
  local ok, result = pcall(fn, ...)
  if not ok then
    self:TurnOff(result)
    return false
  end
  return true, result
end

-- For hooks that should just do nothing once the hookup is off.
function Hookup:Guard(fn)
  return function(...)
    self:Safely(fn, ...)
  end
end

function Hookup:StatusText()
  if not self.present then return "not loaded" end
  if self.off then return "|cffff4040off|r (" .. (self.reason or "?") .. ")" end
  return "|cff40ff40on|r"
end

-- /purse retry: clear every automatic switch-off for the next /reload.
function ns.RetryHookups()
  for _, hookup in ipairs(ns.hookups) do
    local state = hookup:State()
    state.offFor, state.reason = nil, nil
  end
  ns.Print("hookups that turned themselves off will try again after a /reload.")
end
