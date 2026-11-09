# Decoder core review

Scope: six units in Source/Core. The vendored originals in ThirdParty were preserved. No files in SYNC_RhythmShooter were changed. Reviewed the units as self-contained mathematical decoding and stream parsing: no process execution, network access, installation or external runtime dependency.

## Algorithm corrections

- MPEG-2/2.5 scalefactor partition selection: advance by the final four-entry row, matching the original C for-loop's post-increment. The translation previously selected the preceding partition.
- Mixed short blocks at 8 kHz: choose four long subbands using the raw sample-rate index, not the compressed table index.
- Disable granule scalefactor reuse for short blocks and initialize intensity/scalefactor history deterministically.

## Input safety

- Huffman cache lookahead returns zero beyond the supplied buffer without dereferencing past it. No caller padding requirement.
- Validate bit-count/offset/position/skip arguments and bounded stream sizes. Zero-bit reads do not dereference the input.
- Validate granule lengths and scalefactor/pair bit budgets; reject reserved Huffman tables 4 and 14 and invalid region/band progression.
- Bound count1 output to the 576-coefficient spectrum.
- Reject reserved MPEG version, require full side information, validate channels, and allow parsing a header at the final four bytes.
- CRC bytes are the outer frame reader's responsibility; this parser expects the reader already skipped them. CRC checksum verification is not implemented.

## Build checks

Delphi 37 dcc64 Release build passed. Separate Build/Debug executable compiled with range and integer-overflow checks enabled. Both 11.025 kHz stereo (MPEG-2.5) and 44.1 kHz stereo (MPEG-1) valid fixtures decoded successfully with checks enabled. The damaged-middle fixture was rejected cleanly. Full numerical regression results belong to the test harness report, not this source audit.

## Limits

This is a targeted audit and hardening pass, not a proof of safety or bitstream completeness. Free-format is unsupported by the outer decoder. Additional independent corpus testing, intensity-stereo/mixed-block/CRC fixtures and fuzzing remain useful. The core retains the upstream minimp3 int16 synthesis/rounding path before conversion to float, so numerical equality with FFmpeg float output is not expected.

Sources: gustavoeenriquez/delphi-libraries commit 849dbaf1892486a6dc5f1ebb555c949a6c4dd4d9 and read-only comparison against https://github.com/lieff/minimp3/blob/master/minimp3.h (reviewed 2026-11-06 UTC).
## Version 2: Xing metadata consistency

The expanded encoder tests identified FFmpeg `mp3_mf` output whose Xing frame count describes encoder packets rather than individual MPEG frames. In the observed fixture, 15 packets contain 49 MPEG audio frames. Rejecting this count discrepancy unconditionally rejects otherwise decodable output.

Version 2 records both the declared counts and the actual parsed MPEG frame span. A frame-count mismatch is accepted only when a nonzero Xing byte count matches that span. Every nonzero declared byte count is checked independently of the frame count, and the parsed frame end must reach the audio end after excluding trailing ID3v1. Leading ID3v2 is not part of the MPEG span. Matching byte counts establish metadata consistency, not authenticity or proof that a file was never edited.

Targeted metadata regression: 12/12 passed in `tests/metadata/20261107-081737-613/report.json`, with range and integer-overflow checks enabled in an isolated build. Coverage includes correct input; wrong frame count with matching byte size; wrong/zero declared byte size; wrong byte size even with correct frame count; whole-frame truncation; 1, 3 and 17 trailing junk bytes even when the declaration matches the enlarged file span; and ID3v1 byte accounting. The prior four acceptance failures are now rejected correctly. No crash or runtime-safety exception occurred.

`Scripts/Test-Metadata.ps1` now selects the most recently modified `rate44100_ch2_cbr/input.mp3` under direct `tests/runs` run directories, excludes reparse-point candidates, and records the selected source and hash. An explicit `-Source` remains supported; absence of a fixture produces an actionable error. This rerun used `tests/runs/20261107-081719-637/rate44100_ch2_cbr/input.mp3`. It did not modify decoder source, seed fixtures, or the Release executable. Release SHA-256 before and after remained `F43BEDB47C455435ECDE7440ED81268825C8E02E9D6DC059CEFAD7D57CC76AB4`.