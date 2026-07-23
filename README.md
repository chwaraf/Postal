# Postal — TBC Anniversary

**Postal** is a mailbox enhancement addon for **World of Warcraft Classic: The Burning Crusade Anniversary**. It adds convenient tools for opening and returning selected mail, collecting attachments and gold, sending items quickly, managing recipient names, forwarding mail, and filtering mailbox actions.

This package is installed as `Interface/AddOns/Postal`.

## Features

Postal includes the following mailbox modules:

- **Open All** — collect attachments and money in bulk, with configurable mail filters.
- **Select** — select individual inbox messages and then open or return only the selected mail.
- **Express** — speed up sending items from bags.
- **QuickAttach** — quickly attach items to mail.
- **BlackBook** — remember and manage recipient names.
- **CarbonCopy** — copy recipients while composing mail.
- **Forward** — forward mail and attachments.
- **Rake** — report money collected during a mailbox session.
- **DoNotWant**, **TradeBlock**, and **Wire** — further filtering and mail-handling options.

## Custom changes

### Compact Select actions

The **Open** and **Return** buttons added by the Select module were reduced in size and repositioned to fit the TBC Anniversary mailbox UI more cleanly.

| Button | Width | Scale | Position |
| --- | ---: | ---: | --- |
| **Open** | 60 px | 80% | Anchored from the top-right of the inbox: `-90, -12` |
| **Return** | 60 px | 80% | Anchored from the top-left of the inbox: `-85, -12` |

The buttons retain their standard behavior:

- **Open** collects attachments and money from selected mail.
- **Return** returns selected mail.

### Postal options arrow moved

The small Postal options dropdown arrow is now positioned **under the mailbox close (X) button**. This prevents it from being obscured or overlapped by TradeSkillMaster (TSM) interface elements.

### TradeBlock disabled by default

The **TradeBlock** module is disabled in the default Postal profile. It can be enabled from Postal’s mailbox options if wanted.

### OpenAll disabled by default

The **OpenAll** module is disabled in the default Postal profile. It can be enabled from Postal’s mailbox options if wanted.

### Express item matching order

The Express module’s item matching order was adjusted. It now prioritizes an exact item-ID match before progressively broader matches (subclass, class, quality, and general/common matching), improving the choice of items when preparing mail.

## Installation

1. Exit World of Warcraft completely.
2. Extract `Postal.zip`.
3. Copy the extracted `Postal` folder to your TBC Anniversary AddOns directory:
   ```text
   World of Warcraft/_anniversary_/Interface/AddOns/Postal/
   ```
4. Start the game and make sure **Postal** is enabled in the AddOns list at character selection.
5. Open a mailbox to use and configure the addon.

## Configuration

Use the Postal dropdown arrow in the mailbox window to enable modules and change their options. Settings are stored per the `Postal3DB` SavedVariables profile.

## Credits

Postal retains the original addon credits in its `.toc` metadata, including Xinhuan and the original contributors.

## License

The included `LICENSE.txt` states: **“All Rights Reserved unless otherwise explicitly stated.”** Preserve included notices and verify permissions before redistributing modified versions.
