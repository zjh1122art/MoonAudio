///|
pub(all) struct Pcm {
  rate : Int
  channels : Int
  samples : Array[Int16]
} derive(Show)

///|
pub(all) struct AudioInfo {
  rate : Int
  channels : Int
  frames : Int
  format : String
} derive(Show)

///|
pub suberror AudioError {
  InvalidInput(String)
  Unsupported(String)
  Truncated
} derive(Show, Eq)

///|
fn[T] fail(message : String) -> T raise AudioError {
  raise InvalidInput(message)
}

///|
pub fn Pcm::frames(self : Pcm) -> Int {
  self.samples.length() / self.channels
}

///|
pub fn Pcm::info(self : Pcm, format : String) -> AudioInfo {
  { rate: self.rate, channels: self.channels, frames: self.frames(), format, }
}

///|
pub fn Pcm::resample(
  self : Pcm,
  target_rate : Int,
  target_channels : Int,
) -> Pcm raise AudioError {
  if target_rate <= 0 || target_channels <= 0 {
    fail("resample target must be positive")
  }
  let source_frames = self.frames()
  let target_frames = if source_frames == 0 {
    0
  } else {
    (source_frames * target_rate + self.rate / 2) / self.rate
  }
  let output = Array::make(target_frames * target_channels, Int16::from_int(0))
  for frame = 0; frame < target_frames; frame = frame + 1 {
    let position = if target_frames <= 1 {
      0.0
    } else {
      frame.to_double() * self.rate.to_double() / target_rate.to_double()
    }
    let left = position.to_int()
    let fraction = position - left.to_double()
    for channel = 0; channel < target_channels; channel = channel + 1 {
      let source_channel = if self.channels == 1 {
        0
      } else if target_channels == 1 {
        -1
      } else {
        channel % self.channels
      }
      let sample = if source_channel >= 0 {
        self.interpolate(left, fraction, source_channel)
      } else {
        let mut total = 0
        for c = 0; c < self.channels; c = c + 1 {
          total = total + self.interpolate(left, fraction, c).to_int()
        }
        Int16::from_int(total / self.channels)
      }
      output[frame * target_channels + channel] = sample
    }
  }
  { rate: target_rate, channels: target_channels, samples: output, }
}

///|
fn Pcm::interpolate(
  self : Pcm,
  frame : Int,
  fraction : Double,
  channel : Int,
) -> Int16 {
  let a = self.sample_at(frame, channel).to_int()
  let b = self.sample_at(frame + 1, channel).to_int()
  clamp_i16(
    (a.to_double() * (1.0 - fraction) + b.to_double() * fraction).to_int(),
  )
}

///|
fn Pcm::sample_at(self : Pcm, frame : Int, channel : Int) -> Int16 {
  if frame < 0 || frame >= self.frames() {
    0
  } else {
    self.samples[frame * self.channels + channel]
  }
}

///|
fn clamp_i16(value : Int) -> Int16 {
  if value < -32768 {
    -32768
  } else if value > 32767 {
    32767
  } else {
    value.to_int16()
  }
}

///|
pub fn Pcm::to_wav(self : Pcm) -> Bytes {
  WavWriter::encode(self)
}

///|
pub fn decode(input : Bytes) -> Pcm raise AudioError {
  if input.length() >= 4 &&
    input[0] == b'R' &&
    input[1] == b'I' &&
    input[2] == b'F' &&
    input[3] == b'F' {
    WavReader::decode(input)
  } else if input.length() >= 4 &&
    input[0] == b'O' &&
    input[1] == b'g' &&
    input[2] == b'g' &&
    input[3] == b'S' {
    VorbisDecoder::decode(input)
  } else {
    fail("unknown audio container")
  }
}
