-------------------------------------------------------------------------------
-- Options page: Options > AddOns > Mother's Purse Forever
-------------------------------------------------------------------------------

local ADDON_NAME, ns = ...

-- Keys you can mark with. Shift plus the same key toggles auction.
local KEYS = { "SPACE", "F", "G", "T", "BUTTON3", "BUTTON4", "BUTTON5" }

local optionsCategory

local function BuildOptionsPage()
  if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then
    return
  end
  local db = ns.Settings()
  local category, layout = Settings.RegisterVerticalLayoutCategory("Mother's Purse Forever")
  optionsCategory = category

  local function AddHeader(text)
    if CreateSettingsListSectionHeaderInitializer and layout then
      pcall(function() layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text)) end)
    end
  end

  local function Register(key, label, default)
    local setting = Settings.RegisterAddOnSetting(category, "MothersPurse_" .. key, key, db, type(default), label, default)
    setting:SetValueChangedCallback(function() ns.ApplySetting(key) end)
    return setting
  end

  AddHeader("Marking")
  Settings.CreateCheckbox(category, Register("enabled", "Enable marking", true),
    "Hovering a bag item borrows the mark key, and marks show in your bags.")

  do
    local setting = Register("key", "Mark key", "SPACE")
    local function GetOptions()
      local container = Settings.CreateControlTextContainer()
      for _, key in ipairs(KEYS) do container:Add(key, GetBindingText(key)) end
      return container:GetData()
    end
    Settings.CreateDropdown(category, setting, GetOptions,
      "Press it over a bag item to cycle junk, favorite and regular. Hold Shift with it to toggle auction. It only takes over the key while you're pointing at your bags.")
  end

  Settings.CreateCheckbox(category, Register("hints", "Show key hints on tooltips", true),
    "Adds a line to the bottom of bag item tooltips saying what the key will do, like Mark as junk.")
  Settings.CreateCheckbox(category, Register("sound", "Sound when marking", true),
    "Plays a sound each time you mark or unmark an item, a coin for auction marks and a gem for the rest.")
  Settings.CreateCheckbox(category, Register("autoJunk", "Treat grey items as junk", true),
    "Grey items show as junk and sell with the rest, unless you mark them as something else.")

  AddHeader("Vendor")
  Settings.CreateCheckbox(category, Register("sellButton", "Sell marked junk with Sell All Junk", true),
    "Blizzard's Sell All Junk button on vendors sells what you marked as junk along with the grey items it always sells, "
      .. "12 per click so you can buy any of them back, and never sells favorites or auction items. "
      .. "Turn it off to give the button back to Blizzard.")

  AddHeader("Auction house")
  Settings.CreateCheckbox(category, Register("ahGlow", "Highlight auction items", true),
    "While the auction house is open, items marked for auction glow in your bags so they're easy to find.")

  AddHeader("Marks")
  do
    local setting = Register("forgetDays", "Forget marks on old gear", 90)
    local function GetOptions()
      local container = Settings.CreateControlTextContainer()
      container:Add(0, "Never")
      for _, days in ipairs({ 30, 90, 180 }) do container:Add(days, ("After %d days"):format(days)) end
      return container:GetData()
    end
    Settings.CreateDropdown(category, setting, GetOptions,
      "Gear is marked one copy at a time, so a mark on a piece you no longer have is never needed again. "
      .. "This forgets marks on gear that hasn't been in your bags or bank for that long. Items on an alt, in the mail "
      .. "or on the auction house keep their marks until they've been gone that long. Marks on stackable items, like "
      .. "herbs, are never forgotten, so the next ones you pick up are marked too.")
  end
  if CreateSettingsButtonInitializer and layout then
    pcall(function()
      layout:AddInitializer(CreateSettingsButtonInitializer(
        "Junk marks", "Clear", function()
          ns.ClearMarks(ns.JUNK)
          ns.Print("cleared junk marks.")
        end, "Removes every junk mark.", true))
      layout:AddInitializer(CreateSettingsButtonInitializer(
        "All marks", "Clear", function()
          ns.ClearMarks(nil)
          ns.Print("cleared all marks.")
        end, "Removes every junk, favorite and auction mark.", true))
    end)
  end

  -- One checkbox per installed addon that has a hookup (Hookups.lua).
  local first = true
  for _, hookup in ipairs(ns.hookups) do
    if hookup.present and Settings.RegisterProxySetting then
      if first then
        AddHeader("Other addons")
        first = false
      end
      local setting = Settings.RegisterProxySetting(category, "MothersPurse_hookup_" .. hookup.id, "boolean",
        "Work with " .. hookup.label, true,
        function() return hookup:IsEnabled() end,
        function(value) hookup:SetEnabled(value) end)
      Settings.CreateCheckbox(category, setting,
        ("Shows marks in %s and keeps them in sync. Turning it off takes effect right away, and turning it back on needs a /reload. "
          .. "If %s changes in an update and this stops working, it turns itself off and says so in chat.\n\nRight now: %s")
          :format(hookup.label, hookup.label, hookup:StatusText()))
    end
  end

  Settings.RegisterAddOnCategory(category)
end

function ns.OpenOptions()
  if optionsCategory and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(optionsCategory:GetID())
  else
    ns.Print("the options page isn't available, so use the /purse commands instead.")
  end
end

ns.On("Loaded", BuildOptionsPage)
