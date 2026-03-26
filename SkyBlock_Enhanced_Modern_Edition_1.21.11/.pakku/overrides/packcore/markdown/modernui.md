# Modern UI

Modern UI is a rendering library that enhances several visual aspects of the game and includes some small optimization improvements. The options on the right let you configure its main features.

---

## Font

Choose which font the game uses.

### Inter (Modpack Font)

The default. Uses **Inter** — a clean, modern sans-serif typeface — with the Modern Text Engine active for high-quality rendering.

**Keep this selected** unless you have a specific reason to switch.

### Vanilla Font

Reverts to the default Minecraft font. Selecting this automatically disables the Modern Text Engine, which is required for full compatibility with some other mods.

Use this if:
- You use the **SBO Party Finder** (the inter font can look bad in this menu)
- You prefer the classic Minecraft look
- You have a **resource pack that includes a custom font** — with the vanilla renderer active, resource pack fonts work correctly

> **Requires a restart** to take effect.

---

## Fancy Tooltips

Replaces the standard vanilla tooltip boxes with styled, rounded tooltips. Features include:

- Rounded corners with a soft shadow
- Gradient border that adapts to the item's rarity color
- Centered item name with a decorative title break

Turn this off if you use a resource pack that already styles tooltips, or if you prefer the vanilla look.

---

## Startup Ding

Plays a short sound effect when the game finishes loading. You'll know the game is ready without watching the screen.

Turn this off if you find it annoying, or if you are using a custom startup sound via a resource pack.

---

> **Fancy Tooltips** and **Startup Ding** take effect immediately after applying.
> **Font** changes require a **full game restart**.

For deeper configuration, open the **Mods** menu, find **Modern UI** in the list, and click it. You can also configure Modern UI features at any time using the command `/packcore modernui`.