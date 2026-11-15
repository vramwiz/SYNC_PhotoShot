unit SYNC_SmartphoneRenderer;

// SYNC_Mine のスマホ外形・配置・透明面描画を抽出した再利用ライブラリ。
// 会話モデル、設定 UI、素材ファイル、AviUtl2 SDK に依存しない。
// コピー元とライセンスは同じフォルダーの README.md / LICENSE.SYNC_Mine.txt を参照。

interface

uses
  System.Types, Winapi.Windows, Winapi.GDIPAPI, Winapi.GDIPOBJ;

type
  TSmartphoneRenderer = class
  private
    FGraphicsToken: ULONG_PTR;
    FSurface: TGPBitmap;
  public
    // GDI+ を開始する。失敗時は例外。インスタンスは同時に複数スレッドから使用しない。
    constructor Create;
    // 所有する描画面を破棄してから、このインスタンスの GDI+ を終了する。
    destructor Destroy; override;
    // Target にスマホを描く。向きは 0=縦、1=横。色は不透明 RGB として使用する。
    // ScreenImage は借用し、角丸画面内へ伸縮表示する。nil の場合は背景色のみ。
    // RaisedCase は既存の外形内に保護ケースの厚み・縁・ガラスの段差を描く。
    // 描画先の変換・クリップを復元する。引数の画像や Target を保持・解放しない。
    procedure Draw(Target: TGPGraphics; const Destination: TRect;
      Orientation: Integer; PhoneColor: ARGB = $FF303840;
      ScreenColor: ARGB = $FFFFFFFF; ScreenImage: TGPBitmap = nil;
      ImageRect: PGPRectF = nil; RaisedCase: Boolean = False);
    // Clipped は描画対象の映像内矩形。透明 PARGB 面を返す。空矩形では nil。
    // 戻り値は本インスタンス所有。次の呼出し／破棄まで有効で、呼出側は解放しない。
    // ScreenImage に以前返した描画面自身を渡さない。
    function RenderSurface(const Destination, Clipped: TRect;
      Orientation: Integer; PhoneColor: ARGB = $FF303840;
      ScreenColor: ARGB = $FFFFFFFF; ScreenImage: TGPBitmap = nil): TGPBitmap;
  end;

// 0（および 1 以外）は縦 420x820、1 は横 820x420。戻り値なし、状態変更なし。
procedure SmartphoneSize(Orientation: Integer; out Width, Height: Integer);
// 映像サイズと中心からの X/Y オフセット、倍率（1=原寸）から配置矩形を返す。
// Mine と同じく倍率を 0..10、オフセットを -32768..32768 に制限する。
function SmartphoneBounds(Width, Height, Orientation: Integer;
  X, Y, Scale: Double): TRect;

implementation

uses
  System.Math, System.SysUtils;

constructor TSmartphoneRenderer.Create;
var
  Input: TGdiplusStartupInput;
begin
  inherited Create;
  Input := Default(TGdiplusStartupInput);
  Input.GdiplusVersion := 1;
  if GdiplusStartup(FGraphicsToken, @Input, nil) <> Ok then
    raise Exception.Create('Unable to initialize GDI+ for smartphone rendering');
end;

destructor TSmartphoneRenderer.Destroy;
begin
  FSurface.Free;
  if FGraphicsToken <> 0 then GdiplusShutdown(FGraphicsToken);
  inherited Destroy;
end;

procedure SmartphoneSize(Orientation: Integer; out Width, Height: Integer);
begin
  if Orientation = 1 then
  begin
    Width := 820;
    Height := 420;
  end
  else
  begin
    Width := 420;
    Height := 820;
  end;
end;

function SmartphoneBounds(Width, Height, Orientation: Integer; X, Y, Scale: Double): TRect;
var
  W, H: Integer;
begin
  SmartphoneSize(Orientation, W, H);
  Scale := EnsureRange(Scale, 0.0, 10.0);
  X := Width / 2 + EnsureRange(X, -32768.0, 32768.0);
  Y := Height / 2 + EnsureRange(Y, -32768.0, 32768.0);
  Result := Rect(Round(X - W * Scale / 2), Round(Y - H * Scale / 2),
    Round(X + W * Scale / 2), Round(Y + H * Scale / 2));
end;

function RoundPath(X, Y, W, H, Radius: Single): TGPGraphicsPath;
begin
  Result := TGPGraphicsPath.Create;
  Radius := Min(Radius, Min(W, H) / 2) * 2;
  Result.AddArc(X, Y, Radius, Radius, 180, 90);
  Result.AddArc(X + W - Radius, Y, Radius, Radius, 270, 90);
  Result.AddArc(X + W - Radius, Y + H - Radius, Radius, Radius, 0, 90);
  Result.AddArc(X, Y + H - Radius, Radius, Radius, 90, 90);
  Result.CloseFigure;
