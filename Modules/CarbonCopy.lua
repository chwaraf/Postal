local Postal = LibStub("AceAddon-3.0"):GetAddon("Postal")
local Postal_CarbonCopy = Postal:NewModule("CarbonCopy", "AceHook-3.0", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("Postal")
Postal_CarbonCopy.description = L["Allows you to copy the contents of a mail."]

-- luacheck: globals InboxFrame OpenMailScrollFrame

function Postal_CarbonCopy:OnEnable()
	if type(OpenMail_Update) == "function" then
		self:Hook("OpenMail_Update", true)
	end
	if OpenMailFrame then
		self:HookScript(OpenMailFrame, "OnShow", "ScheduleOpenMailUpdate")
		self:HookScript(OpenMailFrame, "OnHide", "HideButton")
	end
	self:RegisterEvent("MAIL_INBOX_UPDATE", "ScheduleOpenMailUpdate")
	self:ScheduleOpenMailUpdate()
end

-- Disabling modules unregisters all events/hook automatically
function Postal_CarbonCopy:OnDisable()
	self:UnregisterEvent("MAIL_INBOX_UPDATE")
	self:HideButton()
end

function Postal_CarbonCopy:ScheduleOpenMailUpdate()
	if C_Timer then
		C_Timer.After(0, function()
			if Postal_CarbonCopy:IsEnabled() then Postal_CarbonCopy:OpenMail_Update() end
		end)
	else
		self:OpenMail_Update()
	end
end

function Postal_CarbonCopy:HideButton()
	if self.button then self.button:Hide() end
end

function Postal_CarbonCopy:OpenMail_Update()
	local mailID = InboxFrame and InboxFrame.openMailID
	if not mailID then self:HideButton(); return end
	local bodyText, _, _, isInvoice = GetInboxText(mailID)

	-- Show or hide the button as necessary
	if isInvoice or (bodyText and #bodyText > 0) then
		if self.CreateButton then
			self:CreateButton()
		end
		if self.button then self.button:Show() end
	else
		self:HideButton()
	end
end

local function Postal_CarbonCopy_GetCopyIcon()
	if C_Spell and C_Spell.GetSpellTexture then
		return C_Spell.GetSpellTexture(586) or 135994 -- Fade
	elseif GetSpellTexture then
		return GetSpellTexture(586) or 135994
	elseif GetSpellInfo then
		return select(3, GetSpellInfo(586)) or 135994
	end
	return 135994
end

function Postal_CarbonCopy:CopyMail()
	-- Build the string
	local _, _, sender, subject = GetInboxHeaderInfo(InboxFrame.openMailID)
	sender = FROM.." "..(sender or UNKNOWN).."\r\n"
	subject = MAIL_SUBJECT_LABEL.." "..subject.."\r\n\r\n"
	local bodyText, _, _, isInvoice = GetInboxText(InboxFrame.openMailID)
	bodyText = bodyText or ""
	if isInvoice then
		local invoiceType, itemName, playerName, bid, buyout, deposit, consignment = GetInboxInvoiceInfo(InboxFrame.openMailID)
		if playerName then
			if invoiceType == "buyer" then
				bodyText = bodyText..ITEM_PURCHASED_COLON.." "..itemName
				if bid == buyout then
					bodyText = bodyText.." ("..BUYOUT..")\r\n"
				else
					bodyText = bodyText.." ("..HIGH_BIDDER..")\r\n"
				end
				bodyText = bodyText..SOLD_BY_COLON.." "..playerName.."\r\n"
					.."----------------------------------------\r\n"
					..AMOUNT_PAID_COLON.." "..Postal:GetMoneyStringPlain(bid)
			elseif invoiceType == "seller" then
				bodyText = bodyText..ITEM_SOLD_COLON.." "..itemName.."\r\n"
				..PURCHASED_BY_COLON.." "..playerName
				if bid == buyout then
					bodyText = bodyText.." ("..BUYOUT..")\r\n\r\n"
				else
					bodyText = bodyText.." ("..HIGH_BIDDER..")\r\n\r\n"
				end
				bodyText = bodyText..SALE_PRICE_COLON.." "..Postal:GetMoneyStringPlain(bid).."\r\n"
					..DEPOSIT_COLON.." "..Postal:GetMoneyStringPlain(deposit).."\r\n"
					..AUCTION_HOUSE_CUT_COLON.." "..Postal:GetMoneyStringPlain(consignment).."\r\n"
					.."----------------------------------------\r\n"
					..AMOUNT_RECEIVED_COLON.." "..Postal:GetMoneyStringPlain(bid+deposit-consignment)
			end
		end
	end

	-- Copy to frame
	if Postal.CreateAboutFrame then
		Postal:CreateAboutFrame()
	end
	Postal.aboutFrame:Show()
	Postal.aboutFrame.editBox:SetText(sender..subject..bodyText.."\r\n")
	Postal.aboutFrame.editBox:HighlightText(0)
	Postal.aboutFrame.editBox:SetFocus()
end

function Postal_CarbonCopy:CreateButton()
	if not OpenMailScrollFrame then return end
	local button = CreateFrame("Button", nil, OpenMailScrollFrame)
	button:SetPoint("TOPRIGHT", OpenMailScrollFrame, "TOPRIGHT", 0, 0)
	button:SetHeight(10)
	button:SetWidth(10)
	button:SetNormalTexture(Postal_CarbonCopy_GetCopyIcon())
	button:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]])
	button:SetScript("OnClick", function()
		Postal_CarbonCopy:CopyMail()
	end)
	button:SetScript("OnEnter", function(self)
		self:SetHeight(28)
		self:SetWidth(28)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:ClearLines()
		GameTooltip:AddLine(L["Copy this mail"])
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function(self)
		self:SetHeight(10)
		self:SetWidth(10)
		GameTooltip:Hide()
	end)
	self.button = button
	OpenMailScrollFrame.PostalCarbonCopyButton = button
	self.CreateButton = nil -- Kill ourselves
end
