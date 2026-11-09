library SYNC_PhotoShot;

// 写真撮影のAviUtl2 DLL境界。

{$ALIGN 8}

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

function InitializePlugin(Version: Cardinal): Byte; cdecl;
begin
  Result := 0;
  try
    if not StartPhotoShotGraphics then Exit;
    SetPhotoShotHostVersion(Version);
    GetPhotoShotFilterTable;
    Result := 1;
  except
    StopPhotoShotGraphics;
    // Delphi例外をAviUtl2のCコールバック境界へ漏らさない。
  end;
end;

procedure UninitializePlugin; cdecl;
begin
  StopPhotoShotGraphics;
end;

function GetFilterPluginTable: PFILTER_PLUGIN_TABLE; cdecl;
begin
  Result := nil;
  try
    Result := GetPhotoShotFilterTable;
  except
    // 登録失敗時はテーブルを返さずホスト側へ判断を委ねる。
  end;
end;

exports
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  GetFilterPluginTable name 'GetFilterPluginTable',
  SetPhotoShotLogger name 'InitializeLogger';

begin
end.
