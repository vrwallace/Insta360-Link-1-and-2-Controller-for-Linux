unit mock_camera;
{$mode objfpc}{$H+}
interface
uses SysUtils, BaseUnix, uv4l2;
var FailPan, FailTilt, FailZoom, FailRead, FailMode: Boolean;
    CurrentPan, CurrentTilt, CurrentZoom: LongInt;
    Writes: Integer;
    ResetAccepted: Boolean;
    ResetWrites: Integer;
    ModeLength: Word = 52;
    LastMode: Byte;
function MockIoctl(fd: cint; Request: LongWord; Data: Pointer): cint;
implementation
function MockIoctl(fd: cint; Request: LongWord; Data: Pointer): cint;
var C: ^Tv4l2_control; Q: ^Tv4l2_queryctrl; U: ^Tuvc_xu_control_query;
begin
  Result := -1;
  fpSetErrno(ESysEIO);
  if Request = VIDIOC_QUERYCAP then
  begin
    FillChar(Data^, SizeOf(Tv4l2_capability),0);
    Tv4l2_capability(Data^).capabilities := V4L2_CAP_VIDEO_CAPTURE;
    Exit(0);
  end;
  if Request = VIDIOC_QUERYCTRL then
  begin
    Q := Data; Q^.minimum := -324000; Q^.maximum := 324000; Q^.step := 1;
    Q^.flags := 0; Exit(0);
  end;
  if Request = VIDIOC_G_CTRL then
  begin
    if FailRead then Exit;
    C := Data;
    case C^.id of
      V4L2_CID_PAN_ABSOLUTE: C^.value := CurrentPan;
      V4L2_CID_TILT_ABSOLUTE: C^.value := CurrentTilt;
      V4L2_CID_ZOOM_ABSOLUTE: C^.value := CurrentZoom;
    else C^.value := 0; end;
    Exit(0);
  end;
  if Request = VIDIOC_S_EXT_CTRLS then Exit; // exercise separate-axis fallback
  if Request = VIDIOC_S_CTRL then
  begin
    Inc(Writes); C := Data;
    case C^.id of
      V4L2_CID_PAN_ABSOLUTE: if not FailPan then begin CurrentPan:=C^.value; Exit(0); end;
      V4L2_CID_TILT_ABSOLUTE: if not FailTilt then begin CurrentTilt:=C^.value; Exit(0); end;
      V4L2_CID_ZOOM_ABSOLUTE: if not FailZoom then begin CurrentZoom:=C^.value; Exit(0); end;
    end;
    Exit;
  end;
  if Request = UVCIOC_CTRL_QUERY then
  begin
    U := Data;
    if (U^.xu_unit=4) and (U^.selector=14) and ResetAccepted then
    begin
      if U^.query=UVC_GET_LEN then begin PWord(U^.data)^:=1; Exit(0); end;
      if U^.query=UVC_GET_INFO then begin PByte(U^.data)^:=2; Exit(0); end;
      if U^.query=UVC_SET_CUR then begin Inc(ResetWrites); Exit(0); end;
    end;
    if (U^.xu_unit = 4) and (U^.selector = 2) then
    begin
      if U^.query = UVC_GET_LEN then begin PWord(U^.data)^ := ModeLength; Exit(0); end;
      if U^.query = UVC_GET_INFO then begin PByte(U^.data)^ := 3; Exit(0); end;
      if U^.query = UVC_GET_CUR then
      begin
        if U^.size<>ModeLength then Exit;
        FillChar(U^.data^, U^.size, 0); PByte(U^.data)^:=6; Exit(0);
      end;
      if U^.query = UVC_SET_CUR then
      begin Inc(Writes); if not FailMode then begin LastMode:=PByte(U^.data)^; Exit(0); end; end;
    end;
  end;
end;
initialization
  CurrentPan:=12; CurrentTilt:=34; CurrentZoom:=100;
  FailRead:=GetEnvironmentVariable('PRO3_TEST_FAIL')='read';
  FailMode:=GetEnvironmentVariable('PRO3_TEST_FAIL')='mode';
  FailZoom:=GetEnvironmentVariable('PRO3_TEST_FAIL')='zoom';
  CameraIoctlHook:=@MockIoctl;
end.
