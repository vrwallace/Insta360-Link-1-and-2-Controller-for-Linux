{
  umainform.pas - Lazarus GUI for Insta360 Link Webcam Controller
  ================================================================
  Full GUI with:
    - Device selection and connection
    - PTZ controls (D-pad style buttons + sliders)
    - AI Tracking, DeskView, Whiteboard, Overhead mode buttons
    - Image adjustment sliders (brightness, contrast, etc.)
    - Exposure and Focus controls
    - 6 preset position slots (save/recall)
    - Activity log
    - Settings persistence via INI file
}
unit umainform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, Spin, Buttons, IniFiles, uv4l2, uinsta360link,
  uvideocap;

type
  { TfrmMain }
  TfrmMain = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
  private
    FCam: TInsta360Link;
    FUpdating: Boolean;  // Prevent feedback loops on slider changes

    // --- Live preview ---
    FCapture: TVideoCapture;
    FPreviewBmp: TBitmap;
    grpPreview: TGroupBox;
    pnlPreviewBar: TPanel;
    imgPreview: TImage;
    btnPreview: TButton;
    lblPreviewInfo: TLabel;
    tmrPreview: TTimer;

    // --- Press-and-hold PTZ ---
    tmrPTZ: TTimer;
    FPTZPanStep: Integer;   // degrees per tick while a D-pad button is held
    FPTZTiltStep: Integer;

    // --- Top bar: Device ---
    pnlTop: TPanel;
    lblDevice: TLabel;
    cboDevice: TComboBox;
    btnConnect: TButton;
    btnDisconnect: TButton;
    btnRefresh: TButton;
    lblStatus: TLabel;

    // --- Left column: PTZ + Modes ---
    pnlLeft: TPanel;

    grpPTZ: TGroupBox;
    btnUp: TSpeedButton;
    btnDown: TSpeedButton;
    btnLeft: TSpeedButton;
    btnRight: TSpeedButton;
    btnUpLeft: TSpeedButton;
    btnUpRight: TSpeedButton;
    btnDownLeft: TSpeedButton;
    btnDownRight: TSpeedButton;
    btnHome: TSpeedButton;
    lblPanStep: TLabel;
    sePanStep: TSpinEdit;
    lblTiltStep: TLabel;
    seTiltStep: TSpinEdit;
    lblZoom: TLabel;
    tbZoom: TTrackBar;
    lblZoomVal: TLabel;

    grpModes: TGroupBox;
    btnTrackingOn: TButton;
    btnTrackingOff: TButton;
    tmrTrackingPoll: TTimer;
    lblTrackFrame: TLabel;
    cboTrackFrame: TComboBox;
    btnDeskView: TButton;
    btnWhiteboard: TButton;
    btnOverhead: TButton;
    btnNormal: TButton;
    btnGimbalReset: TButton;

    // --- Center column: Image + Exposure + Focus ---
    pnlCenter: TPanel;

    grpImage: TGroupBox;
    lblBrightness: TLabel;
    tbBrightness: TTrackBar;
    lblBrightnessV: TLabel;
    lblContrast: TLabel;
    tbContrast: TTrackBar;
    lblContrastV: TLabel;
    lblSaturation: TLabel;
    tbSaturation: TTrackBar;
    lblSaturationV: TLabel;
    lblSharpness: TLabel;
    tbSharpness: TTrackBar;
    lblSharpnessV: TLabel;
    lblGain: TLabel;
    tbGain: TTrackBar;
    lblGainV: TLabel;
    chkAutoWB: TCheckBox;
    lblWBTemp: TLabel;
    tbWBTemp: TTrackBar;
    lblWBTempV: TLabel;
    chkBacklight: TCheckBox;

    grpExposure: TGroupBox;
    chkAutoExposure: TCheckBox;
    lblExposure: TLabel;
    tbExposure: TTrackBar;
    lblExposureV: TLabel;

    grpFocus: TGroupBox;
    chkAutoFocus: TCheckBox;
    lblFocus: TLabel;
    tbFocus: TTrackBar;
    lblFocusV: TLabel;

    // --- Right column: Presets + Log ---
    pnlRight: TPanel;

    grpPresets: TGroupBox;
    btnPresetRecall: array[0..5] of TButton;
    btnPresetSave: array[0..5] of TButton;
    edtPresetName: array[0..5] of TEdit;

    grpLog: TGroupBox;
    memoLog: TMemo;
    btnClearLog: TButton;
    btnScanXU: TButton;

    procedure BuildUI;
    procedure RefreshDeviceList;
    procedure ConnectClick(Sender: TObject);
    procedure DisconnectClick(Sender: TObject);
    procedure RefreshClick(Sender: TObject);

    // PTZ handlers (press-and-hold)
    procedure PTZMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PTZMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PTZRepeatTimer(Sender: TObject);
    procedure HomeClick(Sender: TObject);
    procedure ZoomChange(Sender: TObject);

    // Preview handlers
    procedure PreviewToggleClick(Sender: TObject);
    procedure PreviewTimer(Sender: TObject);
    procedure StartPreview;
    procedure StopPreview;

    // Mode handlers
    procedure TrackingOnClick(Sender: TObject);
    procedure TrackingOffClick(Sender: TObject);
    procedure TrackFrameChange(Sender: TObject);
    procedure TrackingPollTimer(Sender: TObject);
    procedure ModeButtonClick(Sender: TObject);
    procedure GimbalResetClick(Sender: TObject);

    // Image handlers
    procedure ImageSliderChange(Sender: TObject);
    procedure AutoWBChange(Sender: TObject);
    procedure WBTempChange(Sender: TObject);
    procedure BacklightChange(Sender: TObject);
    procedure AutoExposureChange(Sender: TObject);
    procedure ExposureChange(Sender: TObject);
    procedure AutoFocusChange(Sender: TObject);
    procedure FocusChange(Sender: TObject);

    // Preset handlers
    procedure PresetRecallClick(Sender: TObject);
    procedure PresetSaveClick(Sender: TObject);

    // Diagnostics
    procedure ScanXUClick(Sender: TObject);

    // Log
    procedure ClearLogClick(Sender: TObject);
    procedure CamLog(Sender: TObject; const Msg: string);

    // UI helpers
    procedure UpdateUIState;
    procedure ReadCurrentValues;
    procedure SetupTrackBar(tb: TTrackBar; const Range: TCtrlRange);
    procedure SaveSettings;
    procedure LoadSettings;
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

