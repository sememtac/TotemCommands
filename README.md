# Totem Commands

Command your totems from a single crossbar button in **World of Warcraft: Forever**'s gamepad mode.

Put **Call of the Elements** on any crossbar slot, and that button now does three things:

| You do | You feel / see | On release it casts |
|---|---|---|
| **Tap** | nothing | Call of the Elements |
| **Hold** (~0.5 s) | a rumble, "Release for Totemic Recall" | Totemic Recall |
| **Keep holding** (~1.4 s) | a double rumble, "Release for Totemic Call" | Totemic Call |

Nothing is cast until you let go, so you can hold past a stage you don't want. Every other slot on your
crossbar works exactly as before.

## Setup

1. Put Call of the Elements on a crossbar slot (any bar, any page).
2. Type `/totemcommands test`. It changes nothing and checks that the spells are known, which slot holds
   Call of the Elements, and that the hold timing works.
3. Type `/totemcommands on` (out of combat).

## Commands

| Command | What it does |
|---|---|
| `/totemcommands test` | Check spells, the Call of the Elements slot and the hold timing |
| `/totemcommands on` / `off` | Turn it on or off. `off` returns your buttons to normal immediately |
| `/totemcommands hold 4` | Hold length for Totemic Recall, in steps of about 0.2 s (2–6, default 3) |
| `/totemcommands hold2 9` | Hold length for Totemic Call (default 7) |
| `/totemcommands debug` | Print where each crossbar press goes (for troubleshooting) |

## Good to know

- **Taps cast on release** rather than on press, so a tap has a tiny delay compared with a normal button.
- **Hold timing is approximate.** Secure game code has no clock, so the hold is counted in game updates
  of about 0.2 s; it can arm slightly early in very busy combat. Use `hold`/`hold2` to lengthen it.
- **Totemic Call is found by name**, so on non-English clients the long hold falls back to Totemic Recall.
- Settings can only be changed out of combat. The tap/hold itself works in combat.

## How it works

Everything that casts runs in the game's secure environment: each crossbar button is wrapped with
Blizzard's `SecureHandlerWrapScript`, and the press/release decision is made there. The addon never
changes Blizzard's settings or code, so it doesn't cause "action blocked" errors.

## Install

- **CurseForge app:** coming soon.
- **Manually:** download `TotemCommands-<version>-forever.zip` from the
  [latest release](https://github.com/sememtac/TotemCommands/releases/latest) and extract it into
  `World of Warcraft\_forever_\Interface\AddOns\`. Restart the game (a `/reload` doesn't pick up new addons).

## Troubleshooting

If a button doesn't react, run `/totemcommands debug`, press it, and open an issue with the chat lines
it prints. If anything ever gets blocked, `/totemcommands off` puts your buttons back to normal.

## License

[MIT](LICENSE)
