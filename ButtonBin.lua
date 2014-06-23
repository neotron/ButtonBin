
--[[
**********************************************************************
ButtonBin - A displayer for LibDataChron compatible addons
**********************************************************************
Some code from Fortress was used in this addon with permission from the
author Borlox.
**********************************************************************
]]
local ButtonBin = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon("ButtonBin", false, "Gemini:Event-1.0", "Gemini:Timer-1.0" )

local LDC = Apollo.GetPackage("Lib:DataChron-1.0").tPackage
--local R = LibStub("AceConfigRegistry-3.0")
local GeminiGUI = Apollo.GetPackage("Gemini:GUI-1.0").tPackage
local GeminiLogging = Apollo.GetPackage("Gemini:Logging-1.2").tPackage

local BB_DEBUG = false


-- Silently fail embedding if it doesn't exist
local log
--local C = LibStub("AceConfigDialog-3.0")
--local DBOpt = LibStub("AceDBOptions-3.0")
--local media = LibStub("LibSharedMedia-3.0")
local mod

local fmt = string.format
local ipairs = ipairs
local lower = string.lower
local pairs = pairs
local select = select
local setmetatable = setmetatable
local tconcat = table.concat
local tinsert = table.insert
local tostring = tostring
local tremove = table.remove
local tsort   = table.sort
local type = type
local unpack = unpack

local bins = {}
local binTimers = {}

local ldbObjects = {}
local buttonFrames = {}
local options
local db

local unlockButtons = false
local unlockFrames = false
local playerInCombat = false

function ButtonBin.clear(tbl)
   if type(tbl) == "table" then
      for id,data in pairs(tbl) do
         if type(data) == "table" then mod.del(data) end
         tbl[id] = nil
      end
   end
end

local defaults = {
   profile = {
      enabledDataObjects = {
         ['*'] = {
            enabled = true,
            tooltipScale = 1.0,
         },
      },
      size = 24,
      scale = 1.0,
      tooltipScale = 1.0,
      width  = 20,
      hpadding = 0.5,
      vpadding = 0.5,
      bins = {
	 ['**'] =  {
	    colors = {
	       backgroundColor = { 0, 0, 0, 0.5},
	       borderColor = { 0.88, 0.88, 0.88, 0.8 },
	       labelColor  = { 1, 1, 1 },
	       textColor   = { 1, 1, 1 },
	       unitColor   = { 1, 1, 1 },
	       valueColor   = { 0.9, 0.9, 0 },
	    },
	    background = "Solid",
	    binLabel = true,
	    border = "None",
	    clampToScreen = true,
	    collapsed = false,
	    edgeSize = 10,
	    flipx = false,
	    flipy = false,
	    font = "Friz Quadrata TT",
	    moveFrames = false,
	    fontsize = 12,
	    hidden = true,
	    hideAllText = false,
	    hideEmpty = true,
	    hideLabel = true,
	    hideTimeout = 2,
	    hpadding = 0.5,
	    labelOnMouse = false,
	    pixelwidth = 0,
	    scale = 1.0,
	    size = 24,
	    sortedButtons = {},
	    tooltipScale = 1.0,
	    useGlobal = true,
	    visibility = "always",
	    vpadding = 0.5,
	    width = 10,
	    binTexture = "Interface\\AddOns\\ButtonBin\\bin.tga",
	    center = false, 
	 }
      }
   }
}

local function ColorToHex(c)
   return ("%02x%02x%02x"):format(c[1]*255, c[2]*255, c[3]*255)
end

local GameTooltip = GameTooltip
local function GT_OnLeave(self)
   self:SetScript("OnLeave", self.oldOnLeave)
   self.oldOnLeave = nil
   if self.oldScale then
      self:SetScale(self.oldScale)
      self.oldScale = nil
   end
   self:Hide()
   GameTooltip:EnableMouse(false)
end

local function getAnchors(frame)
   local x, y = frame:GetCenter()
   local leftRight
   if x < GetScreenWidth() / 2 then
      leftRight = "LEFT"
   else
      leftRight = "RIGHT"
   end
   if y < GetScreenHeight() / 2 then
      return "BOTTOM", "TOP"
   else
      return "TOP", "BOTTOM"
   end
end

local function SetTooltipScale(tooltip, frame)
   
end

local function PrepareTooltip(frame, anchorFrame, isGameTooltip)
   if frame == GameTooltip then
      frame.oldOnLeave = frame:GetScript("OnLeave")
      frame:EnableMouse(true)
      frame:SetScript("OnLeave", GT_OnLeave)
   end
   frame:SetOwner(anchorFrame, "ANCHOR_NONE")
   frame:ClearAllPoints()
   local a1, a2 = getAnchors(anchorFrame)
   frame:SetPoint(a1, anchorFrame, a2)
   SetTooltipScale(frame, anchorFrame)
end

local tablet
local function LDC_OnReceiveDrag(self, button)
   if self._ondrag then
      self._ondrag(self, button)
   end
end

local function LDC_OnClick(self, button)
   if self._onclick then
      LDC_OnLeave(self)
      self._onclick(self, button)
   end
end

local function BB_OnClick(self, button)
   LDC_OnLeave(self)
   if button == "LeftButton" then
      if IsAltKeyDown() then
         mod:ToggleButtonLock()
      else
         mod:ToggleCollapsed(self)
      end
   elseif button == "MiddleButton" then
      mod:ToggleLocked()
   elseif button == "RightButton" then
      mod:ToggleConfigDialog(self)
   end
end

function ButtonBin:Print(...)
   log:info(...)
end

function ButtonBin:OnInitialize()
   mod = self
   self.db = Apollo.GetPackage("Gemini:DB-1.0").tPackage:New(self,  defaults)
   self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
   self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
   self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
   db = self.db.profile
   
   if BB_DEBUG then
      -- Just for easy access while debugging
      bbdb = db
      bns = bins
      bf = buttonFrames
   end
   Apollo.LoadSprites(Apollo.GetAssetFolder().."\\Sprites.xml")
end

