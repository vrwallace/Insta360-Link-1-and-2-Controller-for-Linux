{
  uv4l2.pas - Video4Linux2 + UVC Extension Unit API for Free Pascal
  ===================================================================
  Provides:
    - Standard V4L2 control ioctls (QUERYCTRL, G_CTRL, S_CTRL)
    - UVC Extension Unit (XU) ioctls for vendor-specific controls
    - All relevant control ID constants for PTZ cameras
    - Convenience wrappers

  Designed for use with the Insta360 Link (USB VID:0x2E1A PID:0x4C01)
  but works with any V4L2/UVC webcam on Linux.
}
unit uv4l2;

{$mode objfpc}{$H+}

interface

uses
  BaseUnix, Unix, SysUtils;

{ ===== ioctl helpers ===== }
const
  _IOC_NRBITS   = 8;
  _IOC_TYPEBITS = 8;
  _IOC_SIZEBITS = 14;
  _IOC_DIRBITS  = 2;
  _IOC_NONE     = 0;
  _IOC_WRITE    = 1;
  _IOC_READ     = 2;
  _IOC_NRSHIFT  = 0;
  _IOC_TYPESHIFT = 8;
  _IOC_SIZESHIFT = 16;
  _IOC_DIRSHIFT  = 30;

function _IOC(dir, ioctype, nr, size: LongWord): LongWord; inline;

{ ===== V4L2 ioctl type ===== }
const
  VIDIOC_TYPE = Ord('V');

{ ===== V4L2 User-class control IDs (base $00980900) ===== }
const
  V4L2_CID_BASE                     = $00980900;
  V4L2_CID_BRIGHTNESS               = V4L2_CID_BASE + 0;
  V4L2_CID_CONTRAST                 = V4L2_CID_BASE + 1;
  V4L2_CID_SATURATION               = V4L2_CID_BASE + 2;
  V4L2_CID_HUE                      = V4L2_CID_BASE + 3;
  V4L2_CID_AUTO_WHITE_BALANCE       = V4L2_CID_BASE + 12;
  V4L2_CID_GAMMA                    = V4L2_CID_BASE + 17;
  V4L2_CID_GAIN                     = V4L2_CID_BASE + 19;
  V4L2_CID_POWER_LINE_FREQUENCY     = V4L2_CID_BASE + 24;
  V4L2_CID_WHITE_BALANCE_TEMPERATURE = V4L2_CID_BASE + 26;
  V4L2_CID_SHARPNESS                = V4L2_CID_BASE + 27;
  V4L2_CID_BACKLIGHT_COMPENSATION   = V4L2_CID_BASE + 28;

{ ===== V4L2 Camera-class control IDs (base $009A0900) ===== }
const
  V4L2_CID_CAMERA_CLASS_BASE       = $009A0900;
  V4L2_CID_EXPOSURE_AUTO           = V4L2_CID_CAMERA_CLASS_BASE + 1;
  V4L2_CID_EXPOSURE_ABSOLUTE       = V4L2_CID_CAMERA_CLASS_BASE + 2;
  V4L2_CID_EXPOSURE_AUTO_PRIORITY  = V4L2_CID_CAMERA_CLASS_BASE + 3;
  V4L2_CID_PAN_RELATIVE            = V4L2_CID_CAMERA_CLASS_BASE + 4;
  V4L2_CID_TILT_RELATIVE           = V4L2_CID_CAMERA_CLASS_BASE + 5;
  V4L2_CID_PAN_RESET               = V4L2_CID_CAMERA_CLASS_BASE + 6;
  V4L2_CID_TILT_RESET              = V4L2_CID_CAMERA_CLASS_BASE + 7;
  V4L2_CID_PAN_ABSOLUTE            = V4L2_CID_CAMERA_CLASS_BASE + 8;
  V4L2_CID_TILT_ABSOLUTE           = V4L2_CID_CAMERA_CLASS_BASE + 9;
  V4L2_CID_FOCUS_ABSOLUTE          = V4L2_CID_CAMERA_CLASS_BASE + 10;
  V4L2_CID_FOCUS_RELATIVE          = V4L2_CID_CAMERA_CLASS_BASE + 11;
  V4L2_CID_FOCUS_AUTO              = V4L2_CID_CAMERA_CLASS_BASE + 12;
  V4L2_CID_ZOOM_ABSOLUTE           = V4L2_CID_CAMERA_CLASS_BASE + 13;
  V4L2_CID_ZOOM_RELATIVE           = V4L2_CID_CAMERA_CLASS_BASE + 14;
  V4L2_CID_ZOOM_CONTINUOUS         = V4L2_CID_CAMERA_CLASS_BASE + 15;
  V4L2_CID_PAN_SPEED               = V4L2_CID_CAMERA_CLASS_BASE + 32;
  V4L2_CID_TILT_SPEED              = V4L2_CID_CAMERA_CLASS_BASE + 33;

