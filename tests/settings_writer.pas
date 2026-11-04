program settings_writer;
{$mode objfpc}{$H+}
uses SysUtils, ulinksettings, uinsta360link;
var Settings:TLinkSettings; P:TPresetPosition; Slot,I:Integer; C:TInsta360Link;
begin
  if ParamStr(1)='check' then
  begin
    C:=TInsta360Link.Create;
    try
      LoadLinkPresets(C);
      for Slot:=0 to 1 do
      begin
        P:=C.GetPreset(Slot);
        if (P.Pan<>19) or (P.Name<>'writer'+IntToStr(Slot)) then
          raise Exception.Create('Concurrent preset update lost');
      end;
    finally C.Free; end;
    Exit;
  end;
  Slot:=StrToInt(ParamStr(1));
  P.Name:='writer'+IntToStr(Slot); P.Valid:=True; P.Tilt:=0; P.Zoom:=100;
  for I:=0 to 19 do
  begin
    Settings:=TLinkSettings.Create;
    try
      P.Pan:=I;
      Settings.WritePreset(Slot,P);
      Sleep(2); // overlap competing read/merge/write transactions
      Settings.Commit;
    finally Settings.Free; end;
  end;
end.