function ButtonBin:AddNewBin()
   db.bins[#db.bins+1].hidden = false
   mod:LoadPosition(mod:CreateBinFrame(#db.bins, db.bins[#db.bins]))
   self:SetupBinOptions(true)
end

do
   local tooltip = "<P>Button Bin %d<BR/></P>"..
      "<P><T TextColor=\"ffffff00\">Left click</T> to collapse/uncollapse all other icons.<BR /></P>"..
      "<P><T TextColor=\"ffffff00\">Alt-Left click</T> to toggle the button lock.<BR /></P>"..
      "<P><T TextColor=\"ffffff00\">Middle click</T> to toggle the Button Bin window lock.<BR /></P>"..
      "<P><T TextColor=\"ffffff00\">Right click</T> to open the Button Bin configuration.</P>"
   function ButtonBin:CreateBinFrame(id, bdb)
      local f = mod:GetBinFrame()
      local sdb
      if bdb.useGlobal then sdb = db else sdb = bdb end
      bins[id] = f
      f.binId = id
      f:SetClampedToScreen(bdb.clampToScreen)
      f:SetScale(sdb.scale)
      f:FixBackdrop()
      f.button.wnd:SetTooltip(tooltip:format(id))
      f.button.db = { tooltiptext = tooltip:format(id), bin = id }
      f.button.obj = f.button.db
      f.button.name = "ButtonBin"
      mod:SetBinIconAndLabel(f, bdb)
      --      f._isMouseOver = true
      mod:SortFrames(f)
      return f
   end
end

function ButtonBin:SetBinIconAndLabel(frame, bdb)
   if bdb.binLabel then
      local label = bdb.binName or "Bin #"..frame.binId
      frame.button.plainText = label
      frame.button.buttonBinText = "<P Font=\"CRB_Header12\">"..label.."</P>"
   else
      frame.button.plainText = ""
   end
   frame.button.icon:SetSprite("ButtonBin_Icon")
end

function ButtonBin:LibDataChron_DataObjectCreated(event, name, obj)
   ldbObjects[name] = obj
   if db.enabledDataObjects[name].enabled then
      mod:EnableDataObject(name, obj)
      local binid = buttonFrames[name].db.bin
      local bdb = db.bins[binid]
      for _,bname in ipairs(bdb.sortedButtons) do
         if name == bname then
            return
         end
      end
      bdb.sortedButtons[#bdb.sortedButtons+1] = name
      mod:SortFrames(bins[binid])
   end
end

local function TextUpdater(frame, value, name, obj, delay)
   local bin = bins[frame.db.bin]
   local bdb,sdb = mod:GetBinSettings(bin)

   if mod:DataBlockConfig(name, "hideLabel", bdb.hideAllText) and
      mod:DataBlockConfig(name, "hideText",  bdb.hideAllText) and
   mod:DataBlockConfig(name, "hideValue", bdb.hideAllText) then
      frame.buttonBinText = nil
   else
      local showLabel = not mod:DataBlockConfig(name, "hideLabel", bdb)
      local showText  = not mod:DataBlockConfig(name, "hideText",  bdb)
      local showValue = not mod:DataBlockConfig(name, "hideValue", bdb)
 
      local labelColor = ColorToHex(bdb.colors.labelColor)
      local textColor = ColorToHex(bdb.colors.textColor)
      local unitColor = ColorToHex(bdb.colors.unitColor)
      local valueColor = ColorToHex(bdb.colors.valueColor)

      local text
      local plaintext
      if showLabel and obj.label then  -- try to show the label
         if showValue and obj.value then
            text = fmt("<P><T TextColor=\"ff%s\">%s:</T> <T TextColor=\"ff%s\">%s</T><T TextColor=\"ff%s\"> %s</T></P>", labelColor, obj.label,
                       valueColor, obj.value, unitColor, obj.suffix or "")
            plaintext = fmt("%s: %s %s>", obj.label, obj.value, obj.suffix or "")
	    
         elseif showText and obj.text and obj.text ~= obj.label then
	    text = fmt("<P><T TextColor=\"%s\">%s:</T> <T TextColor=\"ff%s\">%s</T></P>",
		       labelColor, obj.label, textColor, obj.text)
	    plaintext = fmt("%s: %s", obj.label, obj.text)

         else
            text = fmt("<P><T TextColor=\"ff%s\">%s</T></P>", labelColor, obj.label)
	    plaintext = obj.label
         end
      elseif showLabel and type == "launcher" then
         -- show the addonname for launchers if no label is set
         local addonName, addonTitle = GetAddOnInfo(obj.tocname or name)
	 plaintext  = addonTitle or addonName or name
         text = fmt("<P TextColor=\"ff%s\">%s</P>", labelColor, plaintext)
      elseif showText and obj.text then
         if showValue and obj.value then
            text = fmt("<P Font=\"CRB_Header12\"><T TextColor=\"ff%s\">%s</T><T TextColor=\"ff%s\"> %s</T></P>", valueColor,
                       obj.value, unitColor, obj.suffix or "")
            plaintext = fmt("%s %s", obj.value, obj.suffix or "")
         else
            text = fmt("<P Font=\"CRB_Header12\" TextColor=\"ff%s\">%s</P>", textColor, obj.text)
            plaintext = obj.text
         end
      end
      log:info(text)
      frame.buttonBinText = text
      frame.plainText = plaintext
   end
   if not delay then
      local w = frame:GetWidth()
      frame:resizeWindow(true)
      w = w - frame:GetWidth()
      if w > 0 or w < -10 then
         mod:SortFrames(frame:GetParent())
      end
   end
end

local function SetTexCoord(frame, value, name, object)
   --   object.texcoord = value
   --   if object.texcoord then
   --      frame.icon:SetTexCoord(unpack(object.texcoord))
   --   end
end

local function SetIconColor(frame, object)
   frame.icon:SetBGColor(ApolloColor.new(object.iconR or 1,
					 object.iconG or 1,
					 object.iconB or 1,
					 1))
end



local updaters = {
   text   = TextUpdater,   value  = TextUpdater,
   suffix = TextUpdater,   label  = TextUpdater,
   textcoord = SetTexCoord,
   iconCoords = SetTexCoord,
   iconR = function(frame, value, name, object)
      object.iconR = value
      SetIconColor(frame, object)
   end,
   iconG = function(frame, value, name, object)
      object.iconG = value
      SetIconColor(frame, object)
   end,
   iconB = function(frame, value, name, object)
      object.iconB = value
      SetIconColor(frame, object)
   end,
   icon = function(frame, value, name, object, delay)
      frame.icon:SetSprite(value)
      local has_texture = not not value
      if has_texture ~= frame._has_texture then
	 frame._has_texture = has_texture
	 if not delay then
	    if has_texture then
	       mod:SortFrames(frame:GetParent()) -- we grew
	    else
	       frame:resizeWindow(true)
	    end
	 end
      end
   end,
   OnClick = function(frame, value)
      frame._onclick = value
      if value then
	 --frame:SetScript("OnClick", LDC_OnClick)
      else
	 --frame:SetScript("OnClick", nil)
      end
   end,
   OnReceiveDrag = function(frame, value)
      frame._ondrag = value
      if value then
	 --frame:SetScript("OnReceiveDrag", LDC_OnReceiveDrag)
      else
	 --frame:SetScript("OnReceiveDrag", nil)
      end
   end,
   tooltiptext = function(frame, value, name, object)
      if object.tooltiptext then
	 frame.wnd:SetTooltip(object.tooltiptext)
      else
	 frame.wnd:SetTooltip("")
      end
   end,
}

function ButtonBin:AttributeChanged(event, name, key, value)
   if not db.enabledDataObjects[name].enabled then return end
   local f = buttonFrames[name]
   local obj = ldbObjects[name]
   obj[key] = value
   if f and obj then
      if updaters[key] then
         updaters[key](f, value, name, obj)
      end
   end
end

function ButtonBin:EnableDataObject(name, obj)
   db.enabledDataObjects[name].enabled = true
   -- create frame for object
   local frame = buttonFrames[name]
   local binId = 1
   local bin
   if frame then
      binId = frame.db.bin
   end
   local bin = bins[binId]
   frame = frame or mod:GetFrame(nil, bin.left) -- TODO fix which one to use
   buttonFrames[name] = frame
   frame.db = db.enabledDataObjects[name]
   frame.name = name
   frame.obj = obj
   frame.db.bin = binId
   --   frame:SetScript("OnEnter", LDC_OnEnter)
   --   frame:SetScript("OnLeave", LDC_OnLeave)
   mod:UpdateBlock(name, frame, true)

   mod:RegisterEvent("LibDataChron_AttributeChanged_"..name, "AttributeChanged")
   mod:SortFrames(bin)
   mod:SetupDataBlockOptions(true)
end

function ButtonBin:DisableDataObject(name, obj)
   db.enabledDataObjects[name].enabled = false
   mod:UnregisterEvent("LibDataChron_AttributeChanged_"..name)
   if buttonFrames[name] then
      self:ReleaseFrame(buttonFrames[name])
   end
   mod:SetupDataBlockOptions(true)
end

function ButtonBin:OnEnable()
   self.bins = bins
   self.buttonFrames = buttonFrames
   
   log = GeminiLogging:GetLogger({
				    level = GeminiLogging.INFO,
				    pattern = "%d %n %c %l - %m",
				    appender = "GeminiConsole"
   })
   if BB_DEBUG then
      log:SetLevel(GeminiLogging.DEBUG)
   end

   -- Make sure we have the default set of bins
   if not db.bins or #db.bins == 0 then
      mod:LoadDefaultBins()
   else
      for id,bdb in pairs(db.bins) do
	 mod:CreateBinFrame(id, bdb)
      end
   end
   mod:SetupOptions()

   self:ApplyProfile()
   self:RegisterEvent("LibDataChron_DataObjectCreated")
   for _,bin in ipairs(bins) do
      self:SortFrames(bin)
   end
   -- Seems to fire when resizing the window or switching from fullscreen to
   -- windowed mode but not at other times
   self:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS","RecalculateSizes")
   self:RegisterEvent("PLAYER_REGEN_ENABLED")
   self:RegisterEvent("PLAYER_REGEN_DISABLED")


   LDC:NewDataObject("Test1", {
			type = "launcher",
			text = "Test 1",
			icon = "achievements:sprAchievements_Icon_Group",
			label = "A label",
			value = "12.0",
			suffix = "fps",
			tooltiptext = "A small tooltip.",
			OnClick = function(clickedframe, button)
			   log:info("button clicked")
			end
   })

   LDC:NewDataObject("Another Test", {
			text = "Testing", 
			icon = "abilities:sprAbility_CapEnd3",
			label = "Another label",
			tooltiptext = "Hello america.",
			OnClick = function(clickedframe, button)
			   log:info("button 2clicked")
			end
   })
end

function ButtonBin:OnDisable()
   self:UnregisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
   self:UnregisterEvent("PLAYER_REGEN_ENABLED")
   self:UnregisterEvent("PLAYER_REGEN_DISABLED")
   LDC.UnregisterAllCallbacks(self)

   for id,bin in ipairs(bins) do
      bin:Hide()
      if binTimers[id] then
         self:CancelTimer(binTimers[id], true)
         binTimers[id] = nil
      end

   end
end

function ButtonBin:PLAYER_REGEN_ENABLED()
   playerInCombat = false
   for id,bin in ipairs(bins) do
      bin:ShowOrHide(db.bins[id].visibility == "inCombat")
   end
end

function ButtonBin:PLAYER_REGEN_DISABLED()
   playerInCombat = true
   for id,bin in ipairs(bins) do
      bin:ShowOrHide(db.bins[id].visibility == "noCombat")
   end
end

do
   local timer
   local function Low_RecalculateSizes()
      for _,bin in ipairs(bins) do
         mod:SortFrames(bin)
      end
   end
   function ButtonBin:RecalculateSizes()
      if timer then mod:CancelTimer(timer, true) timer = nil end
      timer = mod:ScheduleTimer(Low_RecalculateSizes, 1)
   end
end

-- Migrate settings

do
   local migrated = {
      shortLabels = "hideLabel"
   }
   local migratedobj = {
   }
   function ButtonBin:ConvertBinOptions(bin)
      if bin.showLabels ~= nil then
         bin.hideAllText = not bin.showLabels
         bin.showLabels = nil
      end
      for from,to in pairs(migrated) do
         if bin[from] ~= nil then
            bin[to] = bin[from]
            bin[from] = nil
         end
      end
   end
   function ButtonBin:ConvertBlockOptions(obj)
      for from,to in pairs(migratedobj) do
         if obj[from] ~= nil then
            obj[to] = obj[from]
            obj[from] = nil
         end
      end
   end
end

function ButtonBin:ApplyProfile()
   -- clean stuff up
   for id,bin in ipairs(db.bins) do
      local seen = {}
      local newButtons = {}
      for bid, name in pairs(bin.sortedButtons) do
         if not seen[name] then
            seen[name] = true
            if db.enabledDataObjects[name].bin == id then
               newButtons[#newButtons+1] = name
            end
         end
      end
      mod:ConvertBinOptions(bin)
      bin.sortedButtons = newButtons
   end

   for id, obj in pairs(db.enabledDataObjects) do
      mod:ConvertBlockOptions(obj)
   end
   for _,frame in pairs(buttonFrames) do
      mod:ReleaseFrame(frame)
   end
   for name, obj in LDC:DataObjectIterator() do
      self:LibDataChron_DataObjectCreated(nil, name, obj)
   end
   for id,bin in ipairs(bins) do
      mod:LoadPosition(bin)
      if bin.mover:IsVisible() then
         mod:ToggleLocked()
      else
         self:SortFrames(bin) -- will handle any size changes etc
      end
   end
end

function ButtonBin:SavePosition(bin)
   local s = bin:GetEffectiveScale()
   local bdb = db.bins[bin.binId]
   local top = bin:GetTop()
   if not top then return end -- the bin is empty, and bin icon hidden
   if bdb.flipy then
      bdb.posy = bin:GetBottom() * s
      bdb.anchor = "BOTTOM"
   else
      bdb.posy =  top * s - UIParent:GetHeight()*UIParent:GetEffectiveScale()
      bdb.anchor = "TOP"
   end
   if bdb.flipx then
      bdb.anchor = bdb.anchor .. "RIGHT"
      bdb.posx = bin:GetRight() * s - UIParent:GetWidth()*UIParent:GetEffectiveScale()
   else
      bdb.anchor = bdb.anchor .. "LEFT"
      bdb.posx = bin:GetLeft() * s
   end
end

function ButtonBin:LoadPosition(bin)
   local bdb = db.bins[bin.binId]
   local posx = bdb.posx
   local posy = bdb.posy

   if false then 
      local anchor = bdb.anchor
      bin:ClearAllPoints()
      if not anchor then  anchor = "TOPLEFT" end
      local s = bin:GetEffectiveScale()
      if posx and posy then
	 bin:SetPoint(anchor, posx/s, posy/s)
      else
	 bin:SetPoint(anchor, UIParent, "CENTER")
      end
   end
end

function ButtonBin:OnProfileChanged(event, newdb, src)
   db = self.db.profile
   for id,frame in ipairs(bins) do
      mod:ReleaseBinFrame(frame)
   end
   if event == "OnProfileReset" or #db.bins == 0 then
      for id,frame in ipairs(bins) do
         db.bins[id] = nil
      end
      db.bins[1].hidden = false
   end
   for id,bdb in pairs(db.bins) do
      mod:CreateBinFrame(id, bdb)
   end
   self:ApplyProfile()
   self:SetupBinOptions(true)
end


function ButtonBin:LoadDefaultBins()
   local defaults = {
      posy = 0.5,
      posx = 0,
      hidden = false,
      binLabel = true,
      hideBinIcon = false,
      edgeSize = 0,
      moveFrames = true,
      anchor = "TOPLEFT",
      pixelwidth = Apollo.GetScreenSize(),
      width = 100,
      clampToScreen = false,
      binName = "Button Bin"
   }
   for id in ipairs(db.bins) do
      if bins[id] then
	 mod:ReleaseBinFrame(bins[id])
      end
      db.bins[id] = nil
   end
   local bdb = db.bins[1]
   for key, val in pairs(defaults) do
      bdb[key] = val
   end

   for id, data in pairs(db.enabledDataObjects) do
      data.bin = 1
   end

   for id,bdb in pairs(db.bins) do
      mod:CreateBinFrame(id, bdb)
   end      
   self:ApplyProfile()
   self:SetupBinOptions(true)
end

function ButtonBin:ToggleLocked()
   unlockFrames = not unlockFrames
   if false then
      for id,bin in ipairs(bins) do
	 if not unlockFrames then
	    local s = bin:GetEffectiveScale()
	    bin.mover:RegisterForDrag()
	    bin.mover:Hide()
	    bin.mover.text:Hide()
	    mod:LoadPosition(bin)
	 else
	    bin.mover:SetWidth(bin:GetWidth())
	    bin.mover:SetHeight(bin:GetHeight())
	    bin.mover:SetScale(bin:GetScale())
	    bin.mover:SetPoint(bin:GetPoint())
	    bin.mover:RegisterForDrag("LeftButton")
	    bin:ClearAllPoints()
	    bin:SetPoint("TOPLEFT", bin.mover)
	    bin.mover:Show()
	    bin.mover.text:Show()
	 end
	 bin:ShowOrHide()
	 mod:SortFrames(bin)
      end
   end
end

function ButtonBin:ToggleButtonLock()
   unlockButtons = not unlockButtons

   local dragButton
   if unlockButtons then dragButton = "LeftButton" end
   if unlockButtons then
      mod:Print("Button positions are now unlocked.")
   else
      mod:Print("Locking button positions.")
   end
   for name,frame in pairs(buttonFrames) do
      frame:RegisterForDrag(dragButton)
      frame:SetMovable(unlockButtons)
      if unlockButtons then
         frame._onenter = frame:GetScript("OnEnter")
         frame._onleave = frame:GetScript("OnLeave")
         frame:SetScript("OnEnter", nil)
         frame:SetScript("OnLeave", nil)
      else
         if name ~= "ButtonBin" or not db.hideBinTooltip then
            frame:SetScript("OnEnter", frame._onenter or LDC_OnEnter)
            frame:SetScript("OnLeave", frame._onleave or LDC_OnLeave)
         end
         frame._onenter = nil frame._onleave = nil
      end
   end
   for _,bin in ipairs(bins) do
      bin:ShowOrHide()
   end
end

function ButtonBin:ReloadFrame(bin)
   local wasUnlocked = unlockFrames
   if wasUnlocked then mod:ToggleLocked() end
   if not db.hideBinTooltip then
      bin.button:SetScript("OnEnter", LDC_OnEnter)
      bin.button:SetScript("OnLeave", LDC_OnLeave)
   else
      bin.button:SetScript("OnEnter", nil)
      bin.button:SetScript("OnLeave", nil)
   end
   mod:UpdateAllBlocks(bin)
   mod:SavePosition(bin)
   mod:LoadPosition(bin)
   mod:SortFrames(bin)
   if wasUnlocked then mod:ToggleLocked() end
end

options = {
   global = {
      type = "group",
      name = "Global Settings",
      order = 4,
      childGroups = "tab",
      handler = mod,
      get = "GetOption",
      set = "SetOption",
      args = {
         toggle ={
            type = "toggle",
            name = "Lock the button bin frame",
            width = "full",
            get = function() return not unlockFrames end,
            set = function() mod:ToggleLocked() end,
         },
         tooltipScale = {
            type = "range",
            name = "Tooltip Scale",
            desc = "The scale of the tooltip for this datablock",
            width="full",
            min = 0.1, max = 5, step = 0.05,
         },
         toggleButton = {
            type = "toggle",
            name = "Lock data broker button positions",
            desc = "When unlocked, you can move buttons into a new position on the bar.",
            width = "full",
            get = function() return not unlockButtons end,
            set = function() mod:ToggleButtonLock() end
         },
         hideBinTooltip = {
            type = "toggle",
            width = "full",
            name = "Hide Button Bin tooltips",
            desc = "Decide whether or not to show the helper tooltip when mousing over the Button Bin icons.",
         },
         globalScale = {
            type = "group",
            name = "Scale and size",
            args = {
               hpadding = {
                  type = "range",
                  name = "Horizontal button padding",
                  width = "full",
                  min = 0, max = 50, step = 0.1,
                  order = 130,
               },
               vpadding = {
                  type = "range",
                  name = "Vertical button padding",
                  width = "full",
                  min = 0, max = 50, step = 0.1,
                  order = 140,
               },
               size = {
                  type = "range",
                  name = "Button size",
                  width = "full",
                  min = 5, max = 50, step = 1,
                  order = 160,
               },
               scale = {
                  type = "range",
                  name = "Bin scale",
                  width = "full",
                  min = 0.01, max = 5, step = 0.01,
                  order = 170,
               },
            }

         }
      }
   },

   dataBlock = {
      type = "group",
      handler = mod,
      set = "SetDataBlockOption",
      get = "GetDataBlockOption",
      args = {
         help = {
            type = "description",
            name = "You can override the bar level configuration in this section. Note that when enabled, these settings will always override the settings of the individual bins.",
            order = 0,
            hidden = function() return bins[1] == nil end,
         },
         enabled = {
            type="toggle",
            name = "Enabled",
            desc = "Toggle to enable display of this datablock.",
            order = 1,
            disabled = function() return bins[1] == nil end,
         },
         blockOverride = {
            type = "toggle",
            name = "Override bin config",
            desc = "If override is enabled, the settings here are used over the bin level configuration. Otherwise the block will be displayed as per the bin settings.",
            order = 2,
            hidden = "HideOverrideConfig",
         },
	 hideTooltip = {
	    type = "toggle",
	    name = "Hide tooltip",
	    desc = "Don't show the mouseover tooltip for this block.",
	    order = 10,
	 },	 
         hideIcon = {
            type = "toggle",
            name = "Hide icon",
            desc = "Hide the icon for this datablock.",
            hidden = "HideDataBlockOptions"
         },
         hideLabel = {
            type = "toggle",
            name = "Hide label",
            desc = "Hide the label for this datablock",
            hidden = "HideDataBlockOptions"
         },
         hideText = {
            type = "toggle",
            name = "Hide text",
            desc = "Hide the text for this data block.",
            hidden = "HideDataBlockOptions",
         },
         hideValue = {
            type = "toggle",
            name = "Hide values",
            desc = "Hide the value for this data block.",
            hidden = "HideDataBlockOptions",
         },
         tooltipScale = {
            type = "range",
            name = "Tooltip Scale",
            desc = "The scale of the tooltip for this datablock",
            width="full",
            min = 0.1, max = 5, step = 0.05,
            hidden = "HideDataBlockOptions"
         },
         bin = {
            type = "select",
            name = "Bin",
            desc = "The bin this datablock resides in.",
            width = "full",
            values = function() local val = {}
	       for id,bdb in pairs(db.bins) do
		  val[id]= bdb.binName
	       end
	       return val
                     end,
         }
      }
   },

   bins = {
      type = "group",
      name = "Bins",
      handler = mod,
      args = {
         newbin = {
            type = "execute",
            name = "Add a new bin",
            desc = "Create a new display bin.",
            func = "AddNewBin",
         },
	 loaddefaults = {
	    type = "execute",
	    name = "Reset Bin Layout",
	    desc = "This will remove your existing set of bins and load the default three bin left/center/right setup. All datablocks will be reset to be shown in the first bin as well.",
	    func = "LoadDefaultBins",
	 }
      }
   },
   binConfig = {
      type = "group",
      name = "Bin #",
      order = 4,
      --      childGroups = "tab",
      get = "GetOption",
      set = "SetOption",
      args = {
         help = {
            type = "description",
            name = "Select the sub-sections to configure this bin. You can also delete the bin permanently by clicking the button below.",
            order = 1,
         },
         separator = {
            type = "header",
            name = "",
            order = 2,
         },
         delete = {
            type = "execute",
            name = "Delete bin",
            desc = "Delete this bin. All objects displayed in this bin will be hidden and all settings purged.",
            func = "DeleteBin",
            confirm = true,
            confirmText = "Are you sure that you want to delete this bin? This action can't be reverted.",
            order = 10,
         },
         binIcon = {
            type = "group",
            name = "Bin Icon and Name",
            args = {
               binName = {
                  type = "input",
                  name = "Bin Name",
                  desc = "The name of the bin, used in the configuration UI and the bin icon if shown.",
                  order = 3,
                  disabled = "DisableBinIconOptions",
               },
               binTexture =  {
                  type = "input",
                  name = "Bin Icon Texture",
                  desc = "The path to the texture used as the bin icon.",
                  order = 4,
                  disabled = "DisableBinIconOptions",
               },
               hideBinIcon = {
                  width = "full",
                  type = "toggle",
                  name = "Hide button bin icon",
                  desc = "Hide or show the button bin icon for this bin.",
                  order = 1
               },
               binLabel = {
                  type = "toggle",
                  width = "full",
                  name = "Show label for the ButtonBin icon ",
                  order = 50,
                  disabled = "DisableBinLabelOption",
               },
            },
         },
         general = {
            type = "group",
            name = "General",
            args = {
               hideEmpty = {
                  type = "toggle",
                  name = "Hide blocks without icons",
                  desc = "This will hide all addons that lack icons instead of showing an empty space.",
                  width = "full",
                  order = 10,
               },
               hideTooltips = {
                  type = "toggle",
                  name = "Hide tooltips",
                  desc = "Don't show the mouseover tooltips for any blocks in this bin, unless overriden by the block level configuration.",
                  width = "full",
                  order = 10,
               },
               moveFrames = {
                  type = "toggle",
                  name = "Move Blizzard frames",
                  desc = "When enabled, default Blizzard frames such as the minimap, buff frame etc will be moved to make room for this bin. This is useful if you want your bin to sit at the top or bottom of the frame without overlapping Blizzard frames..",
                  width = "full",
                  order = 10,
               },
               clampToScreen = {
                  type = "toggle",
                  name = "Clamp to screen",
                  desc = "Prevent the bin to be moved outside the boundaries of the screen.",
                  width = "full",
                  order = 10,
               },
               hidden = {
                  type = "toggle",
                  name = "Hide button bin",
                  width = "full",
                  desc = "Hide or show this bin.",
                  order = 20,
               },
               hideIcons = {
                  width = "full",
                  type = "toggle",
                  name = "Hide all icons",
                  desc = "Hide the icons of all datablocks in this bin. Note that datablocks without a label will be invisible if this is enabled.",
                  order = 31,
                  disabled = "DisableLabelOption",
               },
               headerVisibility = {
                  type = "header",
                  name = "Visibility",
                  order = 100,
               },
               visibility = {
                  type = "select",
                  name = "Bin visibility",
                  values = {
                     always = "Always visible",
                     mouse = "Show on mouseover",
                     inCombat = "Show only in combat",
                     noCombat = "Hide during combat",
                     mouseNoCombat = "Mouseover, not combat",
                  },
                  order = 110,
               },
               hideTimeout = {
                  type = "range",
                  name = "Seconds until hidden",
                  desc = "Wait this many seconds until hiding the bin after the condition is met (in combat etc).",
                  disabled = "DisableHideOption",
                  min = 0, max = 15, step = 0.1,
                  order = 120,
               },

            }
         },
         colors = {
            type = "group",
            name = "Text Colors",
            set = "SetColorOpt",
            get = "GetColorOpt",
            args = {
               labelColor = {
                  type = "color",
                  name = "Label color",
                  hasAlpha = false,
               },
               textColor = {
                  type = "color",
                  name = "Text color",
                  hasAlpha = false,
               },
               unitColor = {
                  type = "color",
                  name = "Unit color",
                  hasAlpha = false,
               },
               valueColor = {
                  type = "color",
                  name = "Value color",
                  hasAlpha = false,
               },
            }
         },
         labels = {
            type = "group",
            name = "Text Labels",
            args = {
               hideAllText = {
                  width = "full",
                  type = "toggle",
                  name = "Hide all text",
                  desc = "Hide all text, showing only the icons.",
                  order = 40,
               },
               labelOnMouse = {
                  width = "full",
                  type = "toggle",
                  name = "Show text only on mouse over",
                  desc = "Don't show any datablock text unless the cursor is hovering over it.",
                  order = 80,
                  disabled = "DisableLabelOption",
               },
               hideLabel = {
                  width = "full",
                  type = "toggle",
                  name = "Hide labels",
                  desc = "Hide the data block labels.",
                  order = 70,
                  disabled = "DisableLabelOption",
               },
               hideText = {
                  width = "full",
                  type = "toggle",
                  name = "Hide text",
                  desc = "Hide the data block text.",
                  order = 70,
                  disabled = "DisableLabelOption",
               },
               hideValue = {
                  width = "full",
                  type = "toggle",
                  name = "Hide values",
                  desc = "Hide the data block values.",
                  order = 70,
                  disabled = "DisableLabelOption",
               },
            },
         },
         lookandfeel = {
            type = "group",
            name = "Look & Feel",
            args = {
               background= {
                  type = 'select',
                  dialogControl = 'LSM30_Background',
                  name = 'Background texture',
                  desc = 'The background texture used for the bin.',
                  order = 20,
                  values = {} --AceGUIWidgetLSMlists.background,
               },
               border = {
                  type = 'select',
                  dialogControl = 'LSM30_Border',
                  name = 'Border texture',
                  desc = 'The border texture used for the bin.',
                  order = 40,
                  values = {} --AceGUIWidgetLSMlists.border,
               },
               backgroundColor = {
                  type = "color",
                  name = "Background color",
                  hasAlpha = true,
                  set = "SetColorOpt",
                  get = "GetColorOpt",
                  order = 30,
               },
               borderColor = {
                  type = "color",
                  name = "Border color",
                  hasAlpha = true,
                  set = "SetColorOpt",
                  get = "GetColorOpt",
                  order = 50,
               },
               edgeSize = {
                  type = "range",
                  name = "Edge size",
                  desc = "Width of the border.",
                  min = 1, max = 50, step = 0.1,
               },
               font = {
                  type = 'select',
                  dialogControl = 'LSM30_Font',
                  name = 'Font',
                  desc = 'Font used on the bars',
                  values =  {}, --AceGUIWidgetLSMlists.font,
		  order = 1,
               },
               fontsize = {
                  order = 1,
                  type = "range",
                  name = "Font size",
                  min = 1, max = 30, step = 1,
                  order = 2
               },
            },
         },
         orientation = {
            type = "group",
            name = "Orientation",
            args = {
               flipx = {
                  type = "toggle",
                  name = "Flip x-axis",
                  desc = "If toggled, the buttons will expand to the left instead of to the right.",
                  order = 90,
               },
               flipy = {
                  type = "toggle",
                  name = "Flip y-axis",
                  desc = "If toggled, the buttons will expand upwards instead of downwards.",
                  order = 100,
               },
               flipicons = {
                  type = "toggle",
                  name = "Icons on the right",
                  desc = "If checked, icons will be placed to the right of the label.",
                  order = 110,
               },
               center = {
                  type = "toggle",
                  name = "Center alignment",
                  desc = "All rows will be center aligned in the bin.",
                  order = 120,
               }
            }
         },
         spacing = {
            type = "group",
            name = "Sizing",
            args = {
               useGlobal = {
                  type = "toggle",
                  name = "Use global settings",
                  desc = "Use global settings for scale, button size and padding.",
                  order = 1,
               },
               resetFromGlobal = {
                  type = "execute",
                  name = "Copy global settings",
                  desc = "Copy parameters from the global Button Bin settings. This will override the bin specific settings.",
                  func = "CopyGlobalSettings",
                  disabled = "UsingGlobalScale",
                  order = 2,
               },
               hpadding = {
                  type = "range",
                  name = "Horizontal padding",
                  desc = "Horizontal space between each datablock.",
                  width = "full",
                  hidden = "UsingGlobalScale",
                  min = 0, max = 50, step = 0.1,
                  order = 130,
               },
               vpadding = {
                  type = "range",
                  hidden = "UsingGlobalScale",
                  name = "Vertical padding",
                  desc = "Space between datablock rows.",
                  width = "full",
                  min = 0, max = 50, step = 0.1,
                  order = 140,
               },
               size = {
                  type = "range",
                  name = "Icon size",
                  hidden = "UsingGlobalScale",
                  desc = "Icon size in pixels.",
                  width = "full",
                  min = 5, max = 50, step = 1,
                  order = 160,
               },
               scale = {
                  type = "range",
                  hidden = "UsingGlobalScale",
                  name = "Bin scale",
                  desc = "Relative scale of the bin and all contents.",
                  width = "full",
                  min = 0.01, max = 5, step = 0.01,
                  order = 170,
               },
               width = {
                  type = "range",
                  name = "Max blocks per row",
                  desc = "Maximum number of blocks to place per row. Note that regardless of this setting, you will never get a bin wider than the absolute width specified.",
                  width = "full",
                  min = 1, max = 200, step = 1,
                  order = 180,
               },
               pixelwidth = {
                  type = "range",
                  name = "Bin width",
                  desc = "Width of the bin. If zero, the width is dynamically determined by the max blocks setting. If non-zero the row will wrap to avoid going beyond this width. Note that at minimum of one block always be placed on each row so for very small values, the bin might be wider than this setting.",
                  width = "full",
                  min = 0, max = 4000, step = 1,
                  order = 180,
               },
               tooltipScale = {
                  type = "range",
                  name = "Tooltip Scale",
                  desc = "The scale of the tooltips for the datablocks in this bin.",
                  width="full",
                  min = 0.1, max = 5, step = 0.05,
                  disabled = "UsingGlobalScale",
                  order = 190,
               },
            }
         }
      }
   },
   objconfig = {
      name = "Data Object Configuration",
      type = "group",
      args = {
         help = {
            type = "description",
            name = "There are currently no bins configured. Please add a bin before configuring the data blocks.\n\n",
            order = 0,
            hidden = function() return bins[1] end,
         },
      }
   },
   cmdline = {
      name = "Command Line",
      type = "group",
      args = {
         config = {
            type = "execute",
            name = "Show configuration dialog",
            func = function() mod:ToggleConfigDialog() end,
            dialogHidden = true
         },
         toggle = {
            type = "execute",
            name = "Toggle the frame lock",
            func = function() mod:ToggleLocked() end,
            dialogHidden = true
         },
      }
   }
}


function ButtonBin:OptReg(optname, tbl, dispname, cmd)
   if dispname then
      optname = "ButtonBin"..optname
      LibStub("AceConfig-3.0"):RegisterOptionsTable(optname, tbl, cmd)
      if not cmd then
         return LibStub("AceConfigDialog-3.0"):AddToBlizOptions(optname, dispname, "Button Bin")
      end
   else
      LibStub("AceConfig-3.0"):RegisterOptionsTable(optname, tbl, cmd)
      if not cmd then
         return LibStub("AceConfigDialog-3.0"):AddToBlizOptions(optname, "Button Bin")
      end
   end
end

function ButtonBin:SetDataBlockOption(info, val)
   local var  = info[#info]
   local name = options.objconfig.args[info[#info - 1]].desc

   if var == "bin" and val ~= db.enabledDataObjects[name][var] then
      -- Moving this to another bin
      local oldBin = db.enabledDataObjects[name][var]
      buttonFrames[name]:SetParent(bins[val])
      local oldBinButtons = {}
      for _,bname in ipairs(db.bins[oldBin].sortedButtons) do
         if bname ~= name then
            oldBinButtons[#oldBinButtons+1] = bname
         end
      end
      db.bins[oldBin].sortedButtons = oldBinButtons
      db.bins[val].sortedButtons[#db.bins[val].sortedButtons+1] = name
      mod:SortFrames(bins[oldBin])
      mod:SortFrames(bins[val])
   end

   db.enabledDataObjects[name][var] = val

   if buttonFrames[name] then
      mod:UpdateBlock(name)
      buttonFrames[name]:resizeWindow(true)
   end
   if var == "enabled" then
      if val then
         mod:LibDataChron_DataObjectCreated("config", name,
					    LDC:GetDataObjectByName(name))
      else
         mod:DisableDataObject(name)
      end
   end
   mod:SetupDataBlockOptions(true)
end

function ButtonBin:GetDataBlockOption(info)
   local var  = info[#info]
   local name = options.objconfig.args[info[#info - 1]].desc
   return db.enabledDataObjects[name][var]
end

function ButtonBin:HideOverrideConfig(info)
   local name = options.objconfig.args[info[#info - 1]].desc
   return not db.enabledDataObjects[name].enabled
end

function ButtonBin:HideDataBlockOptions(info)
   local name = options.objconfig.args[info[#info - 1]].desc
   return not db.enabledDataObjects[name].blockOverride or
      mod:HideOverrideConfig(info)
end

function ButtonBin:GetOption(info)
   return db[info[#info]]
end

function ButtonBin:SetOption(info, val)
   local var = info[#info]
   db[var] = val
   for _,bin in pairs(bins) do
      mod:ReloadFrame(bin)
   end
end

local barFrameMT = {__index = GeminiGUI:Create({}):GetInstance().__index }
local binMetaTable =  setmetatable({}, barFrameMT)
ButtonBin.binMetaTable = binMetaTable
ButtonBin.binMetaTable_mt = {__index = binMetaTable }


function binMetaTable:FixBackdrop()
   local bdb = db.bins[self.binId]
   self.bin:SetBGColor(ApolloColor.new(unpack(bdb.colors.backgroundColor)))
   
   if false then 
      local bgFrame = self:GetBackdrop()
      if not bgFrame then
	 bgFrame = {
	    insets = {left = 1, right = 1, top = 1, bottom = 1}
	 }
      end
      
      local edge = 0
      if bdb.border ~= "None" then
	 edge = bdb.edgeSize
      end
      bgFrame.edgeSize = edge
      edge = edge / 4
      bgFrame.insets.left   = edge
      bgFrame.insets.right  = edge
      bgFrame.insets.top    = edge
      bgFrame.insets.bottom = edge
      
      
      bgFrame.edgeFile = media:Fetch("border", bdb.border)
      bgFrame.bgFile = media:Fetch("background", bdb.background)
      self:SetBackdrop(bgFrame)
      self:SetBackdropColor(unpack(bdb.colors.backgroundColor))
      self:SetBackdropBorderColor(unpack(bdb.colors.borderColor))
   end
end

local function ShowOrHideOnMouseover(self, bdb, force)
   self:Show()
   if not self._isMouseOver and not force then
      self:SetAlpha(0.0)
      for _,name in ipairs(bdb.sortedButtons) do
         if buttonFrames[name] then
            buttonFrames[name]:Hide()
         end
      end
   else
      if not bdb.hideBinIcon and self.button then self.button:resizeWindow() end
      if not bdb.collapsed or force then
         for _,name in ipairs(bdb.sortedButtons) do
            if buttonFrames[name] then
               buttonFrames[name]:resizeWindow()
            end
         end
      end
   end
end

function binMetaTable:OnMouseEnter()
--n   self._isMouseOver = true
--   self:ShowOrHide(nil, true)
end

function binMetaTable:OnMouseLeave()
--   self._isMouseOver = nil
--   self:ShowOrHide(true) 
end

function binMetaTable:LDC_OnMouseEnter()
   local obj = self.obj
   local bin = self:GetParent()
   local bdb = mod:GetBinSettings(bin)
   local hideTooltip = mod:DataBlockConfig(self.name, "hideTooltip", bdb.hideTooltips)
   if not hideTooltip then
      if obj.tooltip then
	 PrepareTooltip(obj.tooltip, self)
	 obj.tooltip:Show()
	 if obj.tooltiptext then
	    obj.tooltip:SetText(obj.tooltiptext)
	 end
      elseif obj.OnTooltipShow then
	 PrepareTooltip(GameTooltip, self, true)
	 obj.OnTooltipShow(GameTooltip)
	 GameTooltip:Show()
      elseif obj.tooltiptext then
	 PrepareTooltip(GameTooltip, self, true)
	 GameTooltip:SetText(obj.tooltiptext)
	 GameTooltip:Show()
      elseif self.buttonBinText and not obj.OnEnter then
	 PrepareTooltip(GameTooltip, self, true)
	 GameTooltip:SetText(self.buttonBinText)
	 GameTooltip:Show()
	 self.hideTooltipOnLeave = true
      end
      if obj.OnEnter then
	 obj.OnEnter(self)
      end
   end
   self._isMouseOver = true
   self:resizeWindow()
   bin._isMouseOver = true
   bin:ShowOrHide()
end

function binMetaTable:LDC_OnMouseLeave()
   local obj = self.obj
   local bin = self:GetParent()
   self._isMouseOver = nil
   bin._isMouseOver = nil
   bin:ShowOrHide(true)
   self:resizeWindow()
   if not obj then return end
   if mod:MouseIsOver(GameTooltip) and (obj.tooltiptext or obj.OnTooltipShow)
   then
      return
   end

   if self.hideTooltipOnLeave or obj.tooltiptext or obj.OnTooltipShow then
      GT_OnLeave(GameTooltip)
      self.hideTooltipOnLeave = nil
   end
   if obj.OnLeave then
      obj.OnLeave(self)
   end
end



function binMetaTable:ShowOrHide(timer, onenter)
   local bdb = db.bins[self.binId]
   local forceShow = false
   if timer and bdb.hideTimeout > 0 and bdb.visibility ~= "always" then
      if binTimers[self.binId] then
         mod:CancelTimer(binTimers[self.binId], true)
      end
      binTimers[self.binId] = mod:ScheduleTimer(binMetaTable.ShowOrHide, bdb.hideTimeout, self)
   else
      self:SetAlpha(1.0)
      if unlockButtons or unlockFrames then
         self:Show()
         forceShow = true
      elseif bdb.hidden then
         self:Hide()
      elseif bdb.visibility == "noCombat" then
         if playerInCombat then
            self:Hide()
         else
            self:Show()
            forceShow = true
         end
      elseif bdb.visibility == "inCombat" then
         if playerInCombat then
            forceShow = true
            self:Show()
         else
            self:Hide()
         end
      elseif bdb.visibility == "mouse" then
         ShowOrHideOnMouseover(self, bdb)
      elseif bdb.visibility == "mouseNoCombat" then
         if playerInCombat then
            self:Hide()
         else
            ShowOrHideOnMouseover(self, bdb)
         end
      else
         self:Show()
         forceShow = true
      end
   end
   if forceShow and not bdb.collapsed then
      ShowOrHideOnMouseover(self, bdb, true)
   end
   if onenter and self:IsVisible() and self:GetAlpha() > 0 then
      mod:SortFrames(self)
   end
   --   mod:LoadPosition(self) -- this will make sure hiding / showing works as expected
   binTimers[self.binId] = nil
end

function binMetaTable:SetColorOpt(arg, r, g, b, a)
   local bdb = db.bins[self.binId]
   local color = arg[#arg]
   bdb.colors[color][1] = r
   bdb.colors[color][2] = g
   bdb.colors[color][3] = b
   bdb.colors[color][4] = a
   self:FixBackdrop()
   mod:UpdateAllBlocks(self)
end

function binMetaTable:GetColorOpt(arg)
   local bdb = db.bins[self.binId]
   local color = arg[#arg]
   return unpack(bdb.colors[color])
end

function binMetaTable:DisableBinIconOptions(info)
   return db.bins[self.binId].hideBinIcon
end

function binMetaTable:DisableLabelOption(info)
   local bdb = db.bins[self.binId]
   return bdb.hideAllText
end

function binMetaTable:DisableHideIconOption(info)
   local bdb = db.bins[self.binId]
   return bdb.hideAllText or bdb.labelOnMouse
end

function binMetaTable:DisableBinLabelOption(info)
   local bdb = db.bins[self.binId]
   return bdb.hideAllText or bdb.hideBinIcon
end

function binMetaTable:DisableHideOption(info)
   local bdb = db.bins[self.binId]
   return bdb.visibility == "always"
end

function binMetaTable:UsingGlobalScale(info)
   local bdb = db.bins[self.binId]
   return bdb.useGlobal
end

function binMetaTable:DeleteBin(info)
   local bdb = db.bins[self.binId]
   self.disabled = true
   -- Disabled all datablocks in this bin
   for id, button in pairs(bdb.sortedButtons) do
      mod:DisableDataObject(button)
      db.enabledDataObjects[button].bin = 1 -- default to be added to bin 1
   end

   -- This makes sure to "move" objects to a lower bin
   for id, data in pairs(db.enabledDataObjects) do
      if data.bin and data.bin > self.binId then
         data.bin = data.bin - 1
      end
   end
   -- We're shifting bins down one
   for id = self.binId+1,#db.bins do
      local bdb = db.bins[id]
      local sdb
      if bdb.useGlobal then sdb = db else sdb = bdb end
      local destBinID = id - 1
      db.bins[destBinID] = db.bins[id]
      local f = bins[id]
      bins[destBinID] = f
      if f then
         f.binId = destBinID
         if bdb.binLabel then
            f.button.buttonBinText = "Bin #"..destBinID
         end
      end
   end
   mod:ReleaseBinFrame(self, true)
   -- remove the last one
   db.bins[#db.bins] = nil
   bins[#bins]= nil
   mod:SetupBinOptions(true)
end

function binMetaTable:GetOption(info)
   local bdb = db.bins[self.binId]
   local var = info[#info]
   return bdb[var]
end

function binMetaTable:SetOption(info, val)
   local bdb = db.bins[self.binId]
   local var = info[#info]

   bdb[var] = val
   if var == "scale" then
      self:SetScale(val)
      self.mover:SetScale(self:GetScale())
   elseif var == "hidden" or var == "visibility" then
      self:ShowOrHide()
   elseif var == "binLabel"  or var == "binName" or var == "binTexture" then
      mod:SetBinIconAndLabel(self, bdb)
      if not bdb.hideBinIcon then
         self.button:resizeWindow()
      end
      if var == "binName" then
         mod:SetupBinOptions(true) -- reload list of bins
      end
      return
   elseif var == "background" or var == "border" or var == "edgeSize"then
      self:FixBackdrop()
   elseif var == "clampToScreen" then
      self:SetClampedToScreen(val)
      self.mover:SetClampedToScreen(val)
   end
   mod:ReloadFrame(self)
end

do
   local params = { 'size', 'scale', 'hpadding', 'vpadding' }

   function binMetaTable:CopyGlobalSettings()
      local bdb = db.bins[self.binId]
      for _,param in ipairs(params) do
         bdb[param] = db[param]
      end
      mod:ReloadFrame(self)
   end
end

-- Proxy/compatibility methods
function binMetaTable:Show()
   if not self.bin:IsVisible() then
      self.bin:Show(true)
   end
end

function binMetaTable:Hide()
   self.bin:Show(false)
end

function binMetaTable:SetAlpha(alpha)
   self.bin:SetOpacity(alpha)
end

function binMetaTable:SetClampedToScreen(clamped)
   -- TODO
end

function binMetaTable:SetScale(scale)
   self.bin:SetScale(Scale or 1)
end

function binMetaTable:GetScale()
   return self.bin:GetScale()
end

function binMetaTable:SetWidth(width)
   left, top, right, bottom = self.bin:GetAnchorOffsets()
   self.bin:SetAnchorOffsets(left, top, left+width, bottom)
end

function binMetaTable:SetHeight(height)
   left, top, right, bottom = self.bin:GetAnchorOffsets()
   self.bin:SetAnchorOffsets(left, top, right, top + (height or 30))
end

function binMetaTable:GetHeight()
   self.bin:GetHeight()
end


function ButtonBin:SetupBinOptions(reload)
   for id, data in pairs(options.bins.args) do
      if data.type == "group" then
         options.bins.args[id] = nil
      end
   end
   for id, bdb in ipairs(db.bins) do
      local bin = {}
      for key,val in pairs(options.binConfig) do
         bin[key] = val
      end
      if bdb.binName then
         bin.name = bdb.binName
      else
         bin.name = bin.name .. id
      end
      bin.handler = bins[id]
      options.bins.args[tostring(id)] = bin
   end
   if reload then
      if R then R:NotifyChange("Button Bin: Bins") end
   else
      mod.binopts = mod:OptReg(": Bins", options.bins, "Bins")
   end
end

do
   local updateOnce  = { value=true, suffix=true, label=true, text=true }
   function ButtonBin:UpdateBlock(name, frame, delay)
      frame = frame or buttonFrames[name]
      local updated, uonce
      if frame then
         local obj = ldbObjects[name]
         for key, func in pairs(updaters) do
            uonce = updateOnce[key]
            if not uonce or not updated then
               func(frame, obj[key], name, obj, delay)
            end
            updated = uonce or updated
         end
      end
   end
end

function ButtonBin:UpdateAllBlocks(name, parent)
   for name,frame in pairs(buttonFrames) do
      if not parent or  frame:GetParent() == parent then
         mod:UpdateBlock(name, frame)
      end
   end
end

local disabled = "|cff999999%s|r"
local override = "|cffffff00%s|r"
--local enabled = "|cff00cf00%s|r"

function ButtonBin:SetupDataBlockOptions(reload)

   local conf = options.objconfig.args
   local counter = 1

   local used = {}
   if reload then
      for id,data in pairs(conf) do
         if data.desc then
            used[data.desc] = data
            conf[id] = nil
         end
      end
   end

   -- sort by name
   local sorted = {}
   for name in pairs(db.enabledDataObjects) do
      sorted[#sorted+1] = name
   end
   tsort(sorted)

   --
   for _,name in ipairs(sorted) do
      local data = db.enabledDataObjects[name]
      if LDC:GetDataObjectByName(name) then
         local obj = used[name]
         if not obj then
            obj = {}
            for key, val in pairs(options.dataBlock) do
               obj[key] = val
            end
         end
         if data.enabled then
            if db.enabledDataObjects[name].blockOverride then
               obj.name = override:format(name)
            else
               obj.name = name
            end
         else
            obj.name = disabled:format(name)
         end
         obj.desc = name
         obj.order = counter
         conf[tostring(counter)] = obj
         counter = counter + 1
      end
   end

   if reload then
      if R then R:NotifyChange("Button Bin: Datablock Configuration") end
   else
      mod:OptReg(": Datablock Config", options.objconfig, "Datablock Configuration")
   end
end

function ButtonBin:SetupOptions()
   if false then
      options.profile = DBOpt:GetOptionsTable(self.db)
      mod.main = mod:OptReg("Button Bin", options.global)
      mod:SetupBinOptions()
      mod:SetupDataBlockOptions()
      mod.profile = mod:OptReg(": Profiles", options.profile, "Profiles")
      mod:OptReg("Button Bin CmdLine", options.cmdline, nil,  { "buttonbin", "bin" })
   end
   
end

function ButtonBin:ToggleConfigDialog(frame)
   InterfaceOptionsFrame_OpenToCategory(mod.profile)
   InterfaceOptionsFrame_OpenToCategory(mod.main)
end

function ButtonBin:ToggleCollapsed(frame)
   local bdb
   local bin = frame:GetParent()
   bdb = db.bins[bin.binId]
   bdb.collapsed = not bdb.collapsed
   bin._isMouseOver = true
   mod:SortFrames(bin)
end

function ButtonBin:GetBinSettings(bin)
   local bdb = db.bins[bin.binId]
   if bdb.useGlobal then
      return bdb, db
   else
      return bdb, bdb
   end
end

function ButtonBin:SortFrames(bin)
   if not bin or bin.disabled then return end
   local bdb,sdb = mod:GetBinSettings(bin)
   local sizeOptions
   local xoffset = 0
   local width = 0
   local height = 0
   local sorted = bdb.sortedButtons
   local frame
   local addBin = false
   if not bdb.hideBinIcon and bdb.collapsed
   and not (unlockButtons or unlockFrames) then
      for id,name in pairs(sorted) do
         if buttonFrames[name] then
            buttonFrames[name]:Show(false)
         end
      end
      sorted = {}
   end
   if sdb.scale ~= bin:GetScale() then
      bin:SetScale(sdb.scale)
   end
   bin:SetWidth(bdb.pixelWidth or sdb.pixelWidth or Apollo.GetScreenSize())
   bin:SetHeight(sdb.size + (sdb.vpadding or 0))

   bin:ShowOrHide()
   bin.left:ArrangeChildrenHorz(0)
   bin.center:ArrangeChildrenHorz(1)
   bin.right:ArrangeChildrenHorz(2)
end

function ButtonBin:OldSortFramesCont()      
   local count = 1
   local previousFrame

   local anchor, xmulti, ymulti, otheranchor
   
   if bdb.flipy then ymulti = 1 anchor = "BOTTOM" otheranchor = "BOTTOM"
   else ymulti = -1 anchor = "TOP" otheranchor = "TOP" end

   if bdb.flipx then
      anchor = anchor .. "RIGHT"
      otheranchor = otheranchor.. "LEFT"
      xmulti = -1
   else
      otheranchor = otheranchor .. "RIGHT"
      anchor = anchor .. "LEFT"
      xmulti = 1
   end
   local inset = 0
   if bdb.border ~= "None" then
      inset = bdb.edgeSize / 2
   end

   local hpadding = (sdb.hpadding or 0)
   local vpadding = (sdb.size + (sdb.vpadding or 0))
   local frameAlign = {}
   if not bdb.hideBinIcon then
      previousFrame = bin.button
      previousFrame:resizeWindow()
      previousFrame:ClearAllPoints()
      previousFrame:SetPoint(anchor, bin, anchor, xmulti*inset, ymulti*inset)
      width = previousFrame:GetWidth() + inset
      height = vpadding + inset
      if bdb.width > 1 then
         xoffset = hpadding + width
         count = 2
         frameAlign[1] = { frame = previousFrame, width = xoffset, ypos = ymulti*inset }
      else
         previousFrame = nil
      end
   else
      if bin.button then
	 bin.button:ClearAllPoints()
	 bin.button:Hide()
      end
      width = inset
      height = inset
   end
   local lineWidth = 0
   for _,name in ipairs(sorted) do
      frame = buttonFrames[name]
      if frame then
         frame:ClearAllPoints()
         if (not bdb.hideEmpty or frame._has_texture) then
            frame:resizeWindow()
            local fwidth = frame:GetWidth()
            xoffset = xoffset + hpadding + fwidth
            if (bdb.width > 1 and bdb.pixelwidth > 0
		   and xoffset > bdb.pixelwidth )
	    or count > bdb.width then
               previousFrame = nil
               xoffset = hpadding + fwidth
               count = 1
            else
               lineWidth = xoffset
            end
            count = count + 1
            if xoffset > width then width =  xoffset end
            if previousFrame then
               frame:SetPoint(anchor, previousFrame, otheranchor, xmulti*hpadding, 0)
            else
               height = height + vpadding
               local ypos = ymulti*(height-vpadding)
               if bdb.center then
                  local frameCount = #frameAlign
                  if frameCount > 0 then
                     frameAlign[frameCount].width = lineWidth
                  end
                  frameAlign[frameCount+1] = { frame = frame, width = xoffset, ypos = ypos }
               end
               frame:SetPoint(anchor, bin, anchor, xmulti*inset, ypos)
            end
            previousFrame = frame
         else
            frame:Hide()
         end
      end
   end

   if #frameAlign > 0 then
      frameAlign[#frameAlign].width = xoffset
   end

   if bdb.pixelwidth > width then
      width = bdb.pixelwidth
   end
   if bdb.center then
      for id,framedata in ipairs(frameAlign) do
         if framedata.width ~= width then
            framedata.frame:ClearAllPoints()
            framedata.frame:SetPoint(anchor, bin, anchor, xmulti*(inset+(width-framedata.width)/2), framedata.ypos)
         end
      end
   end
   bin:SetWidth(width + inset)
   bin:SetHeight(height + inset)
   --   bin.mover:SetWidth(bin:GetWidth())
   --   bin.mover:SetHeight(bin:GetHeight())
   bin:ShowOrHide()
end


do
   local unusedFrames = {}
   local numBlocks = 1
   local oldSorted

   local function Button_OnDragStart(self)
      local toRemove
      local bin = self:GetParent()
      local bdb = db.bins[bin.binId]
      local newSorted = {}
      for id, name in pairs(bdb.sortedButtons) do
         if name ~= self.name then
            newSorted[#newSorted+1] = name
         end
      end
      oldSorted = bdb.sortedButtons
      bdb.sortedButtons = newSorted
      mod:SortFrames(bin)
      self:ClearAllPoints()
      self:StartMoving()
      self:SetAlpha(0.75)
      self:SetFrameLevel(100)
   end

   local function Button_OnDragStop(self)
      local bin = self:GetParent()
      local bdb = db.bins[bin.binId]
      local destFrame, destParent
      self:StopMovingOrSizing()
      self:SetFrameLevel(98)
      self:SetAlpha(1.0)
      for id,frame in ipairs(bins) do
         if mod:MouseIsOver(frame.button) then
            destFrame = frame.button
            destParent = frame
         end
      end

      if not destFrame then
         for name,frame in pairs(buttonFrames) do
            if mod:MouseIsOver(frame) and frame ~= self then
               destFrame = frame
               destParent = frame:GetParent()
               break
            end
         end
      end
      if destFrame and destParent then
         if destParent ~= bin then
            --         mod:Print("Changing parent from "..bin.binId.." to "..destParent.binId)
            self.db.bin = destParent.binId
            self:SetParent(destParent)
            bdb = db.bins[destParent.binId]
         end
         local inserted
         if destParent.button == destFrame then
            tinsert(bdb.sortedButtons, 1, self.name)
            inserted = true
         else
            local x, midpoint
            local add = 0
            if bdb.width > 1 then
               x = GetCursorPosition()
               midpoint = (destFrame:GetLeft() + destFrame:GetWidth()/2)*destParent:GetEffectiveScale()
               if bdb.flipx then
                  if x < midpoint then add = 1 end
               else
                  if x > midpoint then add = 1 end
               end
            else
               x = select(2, GetCursorPosition())
               midpoint = (destFrame:GetBottom() + destFrame:GetHeight()/2)*destParent:GetEffectiveScale()
               if bdb.flipy then
                  if x > midpoint then add = 1 end
               else
                  if x < midpoint then add = 1 end
               end
            end

            --         mod:Print("x = "..x..", mid = "..midpoint.."...")
            for id,n in pairs(bdb.sortedButtons) do
               if destFrame.name == n then
                  id = id + add
                  if id < 1 then id = 1 end
                  if id > (#bdb.sortedButtons+1) then id = id - 1 end
                  tinsert(bdb.sortedButtons, id, self.name)
                  inserted = true
                  break
               end
            end
         end
         if inserted then
            oldSorted = nil
            mod:SortFrames(destParent)
            return
         end
      end
      -- no valid destination, roll state back
      bdb.sortedButtons = oldSorted
      self:SetParent(bin)
      mod:SortFrames(bin)
   end

   function ButtonBin:DataBlockConfig(name, var, global)
      local bcfg = db.enabledDataObjects[name]
      if not bcfg or not bcfg.blockOverride then
         if type(global) == "table" then
            return global[var]
         else
            return global
         end
      end
      return bcfg[var]
   end

   local function Frame_ResizeWindow(self, dontShow)
      local parent = bins[self.db.bin]
      local bdb,sdb,dbs = mod:GetBinSettings(parent)
      local iconWidth, width
      local hideIcon = mod:DataBlockConfig(self.name, "hideIcon", bdb.hideIcons)
      local label = self.buttonBinText or self.plainText
      local showLabel = label ~= ""
      if parent.bin:GetOpacity() < 1.0 then
         self.label:Hide()
         return
      end

      local iconPoints = {}
      local textPoints  = {}
      if self.name ~= "ButtonBin" and hideIcon and showLabel  and not bdb.labelOnMouse then
	 self.icon:Show(false)
         iconWidth = 0
      else
         iconWidth = sdb.size+2
         self.icon:Show(true);
--         if bdb.flipicons then
--            self.icon:SetPoint("RIGHT", self)
--            self.label:SetPoint("RIGHT", self.icon, "LEFT", -2, 0)
--         else
--            self.icon:SetPoint("LEFT", self)
--            self.label:SetPoint(L"EFT", self.icon, "RIGHT", 2, 0)
--         end
	 self.icon:SetAnchorOffsets(2, 0, sdb.size+2, sdb.size)
      end

      if not dontShow then self.wnd:Show(true) end

      if showLabel and (not bdb.labelOnMouse or self._isMouseOver) then
         if bdb.font and bdb.fontsize then
--            self.label:SetFont(media:Fetch("font", bdb.font), bdb.fontsize)
         end
	 if self.buttonBinText then
	    self.label:SetAML(self.buttonBinText)
	 else
	    self.label:SetText(self.plainText)
	 end

	 log:info("Setting text to  "..label)
	 width = Apollo.GetTextWidth(self.label:GetData(), self.plainText or self.label:GetText())
	 log:info("Setting text to  "..label.." with width "..width)
         if width > 0 then
            self.label:Show(true)
            if iconWidth > 0 then
               width = width + iconWidth + 6
            else
               width = width + 3
            end
         else
            width = iconWidth
         end
	 self.label:SetAnchorOffsets(iconWidth+3, 0, iconWidth+width, sdb.size)
      else
         self.label:SetText("")
         self.label:Show(false)
         width = iconWidth
      end
      if bdb.labelOnMouse and showLabel then
--         local oldWidth = self.:GetWidth(self)
--         if oldWidth > 0 and  oldWidth ~= width then
--            parent:SetWidth(parent:GetWidth() - oldWidth + width)
--         end
      end
      log:info("Total width ended up at "..width)
      self.wnd:SetAnchorOffsets(0, 0, width+2, sdb.size)
   end

   function ButtonBin:GetFrame(callback, parent)
      local frame = {}
      callback = callback or frame
      frame.wnd = GeminiGUI:Create(ButtonBin.binButtonTemplate):GetInstance(callback, parent)
      frame.wnd:IsMouseTarget(true)
      frame.icon = frame.wnd:FindChild("Icon")
      frame.label = frame.wnd:FindChild("Text")
      frame.label:SetData("CRB_Header12")

      --      frame:RegisterForClicks("AnyUp")
      frame.resizeWindow = Frame_ResizeWindow
	 --frmae:SetScript("OnDragStart", Button_OnDragStart)
--         frame:SetScript("OnDragStop", Button_OnDragStop)

         numBlocks = numBlocks + 1
      return frame
   end

   function ButtonBin:ReleaseFrame(frame)
      local bin = frame:GetParent()
--      mod:Print("Releasing button frame ", frame.name)
      buttonFrames[frame.name] = nil
      unusedFrames[#unusedFrames+1] = frame
      frame:Hide()
      frame:SetParent(nil)
      frame.buttonBinText = nil
      frame.db = nil
      frame.name = nil
      frame.obj = nil
      frame._has_texture = nil
      frame:SetScript("OnEnter", nil)
      frame:SetScript("OnLeave", nil)
      frame:SetScript("OnClick", nil)
      frame:SetScript("OnReceiveDrag", nil)
      if bin and not bin.disabled then self:SortFrames(bin) end
   end
end

do
   local unusedBinFrames = {}
   local numBinFrames = 1
   local bgFrame = {
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 6,
      insets = {left = 1, right = 1, top = 1, bottom = 1}
   }
   function ButtonBin:ReleaseBinFrame(frame, noClear)
      frame.disabled = true
      for _,obj in pairs(buttonFrames) do
         if obj:GetParent() == frame then
            mod:ReleaseFrame(obj)
         end
      end
      unusedBinFrames[#unusedBinFrames+1] = frame
--      mod:Print("Released bin frame id ", frame.binId,  " at position #", #unusedBinFrames)
      if not noClear then
         bins[frame.binId] = nil
      end
      frame.button.db = nil
      frame.button.binId = nil
      frame.button.obj = nil
      frame.mover.text:Hide()
      frame.mover:Hide()
      frame:Hide()
   end

   function ButtonBin:GetBinFrame()
      local f = {}
      
      setmetatable(f, ButtonBin.binMetaTable_mt)
      local wnd = GeminiGUI:Create({
				      Sizable  = false,
				      Template = "CRB_TooltipSimple",
				      Border = false,
				      Picture = true,
				      UseTemplateBG = true,
				      Pixies = {
					 {
					    Sprite = "WhiteFill",
					    AnchorPoints  = "FILL",
					    AnchorOffsets = {0,0,0,0},
					    BGColor         = "7f000000",
					 },
				      },
				      Children = {
					 {
					    Name = "LeftContainer", 
					    AnchorPoints = "FILL",
					 },
					 {
					    Name = "RightContainer", 
					    AnchorPoints = "FILL",
					 },
					 {
					    Name = "CenterContainer", 
					    AnchorPoints = "FILL",
					 },
					 {
					    -- When this is visible, it's used to drag a bin around.
					    Name = "ButtonBinMover",
					    AnchorPoints = "FILL",
					    AnchorOffsets = {0,0,0,0},
					    NewWindowDepth = true, 
					    Pixies = {
					       Sprite = "WhiteFill",
					       AnchorPoints  = "FILL",
					       AnchorOffsets = {0,0,0,0},
					       BGColor = "ff00ff00",
					       Text          = "Click to stop moving",
					       Font          = "CRB_HeaderHuge",
					       TextColor     = "xkcdYellow",
					    }
					 }
				      }
					 
				   }):GetInstance(f)
      f.bin = wnd
      f.left = wnd:FindChild("LeftContainer")
      f.right = wnd:FindChild("RightContainer")
      f.center = wnd:FindChild("CenterContainer")
      wnd:SetData(f)
      wnd:IsMouseTarget(true)
      wnd:AddEventHandler("MouseEnter", "OnMouseEnter")
      wnd:AddEventHandler("MouseExit", "OnMouseLeave")

      f.mover = wnd:FindChild("ButtonBinMover")
      f.mover:IsMouseTarget(true)
      --      f.mover:RegisterForClicks("AnyUp")
--      f.mover:SetOpacity(0.5)
--      f.mover:AddEvent("OnDragStart",
--		       function(self) self:StartMoving()
--      end)
--      f.mover:AddEvent("OnDragStop",
--		       
--		       function(self)
--			  mod:SavePosition(f)
--			  self:StopMovingOrSizing() end)
--      f.mover:SetScript("OnClick",
--			function(frame,button)
--			   
--			   mod:ToggleLocked()
--      end)
--      
      f.button = self:GetFrame(f, f.left)
      --	 f.button:SetScript("OnClick", BB_OnClick)
      if not db.hideBinTooltip then
--	 f.button.wnd:AddEventHandler("MouseEnter", "LDC_OnMouseEnter")
--	 f.button.wnd:AddEventHandler("MouseExit", "LDC_OnMouseLeave")
      end
      f.mover:Show(false)

      return f
   end
   
end

function ButtonBin:MouseIsOver(frame)
   local x, y = GetCursorPosition();
   x = x / frame:GetEffectiveScale();
   y = y / frame:GetEffectiveScale();

   local left = frame:GetLeft();
   local right = frame:GetRight();
   local top = frame:GetTop();
   local bottom = frame:GetBottom();
   if not left then return nil end
   if ( (x > left and x < right) and (y > bottom and y < top) ) then
      return true
   end
end


ButtonBin.binButtonTemplate = {
   Name = "BinButton",
   TooltipType = "OnCursor", 
   Children = {
      {
	 Name = "Icon",
	 Picture = true, 
      },
      {
	 WidgetType = "MLWindow", 
	 Name = "Text",
	 DT_VCENTER = true,
	 DT_CENTER = true,
	 DT_SINGLELINE = true,
      }
   }
}