{ Exposure modes }
const
  V4L2_EXPOSURE_AUTO               = 0;
  V4L2_EXPOSURE_MANUAL             = 1;
  V4L2_EXPOSURE_SHUTTER_PRIORITY   = 2;
  V4L2_EXPOSURE_APERTURE_PRIORITY  = 3;

{ Control types }
const
  V4L2_CTRL_TYPE_INTEGER = 1;
  V4L2_CTRL_TYPE_BOOLEAN = 2;
  V4L2_CTRL_TYPE_MENU    = 3;
  V4L2_CTRL_TYPE_BUTTON  = 4;

{ Control flags }
const
  V4L2_CTRL_FLAG_DISABLED   = $0001;
  V4L2_CTRL_FLAG_GRABBED    = $0002;
  V4L2_CTRL_FLAG_READ_ONLY  = $0004;
  V4L2_CTRL_FLAG_UPDATE     = $0008;
  V4L2_CTRL_FLAG_INACTIVE   = $0010;
  V4L2_CTRL_FLAG_SLIDER     = $0020;
  V4L2_CTRL_FLAG_WRITE_ONLY = $0040;
  V4L2_CTRL_FLAG_VOLATILE   = $0080;
  V4L2_CTRL_FLAG_NEXT_CTRL  = $80000000;

{ ===== UVC Extension Unit (XU) ioctl constants ===== }

{ UVC XU query request types }
const
  UVC_SET_CUR = 1;
  UVC_GET_CUR = $81;
  UVC_GET_MIN = $82;
  UVC_GET_MAX = $83;
  UVC_GET_RES = $84;
  UVC_GET_LEN = $85;
  UVC_GET_INFO = $86;
  UVC_GET_DEF = $87;

{ ===== Insta360 Link XU Selectors (reverse-engineered) ===== }
{ Insta360 Link XU Selector Map (Unit 9, GUID faf1672d-...)
  CONFIRMED via Windows Kernel Streaming property monitoring
  against the official Insta360 Link Controller desktop app.

  Selector 2 (52 bytes) is the MASTER MODE CONTROL.
  All camera modes go through this single selector:
    byte[0] = mode ID, byte[1] = mode flags, bytes[2..51] = 0

  Mode            byte[0]  byte[1]
  ──────────────────────────────────
  Off/Normal       $00     (any)
  AI Tracking      $01      $00
  Whiteboard       $04      $01
  Overhead         $05      $03
  DeskView         $06      $10

  Other confirmed selectors:
    Sel 13 [129]: Pan/tilt relative control
    Sel 14 [  1]: Gimbal reset (SET-only)
    Sel 11 [  5]: Frame counter / firmware info (read-only)
    Sel 12 [ 32]: Device serial number (read-only)
    Sel 20 [240]: IMU/gyroscope floats (read-only)

  NOT controllable via XU (confirmed by monitoring):
    - HDR: software-only in Link Controller app
    - Gesture control: always-on in firmware
    - Privacy mode: not found
    - Portrait/9:16: not found in Link Controller }
