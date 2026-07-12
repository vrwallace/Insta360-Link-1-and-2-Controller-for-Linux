{
  uinsta360link.pas - High-level Insta360 Link Camera Controller
  ================================================================
  Wraps V4L2 standard controls and UVC Extension Unit commands
  into a clean API for controlling all Insta360 Link features.

  Features controlled:
    - Pan / Tilt / Zoom (absolute & relative)
    - AI Tracking (via XU Selector 2 mode control)
    - DeskView mode (split-screen desk + face view)
    - Whiteboard mode (auto-straighten whiteboard)
    - Overhead mode (document camera view)
    - Image settings (brightness, contrast, saturation, etc.)
    - Exposure settings (auto/manual, absolute value)
    - Focus settings (auto/manual, absolute value)
    - Preset positions (save & recall via software)
    - Gimbal reset (return to center)

  XU Selector Map (confirmed via Windows KS property monitoring):
    Selector 2 (52 bytes) = Master mode control
      byte[0]=$01, byte[1]=$00 = AI Tracking
      byte[0]=$04, byte[1]=$01 = Whiteboard
      byte[0]=$05, byte[1]=$03 = Overhead
      byte[0]=$06, byte[1]=$10 = DeskView
      byte[0]=$00              = Off/Normal

  Usage:
    var Cam: TInsta360Link;
    Cam := TInsta360Link.Create;
    if Cam.Open('/dev/video0') then begin
      Cam.SetAITracking(True);
      Cam.PanTiltRelative(10, 0); // pan right
      Cam.SetZoom(200);           // 2x zoom
      Cam.SetDeskView(True);      // enable desk view
      Cam.Close;
    end;
    Cam.Free;
}
unit uinsta360link;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, BaseUnix, Math, uv4l2;

