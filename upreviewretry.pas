unit upreviewretry;
{$mode objfpc}{$H+}
interface
type
  TPreviewRetry = class
  private
    FActive: Boolean;
    FAttempts: Integer;
    FNextAttempt: QWord;
  public
    procedure BeginRecovery(NowMS: QWord);
    procedure Cancel;
    function Due(NowMS: QWord): Boolean;
    property Active: Boolean read FActive;
    property Attempts: Integer read FAttempts;
  end;
implementation
procedure TPreviewRetry.BeginRecovery(NowMS: QWord);
begin
  // Repeated errors must not reset the retry budget or postpone it forever.
  if FActive then Exit;
  FActive := True;
  FAttempts := 0;
  FNextAttempt := NowMS + 1000;
end;
procedure TPreviewRetry.Cancel;
begin
  FActive := False;
  FAttempts := 0;
end;
function TPreviewRetry.Due(NowMS: QWord): Boolean;
begin
  Result := False;
  if not FActive or (NowMS < FNextAttempt) then Exit;
  if FAttempts >= 5 then
  begin
    FActive := False;
    Exit;
  end;
  Inc(FAttempts);
  FNextAttempt := NowMS + 1000;
  Result := True;
end;
end.