const
  XU_PANTILT_RELATIVE_CONTROL = 13;  // Pan/tilt relative (129 bytes)
  XU_GIMBAL_RESET_CONTROL     = 14;  // Reset gimbal to center (1 byte, SET-only)

  // Master mode control (Selector 2, 52-byte buffer)
  XU_MODE_CONTROL = 2;

  // Mode IDs for XU_MODE_CONTROL byte[0]
  XU_MODE_OFF         = $00;  // Disable active mode
  XU_MODE_AI_TRACKING = $01;  // AI person tracking
  XU_MODE_WHITEBOARD  = $04;  // Whiteboard capture & straighten
  XU_MODE_OVERHEAD    = $05;  // Overhead document view
  XU_MODE_DESKVIEW    = $06;  // Split-screen desk + face

  // Mode flags for XU_MODE_CONTROL byte[1]
  XU_FLAG_AI_TRACKING = $00;
  XU_FLAG_WHITEBOARD  = $01;
  XU_FLAG_OVERHEAD    = $03;
  XU_FLAG_DESKVIEW    = $10;

  // Tracking framing mode (Selector 19, 1-byte value)
  // Controls how much of the body the camera frames during AI tracking
  XU_TRACKING_FRAME_CONTROL = 19;
  XU_FRAME_HEAD      = $01;  // Head/face only
  XU_FRAME_HALF_BODY = $02;  // Upper body
  XU_FRAME_FULL_BODY = $03;  // Whole body

  // Tracking target mode (XU-10, Selector 1, 8-byte buffer, byte[4])
  // Controls whether camera tracks one person or a group
  XU_TRACKING_TARGET_UNIT = 10;
  XU_TRACKING_TARGET_CONTROL = 1;
  XU_TARGET_SINGLE = $00;  // Track single person
  XU_TARGET_GROUP  = $01;  // Track group of people

{ ===== V4L2 Structures ===== }
type
  Tv4l2_queryctrl = packed record
    id: LongWord;
    ctrl_type: LongWord;
    name: array[0..31] of AnsiChar;
    minimum: LongInt;
    maximum: LongInt;
    step: LongInt;
    default_value: LongInt;
    flags: LongWord;
    reserved: array[0..1] of LongWord;
  end;

  Tv4l2_control = packed record
    id: LongWord;
    value: LongInt;
  end;

  Tv4l2_capability = packed record
    driver: array[0..15] of AnsiChar;
    card: array[0..31] of AnsiChar;
    bus_info: array[0..31] of AnsiChar;
    version: LongWord;
    capabilities: LongWord;
    device_caps: LongWord;
    reserved: array[0..2] of LongWord;
  end;

  { UVC XU control query structure for UVCIOC_CTRL_QUERY
    Must match kernel's struct uvc_xu_control_query layout exactly.
    The C struct has padding between fields for natural alignment. }
  Tuvc_xu_control_query = packed record
    xu_unit: Byte;       // offset 0  - Extension unit ID
    selector: Byte;      // offset 1  - Control selector
    query: Byte;         // offset 2  - UVC_SET_CUR, UVC_GET_CUR, etc.
    _pad1: Byte;         // offset 3  - padding for Word alignment
    size: Word;          // offset 4  - Data size in bytes
    _pad2: Word;         // offset 6  - padding for pointer alignment
    data: Pointer;       // offset 8  - Pointer to data buffer
  end;

  { V4L2 extended control (for VIDIOC_S_EXT_CTRLS)
    Matches kernel struct v4l2_ext_control - packed with 8-byte union }
  Tv4l2_ext_control = packed record
    id: LongWord;                    // Control ID
    size: LongWord;                  // Size for pointer controls, 0 for integer
    reserved2: array[0..0] of LongWord;
    case Integer of
      0: (value: LongInt);           // For integer controls
      1: (value64: Int64);           // For 64-bit controls / pointer alignment
  end;

  { V4L2 extended controls wrapper (for VIDIOC_S_EXT_CTRLS)
    Matches kernel struct v4l2_ext_controls }
  Tv4l2_ext_controls = record
    ctrl_class: LongWord;           // V4L2_CTRL_CLASS_* or V4L2_CTRL_WHICH_*
    count: LongWord;                // Number of controls in array
    error_idx: LongWord;            // Index of failing control on error
    request_fd: LongInt;            // Request FD (-1 for none)
    reserved: array[0..0] of LongWord;
    controls: ^Tv4l2_ext_control;   // Pointer to controls array
  end;

