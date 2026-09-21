///|
struct VorbisCodebook {
  dimensions : Int
  entries : Int
  huffman : Huffman
  lookup_type : Int
  multiplicands : Array[Double]
  minimum : Double
  delta : Double
  sequence : Bool
}

///|
struct VorbisFloor {
  kind : Int
  partitions : Array[Int]
  partition_class : Array[Int]
  class_dimensions : Array[Int]
  class_subclasses : Array[Int]
  class_masterbooks : Array[Int]
  subclass_books : Array[Int]
  multiplier : Int
  x_list : Array[Int]
  books : Array[Int]
  order : Int
  rate : Int
  bark : Int
  amplitude_bits : Int
}

///|
struct VorbisResidue {
  kind : Int
  begin : Int
  end : Int
  partition_size : Int
  classifications : Int
  classbook : Int
  cascade : Array[Int]
  books : Array[Int]
}

///|
struct VorbisMapping {
  submaps : Int
  coupling_steps : Int
  magnitude : Array[Int]
  angle : Array[Int]
  mux : Array[Int]
  floors : Array[Int]
  residues : Array[Int]
}

///|
struct VorbisMode {
  blockflag : Bool
  windowtype : Int
  transformtype : Int
  mapping : Int
}

///|
struct VorbisSetup {
  channels : Int
  rate : Int
  block_short : Int
  block_long : Int
  codebooks : Array[VorbisCodebook]
  floors : Array[VorbisFloor]
  residues : Array[VorbisResidue]
  mappings : Array[VorbisMapping]
  modes : Array[VorbisMode]
}

///|
fn VorbisSetup::parse(
  packets : Array[OggPacket],
) -> VorbisSetup raise AudioError {
  if packets.length() < 3 {
    fail("Ogg stream has no Vorbis headers")
  }
  let id = packets[0].data
  if id.length() < 30 || id[0] != 1 || !tag(id, 1, b'v', b'o', b'r', b'b') {
    fail("missing Vorbis identification header")
  }
  let channels = id[11].to_int()
  let rate = u32le(id, 12)
  let block = id[28].to_int()
  let block_short = 1 << (block & 15)
  let block_long = 1 << ((block >> 4) & 15)
  if channels <= 0 ||
    channels > 8 ||
    rate <= 0 ||
    block_short < 64 ||
    block_long < block_short {
    fail("invalid Vorbis identification header")
  }
  let comment = packets[1].data
  if comment.length() < 7 ||
    comment[0] != 3 ||
    !tag(comment, 1, b'v', b'o', b'r', b'b') {
    fail("missing Vorbis comment header")
  }
  let setup = packets[2].data
  if setup.length() < 7 ||
    setup[0] != 5 ||
    !tag(setup, 1, b'v', b'o', b'r', b'b') {
    fail("missing Vorbis setup header")
  }
  let bits = BitReader::new(Bytes::from_array(setup[7:].to_array()))
  parse_setup(bits, channels, rate, block_short, block_long)
}

///|
fn parse_setup(
  bits : BitReader,
  channels : Int,
  rate : Int,
  block_short : Int,
  block_long : Int,
) -> VorbisSetup raise AudioError {
  let codebooks = Array::new()
  let codebook_count = bits.read(8) + 1
  for i = 0; i < codebook_count; i = i + 1 {
    codebooks.push(parse_codebook(bits))
  }
  let time_count = bits.read(6) + 1
  for i = 0; i < time_count; i = i + 1 {
    if bits.read(16) != 0 {
      fail("unsupported Vorbis time transform")
    }
  }
  let floors = Array::new()
  let floor_count = bits.read(6) + 1
  for i = 0; i < floor_count; i = i + 1 {
    floors.push(parse_floor(bits))
  }
  let residues = Array::new()
  let residue_count = bits.read(6) + 1
  for i = 0; i < residue_count; i = i + 1 {
    residues.push(parse_residue(bits))
  }
  let mappings = Array::new()
  let mapping_count = bits.read(6) + 1
  for i = 0; i < mapping_count; i = i + 1 {
    mappings.push(parse_mapping(bits, channels))
  }
  let modes = Array::new()
  let mode_count = bits.read(6) + 1
  for i = 0; i < mode_count; i = i + 1 {
    let blockflag = bits.read1() != 0
    let windowtype = bits.read(16)
    let transformtype = bits.read(16)
    let mapping = bits.read(8)
    if windowtype != 0 || transformtype != 0 || mapping >= mappings.length() {
      fail("invalid Vorbis mode")
    }
    modes.push({ blockflag, windowtype, transformtype, mapping, })
  }
  if bits.read1() != 1 {
    fail("invalid Vorbis setup framing bit")
  }
  {
    channels,
    rate,
    block_short,
    block_long,
    codebooks,
    floors,
    residues,
    mappings,
    modes,
  }
}

