program gui_controls_tests;
{$mode objfpc}{$H+}
uses Interfaces, Forms, SysUtils, Classes, BaseUnix, uv4l2,
     umainform, mock_camera;
var Starts, Stops, I, BaseStarts, BaseStops, BaseModes, BaseResets: Integer;
    F:TfrmMain; BufferFile:TFileStream;
function CaptureIoctl(fd:cint; Request:LongWord; Data:Pointer):cint;
var W:PLongWord;
begin
  W:=Data;
  if Request = _IOC(3, Ord('V'), 5, 208) then
  begin W[2]:=2; W[3]:=2; W[4]:=$56595559; W[6]:=4; Exit(0); end;
  if Request = _IOC(3, Ord('V'), 8, 20) then
  begin if W[0]<>0 then W[0]:=2; Exit(0); end;
  if Request = _IOC(3, Ord('V'), 9, 88) then
  begin PPtrUInt(PByte(Data)+64)^:=W[0]*4096; W[18]:=4096; Exit(0); end;
  if Request = _IOC(3, Ord('V'), 15, 88) then Exit(0);
  if Request = _IOC(3, Ord('V'), 17, 88) then
  begin fpSetErrno(ESysEAGAIN); Exit(-1); end;
  if Request = _IOC(1, Ord('V'), 18, 4) then begin Inc(Starts); Exit(0); end;
  if Request = _IOC(1, Ord('V'), 19, 4) then begin Inc(Stops); Exit(0); end;
  Result:=MockIoctl(fd,Request,Data);
end;
procedure Check(V:Boolean; const Msg:string);
begin
  if not V then raise Exception.Create('FAIL: '+Msg);
  WriteLn('PASS: ',Msg);
end;
begin
  Application.Initialize;
  ResetAccepted:=True;
  CameraIoctlHook:=@CaptureIoctl;
  BufferFile:=TFileStream.Create('gui-camera-buffers',fmCreate);
  BufferFile.Size:=8192;
  F:=TfrmMain.Create(nil);
  try
    F.TestConnect(ExpandFileName('gui-camera-buffers'));
    Check(Starts=1,'GUI starts initial preview');
    BaseStarts:=Starts; BaseStops:=Stops;
    F.TestControl('tracking');
    BaseModes:=ModeWrites; BaseResets:=ResetWrites;
    F.TestControl('home');
    Check((CurrentPan=0) and (CurrentTilt=0),'GUI Home centers');
    F.TestControl('left'); F.TestControl('preset');
    Check((ModeWrites=BaseModes) and (LastMode=XU_MODE_AI_TRACKING),
      'GUI Home/movement/preset preserve tracking');
    Check(ResetWrites=BaseResets,'ordinary movement never resets gimbal');
    F.TestControl('overhead'); F.TestControl('normal'); F.TestControl('deskview');
    Check(ResetWrites=BaseResets,'mode buttons never reset gimbal');
    for I:=1 to 200 do F.TestControl('tick');
    Check((Starts=BaseStarts) and (Stops=BaseStops),
      'controls and stalled-frame polling never cycle preview');
    F.TestControl('reset');
    Check(ResetWrites=BaseResets+1,'only explicit Gimbal Reset sends reset');
    Check((Starts=BaseStarts) and (Stops=BaseStops),'explicit reset preserves stream');
    F.TestControl('preview');
    Check(Stops=BaseStops+1,'Stop Preview explicitly stops stream');
    F.TestControl('home'); F.TestControl('normal');
    Check(Starts=BaseStarts,'controls do not start a stopped preview');
  finally F.Free; BufferFile.Free; end;
end.
