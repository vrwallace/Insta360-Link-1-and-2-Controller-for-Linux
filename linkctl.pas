{
  linkctl.pas - Command-line controller for Insta360 Link webcam
  ===============================================================
  Usage:
    linkctl [options] <command> [args]

  Options:
    -d /dev/videoN   Specify device (default: auto-detect)
    -u N             Specify XU unit ID (default: auto-detect)
    -v               Verbose output

  Commands:
    list             List available V4L2 video devices
    info             Show camera info and all controls
    pan <value>      Set absolute pan (-36000..36000)
    tilt <value>     Set absolute tilt (-36000..36000)
    move <px> <ty>   Relative pan/tilt (-30..30 each)
    zoom <value>     Set zoom (100=1x to 400=4x)
    home             Move pan/tilt to center
    tracking on|off  Enable/disable AI tracking
    frame head|half|full  Set tracking framing mode
    deskview on|off  Toggle DeskView mode
    whiteboard on|off Toggle Whiteboard mode
    overhead on|off  Toggle Overhead document view
    brightness <val> Set brightness
    contrast <val>   Set contrast
    saturation <val> Set saturation
    sharpness <val>  Set sharpness
    gain <val>       Set gain
    wb auto|<temp>   White balance (auto or Kelvin temp)
    exposure auto|<val> Exposure (auto or absolute value)
    focus auto|<val> Focus (auto or absolute value)
    backlight on|off Backlight compensation
    preset save <0-5>  Save current position to preset
    preset recall <0-5> Recall preset position
    xu <sel> <b0> [b1..] Raw XU set (hex bytes)
    get <control_name>  Get a V4L2 control value

  XU Mode Control (confirmed via Windows KS monitoring):
    All modes use XU Unit 9, Selector 2 (52-byte buffer).
    AI Tracking: byte[0]=$01 byte[1]=$00
    Whiteboard:  byte[0]=$04 byte[1]=$01
    Overhead:    byte[0]=$05 byte[1]=$03
    DeskView:    byte[0]=$06 byte[1]=$10
    Off/Normal:  byte[0]=$00

  Examples:
    linkctl list
    linkctl -d /dev/video0 info
    linkctl tracking on
    linkctl move 10 0         (pan right)
    linkctl zoom 200          (2x zoom)
    linkctl deskview on
    linkctl preset save 0
    linkctl xu 3 01           (raw XU selector 3, data 0x01)
}
program linkctl;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, IniFiles, uv4l2, uinsta360link, ulinksettings;

type
  { TInsta360Link.OnLog is a 'procedure ... of object' event, so the callback
    must be a method, not a free-standing procedure. This tiny class adapts the
    console logger to that signature. }
  TConsoleLog = class
    procedure Handle(Sender: TObject; const Msg: string);
  end;

var
  Cam: TInsta360Link;
  ConsoleLog: TConsoleLog;
  DevicePath: string;
  XUnitID: Integer;
  Verbose: Boolean;

procedure ShowHelp;
begin
  WriteLn('Insta360 Link Webcam Controller for Linux');
  WriteLn('==========================================');
  WriteLn;
  WriteLn('Usage: linkctl [options] <command> [args]');
  WriteLn;
  WriteLn('Options:');
  WriteLn('  -d /dev/videoN   Specify device (default: auto-detect)');
  WriteLn('  -u N             Specify XU unit ID (default: auto-detect)');
  WriteLn('  -v               Verbose output');
  WriteLn;
  WriteLn('PTZ Commands:');
  WriteLn('  pan <value>         Set absolute pan');
  WriteLn('  tilt <value>        Set absolute tilt');
  WriteLn('  move <px> <ty>      Relative pan/tilt');
  WriteLn('  zoom <value>        Set zoom (100=1x to 400=4x)');
  WriteLn('  home                Move pan/tilt to center');
  WriteLn;
  WriteLn('AI & Mode Commands:');
  WriteLn('  tracking on|off     AI tracking');
  WriteLn('  frame head|half|full  Tracking framing mode');
  WriteLn('  deskview on|off     DeskView (split desk + face)');
  WriteLn('  whiteboard on|off   Whiteboard mode');
  WriteLn('  overhead on|off     Overhead document view');
  WriteLn('  normal              Reset to normal operating mode');
  WriteLn;
  WriteLn('Image Commands:');
  WriteLn('  brightness <val>    Set brightness');
  WriteLn('  contrast <val>      Set contrast');
  WriteLn('  saturation <val>    Set saturation');
  WriteLn('  sharpness <val>     Set sharpness');
  WriteLn('  gain <val>          Set gain');
  WriteLn('  wb auto|<temp>      White balance');
  WriteLn('  exposure auto|<val> Exposure');
  WriteLn('  focus auto|<val>    Focus');
  WriteLn('  backlight on|off    Backlight compensation');
  WriteLn;
  WriteLn('Other Commands:');
  WriteLn('  get <control_name>  Get control value (e.g. pan, tilt, zoom, brightness, tracking)');
  WriteLn('  list                List video devices');
  WriteLn('  info                Show camera info + all controls');
  WriteLn('  preset save|recall <0-5>');
  WriteLn('  xu <selector> <hex_bytes...>   Raw XU command');
