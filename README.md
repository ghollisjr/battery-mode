# battery-mode

Named charge-limit presets for laptop batteries, with persistent state
across reboots. One command to switch between "conserve" (long battery life), "balanced",
and "full capacity" modes.

Works with either of the kernel's two charge-limit interfaces, detected
automatically:

- **Numeric thresholds** (`charge_control_{start,end}_threshold`) — most
  ThinkPads, Framework, many ASUS. All modes available.
- **Conservation mode** (`charge_types` with `Long_Life`) — Lenovo
  IdeaPad/Yoga and others where the firmware only offers on/off. `conserve` turns
  conservation on (the firmware picks the cap, typically 60–80%); `full` turns
  it off. `balanced` and custom percentages aren't possible on this hardware.

## Why

Lithium batteries age fastest when held at 100% charge. For a laptop that
mostly lives on AC with occasional unplugged use, capping at 80% roughly
doubles the battery's useful lifespan. But before travel you want the full
100% — so you need a quick way to switch.

Existing options are either daemon-level (TLP; declarative, inconvenient to
toggle) or vendor-specific (ipman is IdeaPad-only). `battery-mode` is a
single-purpose CLI with named modes, boot-time restoration, and
passwordless sudo for `wheel`.

## Install

### Arch (AUR)

```
yay -S battery-mode    # or paru
```

Then:

```
sudo systemctl enable --now battery-mode-restore.service
sudo battery-mode conserve
```

### From source

```
git clone https://github.com/ghollisjr/battery-mode
cd battery-mode
sudo install -Dm0755 battery-mode                 /usr/bin/battery-mode
sudo install -Dm0644 battery-mode-restore.service /usr/lib/systemd/system/battery-mode-restore.service
sudo install -Dm0440 battery-mode.sudoers         /etc/sudoers.d/battery-mode
sudo systemctl daemon-reload
sudo systemctl enable --now battery-mode-restore.service
```

## Usage

```
battery-mode conserve   # 40%-80%, long battery life (recommended for plugged-in use)
battery-mode balanced   # 60%-90%, good life + more usable capacity when unplugged
battery-mode full       # 0%-100%, max capacity, use before travel
battery-mode 50 85      # custom start% and end%
battery-mode status     # show current thresholds, battery level, saved mode
battery-mode help       # usage summary
```

Each mode change is remembered and reapplied at boot. `battery-mode reapply`
does that by hand; you'll rarely need it.

`status` works without sudo; everything else needs root (or the sudoers rule).

Version 0.1.0 called `conserve` and `reapply` `save` and `restore`. The old
names still work.

On multi-battery systems the first supported `BAT*` is used; `status` lists
the others. To pick one explicitly, set `BAT=BAT1` in `/etc/battery-mode.conf`.

## How it works

- Writing to `/sys/class/power_supply/BAT*/charge_control_{start,end}_threshold`
  tells the EC when to stop and resume charging (or, on conservation-mode
  hardware, writing `Long_Life`/`Standard` to `charge_types`).
- Every mode change is saved to `/etc/battery-mode.conf` automatically.
- `battery-mode-restore.service` runs `battery-mode reapply` at boot to set
  that mode again, because sysfs values reset on power cycle.

## Modes rationale

| Mode | Start | End | When to use |
|------|------:|----:|-------------|
| conserve | 40 | 80 | Mostly plugged in. Battery held at 80%, waits until 40% to resume charging (fewer small cycles). |
| balanced | 60 | 90 | Mixed use. Shorter unplug tolerance, but 90% available when you need it. |
| full | 0 | 100 | Before travel or extended portable use. |

The 40-point gap in `conserve` prevents a charge cycle every time you briefly
unplug. If you unplug for 20 minutes to grab coffee and come back, nothing
re-charges — only if you actually drain the battery below 40%.

## Compatibility

Tested on Lenovo IdeaPad Slim 5 16IRL8 (82XF), kernel 6.18 (conservation-mode
backend). The numeric-threshold backend is tested only against a simulated
sysfs so far.

Check yours with:

```
battery-mode status
```

It reports the backend in use (`thresholds` or `types`), or explains what's
missing if your laptop isn't supported.

## Why not TLP / ipman?

- **TLP** does this via `/etc/tlp.conf` + `tlp-stat`. It's declarative, so
  switching modes means editing config and restarting a service. Fine for
  "set and forget", awkward for "toggle before a trip."
- **ipman** is IdeaPad-specific, hasn't been actively developed, and doesn't
  do named modes or boot-time restoration.

`battery-mode` complements TLP (which continues to manage CPU governor,
radio devices, USB autosuspend, etc.). If you use both, disable TLP's charge
threshold management by commenting out the `START_CHARGE_THRESH_BAT*` and
`STOP_CHARGE_THRESH_BAT*` lines in `/etc/tlp.conf`. `battery-mode status`
warns if it finds any active.

## Integration ideas

### quickkey entries

Add to `~/.config/quickkey/config`:

```ini
[Battery: Conserve]
command = sudo battery-mode conserve && battery-mode status

[Battery: Balanced]
command = sudo battery-mode balanced && battery-mode status

[Battery: Full]
command = sudo battery-mode full && battery-mode status

[Battery: Status]
command = battery-mode status
```

### IceWM / i3 / sway keybinding

Bind a hotkey to open a chooser (dmenu, rofi, quickkey) listing the modes.

## License

MIT
