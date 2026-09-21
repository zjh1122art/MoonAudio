///|
fn main {
  let args = @env.args()
  if args.length() >= 2 && args[1] == "--self-test" {
    let source = demo_tone(48000, 1, 0.25)
    if args.length() >= 3 {
      try {
        @fs.write_bytes_to_file(args[2], source.to_wav())
        println("wrote self-test WAV: " + args[2])
      } catch {
        @fs.IOError::IOError(message) => println("error: " + message)
      }
    } else {
      println("generated " + source.frames().to_string() + " frames")
      println(source.info("pcm_s16"))
    }
  } else if args.length() >= 3 {
    try {
      let input = @fs.read_file_to_bytes(args[1])
      let audio = @moon_audio.decode(input)
      @fs.write_bytes_to_file(args[2], audio.to_wav())
      println("decoded " + args[1] + " -> " + args[2])
      println(audio.info("pcm_s16"))
    } catch {
      @fs.IOError::IOError(message) => println("file error: " + message)
      _ => println("decode error")
    }
  } else {
    println("usage: moon run cmd/main -- input.ogg output.wav")
    println("       moon run cmd/main -- --self-test [output.wav]")
  }
}

///|
fn demo_tone(rate : Int, channels : Int, seconds : Double) -> @moon_audio.Pcm {
  let frames = (rate.to_double() * seconds).to_int()
  let samples = Array::make(frames * channels, Int16::from_int(0))
  let pi = 3.141592653589793
  for frame = 0; frame < frames; frame = frame + 1 {
    let value = @math.sin(
      frame.to_double() / rate.to_double() * 440.0 * 2.0 * pi,
    )
    let sample = Int16::from_int((value * 16000.0).to_int())
    for channel = 0; channel < channels; channel = channel + 1 {
      samples[frame * channels + channel] = sample
    }
  }
  { rate, channels, samples, }
}