///|
fn parse_codebook(bits : BitReader) -> VorbisCodebook raise AudioError {
  if bits.read(24) != 0x564342 {
    fail("invalid Vorbis codebook sync")
  }
  let dimensions = bits.read(16)
  let entries = bits.read(24)
  if dimensions <= 0 || dimensions > 64 || entries <= 0 {
    fail("invalid Vorbis codebook dimensions")
  }
  let lengths = Array::make(entries, 0)
  let ordered = bits.read1() != 0
  if ordered {
    let mut current = 0
    let mut length = bits.read(5) + 1
    while current < entries {
      let count = bits.read(ilog(entries - current))
      for i = 0; i < count; i = i + 1 {
        if current >= entries {
          fail("Vorbis ordered codebook overflow")
        }
        lengths[current] = length
        current = current + 1
      }
      length = length + 1
    }
  } else {
    let sparse = bits.read1() != 0
    for i = 0; i < entries; i = i + 1 {
      if sparse && bits.read1() == 0 {
        lengths[i] = 0
      } else {
        lengths[i] = bits.read(5) + 1
      }
    }
  }
  let huffman = Huffman::from_lengths(lengths)
  let lookup_type = bits.read(4)
  if lookup_type == 0 {
    {
      dimensions,
      entries,
      huffman,
      lookup_type,
      multiplicands: [],
      minimum: 0.0,
      delta: 0.0,
      sequence: false,
    }
  } else if lookup_type == 1 || lookup_type == 2 {
    let minimum = float32_unpack(bits.read(32))
    let delta = float32_unpack(bits.read(32))
    let value_bits = bits.read(4) + 1
    let sequence = bits.read1() != 0
    let count = if lookup_type == 1 {
      lookup1_values(entries, dimensions)
    } else {
      entries * dimensions
    }
    let multiplicands = Array::make(count, 0.0)
    for i = 0; i < count; i = i + 1 {
      multiplicands[i] = bits.read(value_bits).to_double()
    }
    {
      dimensions,
      entries,
      huffman,
      lookup_type,
      multiplicands,
      minimum,
      delta,
      sequence,
    }
  } else {
    fail("unsupported Vorbis codebook lookup type")
  }
}

///|
fn float32_unpack(value : Int) -> Double {
  let mantissa = value & 0x1fffff
  let sign = if value < 0 { -1.0 } else { 1.0 }
  let exponent = (value >> 21) & 0x3ff
  sign * mantissa.to_double() * 2.0.pow((exponent - 788).to_double())
}

