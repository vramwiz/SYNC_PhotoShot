# MP3 decoder tests (2026-11-09)

This folder contains only synthesized 733 Hz verification signals, not product shutter assets.
The copied native Delphi decoder and PhotoShot float adapter were compiled with Delphi 37.0 Win64.
Compile succeeded: zero errors/warnings; 2 upstream unused-assignment hints.
Namespace scopes System;Winapi are required by the original decoder core.

9 cases cover MPEG 1/2/2.5, all 9 standard sample rates (8 kHz through 48 kHz),
mono/stereo, CBR/VBR and gapless metadata. All decode and float-contract checks passed.
Malformed input was rejected. Output float contract: 44100 Hz, stereo interleaved,
finite samples in [-1,1), with frame counts consistent with rate conversion.

Native PCM16 was compared with FFmpeg s16le decoding of the exact same MP3.
All native sample counts matched. Every maximum absolute sample error was 1 PCM16 LSB.
See results.txt and reference-comparison.txt for individual measurements.
These finite synthetic cases are not a claim of support for every possible MP3.

Runtime decoder is pure Delphi. FFmpeg was used only to generate/reference tests:
D:\DelphiProg\MyApp\SYNC_RhythmShooter\ThirdParty\FFmpeg\bin\ffmpeg.exe
No FFmpeg binaries were copied into PhotoShot.
The independent test does not load or deploy the PhotoShot plugin and does not test AviUtl2 audio callbacks.