end;

function SavePresetToDisk(ACam: TInsta360Link; Index: Integer): Boolean;
var Settings: TLinkSettings; P: TPresetPosition;
begin
  Result := False;
  try
    Settings := TLinkSettings.Create;
    try
      P := ACam.GetPreset(Index);
      P.Name := Settings.Ini.ReadString('Presets', 'Name'+IntToStr(Index), P.Name);
      Settings.WritePreset(Index, P);
      Settings.Commit;
      Result := True;
    finally Settings.Free; end;
  except
    on E: Exception do WriteLn(StdErr, 'ERROR: Could not save preset: ', E.Message);
  end;
end;

function ParseHexByte(const S: string): Byte;
var
  CleanS: string;
  val: LongInt;
begin
  CleanS := Trim(S);
  if (Length(CleanS) >= 2) and (CleanS[1] = '0') and ((CleanS[2] = 'x') or (CleanS[2] = 'X')) then
    CleanS := '$' + Copy(CleanS, 3, Length(CleanS) - 2)
  else if (Length(CleanS) >= 1) and (CleanS[1] <> '$') then
    CleanS := '$' + CleanS;
  if not TryStrToInt(CleanS, val) or (val < 0) or (val > 255) then
    raise EConvertError.Create('Invalid hex byte: ' + S);
  Result := Byte(val);
end;

procedure TConsoleLog.Handle(Sender: TObject; const Msg: string);
begin
  if Verbose then
    WriteLn('[LOG] ', Msg);
end;

procedure DoList;
var
  devs: array[0..31] of string;
  cnt, i: Integer;
begin
  V4L2_EnumDevices(devs, cnt);
  if cnt = 0 then
    WriteLn('No V4L2 video devices found.')
  else
    for i := 0 to cnt - 1 do
      WriteLn(devs[i]);
end;

function AutoDetectDevice: string;
var
  devs: array[0..31] of string;
  cnt, i: Integer;
begin
  Result := '';
  V4L2_EnumDevices(devs, cnt);
  for i := 0 to cnt - 1 do
  begin
    if (Pos('Insta360', devs[i]) > 0) or (Pos('insta360', devs[i]) > 0) then
    begin
      // Extract device path (first token before space)
      Result := Copy(devs[i], 1, Pos(' ', devs[i]) - 1);
      if Result <> '' then Exit;
    end;
  end;
  // Fallback: first device
  if (cnt > 0) and (Result = '') then
  begin
    Result := Copy(devs[0], 1, Pos(' ', devs[0]) - 1);
    if Result = '' then Result := '/dev/video0';
  end;
  if Result = '' then Result := '/dev/video0';
end;

function ParseOnOff(const s: string): Boolean;
begin
  Result := (LowerCase(s) = 'on') or (s = '1') or (LowerCase(s) = 'true') or
            (LowerCase(s) = 'yes') or (LowerCase(s) = 'enable');
end;

function IsOnOff(const S: string): Boolean;
var
  V: string;
begin
  V := LowerCase(S);
  Result := (V = 'on') or (V = 'off') or (V = '1') or (V = '0') or
    (V = 'true') or (V = 'false') or (V = 'yes') or (V = 'no') or
    (V = 'enable') or (V = 'disable');
end;

procedure UsageError(const Msg: string);
begin
  WriteLn(StdErr, 'ERROR: ', Msg);
  WriteLn(StdErr, 'Run "linkctl help" for usage.');
  Halt(2);
end;

