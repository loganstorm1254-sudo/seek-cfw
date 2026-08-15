# rd-132211 oak planks mod

Personal patch for Minecraft pre-Classic **rd-132211**.

## Changes

1. **Removed height-based revert** — blocks no longer look like grass/stone based on Y. Appearance comes from the stored block id.
2. **Oak planks** — left-click place at **one block above the grass layer** (`grassY + 1`, normally Y=43) places oak planks instead of rock.
3. New block ids: `1` rock, `2` grass, `3` oak planks (`0` air). Legacy saves that only had `0/1` are migrated once on load.

## Install (Prism Launcher)

1. Download `minecraft-rd-132211-client-oakplanks.jar` from this agent’s artifacts.
2. Back up the original:
   `...\PrismLauncher\libraries\com\mojang\minecraft\rd-132211\minecraft-rd-132211-client.jar`
3. Replace it with the modded jar (**keep the same filename**: `minecraft-rd-132211-client.jar`).
4. Launch the `rd-132211` instance.

To restore vanilla, put the backed-up jar back.

## Controls (unchanged)

- Left click: place
- Right click: break
- Enter: save `level.dat`
