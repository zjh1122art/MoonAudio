# Moon Audio

Moon Audio is a native MoonBit audio decoding library for WAV PCM and OGG
Vorbis streams. Its public API is intentionally small:

```moonbit nocheck
let audio = @moon_audio.decode(bytes)?
let mono = audio.resample(48000, 1)
let wav = mono.to_wav()
```

The library is an input-to-output decoder. It does not own a device, thread,
or playback backend. Applications receive a `Pcm` value containing signed
16-bit interleaved PCM samples and can send it to any output system.

## Status

- RIFF/WAVE PCM: 8/16/24/32-bit integer and IEEE float, mono or interleaved
  multi-channel, with `fmt ` and `data` chunks in any order.
- Ogg container: page reconstruction, CRC validation, Vorbis packet
  identification and metadata parsing.
- Vorbis audio packets: native decoder for the baseline floor-0/floor-1,
  residue type 0/1/2, inverse coupling, IMDCT and Vorbis windows.
- Linear resampling and channel conversion.
- WAV writer, command-line demo, tests, and CI.
- The command-line file adapter uses `moonbitlang/x/fs`; the core decoder stays
  in-memory and portable.

The implementation is a clean-room MoonBit implementation informed by the
public-domain `stb_vorbis` and `dr_wav` projects. No source code is copied.
The upstream references and their licenses are recorded in `NOTICE`.

## Build and test

```sh
moon check
moon test
moon run cmd/main -- --self-test
```

The demo emits a short sine wave and prints stream metadata:

```sh
moon run cmd/main -- --self-test output.wav
```

## Design

The decoder pipeline is:

1. `OggReader` reconstructs packets from pages and validates page CRCs.
2. `VorbisSetup` parses codebooks, floors, residues, mappings and modes.
3. `VorbisDecoder` turns audio packets into planar float blocks, performs
   inverse coupling and IMDCT, then interleaves signed 16-bit PCM. The current
   decoder does not yet perform full overlap-add or end-granule trimming, so
   Vorbis output should be treated as a development baseline rather than a
   production-complete stb_vorbis replacement.
4. `resample` and `to_wav` are pure transformations over `Pcm`.

The core decoder exposes an in-memory API. The command-line package also
provides a file conversion demo:

```sh
moon run cmd/main -- input.ogg output.wav
moon run cmd/main -- --self-test output.wav
```

Unsupported or malformed input returns `AudioError`; the parser never reads
past the supplied byte slice. The first release intentionally does not
implement chained Ogg logical streams, Vorbis multichannel mappings other
than mapping 0, or non-PCM WAV compression formats.

## Project declaration

This is a MoonBit-native port-inspired implementation for the 2026 MoonBit
open-source hackathon. The project uses the MIT license. See `NOTICE` and
`LICENSE`.
