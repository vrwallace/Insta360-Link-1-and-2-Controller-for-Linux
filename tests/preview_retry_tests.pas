program preview_retry_tests;
{$mode objfpc}{$H+}
uses SysUtils, upreviewretry;
procedure Check(V: Boolean; const Msg: string);
begin
  if not V then raise Exception.Create('FAIL: '+Msg);
  WriteLn('PASS: ',Msg);
end;
var R:TPreviewRetry; I:Integer;
begin
  R:=TPreviewRetry.Create;
  try
    R.BeginRecovery(100);
    Check(not R.Due(1099),'mode restart waits for camera settling');
    Check(R.Due(1100),'delayed mode restart runs');
    R.BeginRecovery(1500); // failed start must preserve budget and next attempt
    Check(R.Due(2100),'failed start is retried without a streaming timer');
    R.Cancel;
    Check(not R.Due(9000),'Stop Preview cancels pending recovery');
    R.BeginRecovery(10000);
    Check(R.Due(11000),'recovery can be requested again');
    R.Cancel; // called only when a frame arrives, not merely STREAMON
    Check(not R.Due(12000),'received frame cancels further restarts');
    R.BeginRecovery(20000);
    for I:=1 to 5 do Check(R.Due(20000+QWord(I)*1000),'bounded recovery attempt');
    Check(not R.Due(26000) and not R.Active,'failed recovery terminates after five attempts');
  finally R.Free; end;
end.