function ConnectCamera: Boolean;
begin
  if DevicePath = '' then
    DevicePath := AutoDetectDevice;

  Cam := TInsta360Link.Create;
  Cam.OnLog := @ConsoleLog.Handle;

  if XUnitID >= 0 then
    Cam.XU_UnitID := Byte(XUnitID);

  Result := Cam.Open(DevicePath);
  if not Result then
  begin
    WriteLn(StdErr, 'ERROR: Cannot open video capture device ', DevicePath);
    WriteLn('Try running with sudo or check device permissions.');
    Cam.Free;
  end
  else
  begin
    LoadLinkPresets(Cam);
    if not Verbose then
      WriteLn('Connected: ', Cam.DeviceName, ' (', DevicePath, ')');
  end;
end;

function PrintControl(const Name: string): Boolean;
var
  Data: array[0..51] of Byte;
  A, B: Boolean;
  function ReadValue(ID: LongWord; const LabelText: string): Boolean;
  var V: LongInt;
  begin
    Result := V4L2_GetCtrl(Cam.FD, ID, V);
    if Result then WriteLn(LabelText, ': ', V);
  end;
begin
  Result := False;
  case Name of
    'pan': Result := ReadValue(V4L2_CID_PAN_ABSOLUTE, 'Pan');
    'tilt': Result := ReadValue(V4L2_CID_TILT_ABSOLUTE, 'Tilt');
    'zoom': Result := ReadValue(V4L2_CID_ZOOM_ABSOLUTE, 'Zoom');
    'brightness': Result := ReadValue(V4L2_CID_BRIGHTNESS, 'Brightness');
    'contrast': Result := ReadValue(V4L2_CID_CONTRAST, 'Contrast');
    'saturation': Result := ReadValue(V4L2_CID_SATURATION, 'Saturation');
    'sharpness': Result := ReadValue(V4L2_CID_SHARPNESS, 'Sharpness');
    'gain': Result := ReadValue(V4L2_CID_GAIN, 'Gain');
    'backlight': Result := ReadValue(V4L2_CID_BACKLIGHT_COMPENSATION, 'Backlight');
    'wb': begin
      A := ReadValue(V4L2_CID_AUTO_WHITE_BALANCE, 'Auto white balance');
      B := ReadValue(V4L2_CID_WHITE_BALANCE_TEMPERATURE, 'White balance temperature');
      Result := A and B;
    end;
    'exposure': begin
      A := ReadValue(V4L2_CID_EXPOSURE_AUTO, 'Exposure mode');
      B := ReadValue(V4L2_CID_EXPOSURE_ABSOLUTE, 'Exposure');
      Result := A and B;
    end;
    'focus': begin
      A := ReadValue(V4L2_CID_FOCUS_AUTO, 'Auto focus');
      B := ReadValue(V4L2_CID_FOCUS_ABSOLUTE, 'Focus');
      Result := A and B;
    end;
    'tracking': begin
      Result := Cam.ReadXUControl(XU_MODE_CONTROL, Data);
      if Result then WriteLn('Tracking: ', Data[0] = XU_MODE_AI_TRACKING);
    end;
    'frame': begin
      Result := Cam.ReadXUControl(XU_TRACKING_FRAME_CONTROL, Data);
      if Result then
        case Data[0] of
          XU_FRAME_HEAD: WriteLn('Frame: head');
          XU_FRAME_HALF_BODY: WriteLn('Frame: half');
          XU_FRAME_FULL_BODY: WriteLn('Frame: full');
        else Result := False; end;
    end;
  end;
end;

procedure DoInfo;
var
  ctrls: TStringList;
  i: Integer;
begin
  WriteLn('Device: ', Cam.DeviceName);
  WriteLn('Driver: ', Cam.DriverName);
  WriteLn('Bus:    ', Cam.BusInfo);
  WriteLn('XU ID:  ', Cam.XU_UnitID);
  WriteLn;
  WriteLn('=== Available Controls ===');

  ctrls := Cam.EnumerateControls;
  try
    for i := 0 to ctrls.Count - 1 do
      WriteLn(ctrls[i]);
  finally
    ctrls.Free;
  end;

  WriteLn;
  WriteLn('=== Control Ranges ===');
  if Cam.PanRange.Available then
    WriteLn(Format('Pan:        %d..%d  current=%d', [Cam.PanRange.Min, Cam.PanRange.Max, Cam.GetPanAbsolute]));
  if Cam.TiltRange.Available then
    WriteLn(Format('Tilt:       %d..%d  current=%d', [Cam.TiltRange.Min, Cam.TiltRange.Max, Cam.GetTiltAbsolute]));
  if Cam.ZoomRange.Available then
    WriteLn(Format('Zoom:       %d..%d  current=%d', [Cam.ZoomRange.Min, Cam.ZoomRange.Max, Cam.GetZoom]));
  if Cam.FocusRange.Available then
    WriteLn(Format('Focus:      %d..%d  current=%d', [Cam.FocusRange.Min, Cam.FocusRange.Max, Cam.GetFocusAbsolute]));
  if Cam.BrightnessRange.Available then
    WriteLn(Format('Brightness: %d..%d  current=%d', [Cam.BrightnessRange.Min, Cam.BrightnessRange.Max, Cam.GetBrightness]));