{ ===== Form lifecycle ===== }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FCam := TInsta360Link.Create;
  FCam.OnLog := @CamLog;
  FUpdating := False;
  FCapture := TVideoCapture.Create;
  FPreviewBmp := TBitmap.Create;
  BuildUI;
  RefreshDeviceList;
  LoadSettings;
  UpdateUIState;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  SaveSettings;
  StopPreview;
  FCapture.Free;
  FPreviewBmp.Free;
  FCam.Free;
end;

procedure TfrmMain.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  StopPreview;
  FCam.Close;
end;

{ ===== UI Construction ===== }

procedure TfrmMain.BuildUI;

  function MakeLabel(AParent: TWinControl; X, Y: Integer; const ACaption: string): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := AParent;
    Result.Left := X;
    Result.Top := Y;
    Result.Caption := ACaption;
  end;

  function MakeTrackBar(AParent: TWinControl; X, Y, W: Integer;
    AMin, AMax: Integer; AOnChange: TNotifyEvent): TTrackBar;
  begin
    Result := TTrackBar.Create(Self);
    Result.Parent := AParent;
    Result.Left := X;
    Result.Top := Y;
    Result.Width := W;
    Result.Height := 25;
    Result.Min := AMin;
    Result.Max := AMax;
    Result.OnChange := AOnChange;
    Result.TickStyle := tsNone;
  end;

  function MakeButton(AParent: TWinControl; X, Y, W, H: Integer;
    const ACaption: string; AOnClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(X, Y, W, H);
    Result.Caption := ACaption;
    Result.OnClick := AOnClick;
  end;

  function MakeSpeedButton(AParent: TWinControl; X, Y, W, H: Integer;
    const ACaption: string; ATag: Integer; AOnClick: TNotifyEvent): TSpeedButton;
  begin
    Result := TSpeedButton.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(X, Y, W, H);
    Result.Caption := ACaption;
    Result.Tag := ATag;
    Result.OnClick := AOnClick;
  end;

var
  i, Y: Integer;
begin
  // === Form setup ===
  Caption := 'Insta360 Link Controller for Linux';
  Width := 1420;
  Height := 760;
  Position := poScreenCenter;

  // === TOP: Device bar ===
  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 40;
  pnlTop.BevelOuter := bvNone;

  lblDevice := MakeLabel(pnlTop, 8, 10, 'Device:');
  cboDevice := TComboBox.Create(Self);
  cboDevice.Parent := pnlTop;
  cboDevice.SetBounds(60, 7, 340, 25);
  cboDevice.Style := csDropDownList;

  btnRefresh := MakeButton(pnlTop, 406, 6, 70, 28, 'Refresh', @RefreshClick);
  btnConnect := MakeButton(pnlTop, 482, 6, 80, 28, 'Connect', @ConnectClick);
  btnDisconnect := MakeButton(pnlTop, 568, 6, 90, 28, 'Disconnect', @DisconnectClick);
  btnDisconnect.Enabled := False;

  lblStatus := MakeLabel(pnlTop, 670, 10, 'Not connected');
  lblStatus.Font.Color := clRed;

  // === LEFT: PTZ + Modes ===
  pnlLeft := TPanel.Create(Self);
  pnlLeft.Parent := Self;
  pnlLeft.Align := alLeft;
  pnlLeft.Width := 260;
  pnlLeft.BevelOuter := bvNone;

  // PTZ group
  grpPTZ := TGroupBox.Create(Self);
  grpPTZ.Parent := pnlLeft;
  grpPTZ.SetBounds(4, 4, 252, 220);
  grpPTZ.Caption := ' PTZ Controls ';

  // D-pad: 3x3 grid of speed buttons
  // Tag encodes direction: bits [7:4]=panDir, [3:0]=tiltDir
  //   panDir: 0=none, 1=left, 2=right
  //   tiltDir: 0=none, 1=up, 2=down
  // Directional buttons use press-and-hold (mouse down/up) for continuous
  // motion; the Home button stays a plain click.
  btnUpLeft  := MakeSpeedButton(grpPTZ,  20, 20, 44, 44, '↖', $11, nil);
  btnUp      := MakeSpeedButton(grpPTZ,  70, 20, 44, 44, '↑', $01, nil);
  btnUpRight := MakeSpeedButton(grpPTZ, 120, 20, 44, 44, '↗', $21, nil);
  btnLeft    := MakeSpeedButton(grpPTZ,  20, 70, 44, 44, '←', $10, nil);
  btnHome    := MakeSpeedButton(grpPTZ,  70, 70, 44, 44, '⌂',   0, @HomeClick);
  btnRight   := MakeSpeedButton(grpPTZ, 120, 70, 44, 44, '→', $20, nil);
  btnDownLeft  := MakeSpeedButton(grpPTZ,  20, 120, 44, 44, '↙', $12, nil);
  btnDown      := MakeSpeedButton(grpPTZ,  70, 120, 44, 44, '↓', $02, nil);
  btnDownRight := MakeSpeedButton(grpPTZ, 120, 120, 44, 44, '↘', $22, nil);

  for i := 0 to 7 do
  begin
    case i of
      0: btnUp.OnMouseDown := @PTZMouseDown;
      1: btnDown.OnMouseDown := @PTZMouseDown;
      2: btnLeft.OnMouseDown := @PTZMouseDown;
      3: btnRight.OnMouseDown := @PTZMouseDown;
      4: btnUpLeft.OnMouseDown := @PTZMouseDown;
      5: btnUpRight.OnMouseDown := @PTZMouseDown;
      6: btnDownLeft.OnMouseDown := @PTZMouseDown;
      7: btnDownRight.OnMouseDown := @PTZMouseDown;
    end;
  end;
  btnUp.OnMouseUp := @PTZMouseUp;
  btnDown.OnMouseUp := @PTZMouseUp;
  btnLeft.OnMouseUp := @PTZMouseUp;
  btnRight.OnMouseUp := @PTZMouseUp;
  btnUpLeft.OnMouseUp := @PTZMouseUp;
  btnUpRight.OnMouseUp := @PTZMouseUp;
  btnDownLeft.OnMouseUp := @PTZMouseUp;
  btnDownRight.OnMouseUp := @PTZMouseUp;

  // Repeat timer drives continuous motion while a button is held down
  tmrPTZ := TTimer.Create(Self);
  tmrPTZ.Interval := 150;
  tmrPTZ.Enabled := False;
  tmrPTZ.OnTimer := @PTZRepeatTimer;

  lblPanStep := MakeLabel(grpPTZ, 174, 30, 'Pan:');
  sePanStep := TSpinEdit.Create(Self);
  sePanStep.Parent := grpPTZ;
  sePanStep.SetBounds(200, 27, 46, 24);
  sePanStep.MinValue := 1; sePanStep.MaxValue := 30; sePanStep.Value := 8;

  lblTiltStep := MakeLabel(grpPTZ, 174, 60, 'Tilt:');
  seTiltStep := TSpinEdit.Create(Self);
  seTiltStep.Parent := grpPTZ;
  seTiltStep.SetBounds(200, 57, 46, 24);
  seTiltStep.MinValue := 1; seTiltStep.MaxValue := 30; seTiltStep.Value := 8;

  lblZoom := MakeLabel(grpPTZ, 8, 172, 'Zoom:');
  tbZoom := MakeTrackBar(grpPTZ, 50, 170, 150, 100, 400, @ZoomChange);
  tbZoom.Position := 100;
  lblZoomVal := MakeLabel(grpPTZ, 206, 172, '1.0x');

  // Modes group
  grpModes := TGroupBox.Create(Self);
  grpModes.Parent := pnlLeft;
  grpModes.SetBounds(4, 228, 252, 300);
  grpModes.Caption := ' Camera Modes ';

  Y := 20;
  MakeLabel(grpModes, 8, Y, 'AI Tracking:');
  btnTrackingOn := MakeButton(grpModes, 100, Y - 3, 60, 26, 'ON', @TrackingOnClick);
  btnTrackingOff := MakeButton(grpModes, 166, Y - 3, 60, 26, 'OFF', @TrackingOffClick);

  // Polling timer for tracking status
  tmrTrackingPoll := TTimer.Create(Self);
  tmrTrackingPoll.Interval := 1000;
  tmrTrackingPoll.Enabled := False;
  tmrTrackingPoll.OnTimer := @TrackingPollTimer;

  Inc(Y, 32);
  lblTrackFrame := MakeLabel(grpModes, 8, Y, 'Framing:');
  cboTrackFrame := TComboBox.Create(Self);
  cboTrackFrame.Parent := grpModes;
  cboTrackFrame.SetBounds(100, Y - 3, 126, 25);
  cboTrackFrame.Style := csDropDownList;
  cboTrackFrame.Items.Add('Head');
  cboTrackFrame.Items.Add('Half Body');
  cboTrackFrame.Items.Add('Full Body');
  cboTrackFrame.ItemIndex := 1;
  cboTrackFrame.OnChange := @TrackFrameChange;

  Inc(Y, 40);
  MakeLabel(grpModes, 8, Y, 'Operating Mode:');
  Inc(Y, 20);
  btnNormal := MakeButton(grpModes, 8, Y, 110, 30, 'Normal', @ModeButtonClick);
  btnNormal.Tag := 0;
  btnDeskView := MakeButton(grpModes, 124, Y, 110, 30, 'DeskView', @ModeButtonClick);
  btnDeskView.Tag := 1;
  Inc(Y, 36);
  btnWhiteboard := MakeButton(grpModes, 8, Y, 110, 30, 'Whiteboard', @ModeButtonClick);
  btnWhiteboard.Tag := 2;
  btnOverhead := MakeButton(grpModes, 124, Y, 110, 30, 'Overhead', @ModeButtonClick);
  btnOverhead.Tag := 3;

  Inc(Y, 44);
  btnGimbalReset := MakeButton(grpModes, 8, Y, 226, 30, 'Gimbal Reset', @GimbalResetClick);

  // === CENTER: Image controls ===
  pnlCenter := TPanel.Create(Self);
  pnlCenter.Parent := Self;
  pnlCenter.Align := alClient;
  pnlCenter.BevelOuter := bvNone;

  grpImage := TGroupBox.Create(Self);
  grpImage.Parent := pnlCenter;
  grpImage.SetBounds(4, 4, 370, 320);
  grpImage.Caption := ' Image Controls ';

  Y := 20;
  lblBrightness := MakeLabel(grpImage, 8, Y, 'Brightness:');
  tbBrightness := MakeTrackBar(grpImage, 90, Y - 2, 220, 0, 100, @ImageSliderChange);
  tbBrightness.Tag := 1;
  tbBrightness.Position := 50;
  lblBrightnessV := MakeLabel(grpImage, 320, Y, '128');

  Inc(Y, 34);
  lblContrast := MakeLabel(grpImage, 8, Y, 'Contrast:');
  tbContrast := MakeTrackBar(grpImage, 90, Y - 2, 220, 0, 100, @ImageSliderChange);
  tbContrast.Tag := 2;
  tbContrast.Position := 50;
  lblContrastV := MakeLabel(grpImage, 320, Y, '128');

  Inc(Y, 34);
  lblSaturation := MakeLabel(grpImage, 8, Y, 'Saturation:');
  tbSaturation := MakeTrackBar(grpImage, 90, Y - 2, 220, 0, 100, @ImageSliderChange);
  tbSaturation.Tag := 3;
  tbSaturation.Position := 50;
  lblSaturationV := MakeLabel(grpImage, 320, Y, '128');

  Inc(Y, 34);
  lblSharpness := MakeLabel(grpImage, 8, Y, 'Sharpness:');
  tbSharpness := MakeTrackBar(grpImage, 90, Y - 2, 220, 0, 100, @ImageSliderChange);
  tbSharpness.Tag := 4;
  tbSharpness.Position := 50;
  lblSharpnessV := MakeLabel(grpImage, 320, Y, '128');

  Inc(Y, 34);
  lblGain := MakeLabel(grpImage, 8, Y, 'Gain:');
  tbGain := MakeTrackBar(grpImage, 90, Y - 2, 220, 0, 100, @ImageSliderChange);
  tbGain.Tag := 5;
  tbGain.Position := 0;
  lblGainV := MakeLabel(grpImage, 320, Y, '0');

  Inc(Y, 36);
  chkAutoWB := TCheckBox.Create(Self);
  chkAutoWB.Parent := grpImage;
  chkAutoWB.SetBounds(8, Y, 150, 22);
  chkAutoWB.Caption := 'Auto White Balance';
  chkAutoWB.Checked := True;
  chkAutoWB.OnChange := @AutoWBChange;

  chkBacklight := TCheckBox.Create(Self);
  chkBacklight.Parent := grpImage;
  chkBacklight.SetBounds(180, Y, 170, 22);
  chkBacklight.Caption := 'Backlight Comp.';
  chkBacklight.OnChange := @BacklightChange;

  Inc(Y, 28);
  lblWBTemp := MakeLabel(grpImage, 8, Y, 'WB Temp:');
  tbWBTemp := MakeTrackBar(grpImage, 90, Y - 2, 220, 2000, 10000, @WBTempChange);
  tbWBTemp.Position := 6400;
  lblWBTempV := MakeLabel(grpImage, 320, Y, '6400K');

  // Exposure
  grpExposure := TGroupBox.Create(Self);
  grpExposure.Parent := pnlCenter;
  grpExposure.SetBounds(4, 328, 370, 90);
  grpExposure.Caption := ' Exposure ';

  chkAutoExposure := TCheckBox.Create(Self);
  chkAutoExposure.Parent := grpExposure;
  chkAutoExposure.SetBounds(8, 20, 130, 22);
  chkAutoExposure.Caption := 'Auto Exposure';
  chkAutoExposure.Checked := True;
  chkAutoExposure.OnChange := @AutoExposureChange;

  lblExposure := MakeLabel(grpExposure, 8, 52, 'Value:');
  tbExposure := MakeTrackBar(grpExposure, 90, 50, 220, 3, 2047, @ExposureChange);
  tbExposure.Position := 250;
  lblExposureV := MakeLabel(grpExposure, 320, 52, '250');

  // Focus
  grpFocus := TGroupBox.Create(Self);
  grpFocus.Parent := pnlCenter;
  grpFocus.SetBounds(4, 422, 370, 90);
  grpFocus.Caption := ' Focus ';

  chkAutoFocus := TCheckBox.Create(Self);
  chkAutoFocus.Parent := grpFocus;
  chkAutoFocus.SetBounds(8, 20, 130, 22);
  chkAutoFocus.Caption := 'Auto Focus';
  chkAutoFocus.Checked := True;
  chkAutoFocus.OnChange := @AutoFocusChange;

  lblFocus := MakeLabel(grpFocus, 8, 52, 'Value:');
  tbFocus := MakeTrackBar(grpFocus, 90, 50, 220, 0, 100, @FocusChange);
  tbFocus.Position := 50;
  lblFocusV := MakeLabel(grpFocus, 320, 52, '0');

  // Live preview (center, right of the image controls).
  // Anchored to the panel edges so it grows with the window; inside, a
  // bottom bar holds the controls and the image fills the remaining space,
  // so nothing is clipped regardless of font size / DPI.
  // Fixed-size landscape box (not anchored to right/bottom) so the image area
  // stays wider-than-tall and matched to the 16:9 frame. A wider-than-frame
  // area would leave empty space beside the centered image; a tall/portrait
  // area would make a 16:9 frame appear cropped.
  grpPreview := TGroupBox.Create(Self);
  grpPreview.Parent := pnlCenter;
  grpPreview.SetBounds(382, 4, 496, 360);
  grpPreview.Anchors := [akLeft, akTop];
  grpPreview.Caption := ' Live Preview ';

  // Bottom control bar (created before the image so alClient gets the rest)
  pnlPreviewBar := TPanel.Create(Self);
  pnlPreviewBar.Parent := grpPreview;
  pnlPreviewBar.Align := alBottom;
  pnlPreviewBar.Height := 44;
  pnlPreviewBar.BevelOuter := bvNone;

  btnPreview := MakeButton(pnlPreviewBar, 8, 6, 150, 32,
    'Start Preview', @PreviewToggleClick);
  lblPreviewInfo := MakeLabel(pnlPreviewBar, 170, 14, '');
  lblPreviewInfo.AutoSize := True;
  lblPreviewInfo.Anchors := [akLeft, akTop];

  // Image fills the landscape area above the bar, scaled to fit (whole frame),
  // left/top-justified (Center := False).
  imgPreview := TImage.Create(Self);
  imgPreview.Parent := grpPreview;
  imgPreview.Align := alClient;
  imgPreview.BorderSpacing.Around := 6;
  imgPreview.Stretch := True;
  imgPreview.Proportional := True;
  imgPreview.Center := False;

  tmrPreview := TTimer.Create(Self);
  tmrPreview.Interval := 40; // ~25 fps poll
  tmrPreview.Enabled := False;
  tmrPreview.OnTimer := @PreviewTimer;

  // === RIGHT: Presets + Log ===
  pnlRight := TPanel.Create(Self);
  pnlRight.Parent := Self;
  pnlRight.Align := alRight;
  pnlRight.Width := 280;
  pnlRight.BevelOuter := bvNone;

  grpPresets := TGroupBox.Create(Self);
  grpPresets.Parent := pnlRight;
  grpPresets.SetBounds(4, 4, 272, 240);
  grpPresets.Caption := ' Preset Positions ';

  for i := 0 to 5 do
  begin
    edtPresetName[i] := TEdit.Create(Self);
    edtPresetName[i].Parent := grpPresets;
    edtPresetName[i].SetBounds(8, 22 + i * 34, 100, 24);
    edtPresetName[i].Text := Format('Preset %d', [i]);

    btnPresetRecall[i] := MakeButton(grpPresets, 114, 20 + i * 34, 70, 28,
      'Recall', @PresetRecallClick);
    btnPresetRecall[i].Tag := i;

    btnPresetSave[i] := MakeButton(grpPresets, 190, 20 + i * 34, 70, 28,
      'Save', @PresetSaveClick);
    btnPresetSave[i].Tag := i;
  end;

  grpLog := TGroupBox.Create(Self);
  grpLog.Parent := pnlRight;
  grpLog.SetBounds(4, 248, 272, 440);
  grpLog.Caption := ' Activity Log ';

  memoLog := TMemo.Create(Self);
  memoLog.Parent := grpLog;
  memoLog.SetBounds(4, 18, 264, 370);
  memoLog.ReadOnly := True;
  memoLog.ScrollBars := ssVertical;
  memoLog.Font.Name := 'Monospace';
  memoLog.Font.Size := 8;

  btnClearLog := MakeButton(grpLog, 4, 396, 80, 28, 'Clear Log', @ClearLogClick);
  btnScanXU := MakeButton(grpLog, 90, 396, 80, 28, 'Read XU', @ScanXUClick);
end;

{ ===== Device Management ===== }

procedure TfrmMain.RefreshDeviceList;
var
  devs: array[0..31] of string;
  cnt, i: Integer;
begin
  cboDevice.Items.Clear;
  V4L2_EnumDevices(devs, cnt);
  for i := 0 to cnt - 1 do
    cboDevice.Items.Add(devs[i]);
  if cnt > 0 then cboDevice.ItemIndex := 0;
end;

procedure TfrmMain.RefreshClick(Sender: TObject);
begin
  RefreshDeviceList;
end;

procedure TfrmMain.ConnectClick(Sender: TObject);
var
  devpath: string;
begin
  if cboDevice.ItemIndex < 0 then
  begin
    ShowMessage('Please select a video device.');
    Exit;
  end;

  // Extract device path from combo item (first token before space)
  devpath := cboDevice.Items[cboDevice.ItemIndex];
  devpath := Copy(devpath, 1, Pos(' ', devpath + ' ') - 1);

  if FCam.Open(devpath) then
  begin
    lblStatus.Caption := 'Connected: ' + FCam.DeviceName;
    lblStatus.Font.Color := clGreen;
    btnConnect.Enabled := False;
    btnDisconnect.Enabled := True;
    ReadCurrentValues;
    UpdateUIState;
    tmrTrackingPoll.Enabled := True;
    CamLog(Self, 'Connected to ' + devpath);
    StartPreview; // auto-start live preview (logs and continues if it fails)
  end
  else
  begin
    ShowMessage('Failed to open ' + devpath + #13#10 +
      'Try running with sudo or check device permissions.');
  end;
end;

procedure TfrmMain.DisconnectClick(Sender: TObject);
begin
  StopPreview; // must stop streaming before the fd is closed
  tmrTrackingPoll.Enabled := False;
  btnTrackingOn.Font.Style := [];
  btnTrackingOn.Caption := 'ON';
  FCam.Close;
  lblStatus.Caption := 'Not connected';
  lblStatus.Font.Color := clRed;
  btnConnect.Enabled := True;
  btnDisconnect.Enabled := False;
  UpdateUIState;
end;

{ ===== PTZ Handlers (press-and-hold) ===== }

procedure TfrmMain.PTZMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  dirTag, panDir, tiltDir: Integer;
begin
  if not FCam.Connected then Exit;
  dirTag := (Sender as TSpeedButton).Tag;
  panDir := (dirTag shr 4) and $F;
  tiltDir := dirTag and $F;

  FPTZPanStep := 0;
  FPTZTiltStep := 0;
  case panDir of
    1: FPTZPanStep := -sePanStep.Value;  // Left
    2: FPTZPanStep := sePanStep.Value;   // Right
  end;
  case tiltDir of
    1: FPTZTiltStep := seTiltStep.Value;  // Up
    2: FPTZTiltStep := -seTiltStep.Value; // Down
  end;

  // Move once immediately, then let the repeat timer continue while held
  FCam.PanTiltRelative(FPTZPanStep, FPTZTiltStep);
  tmrPTZ.Enabled := True;
end;

procedure TfrmMain.PTZMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  tmrPTZ.Enabled := False;
  FPTZPanStep := 0;
  FPTZTiltStep := 0;
end;

procedure TfrmMain.PTZRepeatTimer(Sender: TObject);
begin
  if not FCam.Connected then
  begin
    tmrPTZ.Enabled := False;
    Exit;
  end;
  if (FPTZPanStep <> 0) or (FPTZTiltStep <> 0) then
    FCam.PanTiltRelative(FPTZPanStep, FPTZTiltStep);
end;

procedure TfrmMain.HomeClick(Sender: TObject);
begin
  if FCam.Connected then FCam.GimbalReset;
end;

procedure TfrmMain.ZoomChange(Sender: TObject);
begin
  if FUpdating or not FCam.Connected then Exit;
  FCam.SetZoom(tbZoom.Position);
  lblZoomVal.Caption := Format('%.1fx', [tbZoom.Position / 100.0]);
end;

{ ===== Live Preview ===== }

procedure TfrmMain.StartPreview;
begin
  if FCapture.Streaming then Exit;
  if not FCam.Connected then Exit;

  // Stream on the camera's existing (non-blocking) fd. 1280x720 is requested;
  // the driver negotiates the nearest supported size/format.
  if FCapture.Start(FCam.FD, 1280, 720) then
  begin
    tmrPreview.Enabled := True;
    btnPreview.Caption := 'Stop Preview';
    lblPreviewInfo.Caption := Format('%dx%d %s',
      [FCapture.Width, FCapture.Height, FourCCToStr(FCapture.PixFmt)]);
    CamLog(Self, Format('Preview started: %dx%d %s',
      [FCapture.Width, FCapture.Height, FourCCToStr(FCapture.PixFmt)]));
  end
  else
    CamLog(Self, 'Preview FAILED to start (camera may be in use by another app)');
end;

procedure TfrmMain.StopPreview;
begin
  tmrPreview.Enabled := False;
  if FCapture.Streaming then
  begin
    FCapture.Stop;
    CamLog(Self, 'Preview stopped');
  end;
  if Assigned(btnPreview) then
    btnPreview.Caption := 'Start Preview';
  if Assigned(lblPreviewInfo) then
    lblPreviewInfo.Caption := '';
end;

procedure TfrmMain.PreviewToggleClick(Sender: TObject);
begin
  if FCapture.Streaming then
    StopPreview
  else
    StartPreview;
end;

procedure TfrmMain.PreviewTimer(Sender: TObject);
begin
  if not FCapture.Streaming then Exit;
  if FCapture.GrabFrame(FPreviewBmp) then
  begin
    imgPreview.Picture.Bitmap.Assign(FPreviewBmp);
    imgPreview.Invalidate;
  end;
end;

{ ===== Mode Handlers ===== }

procedure TfrmMain.TrackingOnClick(Sender: TObject);
begin
  if not FCam.Connected then Exit;
  FCam.SetAITracking(True);
  // Sync framing combo with camera's current state
  case FCam.GetTrackingFrame of
    tfHead:     cboTrackFrame.ItemIndex := 0;
    tfHalfBody: cboTrackFrame.ItemIndex := 1;
    tfFullBody: cboTrackFrame.ItemIndex := 2;
  end;
end;

procedure TfrmMain.TrackingOffClick(Sender: TObject);
begin
  if FCam.Connected then FCam.SetAITracking(False);
end;

procedure TfrmMain.TrackFrameChange(Sender: TObject);
begin
  if not FCam.Connected then Exit;
  case cboTrackFrame.ItemIndex of
    0: FCam.SetTrackingFrame(tfHead);
    1: FCam.SetTrackingFrame(tfHalfBody);
    2: FCam.SetTrackingFrame(tfFullBody);
  end;
end;

procedure TfrmMain.TrackingPollTimer(Sender: TObject);
var
  isTracking: Boolean;
begin
  if not FCam.Connected then Exit;

  isTracking := FCam.GetAITracking;
  if isTracking then
  begin
    btnTrackingOn.Font.Style := [fsBold];
    btnTrackingOn.Caption := '● ON';
    btnTrackingOff.Font.Style := [];
    btnTrackingOff.Caption := 'OFF';
  end
  else
  begin
    btnTrackingOn.Font.Style := [];
    btnTrackingOn.Caption := 'ON';
    btnTrackingOff.Font.Style := [];
    btnTrackingOff.Caption := 'OFF';
  end;
end;

procedure TfrmMain.ModeButtonClick(Sender: TObject);
begin
  if not FCam.Connected then Exit;
  case (Sender as TButton).Tag of
    0: FCam.SetCameraMode(cmNormal);
    1: FCam.SetCameraMode(cmDeskView);
    2: FCam.SetCameraMode(cmWhiteboard);
    3: FCam.SetCameraMode(cmOverhead);
  end;
end;

procedure TfrmMain.GimbalResetClick(Sender: TObject);
begin
  if FCam.Connected then FCam.GimbalReset;
end;

{ ===== Image Handlers ===== }

procedure TfrmMain.ImageSliderChange(Sender: TObject);
var
  tb: TTrackBar;
begin
  if FUpdating or not FCam.Connected then Exit;
  tb := Sender as TTrackBar;
  case tb.Tag of
    1: begin FCam.SetBrightness(tb.Position); lblBrightnessV.Caption := IntToStr(tb.Position); end;
    2: begin FCam.SetContrast(tb.Position); lblContrastV.Caption := IntToStr(tb.Position); end;
    3: begin FCam.SetSaturation(tb.Position); lblSaturationV.Caption := IntToStr(tb.Position); end;
    4: begin FCam.SetSharpness(tb.Position); lblSharpnessV.Caption := IntToStr(tb.Position); end;
    5: begin FCam.SetGain(tb.Position); lblGainV.Caption := IntToStr(tb.Position); end;
  end;
end;

procedure TfrmMain.AutoWBChange(Sender: TObject);
begin
  if FUpdating or not FCam.Connected then Exit;
  FCam.SetAutoWhiteBalance(chkAutoWB.Checked);
  tbWBTemp.Enabled := not chkAutoWB.Checked;
end;

procedure TfrmMain.WBTempChange(Sender: TObject);
begin
  if FUpdating or not FCam.Connected then Exit;
  FCam.SetWhiteBalanceTemp(tbWBTemp.Position);
  lblWBTempV.Caption := IntToStr(tbWBTemp.Position) + 'K';
end;

procedure TfrmMain.BacklightChange(Sender: TObject);
begin
  if FUpdating or not FCam.Connected then Exit;
  FCam.SetBacklightCompensation(chkBacklight.Checked);
end;

procedure TfrmMain.AutoExposureChange(Sender: TObject);
begin
  if FUpdating or not FCam.Connected then Exit;
  FCam.SetExposureAuto(chkAutoExposure.Checked);
  tbExposure.Enabled := not chkAutoExposure.Checked;
end;

procedure TfrmMain.ExposureChange(Sender: TObject);
begin
  if FUpdating or not FCam.Connected then Exit;
  FCam.SetExposureAbsolute(tbExposure.Position);
  lblExposureV.Caption := IntToStr(tbExposure.Position);
end;

procedure TfrmMain.AutoFocusChange(Sender: TObject);
begin
  if FUpdating or not FCam.Connected then Exit;
  FCam.SetAutoFocus(chkAutoFocus.Checked);
  tbFocus.Enabled := not chkAutoFocus.Checked;
end;

procedure TfrmMain.FocusChange(Sender: TObject);
begin
  if FUpdating or not FCam.Connected then Exit;
  FCam.SetFocusAbsolute(tbFocus.Position);
  lblFocusV.Caption := IntToStr(tbFocus.Position);
end;

{ ===== Presets ===== }

procedure TfrmMain.PresetRecallClick(Sender: TObject);
var
  p: TPresetPosition;
  wasUpdating: Boolean;
begin
  if not FCam.Connected then Exit;

  p := FCam.GetPreset((Sender as TButton).Tag);
  if not FCam.RecallPreset((Sender as TButton).Tag) then Exit;

  // Recall changes the camera directly, so mirror the recalled zoom in the UI
  // without firing ZoomChange and sending the same command a second time.
  wasUpdating := FUpdating;
  FUpdating := True;
  try
    tbZoom.Position := p.Zoom;
    lblZoomVal.Caption := Format('%.1fx', [tbZoom.Position / 100.0]);
  finally
    FUpdating := wasUpdating;
  end;
end;

procedure TfrmMain.PresetSaveClick(Sender: TObject);
begin
  if FCam.Connected and FCam.SavePreset((Sender as TButton).Tag) then
    // Persist immediately so a saved preset survives a crash or forced exit.
    SaveSettings;
end;

{ ===== Log ===== }

procedure TfrmMain.ClearLogClick(Sender: TObject);
begin
  memoLog.Clear;
end;

procedure TfrmMain.ScanXUClick(Sender: TObject);
begin
  if not FCam.Connected then Exit;
  memoLog.Lines.Add('');
  memoLog.Lines.Add('=== XU Snapshot ' + FormatDateTime('hh:nn:ss', Now) + ' ===');
  FCam.DumpAllXU;
  memoLog.Lines.Add('=== End snapshot ===');
  memoLog.Lines.Add('');
  memoLog.SelStart := Length(memoLog.Text);
end;

procedure TfrmMain.CamLog(Sender: TObject; const Msg: string);
begin
  memoLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + Msg);
  // Auto-scroll to bottom
  memoLog.SelStart := Length(memoLog.Text);
