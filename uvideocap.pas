{
  uvideocap.pas - V4L2 MMAP streaming capture for live preview
  ============================================================
  Lightweight video-capture helper for the Insta360 Link GUI.

  It streams from an already-open V4L2 file descriptor (the same fd the
  TInsta360Link control object owns) using memory-mapped buffers, and
  decodes each frame into a TBitmap for display.

  Two pixel formats are supported:
    - MJPEG (preferred) - decoded natively via TJPEGImage (fast)
    - YUYV  (fallback)  - converted to RGB manually

  Frames are pulled on demand with GrabFrame(); the fd is expected to be
  opened O_NONBLOCK so GrabFrame returns False (rather than blocking) when
  no frame is ready yet. This lets the GUI poll from a TTimer on the main
  thread without freezing the UI.

  This unit is LCL-dependent (uses Graphics) and is therefore only pulled
  in by the GUI, never by the console tool.
}
unit uvideocap;

{$mode objfpc}{$H+}

interface

uses
  BaseUnix, SysUtils, Classes, Graphics, IntfGraphics, fpImage, uv4l2;

type
  TVideoCapture = class
  private
    FFD: cint;                       // borrowed fd (not owned)
    FBufStart: array of Pointer;     // mmap'd buffer addresses
    FBufLen: array of PtrUInt;       // mmap'd buffer lengths
    FWidth, FHeight: Integer;
    FBytesPerLine: LongWord;
    FPixFmt: LongWord;
    FStreaming: Boolean;
    function TrySetFormat(PixFmt: LongWord; W, H: Integer): Boolean;
    function SetFormat(W, H: Integer): Boolean;
    function InitBuffers(Count: Integer): Boolean;
    procedure FreeBuffers;
    procedure DecodeMJPEG(Data: Pointer; Len: LongWord; Bmp: TBitmap);
    procedure DecodeYUYV(Data: Pointer; Bmp: TBitmap);
  public
    constructor Create;
    destructor Destroy; override;

    { Begin streaming on the given fd. PrefW/PrefH are a requested size;
      the driver negotiates the nearest supported resolution. }
    function Start(fd: cint; PrefW, PrefH: Integer): Boolean;
    procedure Stop;

    { Dequeue one frame and draw it into Bmp. Returns False if no frame is
      ready (EAGAIN) or not streaming. }
    function GrabFrame(Bmp: TBitmap): Boolean;

    property Streaming: Boolean read FStreaming;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property PixFmt: LongWord read FPixFmt;
  end;

{ FourCC -> readable string, e.g. for status display }
function FourCCToStr(FourCC: LongWord): string;

implementation

const
  V4L2_BUF_TYPE_VIDEO_CAPTURE = 1;
  V4L2_MEMORY_MMAP            = 1;
  V4L2_FIELD_NONE             = 1;

  V4L2_PIX_FMT_YUYV  = $56595559; // 'YUYV'
  V4L2_PIX_FMT_MJPEG = $47504A4D; // 'MJPG'

