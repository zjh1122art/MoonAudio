///|
struct WavReader {}

///|
fn le16(data : Bytes, at : Int) -> Int raise AudioError {
  if at < 0 || at + 2 > data.length() {
    raise Truncated
  }
  data[at].to_int() | (data[at + 1].to_int() << 8)
}

///|
fn le32(data : Bytes, at : Int) -> Int raise AudioError {
  if at < 0 || at + 4 > data.length() {
    raise Truncated
  }
  le16(data, at) | (le16(data, at + 2) << 16)
}

///|
fn tag(data : Bytes, at : Int, a : Byte, b : Byte, c : Byte, d : Byte) -> Bool {
  at + 4 <= data.length() &&
  data[at] == a &&
  data[at + 1] == b &&
  data[at + 2] == c &&
  data[at + 3] == d
}

///|
fn WavReader::decode(data : Bytes) -> Pcm raise AudioError {
  if data.length() < 12 ||
    !tag(data, 0, b'R', b'I', b'F', b'F') ||
    !tag(data, 8, b'W', b'A', b'V', b'E') {
    fail("invalid RIFF/WAVE header")
  }
  let mut at = 12
  let mut format = 0
  let mut channels = 0
  let mut rate = 0
  let mut bits = 0
  let mut float_format = false
  let mut data_start = -1
  let mut data_size = 0
  while at + 8 <= data.length() {
    let size = le32(data, at + 4)
    if size < 0 || size > data.length() - at - 8 {
      raise Truncated
    }
    let chunk_end = at + 8 + size
    if chunk_end + size % 2 > data.length() {
      raise Truncated
    }
    if tag(data, at, b'f', b'm', b't', b' ') {
      if size < 16 {
        raise Truncated
      }
      format = le16(data, at + 8)
      channels = le16(data, at + 10)
      rate = le32(data, at + 12)
      bits = le16(data, at + 22)
      float_format = format == 3
      if channels <= 0 || rate <= 0 {
        fail("invalid WAV format")
      }
    } else if tag(data, at, b'd', b'a', b't', b'a') {
      data_start = at + 8
      data_size = size
    }
    at = chunk_end + size % 2
  }
  if at != data.length() {
    raise Truncated
  }
  if data_start < 0 || channels <= 0 || rate <= 0 {
    fail("WAV is missing fmt or data chunk")
  }
  if format != 1 && format != 3 {
    raise Unsupported("WAV compression format")
  }
  if bits != 8 && bits != 16 && bits != 24 && bits != 32 {
    raise Unsupported("WAV bit depth")
  }
  let bytes_per_sample = (bits + 7) / 8
  let block = bytes_per_sample * channels
  let frames = data_size / block
  let samples = Array::make(frames * channels, Int16::from_int(0))
  for frame = 0; frame < frames; frame = frame + 1 {
    for channel = 0; channel < channels; channel = channel + 1 {
      let offset = data_start + frame * block + channel * bytes_per_sample
      let sample = if float_format {
        float_to_i16(data, offset, bits)
      } else {
        pcm_to_i16(data, offset, bits)
      }
      samples[frame * channels + channel] = sample
    }
  }
  { rate, channels, samples, }
}

///|
fn le24(data : Bytes, at : Int) -> Int raise AudioError {
  if at < 0 || at + 3 > data.length() {
    raise Truncated
  }
  let raw = data[at].to_int() |
    (data[at + 1].to_int() << 8) |
    (data[at + 2].to_int() << 16)
  if (raw & 0x800000) != 0 {
    raw | (-1 << 24)
  } else {
    raw
  }
}

///|
fn pcm_to_i16(data : Bytes, at : Int, bits : Int) -> Int16 raise AudioError {
  if bits == 8 {
    ((data[at].to_int() - 128) << 8).to_int16()
  } else if bits == 16 {
    le16(data, at).to_int16()
  } else if bits == 24 {
    let raw = le24(data, at)
    (raw >> 8).to_int16()
  } else {
    (le32(data, at) >> 16).to_int16()
  }
}

///|
fn float_to_i16(data : Bytes, at : Int, bits : Int) -> Int16 raise AudioError {
  if bits != 32 {
    raise Unsupported("WAV IEEE float must be 32-bit")
  }
  // IEEE-754 conversion is implemented with integer fields so the decoder is
  // deterministic on every MoonBit backend.
  let raw = le32(data, at)
  let sign = if raw < 0 { -1.0 } else { 1.0 }
  let exponent = (raw >> 23) & 255
  let mantissa = raw & 0x7fffff
  let value = if exponent == 0 {
    sign * (mantissa.to_double() / 8388608.0) * 2.0.pow(-126.0)
  } else if exponent == 255 {
    0.0
  } else {
    sign *
    (1.0 + mantissa.to_double() / 8388608.0) *
    2.0.pow((exponent - 127).to_double())
  }
  clamp_i16((value * 32767.0).to_int())
}

///|
struct WavWriter {}

///|
fn WavWriter::encode(audio : Pcm) -> Bytes {
  let bytes = Array::make(44 + audio.samples.length() * 2, (0).to_byte())
  put_tag(bytes, 0, "RIFF")
  put_u32(bytes, 4, 36 + audio.samples.length() * 2)
  put_tag(bytes, 8, "WAVE")
  put_tag(bytes, 12, "fmt ")
  put_u32(bytes, 16, 16)
  put_u16(bytes, 20, 1)
  put_u16(bytes, 22, audio.channels)
  put_u32(bytes, 24, audio.rate)
  put_u32(bytes, 28, audio.rate * audio.channels * 2)
  put_u16(bytes, 32, audio.channels * 2)
  put_u16(bytes, 34, 16)
  put_tag(bytes, 36, "data")
  put_u32(bytes, 40, audio.samples.length() * 2)
  for i = 0; i < audio.samples.length(); i = i + 1 {
    put_u16(bytes, 44 + i * 2, audio.samples[i].to_int())
  }
  Bytes::from_array(bytes)
}

///|
fn put_tag(out : Array[Byte], at : Int, text : String) -> Unit {
  for i = 0; i < 4; i = i + 1 {
    out[at + i] = text[i].to_byte()
  }
}

///|
fn put_u16(out : Array[Byte], at : Int, value : Int) -> Unit {
  out[at] = (value & 255).to_byte()
  out[at + 1] = ((value >> 8) & 255).to_byte()
}

///|
fn put_u32(out : Array[Byte], at : Int, value : Int) -> Unit {
  put_u16(out, at, value)
  put_u16(out, at + 2, value >> 16)
}
