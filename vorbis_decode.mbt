///|
struct VorbisDecoder {}

///|
fn db_to_linear(value : Int) -> Double {
  let x = if value < 0 { 0.0 } else { value.to_double() / 255.0 }
  @math.pow(10.0, -x * 140.0 / 255.0 / 20.0)
}

///|
fn codebook_scalar(
  book : VorbisCodebook,
  bits : BitReader,
) -> Int raise AudioError {
  book.huffman.read(bits)
}

///|
fn codebook_vector(
  book : VorbisCodebook,
  bits : BitReader,
) -> Array[Double] raise AudioError {
  let entry = codebook_scalar(book, bits)
  let vector = Array::make(book.dimensions, 0.0)
  if book.lookup_type == 0 {
    return vector
  }
  if book.lookup_type == 1 {
    let mut index = entry
    let count = lookup1_values(book.entries, book.dimensions)
    let mut last = 0.0
    for i = 0; i < book.dimensions; i = i + 1 {
      let value = book.multiplicands[index % count]
      index = index / count
      let decoded = book.minimum + value * book.delta
      vector[i] = if book.sequence { last + decoded } else { decoded }
      last = vector[i]
    }
  } else {
    for i = 0; i < book.dimensions; i = i + 1 {
      let decoded = book.minimum +
        book.multiplicands[entry * book.dimensions + i] * book.delta
      vector[i] = decoded
    }
  }
  vector
}

///|
fn floor_decode(
  floor : VorbisFloor,
  setup : VorbisSetup,
  bits : BitReader,
  n2 : Int,
) -> Array[Double]? raise AudioError {
  if bits.read1() == 0 {
    return None
  }
  if floor.kind == 0 {
    return Some(floor0_decode(floor, setup, bits, n2))
  }
  let values = Array::make(floor.x_list.length(), 0)
  let range = if floor.multiplier == 1 {
    256
  } else if floor.multiplier == 2 {
    128
  } else if floor.multiplier == 3 {
    86
  } else {
    64
  }
  values[0] = bits.read(ilog(range - 1))
  values[1] = bits.read(ilog(range - 1))
  let mut offset = 2
  for p in 0..<floor.partitions.length() {
    let class_id = floor.partition_class[p]
    let dimensions = floor.class_dimensions[class_id]
    let subclasses = floor.class_subclasses[class_id]
    let master = floor.class_masterbooks[class_id]
    let selector = if subclasses > 0 {
      codebook_scalar(setup.codebooks[master], bits)
    } else {
      0
    }
    for j = 0; j < dimensions && offset < values.length(); j = j + 1 {
      let selector_index = if subclasses > 0 {
        (selector >> (j * subclasses)) & ((1 << subclasses) - 1)
      } else {
        0
      }
      let book = floor.subclass_books[class_id * 16 + selector_index]
      values[offset] = if book >= 0 {
        codebook_scalar(setup.codebooks[book], bits)
      } else {
        0
      }
      offset = offset + 1
    }
  }
  let curve = Array::make(n2, 0.0)
  let max_y = 1 << 8
  for i = 0; i < values.length(); i = i + 1 {
    let x = floor.x_list[i] * n2 / max_y
    let y = values[i] * floor.multiplier
    let next_x = if i + 1 < values.length() {
      floor.x_list[i + 1] * n2 / max_y
    } else {
      n2
    }
    let next_y = if i + 1 < values.length() {
      values[i + 1] * floor.multiplier
    } else {
      y
    }
    for bin = x; bin < next_x && bin < n2; bin = bin + 1 {
      let t = if next_x == x {
        0.0
      } else {
        (bin - x).to_double() / (next_x - x).to_double()
      }
      let y_at = (y.to_double() * (1.0 - t) + next_y.to_double() * t).to_int()
      curve[bin] = db_to_linear(y_at)
    }
  }
  Some(curve)
}

///|
fn floor0_decode(
  floor : VorbisFloor,
  setup : VorbisSetup,
  bits : BitReader,
  n2 : Int,
) -> Array[Double] {
  ignore(floor)
  ignore(setup)
  ignore(bits)
  Array::make(n2, 0.0)
}

///|
fn residue_decode(
  residue : VorbisResidue,
  setup : VorbisSetup,
  bits : BitReader,
  spectra : Array[Array[Double]],
  channels : Int,
  n2 : Int,
) -> Unit raise AudioError {
  let begin = if residue.begin < n2 { residue.begin } else { n2 }
  let end = if residue.end < n2 { residue.end } else { n2 }
  if end <= begin {
    return
  }
  let partition_size = residue.partition_size
  let partitions = (end - begin) / partition_size
  let active = if residue.kind == 2 { 1 } else { channels }
  for pass = 0; pass < 8; pass = pass + 1 {
    for partition = 0; partition < partitions; partition = partition + 1 {
      let offset = begin + partition * partition_size
      let class_value = if pass == 0 {
        codebook_scalar(setup.codebooks[residue.classbook], bits) %
        residue.classifications
      } else {
        0
      }
      let book_id = residue.books[class_value * 8 + pass]
      if book_id >= 0 {
        let book = setup.codebooks[book_id]
        let step = if residue.kind == 2 {
          book.dimensions
        } else {
          partition_size / book.dimensions
        }
        let count = partition_size / step
        for k = 0; k < count; k = k + 1 {
          let vector = codebook_vector(book, bits)
          for d = 0; d < book.dimensions; d = d + 1 {
            let index = offset + k * book.dimensions + d
            if index < end {
              if residue.kind == 2 {
                let channel = index % channels
                let bin = index / channels
                spectra[channel][bin] = spectra[channel][bin] + vector[d]
              } else {
                for channel = 0; channel < active; channel = channel + 1 {
                  spectra[channel][index] = spectra[channel][index] + vector[d]
                }
              }
            }
          }
        }
      }
    }
  }
}