{ ===== V4L2 ioctl request numbers ===== }
function VIDIOC_QUERYCAP: LongWord;
function VIDIOC_QUERYCTRL: LongWord;
function VIDIOC_G_CTRL: LongWord;
function VIDIOC_S_CTRL: LongWord;
function VIDIOC_S_EXT_CTRLS: LongWord;

{ UVC-specific ioctl }
function UVCIOC_CTRL_QUERY: LongWord;

{ ===== High-level convenience API ===== }

{ Device open/close }
function V4L2_Open(const DevPath: string): cint;
procedure V4L2_Close(fd: cint);

{ Standard V4L2 controls }
function V4L2_QueryCap(fd: cint; out cap: Tv4l2_capability): Boolean;
function V4L2_QueryCtrl(fd: cint; var qc: Tv4l2_queryctrl): Boolean;
function V4L2_GetCtrl(fd: cint; CtrlID: LongWord; out Value: LongInt): Boolean;
function V4L2_SetCtrl(fd: cint; CtrlID: LongWord; Value: LongInt): Boolean;

{ Set multiple controls atomically via VIDIOC_S_EXT_CTRLS.
  Required by some cameras (e.g. Link 2) that reject individual S_CTRL for pan/tilt. }
function V4L2_SetPanTilt(fd: cint; Pan, Tilt: LongInt): Boolean;

{ UVC Extension Unit raw access }
function UVC_XU_SetCur(fd: cint; UnitID, Selector: Byte;
  Data: PByte; DataSize: Word): Boolean;
function UVC_XU_GetCur(fd: cint; UnitID, Selector: Byte;
  Data: PByte; DataSize: Word): Boolean;
function UVC_XU_Query(fd: cint; UnitID, Selector, QueryType: Byte;
  Data: PByte; DataSize: Word): Boolean;

{ Enumerate all available V4L2 devices }
procedure V4L2_EnumDevices(out Devices: array of string; out Count: Integer);

{ Get a human-readable name for a V4L2 CID }
function V4L2_CIDName(CID: LongWord): string;

implementation

uses
  Classes;

function _IOC(dir, ioctype, nr, size: LongWord): LongWord; inline;
begin
  Result := (dir shl _IOC_DIRSHIFT) or
            (ioctype shl _IOC_TYPESHIFT) or
            (nr shl _IOC_NRSHIFT) or
            (size shl _IOC_SIZESHIFT);
end;

function _IOR(t, nr, sz: LongWord): LongWord; inline;
begin Result := _IOC(_IOC_READ, t, nr, sz); end;

function _IOW(t, nr, sz: LongWord): LongWord; inline;
begin Result := _IOC(_IOC_WRITE, t, nr, sz); end;

function _IOWR(t, nr, sz: LongWord): LongWord; inline;
begin Result := _IOC(_IOC_READ or _IOC_WRITE, t, nr, sz); end;

function VIDIOC_QUERYCAP: LongWord;
begin Result := _IOR(VIDIOC_TYPE, 0, SizeOf(Tv4l2_capability)); end;

function VIDIOC_QUERYCTRL: LongWord;
begin Result := _IOWR(VIDIOC_TYPE, 36, SizeOf(Tv4l2_queryctrl)); end;

