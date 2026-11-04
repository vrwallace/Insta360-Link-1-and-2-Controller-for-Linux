program preview_tests;
{$mode objfpc}{$H+}
uses Interfaces, SysUtils, Classes, BaseUnix, uv4l2, uvideocap, Graphics;
type
  TBuffer = packed record
    Index, BType, BytesUsed, Flags, Field, Pad0: LongWord;
    Sec, USec: Int64;
    TimeCode: array[0..15] of Byte;
    Sequence, Memory: LongWord;
    Offset: PtrUInt;
    Length, Reserved, RequestFD, Pad1: LongWord;
  end;
var Dequeues, Queues, Fault: Integer;
    WasStopped, BuffersReleased: Boolean;
function MockIoctl(fd: cint; Request: LongWord; Data: Pointer): cint;
var Words: PLongWord; B: ^TBuffer;
begin
  Result := 0; Words := Data;
  case Request and $FF of
    19: WasStopped:=True;
    5: begin
      if not (WasStopped and BuffersReleased) then
      begin fpSetErrno(ESysEBUSY); Exit(-1); end;
      // S_FMT: force YUYV, 2x2, stride 4
      Words[2]:=2; Words[3]:=2; Words[4]:=$56595559; Words[6]:=4;
    end;
    8: if Words[0]<>0 then Words[0]:=2 else BuffersReleased:=True;
    9: begin B:=Data; B^.Length:=4096; B^.Offset:=B^.Index*4096; end;
    15: begin
      Inc(Queues);
      if Fault=3 then begin fpSetErrno(ESysEIO); Exit(-1); end;
    end;
    17: begin
      Inc(Dequeues);
      if Fault=4 then begin fpSetErrno(ESysEIO); Exit(-1); end;
      if Fault in [1,2] then
      begin
        if Fault=1 then fpSetErrno(ESysEAGAIN) else fpSetErrno(ESysENODEV);
        Exit(-1);
      end;
      B:=Data; B^.Index:=(Dequeues-1) mod 2;
      B^.BytesUsed:=1; // truncated frame must be dropped before bitmap access
    end;
  end;
end;
procedure Check(OK: Boolean; const Msg: string);
begin
  if not OK then raise Exception.Create('FAIL: '+Msg);
  WriteLn('PASS: ',Msg);
end;
var Cap:TVideoCapture; Bitmap:TBitmap; Stream:TFileStream; N:Integer;
begin
  CameraIoctlHook:=@MockIoctl;
  Stream:=TFileStream.Create('fake-frame-buffers',fmCreate);
  Cap:=TVideoCapture.Create; Bitmap:=TBitmap.Create;
  try
    Stream.Size:=8192;
    Check(Cap.Start(Stream.Handle,2,2),'start mock preview');
    N:=Queues;
    Check(not Cap.GrabFrame(Bitmap),'drop truncated YUYV frame');
    Check((Dequeues=2) and (Queues=N+2),'bounded batch requeues every buffer');
    Check(Cap.Streaming and (Cap.LastError=''),'bad frame does not stop capture');
    Fault:=1;
    Check(not Cap.GrabFrame(Bitmap),'no frame yet');
    Check(Cap.Streaming and (Cap.LastError=''),'EAGAIN is nonfatal');
    Fault:=4;
    Check(not Cap.GrabFrame(Bitmap),'temporary signal loss');
    Check(Cap.Streaming and (Cap.LastError=''),'temporary EIO does not disable preview');
    Fault:=0; N:=Queues;
    Cap.GrabFrame(Bitmap);
    Check(Queues=N+2,'capture resumes after temporary EIO');
    Fault:=2;
    Check(not Cap.GrabFrame(Bitmap),'device loss fails capture');
    Check(not Cap.Streaming and (Cap.LastError<>''),'device loss clears streaming');
    Fault:=0;
    Check(Cap.Start(Stream.Handle,2,2),'restart after capture failure');
    Fault:=3;
    Check(not Cap.GrabFrame(Bitmap),'requeue failure propagates');
    Check(not Cap.Streaming and (Cap.LastError<>''),'requeue failure stops stream');
  finally
    Cap.Free; Bitmap.Free; Stream.Free;
    CameraIoctlHook:=nil;
  end;
end.
