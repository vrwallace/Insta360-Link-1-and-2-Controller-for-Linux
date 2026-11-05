# Insta360 Link Webcam Controller for Linux

A Free Pascal / Lazarus application to control the **Insta360 Link** and **Insta360 Link 2** webcams on Linux, providing a full-featured alternative to the official Windows/Mac-only Link Controller software.

## Supported Cameras

| Camera | VID:PID | Modes | Framing | PTZ | Image | Zoom |
|--------|---------|-------|---------|-----|-------|------|
| Insta360 Link | 2E1A:4C01 | ✅ | ✅ | ✅ V4L2 | ✅ | ✅ |
| Insta360 Link 2 | 2E1A:4C04 | ✅ | ✅ | ✅ Combined | ✅ | ✅ |
| Insta360 Link 2 Pro | 2E1A:4C06 | ✅ | ✅ | ✅ Combined | ✅ | ✅ |

All cameras share identical XU GUIDs and mode control protocols.

## Features

### Live Preview (GUI)
- **In-app video preview** — see the camera feed while you adjust controls, no
  second app required. Starts automatically on connect (toggle with the
  **Start/Stop Preview** button).
- Streams from the camera over V4L2 memory-mapped buffers, preferring **MJPEG**
  (decoded natively) and falling back to **YUYV**. The driver negotiates the
  nearest supported size to the requested 1280×720; the active resolution and
  pixel format are shown next to the preview.
- Frames are polled on a timer (~25 fps) so the UI never blocks. If another
  application is already streaming from the camera, preview won't start and the
  log notes why — all other controls still work.

### Standard V4L2 Controls (work with any UVC webcam)
- **Pan / Tilt / Zoom** — absolute and relative positioning, with
  **press-and-hold** D-pad buttons for continuous motion (see below)
- **Image adjustments** — brightness, contrast, saturation, sharpness, gain
- **White balance** — auto or manual temperature (Kelvin)
- **Exposure** — auto or manual absolute value
- **Focus** — auto or manual absolute value
- **Backlight compensation**

### Press-and-Hold PTZ (GUI)
The 8 directional D-pad buttons move the gimbal continuously **while held** and
stop on release (rather than a single step per click). The camera moves once
immediately on press, then repeats every ~150 ms. Movement speed per step is set
by the **Pan** and **Tilt** spin-edits next to the D-pad — lower values give
smooth, slow motion; higher values move faster. The center **⌂** button resets
to home.

### Insta360 Link Proprietary Controls (via UVC Extension Unit)
- **AI Tracking** — enable/disable AI person tracking
- **DeskView mode** — split-screen desk + face view
- **Whiteboard mode** — auto-straighten and enhance whiteboard
- **Overhead mode** — overhead document/desk camera view
- **Preset positions** — save and recall up to 6 camera positions
- **Gimbal reset** — return to center position

### XU Selector Map (Confirmed)
All camera modes are controlled via **XU Unit 9, Selector 2** (52-byte buffer).
The mode is set by writing byte[0]=mode_id, byte[1]=mode_flag:

| Mode | byte[0] | byte[1] | Description |
|------|---------|---------|-------------|
| Off/Normal | `$00` | `$00` | Standard webcam mode |
| AI Tracking | `$01` | `$00` | AI person tracking |
| Whiteboard | `$04` | `$01` | Whiteboard capture & straighten |
| Overhead | `$05` | `$03` | Document camera view |
| DeskView | `$06` | `$10` | Split-screen desk + face |

This mapping was confirmed by monitoring XU selector changes on Windows
using our `xu_monitor` tool alongside the official Insta360 Link Controller.

**Tracking Framing Mode** — controlled via **XU Unit 9, Selector 19** (1-byte value):

| Frame Mode | Value | Description |
|-----------|-------|-------------|
| Head | `$01` | Head/face only |
| Half Body | `$02` | Upper body |
| Full Body | `$03` | Whole body |

**Gimbal Reset** — XU Unit 9, Selector 14 (1-byte, write `$01`).

