# PhotoShot MP3 decoder integration

Copied from D:\DelphiProg\MyApp\SYNC_RhythmShooter on 2026-11-09.
The current reference project uses a pure Delphi decoder, not FFmpeg.
The 7 MP3Decoder/Core Pascal units were copied byte-for-byte to Source/Lib/Audio.
ThirdParty/MP3Decoder retains the original CC0 notice, provenance, original source,
core changes, and the upstream RhythmShooter integration manifest.
The upstream manifest paths describe RhythmShooter, not the PhotoShot directory layout.

SYNC_PhotoShot_MP3.DecodePhotoShotMP3 returns owned managed float PCM:
44100 Hz, stereo, interleaved L/R, normalized by signed PCM16 / 32768.
The source DecodeMP3 API and ToStereo44100 remain available unchanged.
SaveAudioWAV writes a new PCM16 WAV file and refuses to overwrite an existing file.
Decode during preparation, not inside render/audio callbacks.
Cancellation raises EAbort; malformed streams raise EMP3DecodeError.
No FFmpeg executable/DLL is needed or included for runtime use.

No shutter sound assets are included. Any files under Tests/MP3 are synthesized
verification signals, not product sound effects.