end;

var
  i, j, argIdx, expectedArgs: Integer;
  cmd: string;
  ok: Boolean;
  sel: Byte;
  data: array of Byte;
begin
  DevicePath := '';
  XUnitID := -1;
  Verbose := False;
  ConsoleLog := TConsoleLog.Create;

  if ParamCount = 0 then
  begin
    ShowHelp;
    Exit;
  end;

  // Parse options
  argIdx := 1;
  while (argIdx <= ParamCount) and (Length(ParamStr(argIdx)) > 0) and (ParamStr(argIdx)[1] = '-') do
  begin
    case ParamStr(argIdx) of
      '-d': begin
        if argIdx = ParamCount then UsageError('-d requires a device path');
        Inc(argIdx);
        DevicePath := ParamStr(argIdx);
      end;
      '-u': begin
        if argIdx = ParamCount then UsageError('-u requires a unit ID');
        Inc(argIdx);
        if not TryStrToInt(ParamStr(argIdx), XUnitID) or
           (XUnitID < 0) or (XUnitID > 255) then
          UsageError('-u expects a unit ID from 0 to 255');
      end;
      '-v': Verbose := True;
      '-h', '--help': begin ShowHelp; Exit; end;
    else
      UsageError('unknown option: ' + ParamStr(argIdx));
    end;
    Inc(argIdx);
  end;

  if argIdx > ParamCount then
  begin
    ShowHelp;
    Exit;
  end;

  cmd := LowerCase(ParamStr(argIdx));
  Inc(argIdx);

  // Validate the entire command before opening a device.
  case cmd of
    'list', 'info', 'help', 'home', 'normal': expectedArgs := 0;
    'move', 'preset': expectedArgs := 2;
    'xu': expectedArgs := -1;
    'pan', 'tilt', 'zoom', 'tracking', 'frame', 'deskview', 'whiteboard',
    'overhead', 'brightness', 'contrast', 'saturation', 'sharpness', 'gain',
    'backlight', 'wb', 'exposure', 'focus', 'get': expectedArgs := 1;
  else UsageError('unknown command: ' + cmd);
  end;
  if (expectedArgs >= 0) and (ParamCount - argIdx + 1 <> expectedArgs) then
    UsageError(cmd + ' expects ' + IntToStr(expectedArgs) + ' argument(s)');
  if (cmd = 'wb') or (cmd = 'exposure') or (cmd = 'focus') then
    if LowerCase(ParamStr(argIdx)) <> 'auto' then
      if not TryStrToInt(ParamStr(argIdx), i) or (i < 0) then
        UsageError(cmd + ' expects auto or a nonnegative integer');
  if (cmd = 'frame') and (LowerCase(ParamStr(argIdx)) <> 'head') and
     (LowerCase(ParamStr(argIdx)) <> 'half') and
     (LowerCase(ParamStr(argIdx)) <> 'full') then UsageError('frame expects head|half|full');
  if cmd = 'get' then
    case LowerCase(ParamStr(argIdx)) of
      'brightness','contrast','saturation','sharpness','gain','pan','tilt',
      'zoom','wb','exposure','focus','backlight','tracking','frame': ;
    else UsageError('unknown control: ' + ParamStr(argIdx)); end;
  if cmd = 'xu' then
  begin
    if not TryStrToInt(ParamStr(argIdx), i) or (i < 1) or (i > 255) then
      UsageError('xu selector must be from 1 to 255');
    if ParamCount - argIdx > High(Word) then UsageError('too many XU bytes');
    for j := argIdx + 1 to ParamCount do
      try
        ParseHexByte(ParamStr(j));
      except on E: EConvertError do UsageError(E.Message); end;
  end;

  // Validate command arguments before opening the camera. ParamStr returns an
  // empty string for missing arguments, which previously turned into unsafe
  // default values such as pan=0 or zoom=100.
  if (cmd = 'move') and (argIdx + 1 > ParamCount) then
    UsageError('move requires <pan> <tilt>')
  else if (cmd = 'preset') and (argIdx + 1 > ParamCount) then
    UsageError('preset requires save|recall <0-5>')
  else if (cmd = 'xu') and (argIdx + 1 > ParamCount) then
    UsageError('xu requires <selector> <hex_byte> [hex_byte...]')
  else if (cmd = 'get') and (argIdx > ParamCount) then
    UsageError('get requires <control_name>')
  else if (cmd = 'pan') or (cmd = 'tilt') or (cmd = 'zoom') or
          (cmd = 'tracking') or (cmd = 'frame') or (cmd = 'deskview') or
          (cmd = 'whiteboard') or (cmd = 'overhead') or
          (cmd = 'brightness') or (cmd = 'contrast') or
          (cmd = 'saturation') or (cmd = 'sharpness') or (cmd = 'gain') or
          (cmd = 'backlight') or (cmd = 'wb') or (cmd = 'exposure') or
          (cmd = 'focus') then
    if argIdx > ParamCount then UsageError(cmd + ' requires an argument');

  if ((cmd = 'tracking') or (cmd = 'deskview') or (cmd = 'whiteboard') or
      (cmd = 'overhead') or (cmd = 'backlight')) and
     not IsOnOff(ParamStr(argIdx)) then
    UsageError(cmd + ' expects on or off');

  if (cmd = 'pan') or (cmd = 'tilt') or (cmd = 'zoom') or
     (cmd = 'brightness') or (cmd = 'contrast') or (cmd = 'saturation') or
     (cmd = 'sharpness') or (cmd = 'gain') then
    if not TryStrToInt(ParamStr(argIdx), i) then
      UsageError(cmd + ' expects an integer');

  if cmd = 'move' then
  begin
    if not TryStrToInt(ParamStr(argIdx), i) or
       not TryStrToInt(ParamStr(argIdx + 1), j) then
      UsageError('move expects two integers');
  end;

  if cmd = 'preset' then
  begin
    if (LowerCase(ParamStr(argIdx)) <> 'save') and
       (LowerCase(ParamStr(argIdx)) <> 'recall') then
      UsageError('preset expects save or recall');
    if not TryStrToInt(ParamStr(argIdx + 1), i) or (i < 0) or (i > 5) then
      UsageError('preset index must be from 0 to 5');
  end;

  // Commands that don't need a connection
  if cmd = 'list' then
  begin
    DoList;
    Exit;
  end;

  if cmd = 'help' then
  begin
    ShowHelp;
    Exit;
  end;

  // All other commands need a connection
  if not ConnectCamera then
  begin
    ExitCode := 1;
    ConsoleLog.Free;
    Exit;
  end;

  try
    ok := False;

    // ===== PTZ =====
    if cmd = 'pan' then
      ok := Cam.SetPanAbsolute(StrToIntDef(ParamStr(argIdx), 0))
    else if cmd = 'tilt' then
      ok := Cam.SetTiltAbsolute(StrToIntDef(ParamStr(argIdx), 0))
    else if cmd = 'move' then
      ok := Cam.PanTiltRelative(
        StrToIntDef(ParamStr(argIdx), 0),
        StrToIntDef(ParamStr(argIdx + 1), 0))
    else if cmd = 'zoom' then
      ok := Cam.SetZoom(StrToIntDef(ParamStr(argIdx), 100))
    else if cmd = 'home' then
      ok := Cam.MoveHome

    // ===== AI & Modes =====
    else if cmd = 'tracking' then
      ok := Cam.SetAITracking(ParseOnOff(ParamStr(argIdx)))
    else if cmd = 'frame' then
    begin
      case LowerCase(ParamStr(argIdx)) of
        'head':  ok := Cam.SetTrackingFrame(tfHead);
        'half':  ok := Cam.SetTrackingFrame(tfHalfBody);
        'full':  ok := Cam.SetTrackingFrame(tfFullBody);
      else
        WriteLn('Unknown frame mode: ', ParamStr(argIdx), ' (use head|half|full)');
      end;
    end
    else if cmd = 'deskview' then
      ok := Cam.SetDeskView(ParseOnOff(ParamStr(argIdx)))
    else if cmd = 'whiteboard' then
      ok := Cam.SetWhiteboard(ParseOnOff(ParamStr(argIdx)))
    else if cmd = 'overhead' then
      ok := Cam.SetOverhead(ParseOnOff(ParamStr(argIdx)))
    else if cmd = 'normal' then
      ok := Cam.SetCameraMode(cmNormal)

    // ===== Image =====
    else if cmd = 'brightness' then
      ok := Cam.SetBrightness(StrToIntDef(ParamStr(argIdx), 128))
    else if cmd = 'contrast' then
      ok := Cam.SetContrast(StrToIntDef(ParamStr(argIdx), 128))
    else if cmd = 'saturation' then
      ok := Cam.SetSaturation(StrToIntDef(ParamStr(argIdx), 128))
    else if cmd = 'sharpness' then
      ok := Cam.SetSharpness(StrToIntDef(ParamStr(argIdx), 128))
    else if cmd = 'gain' then
      ok := Cam.SetGain(StrToIntDef(ParamStr(argIdx), 0))
    else if cmd = 'backlight' then
      ok := Cam.SetBacklightCompensation(ParseOnOff(ParamStr(argIdx)))
    else if cmd = 'wb' then
    begin
      if LowerCase(ParamStr(argIdx)) = 'auto' then
        ok := Cam.SetAutoWhiteBalance(True)
      else
      begin
        ok := Cam.SetAutoWhiteBalance(False);
        if ok then ok := Cam.SetWhiteBalanceTemp(StrToInt(ParamStr(argIdx)));
      end;
    end
    else if cmd = 'exposure' then
    begin
      if LowerCase(ParamStr(argIdx)) = 'auto' then
        ok := Cam.SetExposureAuto(True)
      else
      begin
        ok := Cam.SetExposureAuto(False);
        if ok then ok := Cam.SetExposureAbsolute(StrToInt(ParamStr(argIdx)));
      end;
    end
    else if cmd = 'focus' then
    begin
      if LowerCase(ParamStr(argIdx)) = 'auto' then
        ok := Cam.SetAutoFocus(True)
      else
      begin
        ok := Cam.SetAutoFocus(False);
        if ok then ok := Cam.SetFocusAbsolute(StrToInt(ParamStr(argIdx)));
      end;
    end

    // ===== Get Control =====
    else if cmd = 'get' then
      ok := PrintControl(LowerCase(ParamStr(argIdx)))

    // ===== Presets =====
    else if cmd = 'preset' then
    begin
      if LowerCase(ParamStr(argIdx)) = 'save' then
      begin
        ok := Cam.SavePreset(StrToIntDef(ParamStr(argIdx + 1), 0));
        if ok then
        begin
          ok := SavePresetToDisk(Cam, StrToInt(ParamStr(argIdx + 1)));
          if ok then WriteLn('Preset ', ParamStr(argIdx + 1), ' saved to config');
        end;
      end
      else if LowerCase(ParamStr(argIdx)) = 'recall' then
        ok := Cam.RecallPreset(StrToIntDef(ParamStr(argIdx + 1), 0))
      else
        WriteLn('Usage: preset save|recall <0-5>');
    end

    // ===== Raw XU =====
    else if cmd = 'xu' then
    begin
      if argIdx <= ParamCount then
      begin
        sel := StrToIntDef(ParamStr(argIdx), 0);
        Inc(argIdx);
        if argIdx <= ParamCount then
        begin
          SetLength(data, ParamCount - argIdx + 1);
          for i := 0 to High(data) do
            data[i] := ParseHexByte(ParamStr(argIdx + i));
          ok := Cam.RawXU_Set(sel, data);
          if ok then WriteLn('XU command sent OK')
          else WriteLn('XU command FAILED');
        end
        else
          UsageError('xu requires data bytes');
      end;
    end

    // ===== Info =====
    else if cmd = 'info' then
    begin
      DoInfo;
      ok := True;
    end
    else
    begin
      WriteLn('Unknown command: ', cmd);
      WriteLn('Run "linkctl help" for usage.');
    end;

    if ok then
      WriteLn('OK')
    else
    begin
      ExitCode := 1;
      WriteLn(StdErr, 'ERROR: Command failed. Run with -v for details.');
    end;

  finally
    Cam.Close;
    Cam.Free;
    ConsoleLog.Free;
  end;
end.