**Not controllable via Linux UVC** (confirmed by testing):
- Tracking target (single/group) — XU-10 Sel 1 byte[4] is read-only on Linux (works on Windows)
- HDR — processed in software by the Link Controller app
- Gesture control — always enabled in camera firmware
- Privacy mode — not found
- Portrait/9:16 mode — not found in Link Controller

### Two Interfaces
1. **GUI Application** (`insta360linkgui`) — full Lazarus GUI with live preview, sliders, press-and-hold PTZ, buttons, presets
2. **CLI Tool** (`linkctl`) — command-line tool for scripting and automation

## Project Structure

```
insta360link/
├── uv4l2.pas              V4L2 + UVC Extension Unit API bindings
├── uvideocap.pas          V4L2 MMAP streaming capture for live preview (GUI only)
├── uinsta360link.pas       High-level Insta360 Link camera controller class
├── umainform.pas           Lazarus GUI form (code-created UI)
├── umainform.lfm           Lazarus form definition
├── insta360linkgui.lpr     Lazarus GUI project main program
├── insta360linkgui.lpi     Lazarus project info file
├── linkctl.pas             Command-line controller tool
├── xu_monitor.pas          Windows XU selector monitor (for reverse engineering)
├── 99-insta360-link.rules  udev rules for non-root access
└── README.md               This file
```

## Prerequisites

- **Linux** (tested on Ubuntu 22.04+, Debian, Fedora, Arch)
- **Free Pascal Compiler** (fpc 3.2.2+)
- **Lazarus IDE** (3.0+) with its **GTK2 LCL widgetset** — for the GUI application
- **Insta360 Link** webcam connected via USB

### Install Free Pascal & Lazarus

```bash
# Ubuntu/Debian
sudo apt install fpc lazarus lcl-gtk2

# Fedora
sudo dnf install fpc lazarus

# Arch
sudo pacman -S fpc lazarus
```

## Building

### GUI Application (requires Lazarus)

```bash
# Option 1: Open in Lazarus IDE
lazbuild --widgetset=gtk2 insta360linkgui.lpi

# Option 2: Command-line build
lazbuild --build-mode=Release --widgetset=gtk2 insta360linkgui.lpi
```

The included `Makefile` builds both the GUI and the CLI tool:

```bash
# Build both GUI and CLI tool
make all

# Build only GUI (release mode with GTK2 widgetset)
make release

# Build only CLI tool
make cli
```

### CLI Tool standalone compilation (requires only fpc)

```bash
fpc -O2 linkctl.pas
```

## Device Permissions

By default, V4L2 devices may require root access. To avoid running with `sudo`:

```bash
# Install udev rules
sudo cp 99-insta360-link.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger

# Or add yourself to the video group
sudo usermod -aG video $USER
# (log out and back in for group change to take effect)
```

## Usage

### GUI Application

```bash
./insta360linkgui
```

1. Select your camera from the device dropdown (the last-used device is
   re-selected automatically on launch)
2. Click **Connect** — the live preview starts automatically
3. Use the PTZ controls, mode buttons, and image sliders. **Hold** a D-pad
   button to move the gimbal continuously; release to stop. Adjust the **Pan**
   and **Tilt** step values to change movement speed.
4. Toggle the feed with **Start/Stop Preview** (e.g. to free the camera for
   another app)
5. Save preset positions for quick recall

### CLI Tool

