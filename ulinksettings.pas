unit ulinksettings;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, IniFiles, BaseUnix, Unix, uinsta360link;
type
  { Lock covers read/merge/atomic replacement, shared by GUI and CLI. }
  TLinkSettings = class
  private
    FLock: cint;
    FPath: string;
    FIni: TMemIniFile;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Commit;
    procedure WritePreset(Index: Integer; const P: TPresetPosition);
    property Ini: TMemIniFile read FIni;
  end;
function LinkConfigPath: string;
procedure LoadLinkPresets(Cam: TInsta360Link);
implementation
function LinkConfigPath: string;
var D: string;
begin
  D := GetEnvironmentVariable('XDG_CONFIG_HOME');
  if D = '' then D := GetEnvironmentVariable('HOME') + '/.config';
  D := IncludeTrailingPathDelimiter(D);
  if not DirectoryExists(D + 'Insta360 Link Controller') and
     DirectoryExists(D + 'insta360link') then
    Result := D + 'insta360link/insta360link.ini'
  else Result := D + 'Insta360 Link Controller/insta360link.ini';
end;
constructor TLinkSettings.Create;
begin
  inherited Create;
  FLock := -1;
  FPath := LinkConfigPath;
  if not ForceDirectories(ExtractFileDir(FPath)) then
    raise Exception.Create('Cannot create settings directory');
  FLock := fpOpen(FPath + '.lock', O_CREAT or O_RDWR, &600);
  if FLock < 0 then RaiseLastOSError;
  if fpFlock(FLock, LOCK_EX) <> 0 then RaiseLastOSError;
  FIni := TMemIniFile.Create(FPath);
end;
destructor TLinkSettings.Destroy;
begin
  FIni.Free;
  if FLock >= 0 then
  begin
    fpFlock(FLock, LOCK_UN);
    fpClose(FLock);
  end;
  inherited Destroy;
end;
procedure TLinkSettings.Commit;
var Tmp: string; Lines: TStringList; F: THandleStream; FD: cint;
begin
  Tmp := GetTempFileName(ExtractFileDir(FPath), '.insta360-');
  FD := fpOpen(Tmp, O_CREAT or O_EXCL or O_WRONLY, &600);
  if FD < 0 then RaiseLastOSError;
  try
    Lines := TStringList.Create;
    try
      FIni.GetStrings(Lines);
      F := THandleStream.Create(FD);
      try
        Lines.SaveToStream(F);
        if fpFsync(F.Handle) <> 0 then RaiseLastOSError;
      finally F.Free; end;
    finally Lines.Free; end;
    if fpRename(Tmp, FPath) <> 0 then RaiseLastOSError;
  finally
    fpClose(FD);
    if FileExists(Tmp) then DeleteFile(Tmp);
  end;
end;
procedure TLinkSettings.WritePreset(Index: Integer; const P: TPresetPosition);
var S: string;
begin
  if (Index < 0) or (Index > 5) then raise ERangeError.Create('Invalid preset index');
  S := IntToStr(Index);
  FIni.WriteString('Presets', 'Name'+S, P.Name);
  FIni.WriteBool('Presets', 'Valid'+S, P.Valid);
  FIni.WriteInteger('Presets', 'Pan'+S, P.Pan);
  FIni.WriteInteger('Presets', 'Tilt'+S, P.Tilt);
  FIni.WriteInteger('Presets', 'Zoom'+S, P.Zoom);
end;
procedure LoadLinkPresets(Cam: TInsta360Link);
var Ini: TMemIniFile; I: Integer; P: TPresetPosition; S: string;
begin
  // Atomic replacement makes an unlocked reader see a complete old or new file.
  Ini := TMemIniFile.Create(LinkConfigPath);
  try
    for I := 0 to 5 do
    begin
      S := IntToStr(I);
      P.Name := Ini.ReadString('Presets','Name'+S,'Preset '+S);
      P.Valid := Ini.ReadBool('Presets','Valid'+S,False);
      P.Pan := Ini.ReadInteger('Presets','Pan'+S,0);
      P.Tilt := Ini.ReadInteger('Presets','Tilt'+S,0);
      P.Zoom := Ini.ReadInteger('Presets','Zoom'+S,100);
      Cam.SetPreset(I,P);
    end;
  finally Ini.Free; end;
end;
end.