end;

{ ===== UI Helpers ===== }

procedure TfrmMain.SetupTrackBar(tb: TTrackBar; const Range: TCtrlRange);
begin
  if Range.Available then
  begin
    tb.Min := Range.Min;
    tb.Max := Range.Max;
    tb.Position := Range.Current;
    tb.Enabled := True;
  end
  else
    tb.Enabled := False;
end;

procedure TfrmMain.ReadCurrentValues;
begin
  FUpdating := True;
  try
    // Zoom
    if FCam.ZoomRange.Available then
    begin
      tbZoom.Min := FCam.ZoomRange.Min;
      tbZoom.Max := FCam.ZoomRange.Max;
      tbZoom.Position := FCam.GetZoom;
      lblZoomVal.Caption := Format('%.1fx', [tbZoom.Position / 100.0]);
    end;

    // Image
    SetupTrackBar(tbBrightness, FCam.BrightnessRange);
    lblBrightnessV.Caption := IntToStr(tbBrightness.Position);
    SetupTrackBar(tbContrast, FCam.ContrastRange);
    lblContrastV.Caption := IntToStr(tbContrast.Position);
    SetupTrackBar(tbSaturation, FCam.SaturationRange);
    lblSaturationV.Caption := IntToStr(tbSaturation.Position);
    SetupTrackBar(tbSharpness, FCam.SharpnessRange);
    lblSharpnessV.Caption := IntToStr(tbSharpness.Position);
    SetupTrackBar(tbGain, FCam.GainRange);
    lblGainV.Caption := IntToStr(tbGain.Position);

    // WB
    chkAutoWB.Checked := FCam.GetAutoWhiteBalance;
    SetupTrackBar(tbWBTemp, FCam.WBTempRange);
    tbWBTemp.Enabled := not chkAutoWB.Checked;
    lblWBTempV.Caption := IntToStr(tbWBTemp.Position) + 'K';

    chkBacklight.Checked := FCam.GetBacklightCompensation;

    // Exposure
    chkAutoExposure.Checked := FCam.GetExposureAuto;
    SetupTrackBar(tbExposure, FCam.ExposureRange);
    tbExposure.Enabled := not chkAutoExposure.Checked;
    lblExposureV.Caption := IntToStr(tbExposure.Position);

    // Focus
    chkAutoFocus.Checked := FCam.GetAutoFocus;
    SetupTrackBar(tbFocus, FCam.FocusRange);
    tbFocus.Enabled := not chkAutoFocus.Checked;
    lblFocusV.Caption := IntToStr(tbFocus.Position);

    // Read current tracking frame (Link 2 only but safe to read)
    case FCam.GetTrackingFrame of
      tfHead:     cboTrackFrame.ItemIndex := 0;
      tfHalfBody: cboTrackFrame.ItemIndex := 1;
      tfFullBody: cboTrackFrame.ItemIndex := 2;
    end;
  finally
    FUpdating := False;
  end;