function VIDIOC_G_CTRL: LongWord;
begin Result := _IOWR(VIDIOC_TYPE, 27, SizeOf(Tv4l2_control)); end;

function VIDIOC_S_CTRL: LongWord;
begin Result := _IOWR(VIDIOC_TYPE, 28, SizeOf(Tv4l2_control)); end;

function VIDIOC_S_EXT_CTRLS: LongWord;
begin Result := _IOWR(VIDIOC_TYPE, 72, SizeOf(Tv4l2_ext_controls)); end;

{ UVCIOC_CTRL_QUERY = _IOWR('u', $21, sizeof(uvc_xu_control_query)) }
function UVCIOC_CTRL_QUERY: LongWord;
begin
  Result := _IOWR(Ord('u'), $21, SizeOf(Tuvc_xu_control_query));
end;

{ ===== High-level API ===== }

function V4L2_Open(const DevPath: string): cint;
begin
  Result := FpOpen(DevPath, O_RDWR or O_NONBLOCK, 0);
end;

procedure V4L2_Close(fd: cint);
begin
  if fd >= 0 then FpClose(fd);
end;

function V4L2_QueryCap(fd: cint; out cap: Tv4l2_capability): Boolean;
begin
  FillChar(cap, SizeOf(cap), 0);
  Result := (FpIOCtl(fd, VIDIOC_QUERYCAP, @cap) = 0);
end;

function V4L2_QueryCtrl(fd: cint; var qc: Tv4l2_queryctrl): Boolean;
begin
  Result := (FpIOCtl(fd, VIDIOC_QUERYCTRL, @qc) = 0);
end;

function V4L2_GetCtrl(fd: cint; CtrlID: LongWord; out Value: LongInt): Boolean;
var
  c: Tv4l2_control;
begin
  c.id := CtrlID;
  c.value := 0;
  Result := (FpIOCtl(fd, VIDIOC_G_CTRL, @c) = 0);
  if Result then Value := c.value;
end;

function V4L2_SetCtrl(fd: cint; CtrlID: LongWord; Value: LongInt): Boolean;
var
  c: Tv4l2_control;
begin
  c.id := CtrlID;
  c.value := Value;
  Result := (FpIOCtl(fd, VIDIOC_S_CTRL, @c) = 0);
end;

function V4L2_SetPanTilt(fd: cint; Pan, Tilt: LongInt): Boolean;
var
  ctrls: Tv4l2_ext_controls;
  ext: array[0..1] of Tv4l2_ext_control;
begin
  FillChar(ext, SizeOf(ext), 0);
  ext[0].id := V4L2_CID_PAN_ABSOLUTE;
  ext[0].size := 0;
  ext[0].value := Pan;
  ext[1].id := V4L2_CID_TILT_ABSOLUTE;
  ext[1].size := 0;
  ext[1].value := Tilt;

  FillChar(ctrls, SizeOf(ctrls), 0);
  ctrls.ctrl_class := 0; // V4L2_CTRL_WHICH_CUR_VAL
  ctrls.count := 2;
  ctrls.request_fd := -1;
  ctrls.controls := @ext[0];

  Result := (FpIOCtl(fd, VIDIOC_S_EXT_CTRLS, @ctrls) = 0);
end;

function UVC_XU_Query(fd: cint; UnitID, Selector, QueryType: Byte;
  Data: PByte; DataSize: Word): Boolean;
var
  q: Tuvc_xu_control_query;
begin
  FillChar(q, SizeOf(q), 0);
  q.xu_unit := UnitID;
  q.selector := Selector;
  q.query := QueryType;
  q.size := DataSize;
  q.data := Data;
  Result := (FpIOCtl(fd, UVCIOC_CTRL_QUERY, @q) = 0);
end;

function UVC_XU_SetCur(fd: cint; UnitID, Selector: Byte;
  Data: PByte; DataSize: Word): Boolean;