///|
fn imdct(input : Array[Double], n : Int) -> Array[Double] {
  let output = Array::make(n, 0.0)
  let half = n / 2
  let pi = 3.141592653589793
  for k = 0; k < n; k = k + 1 {
    let mut sum = 0.0
    for i = 0; i < half; i = i + 1 {
      let angle = pi /
        half.to_double() *
        (i.to_double() + 0.5 + half.to_double() / 2.0) *
        (k.to_double() + 0.5)
      sum = sum + input[i] * @math.cos(angle)
    }
    output[k] = sum / half.to_double()
  }
  output
}

///|
fn vorbis_window(n : Int) -> Array[Double] {
  let window = Array::make(n, 0.0)
  let pi = 3.141592653589793
  for i = 0; i < n; i = i + 1 {
    let x = (i.to_double() + 0.5) / n.to_double()
    window[i] = @math.sin(pi * 0.5 * @math.pow(@math.sin(pi * x), 2.0))
  }
  window
}

///|
fn decode_audio_packet(
  packet : Bytes,
  setup : VorbisSetup,
) -> Array[Array[Double]]? raise AudioError {
  let bits = BitReader::new(Bytes::from_array(packet[1:].to_array()))
  let mode_id = bits.read(ilog(setup.modes.length() - 1))
  if mode_id >= setup.modes.length() {
    fail("invalid Vorbis mode number")
  }
  let mode = setup.modes[mode_id]
  let n = if mode.blockflag { setup.block_long } else { setup.block_short }
  let n2 = n / 2
  let mapping = setup.mappings[mode.mapping]
  let spectra = Array::make(setup.channels, Array::make(n2, 0.0))
  let floors = Array::make(setup.channels, None)
  for channel = 0; channel < setup.channels; channel = channel + 1 {
    let submap = mapping.mux[channel]
    floors[channel] = floor_decode(
      setup.floors[mapping.floors[submap]],
      setup,
      bits,
      n2,
    )
  }
  for submap = 0; submap < mapping.submaps; submap = submap + 1 {
    let residue = setup.residues[mapping.residues[submap]]
    residue_decode(residue, setup, bits, spectra, setup.channels, n2)
  }
  for channel = 0; channel < setup.channels; channel = channel + 1 {
    match floors[channel] {
      Some(curve) =>
        for i = 0; i < n2; i = i + 1 {
          spectra[channel][i] = spectra[channel][i] * curve[i]
        }
      None =>
        for i = 0; i < n2; i = i + 1 {
          spectra[channel][i] = 0.0
        }
    }
  }
  for i = 0; i < mapping.coupling_steps; i = i + 1 {
    let magnitude = mapping.magnitude[i]
    let angle = mapping.angle[i]
    for bin = 0; bin < n2; bin = bin + 1 {
      let m = spectra[magnitude][bin]
      let a = spectra[angle][bin]
      if m > 0.0 {
        spectra[magnitude][bin] = if a > 0.0 { m } else { m + a }
        spectra[angle][bin] = if a > 0.0 { m - a } else { a }
      } else {
        spectra[magnitude][bin] = if a > 0.0 { m + a } else { m }
        spectra[angle][bin] = if a > 0.0 { m - a } else { a }
      }
    }
  }
  let output = Array::make(setup.channels, Array::make(n, 0.0))
  let window = vorbis_window(n)
  for channel = 0; channel < setup.channels; channel = channel + 1 {
    let block = imdct(spectra[channel], n)
    for i = 0; i < n; i = i + 1 {
      output[channel][i] = block[i] * window[i]
    }
  }
  Some(output)
}

///|
fn VorbisDecoder::decode(data : Bytes) -> Pcm raise AudioError {
  let ogg = OggReader::read(data)
  let setup = VorbisSetup::parse(ogg.packets)
  let output = Array::new()
  let start_packet = 3
  for i = start_packet; i < ogg.packets.length(); i = i + 1 {
    let packet = ogg.packets[i].data
    if packet.length() == 0 || (packet[0].to_int() & 1) != 0 {
      continue
    }
    match decode_audio_packet(packet, setup) {
      Some(block) =>
        for frame = 0; frame < block[0].length(); frame = frame + 1 {
          for channel = 0; channel < setup.channels; channel = channel + 1 {
            output.push(clamp_i16((block[channel][frame] * 32767.0).to_int()))
          }
        }
      None => ()
    }
  }
  let samples = if output.length() > 0 { output } else { Array::make(0, 0) }
  { rate: setup.rate, channels: setup.channels, samples, }
}
