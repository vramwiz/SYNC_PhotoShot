program EmbeddedAudioTests;
{$APPTYPE CONSOLE}
{$R '..\..\SYNC_PhotoShot.res'}
{$R '..\..\Source\Plugin\Filter\SYNC_PhotoShot_Audio.res'}

uses
  System.SysUtils, System.Classes, Winapi.Windows, SYNC_PhotoShot_MP3;

const
  Names: array[0..3] of string =
    ('PHOTOSHOT_SMARTPHONE','PHOTOSHOT_COMPACT','PHOTOSHOT_DSLR','PHOTOSHOT_INSTANT');
  Files: array[0..3] of string =
    ('スマホ.mp3','コンデジ.mp3','一眼レフ.mp3','インスタントカメラ.mp3');
var
  I: Integer;
  R: TResourceStream;
  F: TFileStream;
  A,B: TBytes;
  Embedded, FilePCM: TPhotoShotPCM;
  Root: string;
begin
  try
    if ParamCount<>1 then raise Exception.Create('Expected project directory');
    Root:=IncludeTrailingPathDelimiter(ParamStr(1));
    R:=TResourceStream.Create(HInstance,'PLATFORMTARGETS',RT_RCDATA);
    try
      if R.Size<>4 then raise Exception.Create('Existing PLATFORMTARGETS not preserved');
      Writeln('PASS existing PLATFORMTARGETS');
    finally R.Free;end;
    for I:=0 to 3 do
    begin
      R:=TResourceStream.Create(HInstance,Names[I],RT_RCDATA);
      F:=TFileStream.Create(Root+'Mp3\'+Files[I],fmOpenRead or fmShareDenyWrite);
      try
        if R.Size<>F.Size then raise Exception.Create('Resource byte size mismatch');
        SetLength(A,R.Size);SetLength(B,F.Size);
        R.ReadBuffer(A[0],Length(A));F.ReadBuffer(B[0],Length(B));
        if not CompareMem(@A[0],@B[0],Length(A)) then
          raise Exception.Create('Embedded MP3 differs from original');
      finally F.Free;R.Free;end;
      Embedded:=DecodePhotoShotMP3Resource(HInstance,Names[I]);
      FilePCM:=DecodePhotoShotMP3(Root+'Mp3\'+Files[I]);
      if (Length(Embedded.Samples)<>Length(FilePCM.Samples)) or
        not CompareMem(@Embedded.Samples[0],@FilePCM.Samples[0],
          Length(Embedded.Samples)*SizeOf(Single)) then
        raise Exception.Create('Embedded decoder PCM differs from file decoder');
      Writeln('PASS ',Names[I],' bytes=',Length(A),' frames=',Embedded.FrameCount,
        ' seconds=',FormatFloat('0.000',Embedded.FrameCount/Embedded.SampleRate));
    end;
    Writeln('PASS all resources match original MP3 and file-decoded PCM exactly.');
    Writeln('No temporary audio files or external MP3 folders were used for resource decoding.');
  except on E:Exception do begin Writeln('FAIL ',E.ClassName,': ',E.Message);Halt(1);end;end;
end.
