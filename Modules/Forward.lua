local Postal = LibStub("AceAddon-3.0"):GetAddon("Postal")
local Postal_Forward = Postal:NewModule("Forward", "AceHook-3.0", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("Postal")
Postal_Forward.description = L["Allows you to forward the contents of a mail."]
Postal_Forward.description2 = L[ [[|cFFFFCC00*|r Feature is not supported for mail sent with money attached or sent COD.
|cFFFFCC00*|r Feature is not supported for mail sent with stackable items attached.
|cFFFFCC00*|r Forward button will be disabled in these cases.]] ]

local PostalForwardTable = {}
local PostalForwardBodyText = nil
local PostalForwardWaitingForSendInfo = false
local PostalForwardExpectedSendCount = nil

-- Forward has to wait for Blizzard's mail/bag item locks, but the old fixed
-- delays were intentionally conservative.  These shorter delays keep it safe
-- while making 12-attachment forwards much faster.
local POSTAL_FORWARD_INITIAL_DELAY = 0.03
local POSTAL_FORWARD_RETRY_DELAY = 0.02
local POSTAL_FORWARD_NEXT_DELAY = 0.01
local POSTAL_FORWARD_ATTACH_FALLBACK_DELAY = 0.12

local function Postal_Forward_GetForwardButton()
	return OpenMailForwardButton or PostalForwardButton
end

local function Postal_Forward_GetSendMailBodyEditBox()
	-- Blizzard has moved/renamed the send-mail body edit box across clients.
	if MailEditBox then
		if MailEditBox.ScrollBox and MailEditBox.ScrollBox.EditBox then
			return MailEditBox.ScrollBox.EditBox
		end
		if MailEditBox.EditBox then
			return MailEditBox.EditBox
		end
	end
	return SendMailBodyEditBox
end

local function Postal_Forward_SetSendMailBody(text)
	local bodyEditBox = Postal_Forward_GetSendMailBodyEditBox()
	if text and bodyEditBox then bodyEditBox:SetText(text) end
end

local function Postal_Forward_GetMaxBagID()
	local maxBagID = NUM_BAG_FRAMES or NUM_BAG_SLOTS or 4
	if Postal.WOWRetail and NUM_REAGENTBAG_FRAMES then
		maxBagID = maxBagID + NUM_REAGENTBAG_FRAMES
	end
	return maxBagID
end

local function Postal_Forward_GetMaxSendAttachments()
	local maxSend = tonumber(ATTACHMENTS_MAX_SEND) or 0
	if maxSend < 12 then maxSend = 12 end
	return maxSend
end

local function Postal_Forward_GetMaxReceiveAttachments()
	return tonumber(ATTACHMENTS_MAX_RECEIVE) or Postal_Forward_GetMaxSendAttachments()
end

local function Postal_Forward_GetContainerNumFreeSlots(bagID)
	if C_Container and C_Container.GetContainerNumFreeSlots then
		return C_Container.GetContainerNumFreeSlots(bagID)
	elseif GetContainerNumFreeSlots then
		return GetContainerNumFreeSlots(bagID)
	end
	return 0, 0
end

local function Postal_Forward_GetContainerFreeSlots(bagID)
	local slots
	if C_Container and C_Container.GetContainerFreeSlots then
		slots = C_Container.GetContainerFreeSlots(bagID)
	elseif GetContainerFreeSlots then
		slots = GetContainerFreeSlots(bagID)
	end
	if type(slots) ~= "table" then slots = {} end
	return slots
end

local function Postal_Forward_PickupContainerItem(bagID, slotID)
	if C_Container and C_Container.PickupContainerItem then
		C_Container.PickupContainerItem(bagID, slotID)
	elseif PickupContainerItem then
		PickupContainerItem(bagID, slotID)
	end
end

local function Postal_Forward_IsContainerItemLocked(bagID, slotID)
	if C_Container and C_Container.GetContainerItemInfo then
		local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
		return itemInfo and itemInfo.isLocked
	elseif GetContainerItemInfo then
		return select(3, GetContainerItemInfo(bagID, slotID))
	end
	return false
end

local function Postal_Forward_HasSendMailItem(slotID)
	if GetSendMailItemLink and GetSendMailItemLink(slotID) then
		return true
	end
	if HasSendMailItem and HasSendMailItem(slotID) then
		return true
	end
	if GetSendMailItem and GetSendMailItem(slotID) then
		return true
	end
	return false
end

local function Postal_Forward_SendMailAttachmentCount()
	local count = 0
	for slotID = 1, Postal_Forward_GetMaxSendAttachments() do
		if Postal_Forward_HasSendMailItem(slotID) then
			count = count + 1
		end
	end
	return count
end

local function Postal_Forward_GetNextEmptySendMailSlot()
	for slotID = 1, Postal_Forward_GetMaxSendAttachments() do
		if not Postal_Forward_HasSendMailItem(slotID) then
			return slotID
		end
	end
end

local function Postal_Forward_ClickSendMailItemButton(slotID)
	if ClickSendMailItemButton then
		ClickSendMailItemButton(slotID)
	elseif SendMailAttachmentButton_OnDropAny then
		SendMailAttachmentButton_OnDropAny()
	end
end

local function Postal_Forward_GetItemInfo(itemID)
	if C_Item and C_Item.GetItemInfo then
		return C_Item.GetItemInfo(itemID)
	elseif GetItemInfo then
		return GetItemInfo(itemID)
	end
end

local function Postal_Forward_GetInboxAttachmentInfo(messageIndex, attachmentIndex)
	local name, value2, value3, value4 = GetInboxItem(messageIndex, attachmentIndex)
	if not name then return nil end

	local itemID, count
	if type(value2) == "number" then
		-- Modern clients: name, itemID, texture, count, quality, canUse
		itemID = value2
		count = tonumber(value4) or 1
	else
		-- Older clients: name, texture, count, quality, canUse
		count = tonumber(value3) or 1
		local itemLink = GetInboxItemLink and GetInboxItemLink(messageIndex, attachmentIndex)
		itemID = itemLink and tonumber(itemLink:match("item:(%d+)"))
	end
	return name, itemID, count
end

local function Postal_Forward_InboxAttachmentCount(messageIndex)
	local count = 0
	if not messageIndex then return count end
	for i = 1, Postal_Forward_GetMaxReceiveAttachments() do
		if Postal_Forward_GetInboxAttachmentInfo(messageIndex, i) then
			count = count + 1
		end
	end
	return count
end

function Postal_Forward:Postal_Forward_ForwardMailItemsEvent(event,...)
	Postal_Forward_ForwardMailItems(2)
end

local function Postal_Forward_ContinueAfterAttach()
	if not PostalForwardWaitingForSendInfo then return end
	PostalForwardWaitingForSendInfo = false
	PostalForwardExpectedSendCount = nil
	Postal_Forward:UnregisterEvent("MAIL_SEND_INFO_UPDATE")
	if C_Timer then
		C_Timer.After(POSTAL_FORWARD_NEXT_DELAY, function() Postal_Forward_ForwardMailItems(1) end)
	else
		Postal_Forward_ForwardMailItems(1)
	end
end

local function Postal_Forward_CheckAttachComplete(attempts)
	if not PostalForwardWaitingForSendInfo then return end
	attempts = attempts or 0
	if SendMailFrame_Update then SendMailFrame_Update() end
	if PostalForwardExpectedSendCount and Postal_Forward_SendMailAttachmentCount() >= PostalForwardExpectedSendCount then
		Postal_Forward_ContinueAfterAttach()
		return
	end
	if C_Timer and attempts < 100 then
		C_Timer.After(POSTAL_FORWARD_RETRY_DELAY, function() Postal_Forward_CheckAttachComplete(attempts + 1) end)
	else
		PostalForwardWaitingForSendInfo = false
		PostalForwardExpectedSendCount = nil
		Postal_Forward:UnregisterEvent("MAIL_SEND_INFO_UPDATE")
		Postal_Forward_SetSendMailBody(PostalForwardBodyText)
		PostalForwardBodyText = nil
		if Postal.Print then Postal:Print("Forward stopped: outgoing attachment was not confirmed by the client.") end
	end
end

function Postal_Forward:Postal_Forward_ForwardMailAttachedEvent(event,...)
	Postal_Forward_CheckAttachComplete(0)
end

-- Create Forward button and hook OnClick event
function Postal_Forward:OnEnable()
	local forwardButton = Postal_Forward_GetForwardButton()
	if not forwardButton then
		forwardButton = CreateFrame("Button", "OpenMailForwardButton", OpenMailFrame, "UIPanelButtonTemplate")
		PostalForwardButton = forwardButton
		forwardButton:SetWidth(82)
		forwardButton:SetHeight(22)
		if OpenMailReplyButton then
			forwardButton:SetPoint("RIGHT", "OpenMailReplyButton", "LEFT", 0, 0)
		else
			forwardButton:SetPoint("BOTTOMRIGHT", OpenMailFrame, "BOTTOMRIGHT", -8, 8)
		end
		forwardButton:SetText(L["Forward"])
		forwardButton:SetScript("OnClick", function() Postal_Forward_OpenMail_Forward() end)
		forwardButton:SetFrameLevel(forwardButton:GetFrameLevel() + 1)
	end
	forwardButton:Show()
	self:SecureHook("InboxFrame_OnClick", Postal_Forward_OpenMailFrameUpdated)
	if OpenMailFrame and not self._openMailOnShowHooked then
		OpenMailFrame:HookScript("OnShow", function()
			if C_Timer then
				C_Timer.After(0, Postal_Forward_OpenMailFrameUpdated)
			else
				Postal_Forward_OpenMailFrameUpdated()
			end
		end)
		self._openMailOnShowHooked = true
	end
	if C_Timer then C_Timer.After(0, Postal_Forward_OpenMailFrameUpdated) end
end

-- Disabling modules unregisters all events/hook automatically
function Postal_Forward:OnDisable()
	Postal_Forward:UnregisterAllEvents()
	PostalForwardBodyText = nil
	PostalForwardWaitingForSendInfo = false
	PostalForwardExpectedSendCount = nil
	local forwardButton = Postal_Forward_GetForwardButton()
	if forwardButton then forwardButton:Hide() end
end

-- Check if table contains a specific value
local function contains(table, val)
   for i=1,#table do
      if table[i] == val then 
         return true
      end
   end
   return false
end

-- Check if a mail message contains any stackable item attachments 
local function ContainsStackableItem(messageindex)
	if not messageindex then return false end
	for itemIndex = 1, Postal_Forward_GetMaxReceiveAttachments() do
		local name, itemID = Postal_Forward_GetInboxAttachmentInfo(messageindex, itemIndex)
		if itemID ~= nil then
			local itemStackCount = select(8, Postal_Forward_GetItemInfo(itemID))
			if itemStackCount and itemStackCount > 1 then return true end
		end
	end
	return false
end

-- Calculate current bag free space
local function FreeBagSpace()
	local FreeSpace = 0
	for bagID = 0, Postal_Forward_GetMaxBagID(), 1 do
		local numberOfFreeSlots = Postal_Forward_GetContainerNumFreeSlots(bagID)
		FreeSpace = FreeSpace + (numberOfFreeSlots or 0)
	end
	return FreeSpace
end

-- Uses Containers free space tables to find and return location of latest item added to inventory
local function Postal_Inventory_Change(action)
	local TempTable = {}
	if action == 1 then	-- take snap shot of current container free space tables and store
		wipe(PostalForwardTable)
		for bagID = 0, Postal_Forward_GetMaxBagID(), 1 do
			table.insert(PostalForwardTable, Postal_Forward_GetContainerFreeSlots(bagID))
		end
		return 0, 0
	end
	if action == 2 then	-- take new snap shot of current container free space tables and compared with stored one
		wipe(TempTable)
		for bagID = 0, Postal_Forward_GetMaxBagID(), 1 do
			TempTable = Postal_Forward_GetContainerFreeSlots(bagID)
			if PostalForwardTable[bagID + 1] then
				for Key = 1, #PostalForwardTable[bagID + 1], 1 do
					if not contains(TempTable, PostalForwardTable[bagID + 1][Key]) then
						return bagID, PostalForwardTable[bagID + 1][Key]
					end
				end
			end
		end
	end
end

-- Enable/Disable Forward button as appropriate for current selected mail
function Postal_Forward_OpenMailFrameUpdated()
	if not OpenMailFrame or not OpenMailFrame:IsVisible() then return end
	local forwardButton = Postal_Forward_GetForwardButton()
	if not forwardButton then return end
	forwardButton:Enable()

	local mailID = InboxFrame and InboxFrame.openMailID
	if not mailID or mailID == 0 then
		forwardButton:Disable()
		return
	end

	local packageIcon, stationeryIcon, sender, subject, money, CODAmount = GetInboxHeaderInfo(mailID)
	money = money or 0
	CODAmount = CODAmount or 0
	local attachmentCount = Postal_Forward_InboxAttachmentCount(mailID)

	-- Disable if mail contains money or was sent COD
	if money > 0 or CODAmount > 0 then forwardButton:Disable(); return end
	-- Disable if mail has more attachments than a new outgoing mail can hold
	if attachmentCount > Postal_Forward_GetMaxSendAttachments() then forwardButton:Disable(); return end
	-- Disable if mail attachments exceed current free bag space
	if FreeBagSpace() - attachmentCount < 0 then forwardButton:Disable(); return end
	-- Disable if mail attachments are of stackable items
	if ContainsStackableItem(mailID) then forwardButton:Disable(); return end
end

-- Generate Forward mail
function Postal_Forward_OpenMail_Forward()
	local mailID = InboxFrame and InboxFrame.openMailID
	local attachmentCount = Postal_Forward_InboxAttachmentCount(mailID)
	if attachmentCount > Postal_Forward_GetMaxSendAttachments() then
		if Postal.Print then Postal:Print("Forward stopped: this mail has more attachments than an outgoing mail can hold.") end
		return
	end
	if FreeBagSpace() - attachmentCount < 0 then
		if Postal.Print then Postal:Print("Forward stopped: not enough empty bag slots for all attachments.") end
		return
	end
	if ContainsStackableItem(mailID) then
		if Postal.Print then Postal:Print("Forward stopped: Postal cannot safely forward stackable attachments.") end
		return
	end

	MailFrameTab_OnClick(nil, 2)
	SendMailNameEditBox:SetText("")
	local subject = OpenMailSubject:GetText()
	local bodyText, stationeryID1, stationeryID2, isTakeable, isInvoice = GetInboxText(InboxFrame.openMailID);
	PostalForwardBodyText = bodyText
	local prefix = "FW: "
	subject = subject or ""
	if (strsub(subject, 1, strlen(prefix)) ~= prefix) then
		subject = prefix..subject
	end
	if subject then SendMailSubjectEditBox:SetText(subject) end

	-- Important retail fix: do NOT set the outgoing body until after the items
	-- are attached.  The send-mail layout can shrink/hide attachment buttons when
	-- the body box has text, which causes no-arg ClickSendMailItemButton() to stop
	-- after only the visible slots (often 3-4).  Attach first, then restore body.
	Postal_Forward_SetSendMailBody("")
	SendMailNameEditBox:SetFocus()
	if C_Timer then
		C_Timer.After(POSTAL_FORWARD_INITIAL_DELAY, function() Postal_Forward_ForwardMailItems(1) end)
	else
		Postal_Forward_ForwardMailItems(1)
	end
end

-- Deal with attachments that need forwarded
function Postal_Forward_ForwardMailItems(action, retries)
	retries = retries or 0
	local hasItem = Postal_Forward_InboxAttachmentCount(InboxFrame.openMailID)
	if action == 1 then
		if hasItem == 0 then
			Postal_Forward_SetSendMailBody(PostalForwardBodyText)
			PostalForwardBodyText = nil
			return
		end
		for itemIndex = 1, Postal_Forward_GetMaxReceiveAttachments() do
			local itemName = Postal_Forward_GetInboxAttachmentInfo(InboxFrame.openMailID, itemIndex)
			if itemName then
				Postal_Inventory_Change(1)
				Postal_Forward:RegisterEvent("BAG_UPDATE", "Postal_Forward_ForwardMailItemsEvent")
				Postal_Forward:RegisterEvent("BAG_UPDATE_DELAYED", "Postal_Forward_ForwardMailItemsEvent")
				TakeInboxItem(InboxFrame.openMailID, itemIndex)
				return
			end
		end
	end
	if action == 2 then
		Postal_Forward:UnregisterEvent("BAG_UPDATE", "Postal_Forward_ForwardMailItemsEvent")
		Postal_Forward:UnregisterEvent("BAG_UPDATE_DELAYED", "Postal_Forward_ForwardMailItemsEvent")
		local bagID, itemIndex = Postal_Inventory_Change(2)
		if not (bagID and itemIndex) then
			if C_Timer and retries < 100 then
				C_Timer.After(POSTAL_FORWARD_RETRY_DELAY, function() Postal_Forward_ForwardMailItems(2, retries + 1) end)
			else
				Postal_Forward_SetSendMailBody(PostalForwardBodyText)
				PostalForwardBodyText = nil
				if Postal.Print then Postal:Print("Forward stopped: could not find the received attachment in your bags.") end
			end
			return
		end
		if SendMailFrame and not SendMailFrame:IsVisible() then
			MailFrameTab_OnClick(nil, 2)
		end

		if Postal_Forward_IsContainerItemLocked(bagID, itemIndex) then
			-- Items taken from mail are often still locked for a short time.  If we
			-- try to pick them up while locked, PickupContainerItem silently fails and
			-- the old code continues looting the rest of the mail into bags.
			if C_Timer and retries < 100 then
				C_Timer.After(POSTAL_FORWARD_RETRY_DELAY, function() Postal_Forward_ForwardMailItems(2, retries + 1) end)
			else
				Postal_Forward_SetSendMailBody(PostalForwardBodyText)
				PostalForwardBodyText = nil
				if Postal.Print then Postal:Print("Forward stopped: the received attachment stayed locked in your bags.") end
			end
			return
		end

		local beforeCount = Postal_Forward_SendMailAttachmentCount()
		local sendSlot = Postal_Forward_GetNextEmptySendMailSlot()
		if not sendSlot then
			Postal_Forward_SetSendMailBody(PostalForwardBodyText)
			PostalForwardBodyText = nil
			if Postal.Print then Postal:Print("Forward stopped: no empty outgoing attachment slot was found.") end
			return
		end

		if ClearCursor then ClearCursor() end
		Postal_Forward_PickupContainerItem(bagID, itemIndex)
		if not (CursorHasItem and CursorHasItem()) then
			if C_Timer and retries < 100 then
				C_Timer.After(POSTAL_FORWARD_RETRY_DELAY, function() Postal_Forward_ForwardMailItems(2, retries + 1) end)
			else
				Postal_Forward_SetSendMailBody(PostalForwardBodyText)
				PostalForwardBodyText = nil
				if Postal.Print then Postal:Print("Forward stopped: could not pick up the received item from your bags.") end
			end
			return
		end

		-- First try Blizzard's normal drop handler. If that does not consume the
		-- cursor, try the explicit outgoing slot.  Do not take the next inbox item
		-- until MAIL_SEND_INFO_UPDATE confirms the outgoing attachment list changed;
		-- otherwise the process can run one item ahead and leave items in bags.
		PostalForwardWaitingForSendInfo = true
		PostalForwardExpectedSendCount = beforeCount + 1
		Postal_Forward:RegisterEvent("MAIL_SEND_INFO_UPDATE", "Postal_Forward_ForwardMailAttachedEvent")
		Postal_Forward_ClickSendMailItemButton()
		if CursorHasItem and CursorHasItem() then
			Postal_Forward_ClickSendMailItemButton(sendSlot)
		end
		if SendMailFrame_Update then SendMailFrame_Update() end
		if CursorHasItem and CursorHasItem() then
			PostalForwardWaitingForSendInfo = false
			Postal_Forward:UnregisterEvent("MAIL_SEND_INFO_UPDATE")
			if ClearCursor then ClearCursor() end
			Postal_Forward_SetSendMailBody(PostalForwardBodyText)
			PostalForwardBodyText = nil
			if Postal.Print then Postal:Print("Forward stopped: could not attach the received item to the outgoing mail.") end
			return
		end
		Postal_Forward_CheckAttachComplete(0)
		return
	end
end
