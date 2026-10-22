# Mobile UI Checker

**A free Roblox Studio plugin that finds UI problems for phone and tablet players**, in one click.

Most Roblox players are on phones. A layout that looks fine on your PC can have buttons on top of each other, buttons too small for a thumb, or menus hidden under the notch. This plugin finds them for you.

By **Doom Studio**.

## What it checks

| Problem | What it means |
|---|---|
| 🔴 **Overlap** | Two buttons on top of each other, or a button on top of Roblox's thumbstick / jump button |
| 🟠 **Small** | A button smaller than a thumb (default 44 px, the Apple / Google guideline) |
| 🟣 **Off-screen** | A button or text partly or fully outside the screen |
| 🔵 **Notch** | A button outside the device's safe area (notch, camera hole, rounded corners) |
| 🟢 **Roblox buttons** | A button under Roblox's own top-left menu buttons |
| 🟡 **Tiny text** | Text too small to read (default 12 px) |

It skips hidden things, cuts items to what scrolling lists really show, and marks problems that sit **under an open window** separately (those are usually covered on purpose).

## Install

**Option A: Creator Store** *(coming soon)*

**Option B: file**
1. Download `MobileUIChecker.lua` from the [Releases](../../releases) page.
2. In Studio: **Plugins** tab → **Plugins Folder** → put the file there.
3. Restart Studio. A **Doom Studio** toolbar appears with **Mobile UI Check**.

## How to use

1. Click **Mobile UI Check** to open the panel.
2. For the real picture: **Test → Device** (Device Emulator), pick a phone or tablet, then press **Play**.
3. Press **SCAN**. Problems appear in the list and as coloured boxes on the screen.
4. Click a problem to select it in the Explorer.
5. Press **WATCH** and click through your menus: it keeps scanning every second and remembers every problem it saw on every screen.
6. Fix, scan again, until it says **No problems found ✓**. Then try another device.

You can change the **Min tap** and **Min text** sizes in the panel. They're saved.

## Tips

- Test at least one small phone (e.g. iPhone SE) and one tablet.
- In Edit mode it checks your `StarterGui`; in Play it checks what the player really sees, including Roblox's touch controls.
- Use `UIScale` or scale-based sizes so buttons grow on bigger screens, and keep a minimum size for small ones.

## Licence

MIT: free to use, change and share.