end;

procedure TfrmMain.UpdateUIState;
var
  connected: Boolean;
begin
  connected := FCam.Connected;
  grpPTZ.Enabled := connected;
  grpModes.Enabled := connected;
  grpImage.Enabled := connected;
  grpExposure.Enabled := connected;
  grpFocus.Enabled := connected;
  grpPresets.Enabled := connected;
  btnPreview.Enabled := connected;

  // Framing only works on Link 2
  if connected and (FCam.CameraModel = cmLink) then
  begin
    cboTrackFrame.Visible := False;
    lblTrackFrame.Caption := 'Framing: Link 2 only';
  end
  else if connected then
  begin
    cboTrackFrame.Visible := True;
    cboTrackFrame.Enabled := True;
    lblTrackFrame.Caption := 'Framing:';
  end;
end;

procedure TfrmMain.SaveSettings;
var
  ini: TIniFile;
  i: Integer;
  p: TPresetPosition;
begin
  ForceDirectories(GetAppConfigDir(False));
  ini := TIniFile.Create(GetAppConfigDir(False) + 'insta360link.ini');
  try
    ini.WriteString('Device', 'LastDevice', FCam.DevicePath);
    ini.WriteInteger('PTZ', 'PanStep', sePanStep.Value);
    ini.WriteInteger('PTZ', 'TiltStep', seTiltStep.Value);
    for i := 0 to 5 do
    begin
      ini.WriteString('Presets', 'Name' + IntToStr(i), edtPresetName[i].Text);
      p := FCam.GetPreset(i);
      ini.WriteBool('Presets', 'Valid' + IntToStr(i), p.Valid);
      ini.WriteInteger('Presets', 'Pan' + IntToStr(i), p.Pan);
      ini.WriteInteger('Presets', 'Tilt' + IntToStr(i), p.Tilt);
      ini.WriteInteger('Presets', 'Zoom' + IntToStr(i), p.Zoom);
    end;
  finally
    ini.Free;
  end;
