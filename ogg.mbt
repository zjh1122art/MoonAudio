///|
struct OggPacket {
  data : Bytes
  granule : Int64
  sequence : Int
  bos : Bool
  eos : Bool
}

///|
struct OggReader {
  packets : Array[OggPacket]
}

///|
fn u32le(data : Bytes, at : Int) -> Int raise AudioError {
  if at < 0 || at + 4 > data.length() {
    raise Truncated
  }
  data[at].to_int() |
  (data[at + 1].to_int() << 8) |
  (data[at + 2].to_int() << 16) |
  (data[at + 3].to_int() << 24)
}

///|
fn u64le(data : Bytes, at : Int) -> Int64 raise AudioError {
  let lo = u32le(data, at).to_int64() & 0xffffffffL
  let hi = u32le(data, at + 4).to_int64() & 0xffffffffL
  lo | (hi << 32)
}

///|
fn crc32_ogg(data : Bytes) -> UInt {
  let mut crc = 0xffffffffU
  for byte in data {
    crc = crc ^ (byte.to_int().to_uint() << 24)
    for i = 0; i < 8; i = i + 1 {
      crc = if crc >> 31 != 0U { (crc << 1) ^ 0x04c11db7U } else { crc << 1 }
    }
  }
  crc
}

///|
fn OggReader::read(data : Bytes) -> OggReader raise AudioError {
  let packets = Array::new()
  let current = Array::new()
  let mut at = 0
  let mut expected_sequence = 0
  let mut stream_serial = -1
  while at < data.length() {
    if at + 27 > data.length() || !tag(data, at, b'O', b'g', b'g', b'S') {
      fail("invalid Ogg page")
    }
    let version = data[at + 4].to_int()
    if version != 0 {
      raise Unsupported("Ogg bitstream version")
    }
    let header_type = data[at + 5].to_int()
    let granule = u64le(data, at + 6)
    let serial = u32le(data, at + 14)
    let sequence = u32le(data, at + 18)
    let checksum = u32le(data, at + 22).reinterpret_as_uint()
    let segments = data[at + 26].to_int()
    if at + 27 + segments > data.length() {
      raise Truncated
    }
    let mut page_size = 27 + segments
    for i = 0; i < segments; i = i + 1 {
      page_size = page_size + data[at + 27 + i].to_int()
    }
    if at + page_size > data.length() {
      raise Truncated
    }
    let page_array = data[at:at + page_size].to_array()
    for i = 22; i < 26; i = i + 1 {
      page_array[i] = (0).to_byte()
    }
    let page = Bytes::from_array(page_array)
    if crc32_ogg(page) != checksum {
      fail("Ogg page CRC mismatch")
    }
    if stream_serial < 0 {
      stream_serial = serial
    } else if serial != stream_serial {
      raise Unsupported("multiple Ogg logical streams")
    }
    if sequence != expected_sequence {
      fail("Ogg page sequence is not contiguous")
    }
    expected_sequence = expected_sequence + 1
    let mut offset = at + 27 + segments
    let continued = (header_type & 1) != 0
    if continued && current.length() == 0 {
      fail("Ogg continued packet flag mismatch")
    }
    if !continued && current.length() > 0 {
      fail("Ogg continued packet flag mismatch")
    }
    for i = 0; i < segments; i = i + 1 {
      let length = data[at + 27 + i].to_int()
      for j = 0; j < length; j = j + 1 {
        current.push(data[offset + j])
      }
      offset = offset + length
      if length < 255 {
        packets.push({
          data: Bytes::from_array(current),
          granule,
          sequence,
          bos: (header_type & 2) != 0,
          eos: (header_type & 4) != 0,
        })
        current.clear()
      }
    }
    at = at + page_size
  }
  if current.length() > 0 {
    fail("truncated Ogg packet")
  }
  { packets, }
}

///|
fn[T] ignore(_value : T) -> Unit {

}