type
  { Camera operating mode }
  TCameraMode = (
    cmNormal,       // Standard webcam mode (no special features)
    cmDeskView,     // Split-screen desk + face view
    cmWhiteboard,   // Whiteboard capture & straighten
    cmOverhead      // Overhead document/desk view (camera points down)
  );

  { Camera model }
  TCameraModel = (
    cmUnknown,
    cmLink,       // Insta360 Link (PID 4C01)
    cmLink2       // Insta360 Link 2 (PID 4C04)
  );

  { AI tracking framing mode }
  TTrackingFrame = (
    tfHead,         // Head/face only framing
    tfHalfBody,     // Upper body framing
    tfFullBody      // Whole body framing
  );

  { AI tracking target mode }
  TTrackingTarget = (
    ttSingle,       // Track single person
    ttGroup         // Track group of people
  );

  { Describes a control's available range }
  TCtrlRange = record
    Available: Boolean;
    Min, Max, Step, Default, Current: LongInt;
  end;

  { Preset position }
  TPresetPosition = record
    Name: string;
    Pan, Tilt, Zoom: LongInt;
    Valid: Boolean;
  end;

  { Event callback types }
  TLogEvent = procedure(Sender: TObject; const Msg: string) of object;

  { ===== Main Camera Controller Class ===== }
  TInsta360Link = class
  private
    FFD: cint;               // V4L2 file descriptor
    FDevicePath: string;
    FConnected: Boolean;
    FCameraModel: TCameraModel;
    FDeviceName: string;
    FDriverName: string;
    FBusInfo: string;
    FXU_UnitID: Byte;        // Extension Unit ID (9 for Insta360 Link)
    FXU_UnitIDOverride: Boolean;
    FXU_Lens: array[1..20] of Word; // Cached GET_LEN for each selector
    FPresets: array[0..5] of TPresetPosition; // Software presets
    FOnLog: TLogEvent;

    // Cached control ranges
    FPanRange: TCtrlRange;
    FTiltRange: TCtrlRange;
    FZoomRange: TCtrlRange;
    FFocusRange: TCtrlRange;
    FBrightnessRange: TCtrlRange;
    FContrastRange: TCtrlRange;
    FSaturationRange: TCtrlRange;
    FSharpnessRange: TCtrlRange;
    FGainRange: TCtrlRange;
    FWBTempRange: TCtrlRange;
    FExposureRange: TCtrlRange;

    // Current state tracking
    FCurrentMode: TCameraMode;
    FAITrackingEnabled: Boolean;
    FTrackingFrame: TTrackingFrame;
    FTrackingTarget: TTrackingTarget;
    FPanPos: LongInt;    // Software-tracked pan position
    FTiltPos: LongInt;   // Software-tracked tilt position

    procedure Log(const Msg: string);
    procedure Log(const Fmt: string; const Args: array of const);
    { Snapshot the current errno once and format it as 'errno=N: message'.
      Avoids evaluating fpGetErrno twice in a single log call, which can
      read a different (stale) errno for the number vs. the message. }
    function ErrInfo: string;
    function QueryControlRange(CtrlID: LongWord): TCtrlRange;
    procedure CacheControlRanges;
    function DetectXU_UnitID: Byte;
    procedure ScanXU_Selectors;
    function XU_SetPadded(Selector: Byte; const Data: array of Byte): Boolean;
    function XU_GetPadded(Selector: Byte; var Data: array of Byte): Boolean;
    function XU_SetMode(ModeID, ModeFlag: Byte): Boolean;
    procedure SetXU_UnitID(Value: Byte);

  public
    constructor Create;
    destructor Destroy; override;

    { Connection }
    function Open(const DevPath: string): Boolean;
    procedure Close;

    { ===== PTZ Controls ===== }

    { Set pan position absolutely (units depend on camera, typically
      -36000..36000 in 1/100 degree steps for the Insta360 Link) }
    function SetPanAbsolute(Value: LongInt): Boolean;
    function GetPanAbsolute: LongInt;

    { Set tilt position absolutely }
    function SetTiltAbsolute(Value: LongInt): Boolean;
    function GetTiltAbsolute: LongInt;

    { Move pan/tilt relative to current position.
      For XU-based relative control: data = [signX, magX, signY, magY]
      signX/Y: 0=stop, 1=positive, 255=negative. magX/Y: 0-30 recommended }
    function PanTiltRelative(PanDelta, TiltDelta: LongInt): Boolean;

    { Stop any pan/tilt movement }
    function PanTiltStop: Boolean;

    { Set zoom level. For Insta360 Link: 100 (1x) to 400 (4x) }
    function SetZoom(Value: LongInt): Boolean;
    function GetZoom: LongInt;

    { Reset gimbal to center position }
    function GimbalReset: Boolean;

    { ===== AI Tracking ===== }

    { Enable or disable AI person tracking (XU Sel 2: mode $01) }
    function SetAITracking(Enable: Boolean): Boolean;

    { Read current AI tracking state from XU }
    function GetAITracking: Boolean;

    { Set tracking framing mode (head, half body, full body) }
    function SetTrackingFrame(Frame: TTrackingFrame): Boolean;

    { Read current tracking framing mode }
    function GetTrackingFrame: TTrackingFrame;

    { Set tracking target (single person or group) }
    function SetTrackingTarget(Target: TTrackingTarget): Boolean;

    { Read current tracking target mode }
    function GetTrackingTarget: TTrackingTarget;

    { ===== Special Modes ===== }

    { Switch camera mode (disables current mode first) }
    function SetCameraMode(Mode: TCameraMode): Boolean;

    { Enable/disable DeskView (split desk + face view, XU Sel 2: mode $06) }
    function SetDeskView(Enable: Boolean): Boolean;

    { Enable/disable Whiteboard mode (XU Sel 2: mode $04) }
    function SetWhiteboard(Enable: Boolean): Boolean;

    { Enable/disable Overhead mode (document cam, XU Sel 2: mode $05) }
    function SetOverhead(Enable: Boolean): Boolean;

    { ===== Image Controls ===== }
    function SetBrightness(Value: LongInt): Boolean;
    function GetBrightness: LongInt;
    function SetContrast(Value: LongInt): Boolean;
    function GetContrast: LongInt;
    function SetSaturation(Value: LongInt): Boolean;
    function GetSaturation: LongInt;
    function SetSharpness(Value: LongInt): Boolean;
    function GetSharpness: LongInt;
    function SetGain(Value: LongInt): Boolean;
    function GetGain: LongInt;
    function SetBacklightCompensation(Enable: Boolean): Boolean;
    function GetBacklightCompensation: Boolean;

    { White balance }
    function SetAutoWhiteBalance(Enable: Boolean): Boolean;
    function GetAutoWhiteBalance: Boolean;
    function SetWhiteBalanceTemp(Value: LongInt): Boolean;
    function GetWhiteBalanceTemp: LongInt;

    { Exposure }
    function SetExposureAuto(Enable: Boolean): Boolean;
    function GetExposureAuto: Boolean;
    function SetExposureAbsolute(Value: LongInt): Boolean;
    function GetExposureAbsolute: LongInt;

    { Focus }
    function SetAutoFocus(Enable: Boolean): Boolean;
    function GetAutoFocus: Boolean;
    function SetFocusAbsolute(Value: LongInt): Boolean;
    function GetFocusAbsolute: LongInt;

    { ===== Presets ===== }
    function SavePreset(Index: Byte): Boolean;
    function RecallPreset(Index: Byte): Boolean;
    function GetPreset(Index: Byte): TPresetPosition;
    procedure SetPreset(Index: Byte; const APreset: TPresetPosition);

    { ===== Utility ===== }

    { Enumerate all V4L2 controls on the device and return them as text }
    function EnumerateControls: TStringList;

    { Send a raw XU command (for experimentation / unknown selectors) }
    function RawXU_Set(Selector: Byte; const Data: array of Byte): Boolean;
    function RawXU_Get(Selector: Byte; var Data: array of Byte; Len: Word): Boolean;

    { Read and log current values of all XU selectors (for reverse engineering) }
    procedure DumpAllXU;

    { Properties }
    property Connected: Boolean read FConnected;
    property CameraModel: TCameraModel read FCameraModel;
    property DevicePath: string read FDevicePath;
    property DeviceName: string read FDeviceName;
    property DriverName: string read FDriverName;
    property BusInfo: string read FBusInfo;
    property FD: cint read FFD;
    property XU_UnitID: Byte read FXU_UnitID write SetXU_UnitID;
    property CurrentMode: TCameraMode read FCurrentMode;
    property AITrackingEnabled: Boolean read FAITrackingEnabled;
    property TrackingFrame: TTrackingFrame read FTrackingFrame;
    property TrackingTarget: TTrackingTarget read FTrackingTarget;

    { Control ranges }
    property PanRange: TCtrlRange read FPanRange;
    property TiltRange: TCtrlRange read FTiltRange;
    property ZoomRange: TCtrlRange read FZoomRange;
    property FocusRange: TCtrlRange read FFocusRange;
    property BrightnessRange: TCtrlRange read FBrightnessRange;
    property ContrastRange: TCtrlRange read FContrastRange;
    property SaturationRange: TCtrlRange read FSaturationRange;
    property SharpnessRange: TCtrlRange read FSharpnessRange;
    property GainRange: TCtrlRange read FGainRange;
    property WBTempRange: TCtrlRange read FWBTempRange;
    property ExposureRange: TCtrlRange read FExposureRange;

    { Events }
    property OnLog: TLogEvent read FOnLog write FOnLog;
  end;

implementation

{ ===== TInsta360Link ===== }

constructor TInsta360Link.Create;
begin
  inherited Create;
  FFD := -1;
  FConnected := False;
  FCameraModel := cmUnknown;
  FXU_UnitID := 9; // Default XU unit ID for Insta360 Link
  FXU_UnitIDOverride := False;
  FillChar(FXU_Lens, SizeOf(FXU_Lens), 0);
  FillChar(FPresets, SizeOf(FPresets), 0);
  FCurrentMode := cmNormal;
  FAITrackingEnabled := False;
  FTrackingFrame := tfHalfBody;
  FTrackingTarget := ttSingle;
  FPanPos := 0;
  FTiltPos := 0;
end;

procedure TInsta360Link.SetXU_UnitID(Value: Byte);
begin
  FXU_UnitID := Value;
  FXU_UnitIDOverride := True;
end;

destructor TInsta360Link.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TInsta360Link.Log(const Msg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(Self, Msg);
end;

procedure TInsta360Link.Log(const Fmt: string; const Args: array of const);
begin
  Log(Format(Fmt, Args));
end;

function TInsta360Link.ErrInfo: string;
var
  e: cint;
begin
  e := fpGetErrno;
  Result := Format('errno=%d: %s', [e, SysErrorMessage(e)]);
end;

function TInsta360Link.QueryControlRange(CtrlID: LongWord): TCtrlRange;
var
  qc: Tv4l2_queryctrl;
begin
  FillChar(Result, SizeOf(Result), 0);
  if not FConnected then Exit;

  FillChar(qc, SizeOf(qc), 0);
  qc.id := CtrlID;
  if V4L2_QueryCtrl(FFD, qc) then
  begin
    Result.Available := (qc.flags and V4L2_CTRL_FLAG_DISABLED) = 0;
    Result.Min := qc.minimum;
    Result.Max := qc.maximum;
    Result.Step := qc.step;
    Result.Default := qc.default_value;
    V4L2_GetCtrl(FFD, CtrlID, Result.Current);
  end;
end;

procedure TInsta360Link.CacheControlRanges;
begin
  FPanRange := QueryControlRange(V4L2_CID_PAN_ABSOLUTE);
  FTiltRange := QueryControlRange(V4L2_CID_TILT_ABSOLUTE);
  FZoomRange := QueryControlRange(V4L2_CID_ZOOM_ABSOLUTE);
  FFocusRange := QueryControlRange(V4L2_CID_FOCUS_ABSOLUTE);
  FBrightnessRange := QueryControlRange(V4L2_CID_BRIGHTNESS);
  FContrastRange := QueryControlRange(V4L2_CID_CONTRAST);
  FSaturationRange := QueryControlRange(V4L2_CID_SATURATION);
  FSharpnessRange := QueryControlRange(V4L2_CID_SHARPNESS);
  FGainRange := QueryControlRange(V4L2_CID_GAIN);
  FWBTempRange := QueryControlRange(V4L2_CID_WHITE_BALANCE_TEMPERATURE);
  FExposureRange := QueryControlRange(V4L2_CID_EXPOSURE_ABSOLUTE);
end;

function TInsta360Link.DetectXU_UnitID: Byte;
var
  buf: array[0..31] of Byte;
  ids: array[0..5] of Byte = (9, 10, 11, 4, 3, 6);
  i: Integer;
  err: cint;
begin
  // Insta360 Link has Extension Units at bUnitID 9, 10, 11
  // Unit 9: GUID faf1672d-... has selectors 1-30 (main proprietary controls)
  // Unit 10: GUID e307e649-... has selectors 1-6
  // Unit 11: GUID a8bd5df2-... has selectors 1-5

  Log('XU query struct size: %d (expected 16 on 64-bit)', [SizeOf(Tuvc_xu_control_query)]);
  Log('UVCIOC_CTRL_QUERY = $%s', [IntToHex(UVCIOC_CTRL_QUERY, 8)]);

  Result := 9; // default
  for i := 0 to High(ids) do
  begin
    FillChar(buf, SizeOf(buf), 0);
    // Try UVC_GET_INFO on selector 1 - always returns exactly 1 byte
    if UVC_XU_Query(FFD, ids[i], 1, UVC_GET_INFO, @buf[0], 1) then
    begin
      Result := ids[i];
      Log('XU Unit ID detected: %d (via GET_INFO, flags=$%s)',
          [ids[i], IntToHex(buf[0], 2)]);
      Exit;
    end;
    err := fpGetErrno;
    Log('  XU probe unit %d failed, errno=%d (%s)',
        [ids[i], err, SysErrorMessage(err)]);
  end;

  // Second pass: try UVC_GET_LEN which returns 2 bytes
  for i := 0 to High(ids) do
  begin
    FillChar(buf, SizeOf(buf), 0);
    if UVC_XU_Query(FFD, ids[i], 1, UVC_GET_LEN, @buf[0], 2) then
    begin
      Result := ids[i];
      Log('XU Unit ID detected: %d (via GET_LEN)', [ids[i]]);
      Exit;
    end;
  end;

  Log('WARNING: Could not detect XU Unit ID, defaulting to 9');
end;

{ ===== XU Selector Scan ===== }

procedure TInsta360Link.ScanXU_Selectors;
var
  sel: Integer;
  unitID: Integer;
  units: array[0..2] of Integer = (9, 10, 11);
  u: Integer;
  lenBuf: array[0..1] of Byte;
  infoBuf: Byte;
  dataBuf: array[0..15] of Byte;
  dataLen: Word;
  err: cint;
  hexStr: string;
  j: Integer;
begin
  for u := 0 to High(units) do
  begin
    unitID := units[u];
    Log('--- Scanning XU unit %d ---', [unitID]);
    for sel := 1 to 20 do
    begin
      FillChar(lenBuf, 2, 0);
      infoBuf := 0;
      if UVC_XU_Query(FFD, unitID, sel, UVC_GET_LEN, @lenBuf[0], 2) then
      begin
        dataLen := lenBuf[0] or (lenBuf[1] shl 8);
        // Cache lengths for primary unit
        if (unitID = FXU_UnitID) and (sel >= 1) and (sel <= 20) then
          FXU_Lens[sel] := dataLen;
        UVC_XU_Query(FFD, unitID, sel, UVC_GET_INFO, @infoBuf, 1);
        // Read current value if small enough
        hexStr := '';
        if (dataLen <= 16) and ((infoBuf and 1) <> 0) then
        begin
          FillChar(dataBuf, SizeOf(dataBuf), 0);
          if UVC_XU_Query(FFD, unitID, sel, UVC_GET_CUR, @dataBuf[0], dataLen) then
          begin
            hexStr := ' cur=[';
            for j := 0 to dataLen - 1 do
            begin
              if j > 0 then hexStr := hexStr + ' ';
              hexStr := hexStr + IntToHex(dataBuf[j], 2);
            end;
            hexStr := hexStr + ']';
          end;
        end;
        Log('  Sel %2d: len=%3d flags=$%s (GET=%s SET=%s)%s',
            [sel, dataLen, IntToHex(infoBuf, 2),
             BoolToStr((infoBuf and 1) <> 0, 'Y', 'N'),
             BoolToStr((infoBuf and 2) <> 0, 'Y', 'N'),
             hexStr]);
      end
      else
      begin
        err := fpGetErrno;
        if (err <> 22) and (err <> 2) then
          Log('  Sel %2d: failed errno=%d (%s)', [sel, err, SysErrorMessage(err)]);
      end;
    end;
  end;
  Log('--- End XU scan ---');
end;

{ ===== XU Snapshot (for reverse engineering) ===== }

procedure TInsta360Link.DumpAllXU;
var
  sel: Integer;
  unitID: Integer;
  units: array[0..2] of Integer = (9, 10, 11);
  u: Integer;
  dataBuf: array[0..511] of Byte;
  dataLen: Word;
  hexStr: string;
  j, showBytes: Integer;
begin
  for u := 0 to High(units) do
  begin
    unitID := units[u];
    Log('--- Unit %d snapshot ---', [unitID]);
    for sel := 1 to 20 do
    begin
      if (unitID = FXU_UnitID) and (sel >= 1) and (sel <= 20) then
        dataLen := FXU_Lens[sel]
      else
        dataLen := 0;

      // If we don't have a cached length for this unit/sel, try GET_LEN
      if dataLen = 0 then
      begin
        FillChar(dataBuf, 2, 0);
        if UVC_XU_Query(FFD, unitID, sel, UVC_GET_LEN, @dataBuf[0], 2) then
          dataLen := dataBuf[0] or (dataBuf[1] shl 8)
        else
          Continue; // Selector doesn't exist
      end;

      // Read current value (skip SET-only selectors)
      if dataLen > 512 then dataLen := 512;
      FillChar(dataBuf, SizeOf(dataBuf), 0);

      // Check if GET is supported
      dataBuf[0] := 0;
      UVC_XU_Query(FFD, unitID, sel, UVC_GET_INFO, @dataBuf[0], 1);
      if (dataBuf[0] and 1) = 0 then
      begin
        Log('  U%d S%2d [%3d]: (SET-only)', [unitID, sel, dataLen]);
        Continue;
      end;

      FillChar(dataBuf, SizeOf(dataBuf), 0);
      if UVC_XU_Query(FFD, unitID, sel, UVC_GET_CUR, @dataBuf[0], dataLen) then
      begin
        hexStr := '';
        // Show up to 32 bytes, indicate if truncated
        showBytes := dataLen;
        if showBytes > 32 then showBytes := 32;
        for j := 0 to showBytes - 1 do
        begin
          if j > 0 then hexStr := hexStr + ' ';
          hexStr := hexStr + IntToHex(dataBuf[j], 2);
        end;
        if dataLen > 32 then
          hexStr := hexStr + Format(' ... (%d more)', [dataLen - 32]);
        Log('  U%d S%2d [%3d]: %s', [unitID, sel, dataLen, hexStr]);
      end;
    end;
  end;
end;

{ ===== Padded XU Helpers ===== }
{ These send/receive XU data with the exact buffer size the camera expects }

function TInsta360Link.XU_SetPadded(Selector: Byte; const Data: array of Byte): Boolean;
var
  buf: PByte;
  expectedLen: Word;
  copyLen: Integer;
begin
  Result := False;
  if (Selector < 1) or (Selector > 20) then Exit;
  expectedLen := FXU_Lens[Selector];
  if expectedLen = 0 then
  begin
    // Selector not found during scan - don't attempt (would block/freeze)
    Log('XU_SetPadded: selector %d has no cached length (not found in scan)', [Selector]);
    Exit;
  end;
  buf := GetMem(expectedLen);
  try
    FillChar(buf^, expectedLen, 0);
    copyLen := Length(Data);
    if copyLen > expectedLen then copyLen := expectedLen;
    Move(Data[0], buf^, copyLen);
    Result := UVC_XU_SetCur(FFD, FXU_UnitID, Selector, buf, expectedLen);
  finally
    FreeMem(buf);
  end;
end;

function TInsta360Link.XU_GetPadded(Selector: Byte; var Data: array of Byte): Boolean;
var
  buf: PByte;
  expectedLen: Word;
  copyLen: Integer;
begin
  Result := False;
  if (Selector < 1) or (Selector > 20) then Exit;
  expectedLen := FXU_Lens[Selector];
  if expectedLen = 0 then
  begin
    Log('XU_GetPadded: selector %d has no cached length (not found in scan)', [Selector]);
    Exit;
  end;
  buf := GetMem(expectedLen);
  try
    FillChar(buf^, expectedLen, 0);
    Result := UVC_XU_GetCur(FFD, FXU_UnitID, Selector, buf, expectedLen);
    if Result then
    begin
      copyLen := Length(Data);
      if copyLen > expectedLen then copyLen := expectedLen;
      Move(buf^, Data[0], copyLen);
    end;
  finally
    FreeMem(buf);
  end;
end;

{ ===== XU Mode Control Helper ===== }
{ Writes mode ID and flag to Selector 2 (52-byte buffer) }

function TInsta360Link.XU_SetMode(ModeID, ModeFlag: Byte): Boolean;
var
  buf: array[0..51] of Byte;
begin
  Result := False;
  if not FConnected then Exit;

  FillChar(buf, SizeOf(buf), 0);
  buf[0] := ModeID;
  buf[1] := ModeFlag;
  Result := XU_SetPadded(XU_MODE_CONTROL, buf);
  if Result then
    Log('XU Mode SET: byte[0]=$%s byte[1]=$%s', [IntToHex(ModeID, 2), IntToHex(ModeFlag, 2)])
  else
    Log('XU Mode SET FAILED (%s)', [ErrInfo]);
end;

function TInsta360Link.Open(const DevPath: string): Boolean;
var
  cap: Tv4l2_capability;
  vidName, pidStr: string;
  pidFile: TextFile;
begin
  Result := False;
  Close; // Close any previous connection

  FFD := V4L2_Open(DevPath);
  if FFD < 0 then
  begin
    Log('ERROR: Cannot open %s: %s', [DevPath, SysErrorMessage(fpGetErrno)]);
    Exit;
  end;

  FDevicePath := DevPath;

  // Query capabilities
  if V4L2_QueryCap(FFD, cap) then
  begin
    FDeviceName := PAnsiChar(@cap.card[0]);
    FDriverName := PAnsiChar(@cap.driver[0]);
    FBusInfo := PAnsiChar(@cap.bus_info[0]);
    Log('Connected to: %s', [FDeviceName]);
    Log('Driver: %s  Bus: %s', [FDriverName, FBusInfo]);
  end
  else
    Log('WARNING: QUERYCAP failed');

  FConnected := True;

  // Detect camera model from USB PID via sysfs
  FCameraModel := cmUnknown;
  try
    vidName := ExtractFileName(DevPath); // e.g. 'video0'
    AssignFile(pidFile, '/sys/class/video4linux/' + vidName + '/device/../idProduct');
    {$I-}
    Reset(pidFile);
    {$I+}
    if IOResult = 0 then
    begin
      ReadLn(pidFile, pidStr);
      CloseFile(pidFile);
      pidStr := LowerCase(Trim(pidStr));
      if pidStr = '4c01' then
        FCameraModel := cmLink
      else if pidStr = '4c04' then
        FCameraModel := cmLink2;
    end;
  except
  end;

  case FCameraModel of
    cmLink:    Log('Camera model: Insta360 Link');
    cmLink2:   Log('Camera model: Insta360 Link 2');
    cmUnknown: Log('Camera model: Unknown');
  end;

  // Respect a caller-supplied unit ID; otherwise auto-detect it.
  if not FXU_UnitIDOverride then
    FXU_UnitID := DetectXU_UnitID
  else
    Log('Using requested XU unit ID: %d', [FXU_UnitID]);

  // Scan all selectors on detected unit to find data sizes
  ScanXU_Selectors;

  // Cache all control ranges
  CacheControlRanges;

  // Log available controls summary
  if FPanRange.Available then
    Log('Pan: %d..%d (step %d)', [FPanRange.Min, FPanRange.Max, FPanRange.Step]);
  if FTiltRange.Available then
    Log('Tilt: %d..%d (step %d)', [FTiltRange.Min, FTiltRange.Max, FTiltRange.Step]);
  if FZoomRange.Available then
    Log('Zoom: %d..%d (step %d)', [FZoomRange.Min, FZoomRange.Max, FZoomRange.Step]);

  Result := True;
end;

procedure TInsta360Link.Close;
begin
  if FFD >= 0 then
  begin
    V4L2_Close(FFD);
    FFD := -1;
    FConnected := False;
    Log('Disconnected from %s', [FDevicePath]);
    FDevicePath := '';
    FDeviceName := '';
  end;
end;

{ ===== PTZ Controls ===== }

function TInsta360Link.SetPanAbsolute(Value: LongInt): Boolean;
begin
  Result := False;
  if not FConnected then Exit;

  // Try individual set first (Link 1), fall back to combined (Link 2)
  Result := V4L2_SetCtrl(FFD, V4L2_CID_PAN_ABSOLUTE, Value);
  if not Result then
    Result := V4L2_SetPanTilt(FFD, Value, FTiltPos);

  if Result then
  begin
    FPanPos := Value;
    Log('Pan absolute: %d', [Value]);
  end
  else
    Log('Pan absolute FAILED');
end;

function TInsta360Link.GetPanAbsolute: LongInt;
begin
  Result := FPanPos;
end;

function TInsta360Link.SetTiltAbsolute(Value: LongInt): Boolean;
begin
  Result := False;
  if not FConnected then Exit;

  Result := V4L2_SetCtrl(FFD, V4L2_CID_TILT_ABSOLUTE, Value);
  if not Result then
    Result := V4L2_SetPanTilt(FFD, FPanPos, Value);

  if Result then
  begin
    FTiltPos := Value;
    Log('Tilt absolute: %d', [Value]);
  end
  else
    Log('Tilt absolute FAILED');
end;

function TInsta360Link.GetTiltAbsolute: LongInt;
begin
  Result := FTiltPos;
end;

function TInsta360Link.PanTiltRelative(PanDelta, TiltDelta: LongInt): Boolean;
var
  newPan, newTilt: LongInt;
begin
  Result := False;
  if not FConnected then Exit;

  newPan := FPanPos + PanDelta * 3600;
  newTilt := FTiltPos + TiltDelta * 3600;

  // Clamp to range
  if FPanRange.Available then
  begin
    if newPan < FPanRange.Min then newPan := FPanRange.Min;
    if newPan > FPanRange.Max then newPan := FPanRange.Max;
  end;
  if FTiltRange.Available then
  begin
    if newTilt < FTiltRange.Min then newTilt := FTiltRange.Min;
    if newTilt > FTiltRange.Max then newTilt := FTiltRange.Max;
  end;

  // Try combined set first (works on both Link and Link 2)
  Result := V4L2_SetPanTilt(FFD, newPan, newTilt);
  if not Result then
  begin
    // Fall back to individual sets (shouldn't happen, but just in case)
    V4L2_SetCtrl(FFD, V4L2_CID_PAN_ABSOLUTE, newPan);
    Result := V4L2_SetCtrl(FFD, V4L2_CID_TILT_ABSOLUTE, newTilt);
  end;

  if Result then
  begin
    Log('Pan/Tilt: pan=%d→%d tilt=%d→%d',
        [FPanPos, newPan, FTiltPos, newTilt]);
    FPanPos := newPan;
    FTiltPos := newTilt;
  end
  else
    Log('Pan/Tilt FAILED (%s)', [ErrInfo]);
end;

function TInsta360Link.PanTiltStop: Boolean;
begin
  Result := PanTiltRelative(0, 0);
end;

function TInsta360Link.SetZoom(Value: LongInt): Boolean;
begin
  Result := FConnected and V4L2_SetCtrl(FFD, V4L2_CID_ZOOM_ABSOLUTE, Value);
  if Result then Log('Zoom: %d', [Value])
  else Log('Zoom FAILED');
end;

function TInsta360Link.GetZoom: LongInt;
begin
  Result := 100;
  if FConnected then
    V4L2_GetCtrl(FFD, V4L2_CID_ZOOM_ABSOLUTE, Result);
end;

function TInsta360Link.GimbalReset: Boolean;
var
  data: Byte;
begin
  Result := False;
  if not FConnected then Exit;

  // Try XU reset command
  data := 1;
  XU_SetPadded(XU_GIMBAL_RESET_CONTROL, [data]);

  // Set pan/tilt to 0,0 using combined set (works on both Link and Link 2)
  Result := V4L2_SetPanTilt(FFD, 0, 0);
  if not Result then
  begin
    // Fall back to individual sets
    V4L2_SetCtrl(FFD, V4L2_CID_PAN_ABSOLUTE, 0);
    Result := V4L2_SetCtrl(FFD, V4L2_CID_TILT_ABSOLUTE, 0);
  end;

  if Result then
  begin
    FPanPos := 0;
    FTiltPos := 0;
    Log('Gimbal reset to center');
  end
  else
    Log('Gimbal reset FAILED');
end;

{ ===== AI Tracking ===== }

function TInsta360Link.SetAITracking(Enable: Boolean): Boolean;
begin
  Result := False;
  if not FConnected then Exit;

  if Enable then
    Result := XU_SetMode(XU_MODE_AI_TRACKING, XU_FLAG_AI_TRACKING)
  else
    Result := XU_SetMode(XU_MODE_OFF, 0);

  if Result then
  begin
    FAITrackingEnabled := Enable;
    if Enable then
    begin
      FCurrentMode := cmNormal; // AI tracking is an overlay, not a mode
      Log('AI Tracking: ENABLED');
    end
    else
      Log('AI Tracking: DISABLED');
  end
  else
    Log('AI Tracking FAILED');
end;

function TInsta360Link.GetAITracking: Boolean;
var
  buf: array[0..51] of Byte;
begin
  Result := False;
  if not FConnected then Exit;
  FillChar(buf, SizeOf(buf), 0);
  if XU_GetPadded(XU_MODE_CONTROL, buf) then
    Result := (buf[0] = XU_MODE_AI_TRACKING);
end;

function TInsta360Link.SetTrackingFrame(Frame: TTrackingFrame): Boolean;
var
  data: Byte;
begin
  Result := False;
  if not FConnected then Exit;

  case Frame of
    tfHead:     data := XU_FRAME_HEAD;
    tfHalfBody: data := XU_FRAME_HALF_BODY;
    tfFullBody: data := XU_FRAME_FULL_BODY;
  else
    data := XU_FRAME_HALF_BODY;
  end;

  Log('SetTrackingFrame: writing $%02x to Sel %d (len=%d)',
    [data, XU_TRACKING_FRAME_CONTROL, FXU_Lens[XU_TRACKING_FRAME_CONTROL]]);

  Result := XU_SetPadded(XU_TRACKING_FRAME_CONTROL, [data]);
  if Result then
  begin
    FTrackingFrame := Frame;
    case Frame of
      tfHead:     Log('Tracking frame: HEAD');
      tfHalfBody: Log('Tracking frame: HALF BODY');
      tfFullBody: Log('Tracking frame: FULL BODY');
    end;
  end
  else
    Log('Tracking frame FAILED (%s)', [ErrInfo]);
end;

function TInsta360Link.GetTrackingFrame: TTrackingFrame;
var
  data: array[0..0] of Byte;
begin
  Result := tfHalfBody;
  if not FConnected then Exit;
  data[0] := 0;
  if XU_GetPadded(XU_TRACKING_FRAME_CONTROL, data) then
  begin
    case data[0] of
      XU_FRAME_HEAD:      Result := tfHead;
      XU_FRAME_HALF_BODY: Result := tfHalfBody;
      XU_FRAME_FULL_BODY: Result := tfFullBody;
    end;
    FTrackingFrame := Result;
  end;
end;

function TInsta360Link.SetTrackingTarget(Target: TTrackingTarget): Boolean;
var
  buf: array[0..7] of Byte;
  lenBuf: array[0..1] of Byte;
  dataLen: Word;
begin
  Result := False;
  if not FConnected then Exit;

  // First query the actual data length for XU-10 Sel 1
  FillChar(lenBuf, SizeOf(lenBuf), 0);
  if UVC_XU_Query(FFD, XU_TRACKING_TARGET_UNIT, XU_TRACKING_TARGET_CONTROL,
    UVC_GET_LEN, @lenBuf[0], 2) then
    dataLen := lenBuf[0] or (lenBuf[1] shl 8)
  else
    dataLen := 8; // Default to 8 as seen on Windows

  if dataLen > 8 then dataLen := 8; // Safety cap

  Log('XU-10 Sel 1: detected length = %d', [dataLen]);

  // Read current state to preserve other bytes
  FillChar(buf, SizeOf(buf), 0);
  if not UVC_XU_GetCur(FFD, XU_TRACKING_TARGET_UNIT, XU_TRACKING_TARGET_CONTROL,
    @buf[0], dataLen) then
  begin
    Log('Tracking target: read FAILED (%s)', [ErrInfo]);
    // Try writing anyway with default buffer
    FillChar(buf, SizeOf(buf), 0);
  end
  else
    Log('XU-10 Sel 1 read: %02x %02x %02x %02x %02x %02x %02x %02x',
      [buf[0], buf[1], buf[2], buf[3], buf[4], buf[5], buf[6], buf[7]]);

  case Target of
    ttSingle: buf[4] := XU_TARGET_SINGLE;
    ttGroup:  buf[4] := XU_TARGET_GROUP;
  end;

  Result := UVC_XU_SetCur(FFD, XU_TRACKING_TARGET_UNIT,
    XU_TRACKING_TARGET_CONTROL, @buf[0], dataLen);
  if Result then
  begin
    FTrackingTarget := Target;
    case Target of
      ttSingle: Log('Tracking target: SINGLE');
      ttGroup:  Log('Tracking target: GROUP');
    end;
  end
  else
    Log('Tracking target FAILED (%s)', [ErrInfo]);
end;

function TInsta360Link.GetTrackingTarget: TTrackingTarget;
var
  buf: array[0..7] of Byte;
  lenBuf: array[0..1] of Byte;
  dataLen: Word;
begin
  Result := ttSingle;
  if not FConnected then Exit;

  FillChar(lenBuf, SizeOf(lenBuf), 0);
  if UVC_XU_Query(FFD, XU_TRACKING_TARGET_UNIT, XU_TRACKING_TARGET_CONTROL,
    UVC_GET_LEN, @lenBuf[0], 2) then
    dataLen := lenBuf[0] or (lenBuf[1] shl 8)
  else
    dataLen := 8;

  if dataLen > 8 then dataLen := 8;

  FillChar(buf, SizeOf(buf), 0);
  if UVC_XU_GetCur(FFD, XU_TRACKING_TARGET_UNIT, XU_TRACKING_TARGET_CONTROL,
    @buf[0], dataLen) then
  begin
    case buf[4] of
      XU_TARGET_SINGLE: Result := ttSingle;
      XU_TARGET_GROUP:  Result := ttGroup;
    end;
    FTrackingTarget := Result;
  end;
end;

{ ===== Special Modes ===== }

function TInsta360Link.SetCameraMode(Mode: TCameraMode): Boolean;
begin
  Result := False;
  if not FConnected then Exit;

  // First disable any active mode
  XU_SetMode(XU_MODE_OFF, 0);
  FAITrackingEnabled := False;

  case Mode of
    cmNormal:
      begin
        Result := True;
        Log('Mode: Normal');
      end;
    cmDeskView:   Result := SetDeskView(True);
    cmWhiteboard: Result := SetWhiteboard(True);
    cmOverhead:   Result := SetOverhead(True);
  end;

  if Result then
    FCurrentMode := Mode;
end;

function TInsta360Link.SetDeskView(Enable: Boolean): Boolean;
begin
  Result := False;
  if not FConnected then Exit;

  if Enable then
    Result := XU_SetMode(XU_MODE_DESKVIEW, XU_FLAG_DESKVIEW)
  else
    Result := XU_SetMode(XU_MODE_OFF, 0);

  if Result then
  begin
    if Enable then
    begin
      FCurrentMode := cmDeskView;
      FAITrackingEnabled := False;
      Log('DeskView: ENABLED');
    end
    else
      Log('DeskView: DISABLED');
  end
  else
    Log('DeskView FAILED');
end;

function TInsta360Link.SetWhiteboard(Enable: Boolean): Boolean;
begin
  Result := False;
  if not FConnected then Exit;

  if Enable then
    Result := XU_SetMode(XU_MODE_WHITEBOARD, XU_FLAG_WHITEBOARD)
  else
    Result := XU_SetMode(XU_MODE_OFF, 0);

  if Result then
  begin
    if Enable then
    begin
      FCurrentMode := cmWhiteboard;
      FAITrackingEnabled := False;
      Log('Whiteboard: ENABLED');
    end
    else
      Log('Whiteboard: DISABLED');
  end
  else
    Log('Whiteboard FAILED');
end;

function TInsta360Link.SetOverhead(Enable: Boolean): Boolean;
begin
  Result := False;
  if not FConnected then Exit;

  if Enable then
    Result := XU_SetMode(XU_MODE_OVERHEAD, XU_FLAG_OVERHEAD)
  else
    Result := XU_SetMode(XU_MODE_OFF, 0);

  if Result then
  begin
    if Enable then
    begin
      FCurrentMode := cmOverhead;
      FAITrackingEnabled := False;
      Log('Overhead: ENABLED');
    end
    else
      Log('Overhead: DISABLED');
  end
  else
    Log('Overhead FAILED');
end;

{ ===== Image Controls ===== }

function TInsta360Link.SetBrightness(Value: LongInt): Boolean;
begin Result := FConnected and V4L2_SetCtrl(FFD, V4L2_CID_BRIGHTNESS, Value); end;

function TInsta360Link.GetBrightness: LongInt;
begin Result := 0; if FConnected then V4L2_GetCtrl(FFD, V4L2_CID_BRIGHTNESS, Result); end;

function TInsta360Link.SetContrast(Value: LongInt): Boolean;
begin Result := FConnected and V4L2_SetCtrl(FFD, V4L2_CID_CONTRAST, Value); end;

function TInsta360Link.GetContrast: LongInt;
begin Result := 0; if FConnected then V4L2_GetCtrl(FFD, V4L2_CID_CONTRAST, Result); end;

function TInsta360Link.SetSaturation(Value: LongInt): Boolean;
begin Result := FConnected and V4L2_SetCtrl(FFD, V4L2_CID_SATURATION, Value); end;

function TInsta360Link.GetSaturation: LongInt;
begin Result := 0; if FConnected then V4L2_GetCtrl(FFD, V4L2_CID_SATURATION, Result); end;

function TInsta360Link.SetSharpness(Value: LongInt): Boolean;
begin Result := FConnected and V4L2_SetCtrl(FFD, V4L2_CID_SHARPNESS, Value); end;

function TInsta360Link.GetSharpness: LongInt;
begin Result := 0; if FConnected then V4L2_GetCtrl(FFD, V4L2_CID_SHARPNESS, Result); end;

function TInsta360Link.SetGain(Value: LongInt): Boolean;
begin Result := FConnected and V4L2_SetCtrl(FFD, V4L2_CID_GAIN, Value); end;

function TInsta360Link.GetGain: LongInt;
begin Result := 0; if FConnected then V4L2_GetCtrl(FFD, V4L2_CID_GAIN, Result); end;

function TInsta360Link.SetBacklightCompensation(Enable: Boolean): Boolean;
begin Result := FConnected and V4L2_SetCtrl(FFD, V4L2_CID_BACKLIGHT_COMPENSATION, Ord(Enable)); end;

function TInsta360Link.GetBacklightCompensation: Boolean;
var v: LongInt;
begin Result := False; if FConnected and V4L2_GetCtrl(FFD, V4L2_CID_BACKLIGHT_COMPENSATION, v) then Result := (v <> 0); end;

function TInsta360Link.SetAutoWhiteBalance(Enable: Boolean): Boolean;
begin Result := FConnected and V4L2_SetCtrl(FFD, V4L2_CID_AUTO_WHITE_BALANCE, Ord(Enable)); end;

function TInsta360Link.GetAutoWhiteBalance: Boolean;
var v: LongInt;
begin Result := True; if FConnected and V4L2_GetCtrl(FFD, V4L2_CID_AUTO_WHITE_BALANCE, v) then Result := (v <> 0); end;

function TInsta360Link.SetWhiteBalanceTemp(Value: LongInt): Boolean;
begin Result := FConnected and V4L2_SetCtrl(FFD, V4L2_CID_WHITE_BALANCE_TEMPERATURE, Value); end;

function TInsta360Link.GetWhiteBalanceTemp: LongInt;
begin Result := 4000; if FConnected then V4L2_GetCtrl(FFD, V4L2_CID_WHITE_BALANCE_TEMPERATURE, Result); end;

function TInsta360Link.SetExposureAuto(Enable: Boolean): Boolean;
begin
  if Enable then
    Result := FConnected and V4L2_SetCtrl(FFD, V4L2_CID_EXPOSURE_AUTO, V4L2_EXPOSURE_APERTURE_PRIORITY)
  else
    Result := FConnected and V4L2_SetCtrl(FFD, V4L2_CID_EXPOSURE_AUTO, V4L2_EXPOSURE_MANUAL);
end;

function TInsta360Link.GetExposureAuto: Boolean;
var v: LongInt;
begin Result := True; if FConnected and V4L2_GetCtrl(FFD, V4L2_CID_EXPOSURE_AUTO, v) then Result := (v <> V4L2_EXPOSURE_MANUAL); end;

function TInsta360Link.SetExposureAbsolute(Value: LongInt): Boolean;
begin Result := FConnected and V4L2_SetCtrl(FFD, V4L2_CID_EXPOSURE_ABSOLUTE, Value); end;

function TInsta360Link.GetExposureAbsolute: LongInt;
begin Result := 250; if FConnected then V4L2_GetCtrl(FFD, V4L2_CID_EXPOSURE_ABSOLUTE, Result); end;

function TInsta360Link.SetAutoFocus(Enable: Boolean): Boolean;
begin Result := FConnected and V4L2_SetCtrl(FFD, V4L2_CID_FOCUS_AUTO, Ord(Enable)); end;

function TInsta360Link.GetAutoFocus: Boolean;
var v: LongInt;
begin Result := True; if FConnected and V4L2_GetCtrl(FFD, V4L2_CID_FOCUS_AUTO, v) then Result := (v <> 0); end;

function TInsta360Link.SetFocusAbsolute(Value: LongInt): Boolean;
begin Result := FConnected and V4L2_SetCtrl(FFD, V4L2_CID_FOCUS_ABSOLUTE, Value); end;

function TInsta360Link.GetFocusAbsolute: LongInt;
begin Result := 0; if FConnected then V4L2_GetCtrl(FFD, V4L2_CID_FOCUS_ABSOLUTE, Result); end;

{ ===== Presets ===== }

function TInsta360Link.SavePreset(Index: Byte): Boolean;
var
  p, t, z: LongInt;
begin
  Result := False;
  if not FConnected then Exit;
  if Index > 5 then Exit;

  // Software preset: use tracked positions for pan/tilt (V4L2 reads may be
  // unreliable on some cameras like Link 2), read zoom directly
  p := FPanPos;
  t := FTiltPos;
  z := 100;
  V4L2_GetCtrl(FFD, V4L2_CID_ZOOM_ABSOLUTE, z);
  FPresets[Index].Pan := p;
  FPresets[Index].Tilt := t;
  FPresets[Index].Zoom := z;
  FPresets[Index].Valid := True;
  Result := True;
  Log('Preset %d SAVED: pan=%d tilt=%d zoom=%d', [Index, p, t, z]);
end;

function TInsta360Link.RecallPreset(Index: Byte): Boolean;
begin
  Result := False;
  if not FConnected then Exit;
  if Index > 5 then Exit;
  if not FPresets[Index].Valid then
  begin
    Log('Preset %d not saved yet', [Index]);
    Exit;
  end;

  // Software preset: restore saved pan/tilt/zoom
  // Use combined set for Link 2 compatibility
  Result := V4L2_SetPanTilt(FFD, FPresets[Index].Pan, FPresets[Index].Tilt);
  if not Result then
  begin
    V4L2_SetCtrl(FFD, V4L2_CID_PAN_ABSOLUTE, FPresets[Index].Pan);
    V4L2_SetCtrl(FFD, V4L2_CID_TILT_ABSOLUTE, FPresets[Index].Tilt);
    Result := True; // Best effort
  end;
  V4L2_SetCtrl(FFD, V4L2_CID_ZOOM_ABSOLUTE, FPresets[Index].Zoom);
  FPanPos := FPresets[Index].Pan;
  FTiltPos := FPresets[Index].Tilt;
  if Result then
    Log('Preset %d RECALLED: pan=%d tilt=%d zoom=%d',
        [Index, FPresets[Index].Pan, FPresets[Index].Tilt, FPresets[Index].Zoom])
  else
    Log('Recall preset %d FAILED', [Index]);
end;

function TInsta360Link.GetPreset(Index: Byte): TPresetPosition;
begin
  FillChar(Result, SizeOf(Result), 0);
  if Index <= 5 then
    Result := FPresets[Index];
end;

procedure TInsta360Link.SetPreset(Index: Byte; const APreset: TPresetPosition);
begin
  if Index <= 5 then
    FPresets[Index] := APreset;
end;

{ ===== Utility ===== }

function TInsta360Link.EnumerateControls: TStringList;
var
  qc: Tv4l2_queryctrl;
  val: LongInt;
begin
  Result := TStringList.Create;
  if not FConnected then Exit;

  // Iterate through user controls
  qc.id := V4L2_CID_BASE;
  while qc.id < V4L2_CID_BASE + 100 do
  begin
    if V4L2_QueryCtrl(FFD, qc) then
    begin
      if (qc.flags and V4L2_CTRL_FLAG_DISABLED) = 0 then
      begin
        V4L2_GetCtrl(FFD, qc.id, val);
        Result.Add(Format('%-30s: val=%d  min=%d  max=%d  step=%d  def=%d',
          [PAnsiChar(@qc.name[0]), val, qc.minimum, qc.maximum,
           qc.step, qc.default_value]));
      end;
    end;
    Inc(qc.id);
  end;

  // Camera class controls
  qc.id := V4L2_CID_CAMERA_CLASS_BASE;
  while qc.id < V4L2_CID_CAMERA_CLASS_BASE + 50 do
  begin
    if V4L2_QueryCtrl(FFD, qc) then
    begin
      if (qc.flags and V4L2_CTRL_FLAG_DISABLED) = 0 then
      begin
        V4L2_GetCtrl(FFD, qc.id, val);
        Result.Add(Format('%-30s: val=%d  min=%d  max=%d  step=%d  def=%d',
          [PAnsiChar(@qc.name[0]), val, qc.minimum, qc.maximum,
           qc.step, qc.default_value]));
      end;
    end;
    Inc(qc.id);
  end;
end;

function TInsta360Link.RawXU_Set(Selector: Byte; const Data: array of Byte): Boolean;
var
  buf: array of Byte;
  i: Integer;
begin
  SetLength(buf, Length(Data));
  for i := 0 to High(Data) do
    buf[i] := Data[i];
  Result := UVC_XU_SetCur(FFD, FXU_UnitID, Selector, @buf[0], Length(Data));
end;

function TInsta360Link.RawXU_Get(Selector: Byte; var Data: array of Byte; Len: Word): Boolean;
begin
  Result := UVC_XU_GetCur(FFD, FXU_UnitID, Selector, @Data[0], Len);
end;

end.