end;

procedure FillRound(Target: TGPGraphics; X, Y, W, H, Radius: Single; Color: ARGB);
var
  Path: TGPGraphicsPath;
  Brush: TGPSolidBrush;
begin
  Path := RoundPath(X, Y, W, H, Radius);
  Brush := TGPSolidBrush.Create(Color);
  try
    Target.FillPath(Brush, Path);
  finally
    Brush.Free;
    Path.Free;
  end;
end;

// 不透明な指定色を基準に明暗を作る。黒・白のケースにも輪郭の明度差を残す。
function CaseTone(Color, Tone: ARGB; Amount: Byte): ARGB;
var
  R, G, B, Weight, Opposite: Cardinal;
begin
  Weight := Amount;
  Opposite := 255 - Weight;
  R := (((Color shr 16) and $FF) * Opposite +
    ((Tone shr 16) and $FF) * Weight + 127) div 255;
  G := (((Color shr 8) and $FF) * Opposite +
    ((Tone shr 8) and $FF) * Weight + 127) div 255;
  B := ((Color and $FF) * Opposite + (Tone and $FF) * Weight + 127) div 255;
  Result := $FF000000 or (R shl 16) or (G shl 8) or B;
end;

// 左上を光源とする面または輪郭。追加bitmapや画素単位のぼかしを作らない。
procedure ShadeRound(Target: TGPGraphics; X, Y, W, H, Radius: Single;
  Light, Dark: ARGB; StrokeWidth: Single = 0);
var
  Path: TGPGraphicsPath;
  Brush: TGPLinearGradientBrush;
  Pen: TGPPen;
begin
  Path := RoundPath(X, Y, W, H, Radius);
  Brush := nil;
  Pen := nil;
  try
    Brush := TGPLinearGradientBrush.Create(MakePoint(X, Y),
      MakePoint(X + W, Y + H), Light, Dark);
    if StrokeWidth > 0 then
    begin
      Pen := TGPPen.Create(Brush, StrokeWidth);
      Target.DrawPath(Pen, Path);
    end
    else Target.FillPath(Brush, Path);
  finally
    Pen.Free;
    Brush.Free;
    Path.Free;
  end;
end;

procedure DrawRaisedCase(Target: TGPGraphics; W, H: Integer; Color: ARGB);
begin
  // 外周の影、暗い側面、手前の丸いリップをずらして厚みを表す。
  // 420x820 / 820x420 の内側だけを使い、半透明合成時にも外周を欠けさせない。
  FillRound(Target, 3, 5, W - 4, H - 6, 43, $60000000);
  ShadeRound(Target, 1, 1, W - 4, H - 4, 42,
    CaseTone(Color, $FFFFFFFF, 80), CaseTone(Color, $FF000000, 200));
  ShadeRound(Target, 1.75, 1.75, W - 5.5, H - 5.5, 41.25,
    $B0FFFFFF, $D0000000, 1.5);
  ShadeRound(Target, 4, 4, W - 12, H - 14, 39,
    CaseTone(Color, $FFFFFFFF, 52), CaseTone(Color, $FF000000, 64));
  ShadeRound(Target, 4.75, 4.75, W - 13.5, H - 15.5, 38.25,
    CaseTone(Color, $FFFFFFFF, 120), CaseTone(Color, $FF000000, 140), 1.5);
  // リップの内側は上・左が暗く、右・下が光を受ける凹み。
  ShadeRound(Target, 9, 13, W - 21, H - 29, 34,
    CaseTone(Color, $FF000000, 200), CaseTone(Color, $FFFFFFFF, 96));
  FillRound(Target, 11, 15, W - 22, H - 30, 32, $FF06080B);
  ShadeRound(Target, 12.5, 16.5, W - 25, H - 33, 30.5,
    $FF020306, $FF7C8790, 1.5);
  // ケースに一体化した側面ボタン。横向きでは長辺の上下へ移る。
  if W > H then
  begin
    ShadeRound(Target, 176, 1, 68, 3.5, 1.75,
      CaseTone(Color, $FFFFFFFF, 100), CaseTone(Color, $FF000000, 180));
    ShadeRound(Target, 146, H - 6, 36, 3.5, 1.75, $FF07090C,
      CaseTone(Color, $FFFFFFFF, 60));
    ShadeRound(Target, 196, H - 6, 36, 3.5, 1.75, $FF07090C,
      CaseTone(Color, $FFFFFFFF, 60));
  end
  else
  begin
    ShadeRound(Target, W - 6, 176, 3.5, 68, 1.75,
      CaseTone(Color, $FFFFFFFF, 100), CaseTone(Color, $FF000000, 180));
    ShadeRound(Target, 1, 146, 3.5, 36, 1.75,
      CaseTone(Color, $FFFFFFFF, 60), $FF07090C);
    ShadeRound(Target, 1, 196, 3.5, 36, 1.75,
      CaseTone(Color, $FFFFFFFF, 60), $FF07090C);
  end;