{ ===== V4L2 streaming structures (64-bit Linux layout) ===== }
type
  Tv4l2_pix_format = packed record
    width: LongWord;
    height: LongWord;
    pixelformat: LongWord;
    field: LongWord;
    bytesperline: LongWord;
    sizeimage: LongWord;
    colorspace: LongWord;
    priv: LongWord;
    flags: LongWord;
    enc: LongWord;          // ycbcr_enc / hsv_enc (union)
    quantization: LongWord;
    xfer_func: LongWord;
  end; // 48 bytes

  Tv4l2_format = packed record
    ftype: LongWord;                 // offset 0
    _pad: LongWord;                  // offset 4 (union is 8-byte aligned)
    pix: Tv4l2_pix_format;           // offset 8 (48 bytes)
    _rest: array[0..151] of Byte;    // remainder of 200-byte union
  end; // 208 bytes

  Tv4l2_requestbuffers = packed record
    count: LongWord;
    rtype: LongWord;
    memory: LongWord;
    capabilities: LongWord;
    flags: LongWord;                 // u8 flags + u8[3] reserved
  end; // 20 bytes

  Tv4l2_buffer = packed record
    index: LongWord;                 // 0
    btype: LongWord;                 // 4
    bytesused: LongWord;             // 8
    flags: LongWord;                 // 12
    field: LongWord;                 // 16
    _pad0: LongWord;                 // 20 (align timestamp to 8)
    ts_sec: Int64;                   // 24
    ts_usec: Int64;                  // 32
    tc_type: LongWord;               // 40
    tc_flags: LongWord;              // 44
    tc_frames: Byte;                 // 48
    tc_seconds: Byte;                // 49
    tc_minutes: Byte;                // 50
    tc_hours: Byte;                  // 51
    tc_userbits: array[0..3] of Byte;// 52
    sequence: LongWord;              // 56
    memory: LongWord;                // 60
    m_offset: PtrUInt;               // 64 (union offset/userptr/planes)
    length: LongWord;                // 72
    reserved2: LongWord;             // 76
    request_fd: LongInt;             // 80
    _pad1: LongWord;                 // 84 (pad to 88)
  end; // 88 bytes

{ ===== ioctl request numbers (reuse _IOC from uv4l2) ===== }
function _IOW_v(nr, sz: LongWord): LongWord; inline;
begin Result := _IOC(_IOC_WRITE, VIDIOC_TYPE, nr, sz); end;

function _IOWR_v(nr, sz: LongWord): LongWord; inline;
begin Result := _IOC(_IOC_READ or _IOC_WRITE, VIDIOC_TYPE, nr, sz); end;

function VIDIOC_S_FMT: LongWord;     begin Result := _IOWR_v(5, SizeOf(Tv4l2_format)); end;
function VIDIOC_REQBUFS: LongWord;   begin Result := _IOWR_v(8, SizeOf(Tv4l2_requestbuffers)); end;
function VIDIOC_QUERYBUF: LongWord;  begin Result := _IOWR_v(9, SizeOf(Tv4l2_buffer)); end;
function VIDIOC_QBUF: LongWord;      begin Result := _IOWR_v(15, SizeOf(Tv4l2_buffer)); end;
function VIDIOC_DQBUF: LongWord;     begin Result := _IOWR_v(17, SizeOf(Tv4l2_buffer)); end;
function VIDIOC_STREAMON: LongWord;  begin Result := _IOW_v(18, SizeOf(cint)); end;
function VIDIOC_STREAMOFF: LongWord; begin Result := _IOW_v(19, SizeOf(cint)); end;

function FourCCToStr(FourCC: LongWord): string;
begin
  SetLength(Result, 4);
  Result[1] := Chr(FourCC and $FF);
  Result[2] := Chr((FourCC shr 8) and $FF);
  Result[3] := Chr((FourCC shr 16) and $FF);
  Result[4] := Chr((FourCC shr 24) and $FF);
end;

{ ===== TVideoCapture ===== }

constructor TVideoCapture.Create;
begin
  inherited Create;
  FFD := -1;
  FStreaming := False;
end;

destructor TVideoCapture.Destroy;
begin
  Stop;
  inherited Destroy;
end;

function TVideoCapture.TrySetFormat(PixFmt: LongWord; W, H: Integer): Boolean;
var
  fmt: Tv4l2_format;
begin
  FillChar(fmt, SizeOf(fmt), 0);
  fmt.ftype := V4L2_BUF_TYPE_VIDEO_CAPTURE;
  fmt.pix.width := W;
  fmt.pix.height := H;
  fmt.pix.pixelformat := PixFmt;
  fmt.pix.field := V4L2_FIELD_NONE;

  Result := (FpIOCtl(FFD, VIDIOC_S_FMT, @fmt) = 0)
            and (fmt.pix.pixelformat = PixFmt);
  if Result then
  begin
    FWidth := fmt.pix.width;
    FHeight := fmt.pix.height;
    FBytesPerLine := fmt.pix.bytesperline;
    FPixFmt := fmt.pix.pixelformat;
  end;