end;

procedure TfrmMain.LoadSettings;
var
  ini: TIniFile;
  fn, lastDev: string;
  i: Integer;
  p: TPresetPosition;
begin
  fn := GetAppConfigDir(False) + 'insta360link.ini';
  if not FileExists(fn) then Exit;

  ini := TIniFile.Create(fn);
  try
    sePanStep.Value := ini.ReadInteger('PTZ', 'PanStep', 8);
    seTiltStep.Value := ini.ReadInteger('PTZ', 'TiltStep', 8);

    // Re-select the last-used device if it's still present in the list.
    // Combo items are formatted as '<path>  [card - driver]', so match on prefix.
    lastDev := ini.ReadString('Device', 'LastDevice', '');
    if lastDev <> '' then
      for i := 0 to cboDevice.Items.Count - 1 do
        if Pos(lastDev + ' ', cboDevice.Items[i] + ' ') = 1 then
        begin
          cboDevice.ItemIndex := i;
          Break;
        end;
    for i := 0 to 5 do
    begin
      edtPresetName[i].Text := ini.ReadString('Presets', 'Name' + IntToStr(i),
        'Preset ' + IntToStr(i));
      p.Name := edtPresetName[i].Text;
      p.Valid := ini.ReadBool('Presets', 'Valid' + IntToStr(i), False);
      p.Pan := ini.ReadInteger('Presets', 'Pan' + IntToStr(i), 0);
      p.Tilt := ini.ReadInteger('Presets', 'Tilt' + IntToStr(i), 0);
      p.Zoom := ini.ReadInteger('Presets', 'Zoom' + IntToStr(i), 100);
      FCam.SetPreset(i, p);
    end;
  finally
    ini.Free;
  end;
end;

end.