```bash
# List available cameras
./linkctl list

# Show camera info and all controls
./linkctl -d /dev/video0 info

# PTZ
./linkctl pan 3600          # Pan right 10 degrees
./linkctl tilt -1800        # Tilt down 5 degrees
./linkctl move 10 0         # Relative pan right (speed 10)
./linkctl move -5 8         # Pan left, tilt up simultaneously
./linkctl zoom 200          # 2x zoom
./linkctl home              # Reset to center

# AI Features
./linkctl tracking on
./linkctl frame head
./linkctl frame half
./linkctl frame full

# Camera Modes
./linkctl deskview on       # Overhead desk view
./linkctl whiteboard on     # Whiteboard mode
./linkctl overhead on       # Overhead document view
./linkctl deskview off      # Back to normal

# Image Controls
./linkctl brightness 150
./linkctl contrast 140
./linkctl wb auto
./linkctl wb 5600           # Manual white balance at 5600K
./linkctl exposure auto
./linkctl exposure 500      # Manual exposure
./linkctl focus auto

# Presets (persisted in ~/.config/Insta360 Link Controller/insta360link.ini)
./linkctl preset save 0     # Save current position to slot 0
./linkctl preset recall 0   # Recall position from slot 0

# Query Controls
./linkctl get pan           # Get current pan position
./linkctl get tilt          # Get current tilt position
./linkctl get zoom          # Get current zoom
./linkctl get brightness    # Get current brightness
./linkctl get tracking      # Query AI tracking state (TRUE/FALSE)

# Scripting example: presentation mode
./linkctl tracking on
./linkctl frame half

# Raw XU command (advanced/experimental)
./linkctl -v xu 3 01        # Send byte 0x01 to XU selector 3
```

### Verbose Mode

Add `-v` for detailed logging:

```bash
./linkctl -v -d /dev/video0 tracking on
```

## Technical Notes

### How It Works

The Insta360 Link is a standard **UVC (USB Video Class)** device on Linux. It exposes:

1. **Standard V4L2 controls** — brightness, contrast, pan, tilt, zoom, focus, exposure, etc. These are accessed via the `VIDIOC_QUERYCTRL`, `VIDIOC_G_CTRL`, and `VIDIOC_S_CTRL` ioctls.

2. **UVC Extension Unit (XU) controls** — proprietary controls for AI tracking, special modes, presets, etc. These are accessed via the `UVCIOC_CTRL_QUERY` ioctl with the Insta360-specific Extension Unit GUID and selector bytes.

3. **Video stream** — the live preview (`uvideocap.pas`) streams from the same
   device node using the standard V4L2 capture path: `VIDIOC_S_FMT` to negotiate
   format/resolution, `VIDIOC_REQBUFS` + `mmap` for zero-copy buffers, and
   `VIDIOC_QBUF`/`VIDIOC_DQBUF` around `VIDIOC_STREAMON`/`STREAMOFF`. The fd is
   opened `O_NONBLOCK`, so dequeue returns `EAGAIN` when no frame is ready and
   the GUI simply polls again on its next timer tick. MJPEG frames are decoded
   with `TJPEGImage`; YUYV frames are converted to RGB in software.

### USB Identification

| Camera | VID | PID |
|---|---|---|
| Insta360 Link | `0x2E1A` | `0x4C01` |
| Insta360 Link 2 | `0x2E1A` | TBD |

Verify with: `lsusb | grep 2e1a`

### UVC Extension Unit

The Insta360 Link's proprietary features are controlled via UVC Extension Unit commands. The XU unit ID is typically **4** (auto-detected on connection). The selector bytes and data formats were determined through:

- Analysis of the official Link Controller software's WebSocket protocol ([reverse-engineered by @dtinth](https://dt.in.th/Insta360LinkControllerWebSocketProtocol))
- USB traffic capture with Wireshark
- Trial and error with the `UVCIOC_CTRL_QUERY` ioctl

**Important:** The XU selector values and data formats documented in this project are based on community reverse-engineering and may vary between firmware versions. If a proprietary feature doesn't work, it may need different selector values for your firmware version. The standard V4L2 controls (image settings, PTZ) will always work regardless.

### Pan/Tilt Relative Control Format

For the XU-based relative pan/tilt (used by the official app):

```
Data: [signX, magnitudeX, signY, magnitudeY]
  signX/Y: 0 = no movement, 1 = positive, 255 (0xFF) = negative
  magnitudeX/Y: 0-30 (recommended max)
```

### Finding Your Camera's Controls

Use `v4l2-ctl` to list all controls your camera supports:

```bash
v4l2-ctl -d /dev/video0 --list-ctrls-menus
```

Or use the CLI tool:

```bash
./linkctl -d /dev/video0 info
```

## Related Projects