end;

function TVideoCapture.SetFormat(W, H: Integer): Boolean;
begin
  // Prefer MJPEG (compressed, better fps / USB bandwidth), fall back to YUYV.
  Result := TrySetFormat(V4L2_PIX_FMT_MJPEG, W, H)
            or TrySetFormat(V4L2_PIX_FMT_YUYV, W, H);
end;

function TVideoCapture.InitBuffers(Count: Integer): Boolean;
var
  req: Tv4l2_requestbuffers;
  buf: Tv4l2_buffer;
  i: Integer;
begin
  Result := False;

  FillChar(req, SizeOf(req), 0);
  req.count := Count;
  req.rtype := V4L2_BUF_TYPE_VIDEO_CAPTURE;
  req.memory := V4L2_MEMORY_MMAP;
  if FpIOCtl(FFD, VIDIOC_REQBUFS, @req) <> 0 then Exit;
  if req.count < 1 then Exit;

  SetLength(FBufStart, req.count);
  SetLength(FBufLen, req.count);
  for i := 0 to req.count - 1 do
  begin
    FBufStart[i] := nil;
    FBufLen[i] := 0;
  end;

  for i := 0 to req.count - 1 do
  begin
    FillChar(buf, SizeOf(buf), 0);
    buf.index := i;
    buf.btype := V4L2_BUF_TYPE_VIDEO_CAPTURE;
    buf.memory := V4L2_MEMORY_MMAP;
    if FpIOCtl(FFD, VIDIOC_QUERYBUF, @buf) <> 0 then Exit;

    FBufLen[i] := buf.length;
    FBufStart[i] := Fpmmap(nil, buf.length, PROT_READ or PROT_WRITE,
      MAP_SHARED, FFD, buf.m_offset);
    if FBufStart[i] = Pointer(-1) then
    begin
      FBufStart[i] := nil;
      Exit;
    end;

    // Queue the buffer for capture
    if FpIOCtl(FFD, VIDIOC_QBUF, @buf) <> 0 then Exit;
  end;

  Result := True;
end;

procedure TVideoCapture.FreeBuffers;
var
  i: Integer;
begin
  for i := 0 to High(FBufStart) do
    if FBufStart[i] <> nil then
    begin
      Fpmunmap(FBufStart[i], FBufLen[i]);
      FBufStart[i] := nil;
    end;
  SetLength(FBufStart, 0);
  SetLength(FBufLen, 0);
end;

function TVideoCapture.Start(fd: cint; PrefW, PrefH: Integer): Boolean;
var
  bt: cint;
begin
  Result := False;
  if FStreaming then Exit(True);
  if fd < 0 then Exit;
  FFD := fd;

  if not SetFormat(PrefW, PrefH) then Exit;
  if not InitBuffers(4) then
  begin
    FreeBuffers;
    Exit;
  end;

  bt := V4L2_BUF_TYPE_VIDEO_CAPTURE;
  if FpIOCtl(FFD, VIDIOC_STREAMON, @bt) <> 0 then
  begin
    FreeBuffers;
    Exit;
  end;

  FStreaming := True;
  Result := True;
end;

procedure TVideoCapture.Stop;
var
  bt: cint;
  req: Tv4l2_requestbuffers;
begin
  if FStreaming and (FFD >= 0) then
  begin
    bt := V4L2_BUF_TYPE_VIDEO_CAPTURE;
    FpIOCtl(FFD, VIDIOC_STREAMOFF, @bt);
  end;
  FStreaming := False;

  // Unmap our buffers first, then ask the driver to release its buffer set
  // (REQBUFS count=0). Without this the device stays busy and a later S_FMT /
  // restart fails with EBUSY.
  FreeBuffers;
  if FFD >= 0 then
  begin
    FillChar(req, SizeOf(req), 0);
    req.count := 0;
    req.rtype := V4L2_BUF_TYPE_VIDEO_CAPTURE;
    req.memory := V4L2_MEMORY_MMAP;
    FpIOCtl(FFD, VIDIOC_REQBUFS, @req);
  end;

  FFD := -1;
