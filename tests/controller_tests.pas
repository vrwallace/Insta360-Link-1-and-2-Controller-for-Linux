program controller_tests;
{$mode objfpc}{$H+}
uses SysUtils, BaseUnix, uv4l2, uinsta360link, ulinksettings, mock_camera;
procedure Check(OK: Boolean; const Msg: string);
begin
  if not OK then raise Exception.Create('FAIL: '+Msg);
  WriteLn('PASS: ',Msg);
end;
var C: TInsta360Link; P, Saved: TPresetPosition; Settings: TLinkSettings;
    Data: array[0..0] of Byte; Before: Integer;
begin
  C := TInsta360Link.Create;
  try
    CameraIoctlHook:=nil;
    Check(not C.Open('/dev/null'),'reject non-camera fd');
    CameraIoctlHook := @MockIoctl;
    C.XU_UnitID := 4;
    CurrentPan:=12; CurrentTilt:=34; CurrentZoom:=100;
    Check(C.Open('/dev/null'),'open mocked camera');
    Check(C.SetCameraMode(cmNormal),'scan override unit 4');
    C.DumpAllXU;
    Check(C.SetCameraMode(cmNormal),'XU snapshot preserves selector cache');
    C.XU_UnitID:=9;
    Check(not C.SetCameraMode(cmNormal),'changing unit invalidates old selector lengths');
    C.XU_UnitID:=4;
    Check(C.SetCameraMode(cmNormal),'changing unit refreshes selector lengths');
    FailMode := True;
    Check(not C.SetCameraMode(cmNormal),'failed Normal mode');
    FailMode := False;
    P.Name:='position'; P.Valid:=True; P.Pan:=200; P.Tilt:=300; P.Zoom:=150;
    C.SetPreset(0,P);
    Check(C.SetPanAbsolute(12),'set initial pan for partial-write test');
    FailPan:=True; FailTilt:=False;
    Check(not C.RecallPreset(0),'partial preset movement fails');
    FailRead:=True;
    Check(C.GetPanAbsolute=12,'failed pan does not update cached position');
    Check(C.GetTiltAbsolute=300,'successful tilt updates cached position');
    Check(not C.SavePreset(0),'failed read does not save stale preset');
    Saved:=C.GetPreset(0); Check(Saved.Pan=200,'failed save preserves existing preset');
    FailRead:=False;
    Check(not C.PanTiltRelative(1,1),'relative movement propagates pan failure');
    Check(not C.GimbalReset,'reset propagates pan failure');
    FailPan:=False; FailZoom:=True;
    Check(not C.RecallPreset(0),'preset zoom failure propagates');
    FailZoom:=False;
    Check(C.RecallPreset(0),'successful preset recall');
    CurrentPan:=444; CurrentTilt:=555;
    Check(C.SavePreset(1),'save fresh readback after external movement');
    Saved:=C.GetPreset(1); Check((Saved.Pan=444) and (Saved.Tilt=555),'fresh positions persisted in memory');
    ResetAccepted:=True;
    C.XU_UnitID:=4;
    CurrentPan:=10000; CurrentTilt:=-300000;
    Check(C.GimbalReset,'successful reset');
    Check((ResetWrites>0) and (CurrentPan=0) and (CurrentTilt=0),
      'accepted XU reset still sends absolute center');
    Check(C.SetCameraMode(cmDeskView),'enter special mode before reset');
    Check(C.GimbalReset and (LastMode=0),'reset exits special mode before centering');
    Check(C.SetCameraMode(cmOverhead),'enter overhead');
    CurrentTilt:=-300000;
    Check(C.SetCameraMode(cmNormal),'leave overhead');
    Check(CurrentTilt=-300000,'Normal changes mode without moving or resetting');
    Check(C.SetCameraMode(cmDeskView),'enter DeskView');
    CurrentTilt:=-300000;
    Check(C.SetCameraMode(cmNormal),'leave DeskView');
    Check(CurrentTilt=-300000,'Normal does not reset DeskView position');
    Check(C.SetAITracking(True),'enable tracking before Home');
    Before:=ResetWrites;
    Check(C.MoveHome,'Home moves to center');
    Check((CurrentPan=0) and (CurrentTilt=0) and (ResetWrites=Before),
      'Home centers without hardware reset');
    Check(C.AITrackingEnabled and (LastMode=XU_MODE_AI_TRACKING),
      'Home preserves tracking');
    Before:=ModeWrites;
    Check(C.PanTiltRelative(1,1),'manual move while tracking');
    Check(C.RecallPreset(0),'preset while tracking');
    Check((ModeWrites=Before) and C.AITrackingEnabled,'movement and preset do not change modes');
    CurrentPan:=0; CurrentTilt:=0;
    Check(C.PanTiltRelative(1,1),'relative move');
    Check((CurrentPan=3600) and (CurrentTilt=3600),'degree-sized movement restored');
    CurrentTilt:=-250000;
    Check(C.PanTiltRelative(0,-30),'move toward downward limit');
    Check(CurrentTilt=-252000,'manual tilt stops above privacy position');
    C.TestCameraModel:=cmLink2Pro;
    Check(C.SetPanAbsolute(12000),'command Link2 pan');
    Check(C.SetTiltAbsolute(18000),'command Link2 tilt');
    CurrentPan:=0; CurrentTilt:=0; // successful but stale hardware readback
    Check(C.SavePreset(2),'Link2 preset save without mode read support');
    Saved:=C.GetPreset(2);
    Check((Saved.Pan=12000) and (Saved.Tilt=18000),'Link2 preserves commanded coordinates');
    ModeLength:=64; C.XU_UnitID:=4;
    Check(C.ReadXUControl(2,Data),'padded reads use discovered selector length');
    Check(Data[0]=6,'padded reads return mode payload');
    Before:=Writes;
    Check(not C.RawXU_Get(2,Data,52),'reject undersized XU buffer');
    Check(Writes=Before,'invalid XU read does not write');
    Settings:=TLinkSettings.Create;
    try Settings.WritePreset(0,P); Settings.Commit; finally Settings.Free; end;
    Settings:=TLinkSettings.Create;
    try Saved:=C.GetPreset(1); Settings.WritePreset(1,Saved); Settings.Commit; finally Settings.Free; end;
    // GUI preference/name-only save must preserve slots changed by another writer.
    Settings:=TLinkSettings.Create;
    try
      Settings.Ini.WriteInteger('PTZ','PanStep',8);
      Settings.Ini.WriteString('Presets','Name0','renamed');
      Settings.Commit;
    finally Settings.Free; end;
    LoadLinkPresets(C);
    Saved:=C.GetPreset(0); Check((Saved.Pan=200) and (Saved.Name='renamed'),'merge preserves position on name change');
    Saved:=C.GetPreset(1); Check(Saved.Pan=444,'other preset survives preference save');
    CameraIoctlHook:=nil;
  finally C.Free; end;
end.
