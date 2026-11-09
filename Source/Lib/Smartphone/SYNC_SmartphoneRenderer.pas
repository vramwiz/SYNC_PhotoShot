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
    // 描画先の変換・クリップを復元する。引数の画像や Target を保持・解放しない。
    procedure Draw(Target: TGPGraphics; const Destination: TRect;
      Orientation: Integer; PhoneColor: ARGB = $FF303840;
      ScreenColor: ARGB = $FFFFFFFF; ScreenImage: TGPBitmap = nil;
      ImageRect: PGPRectF = nil);
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

procedure TSmartphoneRenderer.Draw(Target: TGPGraphics; const Destination: TRect;
  Orientation: Integer; PhoneColor, ScreenColor: ARGB; ScreenImage: TGPBitmap;
  ImageRect: PGPRectF);
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
    FillRound(Target, 1, 1, W - 2, H - 2, 42, $FF101418);
    FillRound(Target, 3, 3, W - 6, H - 6, 40, PhoneColor or $FF000000);
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
