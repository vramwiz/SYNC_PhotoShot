library SYNC_PhotoShot;

// 写真撮影プラグインの AviUtl2 DLL エントリーポイント。

{$ALIGN 8}
// 標準の DLL を出力し、ビルド後イベントで .aux2 化・配備する（内部でフィルターを登録）。

uses
  SYNC_PhotoShot_Preparation in 'Source\Plugin\Filter\SYNC_PhotoShot_Preparation.pas',
  SYNC_PhotoShot_PreparedStore in 'Source\Common\SYNC_PhotoShot_PreparedStore.pas',
  SYNC_PhotoShot_HostAPI in 'Source\Lib\SYNC_PhotoShot_HostAPI.pas',
  MP3Types in 'Source\Lib\Audio\Core\MP3Types.pas',
  MP3ScaleFactors in 'Source\Lib\Audio\Core\MP3ScaleFactors.pas',
  MP3Layer3 in 'Source\Lib\Audio\Core\MP3Layer3.pas',
  MP3Huffman in 'Source\Lib\Audio\Core\MP3Huffman.pas',
  MP3Frame in 'Source\Lib\Audio\Core\MP3Frame.pas',
  MP3BitStream in 'Source\Lib\Audio\Core\MP3BitStream.pas',
  SYNC_PhotoShot_MP3 in 'Source\Lib\Audio\SYNC_PhotoShot_MP3.pas',
  MP3Decoder in 'Source\Lib\Audio\MP3Decoder.pas',
  SYNC_PhotoShot_Audio in 'Source\Plugin\Filter\SYNC_PhotoShot_Audio.pas',
  SYNC_PhotoShot_AudioMix in 'Source\Common\SYNC_PhotoShot_AudioMix.pas',
  SYNC_PhotoShot_Parameters in 'Source\Plugin\Filter\SYNC_PhotoShot_Parameters.pas',
  SYNC_PhotoShot_Renderer in 'Source\Common\SYNC_PhotoShot_Renderer.pas',
  SYNC_PhotoShot_Capture in 'Source\Common\SYNC_PhotoShot_Capture.pas',
  SYNC_PhotoShot_Timeline in 'Source\Common\SYNC_PhotoShot_Timeline.pas',
  SYNC_SmartphoneRenderer in 'Source\Lib\Smartphone\SYNC_SmartphoneRenderer.pas',
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  PluginFilterTable in 'Source\Lib\FilterTable\PluginFilterTable.pas',
  SYNC_PhotoShot_FilterPlugin in 'Source\Plugin\Filter\SYNC_PhotoShot_FilterPlugin.pas';

{$R *.res}

// 入力 Version は decimal 形式の本体番号。2.1.15 未満は userdata ABI の安全のため拒否。
// 初期登録成功時 1、失敗時 0。
// テーブルは DLL の有効期間中保持し、例外をホストへ伝播させない。
function InitializePlugin(Version: Cardinal): Byte; cdecl;
begin
  Result := 0;
  try
    if Version < 2011500 then Exit;
    InitializePhotoShotPreparation;
    InitializePhotoShotAudio;
    GetPhotoShotFilterTable;
    Result := 1;
  except
    // Delphi例外をAviUtl2のCコールバック境界へ漏らさない。
  end;
end;

// ホスト処理終了後に、事前デコードした共有 PCM を解放する。
procedure UninitializePlugin; cdecl;
begin
  FinalizePhotoShotPreparation;
  ReleasePhotoShotAudio;
end;

// 入力なし。DLL が所有する登録テーブルを返す。ホスト側で解放せず、失敗時は nil。
function GetFilterPluginTable: PFILTER_PLUGIN_TABLE; cdecl;
begin
  Result := nil;
  try
    Result := GetPhotoShotFilterTable;
  except
    // 登録失敗時はテーブルを返さずホスト側へ判断を委ねる。
  end;
end;

// SDK filter2.h の最小本体版通知。事前描画の SDK v2.1.15 に合わせる。
function RequiredVersion: Cardinal; cdecl;
begin
  Result := 2011500;
end;

var
  CommonTable: TPhotoShotCommonPluginTable = (
    Name: 'SYNC 写真撮影';
    Information: '写真準備機能付きフィルタープラグイン'
  );

function GetCommonPluginTable: PPhotoShotCommonPluginTable; cdecl;
begin
  Result := @CommonTable;
end;

procedure RegisterPlugin(Host: PPhotoShotHostAppTable); cdecl;
begin
  try
    RegisterPhotoShotHost(Host);
    if (Host <> nil) and Assigned(Host^.RegisterFilterPlugin) then
      Host^.RegisterFilterPlugin(GetPhotoShotFilterTable);
  except
    // 登録失敗時も例外をホストへ渡さない。
  end;
end;

exports
  RegisterPlugin name 'RegisterPlugin',
  GetCommonPluginTable name 'GetCommonPluginTable',
  PhotoShotSetPreparationSilent name 'PhotoShotSetPreparationSilent',
  PhotoShotPreparationState name 'PhotoShotPreparationState',
  RequiredVersion name 'RequiredVersion',
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  GetFilterPluginTable name 'GetFilterPluginTable';

begin
end.