- [WebCamControl](https://github.com/Daniel15/WebCamControl) — C# Linux GUI for webcam PTZ (Insta360 Link compatible)
- [cameractrls](https://github.com/soyersoyer/cameractrls) — Python V4L2 camera control tool
- [creatorsgarten/insta360-link-controller](https://github.com/creatorsgarten/insta360-link-controller) — Web-based controller via reverse-engineered WebSocket protocol

## Troubleshooting

**"Cannot open /dev/video0"**
- Check permissions: `ls -la /dev/video0`
- Install udev rules or run with `sudo`
- Make sure you're in the `video` group

**"XU command FAILED"**
- The XU selectors may differ for your firmware version
- Try with `-v` flag to see detailed error info
- Standard V4L2 controls will still work even if XU fails
- Some features require a specific firmware version

**Preview won't start / stays black**
- Another application (browser, meeting app) may already be streaming from the
  camera — UVC allows only one streaming client at a time. Close it and toggle
  **Start Preview** again.
- The main `/dev/videoN` node is usually the streaming one; if the camera
  exposes several, connect to the lowest-numbered one (`v4l2-ctl --list-devices`).
- All non-streaming controls (PTZ, image, modes) work even when preview cannot
  start.

**Camera not detected**
- Check USB connection: `lsusb | grep 2e1a`
- Try a different USB port (use USB 3.0 if available)
- Ensure the USB cable supplies sufficient power (5V 1A)

**Multiple /dev/video devices**
- The Insta360 Link may create multiple video nodes
- Usually the first one (lowest number) is the main video stream
- Use `v4l2-ctl --list-devices` to identify them

## License

MIT License — free for personal and commercial use.

## Error handling and regression checks

The CLI exits with status **0** on success, **1** on connection, camera-operation,
read, or preset-storage failure, and **2** on invalid commands or arguments.
Manual white balance, exposure, and focus require `auto` or a nonnegative
integer. Raw XU selectors must be 1–255 and each hexadecimal byte must be 00–FF.
Arguments are checked before opening a camera. A `get` read failure is reported
as an error rather than displaying a default value. Combined white balance,
exposure, and focus queries print their component values on separate lines.

GUI and CLI use the same settings path beneath `$XDG_CONFIG_HOME` (or
`~/.config`), normally `Insta360 Link Controller/insta360link.ini`; an existing
legacy `insta360link` directory is used when the normal directory is absent.
Writers lock, merge their changes with the current file, and atomically replace
it. Closing the GUI preserves presets changed by the CLI unless that slot was
also edited in the GUI. Preset recall refreshes disk values when no local preset
save is pending.

On Link 2/Link 2 Pro, presets use the last commanded pan/tilt coordinates,
restoring the October 31 workaround for unreliable position reads. Tracking or
movement outside this app may not be reflected in those saved coordinates.
Zoom read failure prevents saving. Other models use checked position reads.

Manual moves use degrees times 3600 and the original left/right mapping.
Manual downward tilt is limited to -252000 (-70 degrees) to avoid the privacy
parking position. This limit does not override firmware-driven DeskView/Overhead
movement. Home sends only absolute pan/tilt center commands. Manual movement,
Home, and preset recall preserve tracking and do not reset the camera. Mode
buttons send the requested mode without resetting or recentering. Only the
explicit Gimbal Reset button exits special mode, resets, and centers the gimbal.

Preview uses 30ms polling, a reusable JPEG decoder, and startup cleanup.
Control buttons and stalled-frame polling never stop or restart preview.
Home and Gimbal Reset also leave a stopped preview stopped. Temporary dequeue
EIO is retried; device removal remains a terminal error. Bounded dequeue and
frame validation remain enabled. The GUI preview ABI is restricted to x86-64 Linux.

Run the hardware-independent regression suite with:

```bash
make test
```

It requires Python 3, FPC, Lazarus, Xvfb (`xvfb-run`), and the LCL `nogui` and `gtk2` widgetsets. Tests build in a
temporary directory, use fake ioctl responses and mapped temporary files, and
never open a video device. They cover CLI validation/status, controller failure
paths, preset merging/concurrent writers, bounded preview and error handling,
GUI control isolation (tracking, reset, and stream commands), and cleanup. `make clean` removes the GUI/CLI executables and generated unit
files while preserving source and resources.