end;

procedure TVideoCapture.DecodeMJPEG(Data: Pointer; Len: LongWord; Bmp: TBitmap);
var
  ms: TMemoryStream;
  jpg: TJPEGImage;
begin
  ms := TMemoryStream.Create;
  jpg := TJPEGImage.Create;
  try
    ms.WriteBuffer(Data^, Len);
    ms.Position := 0;
    jpg.LoadFromStream(ms);
    Bmp.Assign(jpg);
  finally
    jpg.Free;
    ms.Free;
  end;
end;

procedure TVideoCapture.DecodeYUYV(Data: Pointer; Bmp: TBitmap);
var
  intf: TLazIntfImage;
  p: PByte;
  x, y: Integer;
  rowBase, base: PtrUInt;
  Y0, Y1, U, V: Integer;

  function Clamp(v: Integer): Word;
  begin
    if v < 0 then v := 0
    else if v > 255 then v := 255;
    Result := Word(v) * 257; // expand 8-bit -> 16-bit channel
  end;

  function YUV(Yv, Uv, Vv: Integer): TFPColor;
  var
    cr, cg, cb, d, e: Integer;
  begin
    d := Uv - 128;
    e := Vv - 128;
    cr := Yv + ((91881 * e) shr 16);
    cg := Yv - ((22554 * d + 46802 * e) shr 16);
    cb := Yv + ((116130 * d) shr 16);
    Result.red := Clamp(cr);
    Result.green := Clamp(cg);
    Result.blue := Clamp(cb);
    Result.alpha := alphaOpaque;
  end;

begin
  p := PByte(Data);
  Bmp.PixelFormat := pf24bit;
  Bmp.SetSize(FWidth, FHeight);
  intf := Bmp.CreateIntfImage;
  try
    for y := 0 to FHeight - 1 do
    begin
      rowBase := PtrUInt(y) * FBytesPerLine;
      x := 0;
      while x < FWidth do
      begin
        base := rowBase + PtrUInt(x) * 2;
        Y0 := p[base];
        U  := p[base + 1];
        Y1 := p[base + 2];
        V  := p[base + 3];
        intf.Colors[x, y] := YUV(Y0, U, V);
        if x + 1 < FWidth then
          intf.Colors[x + 1, y] := YUV(Y1, U, V);
        Inc(x, 2);
      end;
    end;
    Bmp.LoadFromIntfImage(intf);
  finally
    intf.Free;
  end;
end;

function TVideoCapture.GrabFrame(Bmp: TBitmap): Boolean;
var
  buf: Tv4l2_buffer;
begin
  Result := False;
  if not FStreaming then Exit;

  FillChar(buf, SizeOf(buf), 0);
  buf.btype := V4L2_BUF_TYPE_VIDEO_CAPTURE;
  buf.memory := V4L2_MEMORY_MMAP;

  // Non-blocking dequeue; EAGAIN (no frame ready) just returns False.
  if FpIOCtl(FFD, VIDIOC_DQBUF, @buf) <> 0 then Exit;

  try
    if (buf.index <= High(FBufStart)) and
       (buf.bytesused <= FBufLen[buf.index]) then
    begin
      case FPixFmt of
        V4L2_PIX_FMT_MJPEG: DecodeMJPEG(FBufStart[buf.index], buf.bytesused, Bmp);
        V4L2_PIX_FMT_YUYV:  DecodeYUYV(FBufStart[buf.index], Bmp);
      end;
      Result := True;
    end;
  except
    // A malformed frame should be dropped, not terminate the GUI timer or
    // permanently remove this buffer from the capture queue.
    Result := False;
  end;

  // Every successfully dequeued buffer must be returned, even after a decode
  // error, or the stream eventually runs out of buffers and stalls.
  FpIOCtl(FFD, VIDIOC_QBUF, @buf);
end;

end.
</content>