end;

procedure TSmartphoneRenderer.Draw(Target: TGPGraphics; const Destination: TRect;
  Orientation: Integer; PhoneColor, ScreenColor: ARGB; ScreenImage: TGPBitmap;
  ImageRect: PGPRectF; RaisedCase: Boolean);
var
  W, H: Integer;
  State, ImageState: GraphicsState;
  Screen: TGPGraphicsPath;
begin
  if (Target = nil) or Destination.IsEmpty then Exit;
  SmartphoneSize(Orientation, W, H);
  State := Target.Save;
  Screen := nil;
  try
    Target.SetSmoothingMode(SmoothingModeAntiAlias);
    Target.SetInterpolationMode(InterpolationModeHighQualityBicubic);
    Target.TranslateTransform(Destination.Left, Destination.Top);
    Target.ScaleTransform(Destination.Width / W, Destination.Height / H);
    if RaisedCase then DrawRaisedCase(Target, W, H, PhoneColor)
    else
    begin
      FillRound(Target, 1, 1, W - 2, H - 2, 42, $FF101418);
      FillRound(Target, 3, 3, W - 6, H - 6, 40, PhoneColor or $FF000000);
    end;
    Screen := RoundPath(14, 18, W - 28, H - 36, 29);
    Target.SetClip(Screen, CombineModeIntersect);
    FillRound(Target, 14, 18, W - 28, H - 36, 29, ScreenColor or $FF000000);
    if (ScreenImage <> nil) and (ScreenImage.GetLastStatus = Ok) then
      if ImageRect=nil then
        Target.DrawImage(ScreenImage, 14, 18, W - 28, H - 36)
      else
      begin
        // 任意の中央撮影領域。省略時は従来の全面表示を維持する。
        ImageState:=Target.Save;
        try
          Target.SetClip(ImageRect^,CombineModeIntersect);
          Target.DrawImage(ScreenImage,ImageRect^);
        finally Target.Restore(ImageState); end;
      end;
    // ガラスの接触影は端のみに置き、ライブビュー中央を曇らせない。
    if RaisedCase then
      ShadeRound(Target, 14.5, 18.5, W - 29, H - 37, 28.5,
        $98000000, $28FFFFFF, 2);
    // 筐体に固定されたカメラ・スピーカーは横向き時に左辺へ移す。
    if W > H then
      FillRound(Target, 26, H / 2 - 42, 16, 84, 8, $FF101418)
    else
      FillRound(Target, W / 2 - 42, 26, 84, 16, 8, $FF101418);
    FillRound(Target, W / 2 - 54, H - 31, 108, 4, 2, $FF27333E);
  finally
    Screen.Free;
    Target.Restore(State);
  end;
end;

function TSmartphoneRenderer.RenderSurface(const Destination, Clipped: TRect;
  Orientation: Integer; PhoneColor, ScreenColor: ARGB;
  ScreenImage: TGPBitmap): TGPBitmap;
var
  Target: TGPGraphics;
  Local: TRect;
begin
  Result := nil;
  if Destination.IsEmpty or Clipped.IsEmpty then Exit;
  if (ScreenImage <> nil) and (ScreenImage = FSurface) then
    raise EArgumentException.Create('ScreenImage must not be the renderer surface');
  if (FSurface = nil) or (Integer(FSurface.GetWidth) <> Clipped.Width) or
    (Integer(FSurface.GetHeight) <> Clipped.Height) then
  begin
    FreeAndNil(FSurface);
    FSurface := TGPBitmap.Create(Clipped.Width, Clipped.Height, PixelFormat32bppPARGB);
    if FSurface.GetLastStatus <> Ok then
    begin
      FreeAndNil(FSurface);
      raise Exception.Create('Unable to allocate smartphone surface');
    end;
  end;
  Target := TGPGraphics.Create(FSurface);
  try
    Target.Clear(0);
    Local := Destination;
    Local.Offset(-Clipped.Left, -Clipped.Top);
    Draw(Target, Local, Orientation, PhoneColor, ScreenColor, ScreenImage);
  finally
    Target.Free;
  end;
  Result := FSurface;
end;

end.
