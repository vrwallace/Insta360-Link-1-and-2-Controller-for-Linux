# Insta360 Link Webcam Controller for Linux

A Free Pascal / Lazarus application to control the **Insta360 Link** (and Link 2/2C) webcam on Linux, providing a full-featured alternative to the official Windows/Mac-only Link Controller software.

## Features

### Standard V4L2 Controls (work with any UVC webcam)
- **Pan / Tilt / Zoom** — absolute and relative positioning
- **Image adjustments** — brightness, contrast, saturation, sharpness, gain
- **White balance** — auto or manual temperature (Kelvin)
- **Exposure** — auto or manual absolute value
- **Focus** — auto or manual absolute value
- **Backlight compensation**

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

**Not controllable via XU** (confirmed by monitoring):
- HDR — processed in software by the Link Controller app
- Gesture control — always enabled in camera firmware
- Privacy mode — not found
- Portrait/9:16 mode — not found in Link Controller

### Two Interfaces
1. **GUI Application** (`insta360linkgui`) — full Lazarus GUI with sliders, buttons, presets
2. **CLI Tool** (`linkctl`) — command-line tool for scripting and automation

## Project Structure

```
insta360link/
├── uv4l2.pas              V4L2 + UVC Extension Unit API bindings
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
- **Lazarus IDE** (3.0+) — for the GUI application
- **Insta360 Link** webcam connected via USB

### Install Free Pascal & Lazarus

```bash
# Ubuntu/Debian
sudo apt install fpc lazarus

# Fedora
sudo dnf install fpc lazarus

# Arch
sudo pacman -S fpc lazarus
```

## Building

### GUI Application (requires Lazarus)

```bash
# Option 1: Open in Lazarus IDE
lazbuild insta360linkgui.lpi

# Option 2: Command-line build
lazbuild --build-mode=Release insta360linkgui.lpi
```

### CLI Tool (requires only fpc)

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

1. Select your camera from the device dropdown
2. Click **Connect**
3. Use the PTZ controls, mode buttons, and image sliders
4. Save preset positions for quick recall

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
./linkctl trackmode single
./linkctl trackmode group
./linkctl trackspeed 4

# Camera Modes
./linkctl deskview on       # Overhead desk view
./linkctl whiteboard on     # Whiteboard mode
./linkctl portrait on       # Vertical 9:16 mode
./linkctl deskview off      # Back to normal

# Other Features
./linkctl gesture on
./linkctl hdr on
./linkctl privacy on        # Tilt camera down for privacy
./linkctl noise focus       # Voice-isolating noise reduction

# Image Controls
./linkctl brightness 150
./linkctl contrast 140
./linkctl wb auto
./linkctl wb 5600           # Manual white balance at 5600K
./linkctl exposure auto
./linkctl exposure 500      # Manual exposure
./linkctl focus auto

# Presets
./linkctl preset save 0     # Save current position to slot 0
./linkctl preset recall 0   # Recall position from slot 0

# Scripting example: presentation mode
./linkctl tracking on
./linkctl trackmode single
./linkctl trackspeed 3
./linkctl hdr on
./linkctl noise focus

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