begin
  Result := UVC_XU_Query(fd, UnitID, Selector, UVC_SET_CUR, Data, DataSize);
end;

function UVC_XU_GetCur(fd: cint; UnitID, Selector: Byte;
  Data: PByte; DataSize: Word): Boolean;
begin
  Result := UVC_XU_Query(fd, UnitID, Selector, UVC_GET_CUR, Data, DataSize);
end;

procedure V4L2_EnumDevices(out Devices: array of string; out Count: Integer);
var
  SR: TSearchRec;
  cap: Tv4l2_capability;
  fd: cint;
  devpath: string;
begin
  Count := 0;
  FillChar(cap, SizeOf(cap), 0);
  if FindFirst('/dev/video*', faAnyFile, SR) = 0 then
  begin
    repeat
      devpath := '/dev/' + SR.Name;
      fd := V4L2_Open(devpath);
      if fd >= 0 then
      begin
        if V4L2_QueryCap(fd, cap) then
        begin
          if Count <= High(Devices) then
          begin
            Devices[Count] := Format('%s  [%s - %s]',
              [devpath, PAnsiChar(@cap.card[0]), PAnsiChar(@cap.driver[0])]);
            Inc(Count);
          end;
        end;
        V4L2_Close(fd);
      end;
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
end;

function V4L2_CIDName(CID: LongWord): string;
begin
  case CID of
    V4L2_CID_BRIGHTNESS:               Result := 'Brightness';
    V4L2_CID_CONTRAST:                 Result := 'Contrast';
    V4L2_CID_SATURATION:               Result := 'Saturation';
    V4L2_CID_HUE:                      Result := 'Hue';
    V4L2_CID_AUTO_WHITE_BALANCE:       Result := 'Auto White Balance';
    V4L2_CID_GAMMA:                    Result := 'Gamma';
    V4L2_CID_GAIN:                     Result := 'Gain';
    V4L2_CID_POWER_LINE_FREQUENCY:     Result := 'Power Line Frequency';
    V4L2_CID_WHITE_BALANCE_TEMPERATURE: Result := 'White Balance Temp';
    V4L2_CID_SHARPNESS:                Result := 'Sharpness';
    V4L2_CID_BACKLIGHT_COMPENSATION:   Result := 'Backlight Compensation';
    V4L2_CID_EXPOSURE_AUTO:            Result := 'Exposure Mode';
    V4L2_CID_EXPOSURE_ABSOLUTE:        Result := 'Exposure (Absolute)';
    V4L2_CID_EXPOSURE_AUTO_PRIORITY:   Result := 'Exposure Auto Priority';
    V4L2_CID_PAN_ABSOLUTE:             Result := 'Pan (Absolute)';
    V4L2_CID_TILT_ABSOLUTE:            Result := 'Tilt (Absolute)';
    V4L2_CID_PAN_RELATIVE:             Result := 'Pan (Relative)';
    V4L2_CID_TILT_RELATIVE:            Result := 'Tilt (Relative)';
    V4L2_CID_PAN_SPEED:                Result := 'Pan Speed';
    V4L2_CID_TILT_SPEED:               Result := 'Tilt Speed';
    V4L2_CID_PAN_RESET:                Result := 'Pan Reset';
    V4L2_CID_TILT_RESET:               Result := 'Tilt Reset';
    V4L2_CID_FOCUS_ABSOLUTE:           Result := 'Focus (Absolute)';
    V4L2_CID_FOCUS_AUTO:               Result := 'Auto Focus';
    V4L2_CID_ZOOM_ABSOLUTE:            Result := 'Zoom (Absolute)';
    V4L2_CID_ZOOM_RELATIVE:            Result := 'Zoom (Relative)';
    V4L2_CID_ZOOM_CONTINUOUS:          Result := 'Zoom (Continuous)';
  else
    Result := Format('Control $%08X', [CID]);
  end;
end;

end.
