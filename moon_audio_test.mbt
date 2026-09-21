///|
fn put_tag_test(out : Array[Byte], at : Int, text : String) -> Unit {
  for i = 0; i < 4; i = i + 1 {
    out[at + i] = text[i].to_byte()
  }
}

///|
fn put_u16_test(out : Array[Byte], at : Int, value : Int) -> Unit {
  out[at] = (value & 255).to_byte()
  out[at + 1] = ((value >> 8) & 255).to_byte()
}

///|
fn put_u32_test(out : Array[Byte], at : Int, value : Int) -> Unit {
  put_u16_test(out, at, value)
  put_u16_test(out, at + 2, value >> 16)
}

///|
fn write_fmt_test(
  out : Array[Byte],
  at : Int,
  format : Int,
  bits : Int,
) -> Unit {
  put_tag_test(out, at, "fmt ")
  put_u32_test(out, at + 4, 16)
  put_u16_test(out, at + 8, format)
  put_u16_test(out, at + 10, 1)
  put_u32_test(out, at + 12, 8000)
  put_u32_test(out, at + 16, 8000 * ((bits + 7) / 8))
  put_u16_test(out, at + 20, (bits + 7) / 8)
  put_u16_test(out, at + 22, bits)
}

///|
fn write_data_test(out : Array[Byte], at : Int, payload : Bytes) -> Int {
  put_tag_test(out, at, "data")
  put_u32_test(out, at + 4, payload.length())
  for i = 0; i < payload.length(); i = i + 1 {
    out[at + 8 + i] = payload[i]
  }
  at + 8 + payload.length() + payload.length() % 2
}

///|
fn make_wav_test(
  format : Int,
  bits : Int,
  payload : Bytes,
  data_first : Bool,
) -> Bytes {
  let data_padded = payload.length() + payload.length() % 2
  let total = 12 + 12 + 8 + data_padded + 24
  let out = Array::make(total, (0).to_byte())
  put_tag_test(out, 0, "RIFF")
  put_u32_test(out, 4, total - 8)
  put_tag_test(out, 8, "WAVE")
  put_tag_test(out, 12, "JUNK")
  put_u32_test(out, 16, 3)
  out[20] = b'a'
  out[21] = b'b'
  out[22] = b'c'
  let mut at = 24
  if data_first {
    at = write_data_test(out, at, payload)
    write_fmt_test(out, at, format, bits)
  } else {
    write_fmt_test(out, at, format, bits)
    at = write_data_test(out, at + 24, payload)
  }
  ignore(at)
  Bytes::from_array(out)
}

///|
test "decode 16 bit WAV with reordered chunks" {
  let audio = @moon_audio.decode(
    make_wav_test(1, 16, b"\x00\x80\xff\x7f", true),
  )
  assert_eq(audio.rate, 8000)
  assert_eq(audio.channels, 1)
  assert_eq(audio.frames(), 2)
  assert_eq(audio.samples[0], Int16::from_int(-32768))
  assert_eq(audio.samples[1], Int16::from_int(32767))
  let encoded = audio.to_wav()
  let roundtrip = @moon_audio.decode(encoded)
  assert_eq(roundtrip.samples[0], audio.samples[0])
  assert_eq(roundtrip.samples[1], audio.samples[1])
}

///|
test "decode integer WAV bit depths" {
  let audio8 = @moon_audio.decode(make_wav_test(1, 8, b"\x00\xff", false))
  assert_eq(audio8.samples[0], Int16::from_int(-32768))
  assert_eq(audio8.samples[1], Int16::from_int(32512))
  let audio24 = @moon_audio.decode(
    make_wav_test(1, 24, b"\x00\x00\x80\xff\xff\x7f", false),
  )
  assert_eq(audio24.samples[0], Int16::from_int(-32768))
  assert_eq(audio24.samples[1], Int16::from_int(32767))
  let audio32 = @moon_audio.decode(
    make_wav_test(1, 32, b"\x00\x00\x00\x80\xff\xff\xff\x7f", false),
  )
  assert_eq(audio32.samples[0], Int16::from_int(-32768))
  assert_eq(audio32.samples[1], Int16::from_int(32767))
}

///|
test "decode IEEE float WAV" {
  let audio = @moon_audio.decode(
    make_wav_test(3, 32, b"\x00\x00\x80\xbf\x00\x00\x00\x3f", false),
  )
  assert_eq(audio.samples[0], Int16::from_int(-32767))
  assert_eq(audio.samples[1], Int16::from_int(16383))
}

///|
test "resample and downmix" {
  let audio : @moon_audio.Pcm = {
    rate: 2,
    channels: 2,
    samples: [
      Int16::from_int(0),
      Int16::from_int(1000),
      Int16::from_int(10000),
      Int16::from_int(-1000),
    ],
  }
  let converted = audio.resample(4, 1)
  assert_eq(converted.rate, 4)
  assert_eq(converted.channels, 1)
  assert_eq(converted.frames(), 4)
  assert_eq(converted.samples[0], Int16::from_int(500))
  assert_eq(converted.samples[1], Int16::from_int(2500))
  @test.assert_raise(() => audio.resample(0, 1))
}

///|
test "reject malformed input" {
  @test.assert_raise(() => @moon_audio.decode(b"RIFF"))
  @test.assert_raise(() => @moon_audio.decode(b"not audio"))
  let truncated = make_wav_test(1, 16, b"\x00\x00", false)
  @test.assert_raise(() => {
    @moon_audio.decode(
      Bytes::from_array(truncated[:truncated.length() - 1].to_array()),
    )
  })
}