///|
fn parse_floor(bits : BitReader) -> VorbisFloor raise AudioError {
  let kind = bits.read(16)
  if kind == 0 {
    let order = bits.read(8)
    let rate = bits.read(16)
    let bark = bits.read(16)
    let amplitude = bits.read(6)
    let book = bits.read(8)

    {
      kind,
      partitions: [],
      partition_class: [],
      class_dimensions: [],
      class_subclasses: [],
      class_masterbooks: [],
      subclass_books: [],
      multiplier: 1,
      x_list: Array::make(order, 0),
      books: [book],
      order,
      rate,
      bark,
      amplitude_bits: amplitude,
    }
  } else if kind == 1 {
    let partitions = bits.read(5)
    let partition_class = Array::make(partitions, 0)
    let mut max_class = 0
    for i = 0; i < partitions; i = i + 1 {
      partition_class[i] = bits.read(4)
      if partition_class[i] > max_class {
        max_class = partition_class[i]
      }
    }
    let class_dimensions = Array::make(max_class + 1, 0)
    let class_subclasses = Array::make(max_class + 1, 0)
    let class_masterbooks = Array::make(max_class + 1, -1)
    let subclass_books = Array::make((max_class + 1) * 16, -1)
    for i = 0; i <= max_class; i = i + 1 {
      class_dimensions[i] = bits.read(3) + 1
      class_subclasses[i] = bits.read(2)
      if class_subclasses[i] > 0 {
        class_masterbooks[i] = bits.read(8)
      }
      let count = 1 << class_subclasses[i]
      for j = 0; j < count; j = j + 1 {
        subclass_books[i * 16 + j] = bits.read(8) - 1
      }
    }
    let multiplier = bits.read(2) + 1
    let rangebits = bits.read(4)
    let x_list = Array::make(2, 0)
    x_list[0] = 0
    x_list[1] = 1 << rangebits
    for i = 0; i < partitions; i = i + 1 {
      let count = class_dimensions[partition_class[i]]
      for i = 0; i < count; i = i + 1 {
        x_list.push(bits.read(rangebits))
      }
    }
    {
      kind,
      partitions: partition_class,
      partition_class,
      class_dimensions,
      class_subclasses,
      class_masterbooks,
      subclass_books,
      multiplier,
      x_list,
      books: [],
      order: 0,
      rate: 0,
      bark: 0,
      amplitude_bits: 0,
    }
  } else {
    fail("unsupported Vorbis floor type")
  }
}

///|
fn parse_residue(bits : BitReader) -> VorbisResidue raise AudioError {
  let kind = bits.read(16)
  if kind > 2 {
    fail("unsupported Vorbis residue type")
  }
  let begin = bits.read(24)
  let end = bits.read(24)
  let partition_size = bits.read(24) + 1
  let classifications = bits.read(6) + 1
  let classbook = bits.read(8)
  let cascade = Array::make(classifications, 0)
  for i = 0; i < classifications; i = i + 1 {
    let low = bits.read(3)
    let high = if bits.read1() != 0 { bits.read(5) } else { 0 }
    cascade[i] = low | (high << 3)
  }
  let books = Array::make(classifications * 8, -1)
  for i = 0; i < classifications; i = i + 1 {
    for j = 0; j < 8; j = j + 1 {
      if (cascade[i] & (1 << j)) != 0 {
        books[i * 8 + j] = bits.read(8)
      }
    }
  }
  {
    kind,
    begin,
    end,
    partition_size,
    classifications,
    classbook,
    cascade,
    books,
  }
}

///|
fn parse_mapping(
  bits : BitReader,
  channels : Int,
) -> VorbisMapping raise AudioError {
  let submaps = if bits.read1() != 0 { bits.read(4) + 1 } else { 1 }
  let coupling_steps = if bits.read1() != 0 { bits.read(8) + 1 } else { 0 }
  let magnitude = Array::make(coupling_steps, 0)
  let angle = Array::make(coupling_steps, 0)
  let channel_bits = ilog(channels - 1)
  for i = 0; i < coupling_steps; i = i + 1 {
    magnitude[i] = bits.read(channel_bits)
    angle[i] = bits.read(channel_bits)
    if magnitude[i] == angle[i] ||
      magnitude[i] >= channels ||
      angle[i] >= channels {
      fail("invalid Vorbis channel coupling")
    }
  }
  if bits.read(2) != 0 {
    fail("invalid Vorbis mapping reserved bits")
  }
  let mux = Array::make(channels, 0)
  if submaps > 1 {
    for i = 0; i < channels; i = i + 1 {
      mux[i] = bits.read(4)
      if mux[i] >= submaps {
        fail("invalid Vorbis mux")
      }
    }
  }
  let floors = Array::make(submaps, 0)
  let residues = Array::make(submaps, 0)
  for i = 0; i < submaps; i = i + 1 {
    ignore(bits.read(8))
    floors[i] = bits.read(8)
    residues[i] = bits.read(8)
  }
  { submaps, coupling_steps, magnitude, angle, mux, floors, residues, }
}
