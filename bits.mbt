///|
struct BitReader {
  data : Bytes
  mut bit : Int
}

///|
fn BitReader::new(data : Bytes) -> BitReader {
  { data, bit: 0, }
}

///|
fn BitReader::read(self : BitReader, count : Int) -> Int raise AudioError {
  if count < 0 || count > 24 || self.bit + count > self.data.length() * 8 {
    raise Truncated
  }
  let mut value = 0
  for i = 0; i < count; i = i + 1 {
    let byte = self.data[self.bit / 8].to_int()
    let bit = (byte >> (self.bit % 8)) & 1
    value = value | (bit << i)
    self.bit = self.bit + 1
  }
  value
}

///|
fn BitReader::read1(self : BitReader) -> Int raise AudioError {
  self.read(1)
}

///|
fn BitReader::align(self : BitReader) -> Unit {
  self.bit = (self.bit + 7) & 0xfffffff8
}

///|
fn ilog(value : Int) -> Int {
  let mut n = 0
  let mut x = value
  while x > 0 {
    n = n + 1
    x = x >> 1
  }
  n
}

///|
fn lookup1_values(entries : Int, dimensions : Int) -> Int {
  let value = entries.to_double().pow(1.0 / dimensions.to_double()).to_int()
  let mut result = if value < 1 { 1 } else { value }
  while (result + 1).to_double().pow(dimensions.to_double()) <=
        entries.to_double() {
    result = result + 1
  }
  while result.to_double().pow(dimensions.to_double()) > entries.to_double() {
    result = result - 1
  }
  result
}

///|
struct HuffmanCode {
  code : Int
  length : Int
  value : Int
}

///|
struct Huffman {
  codes : Array[HuffmanCode]
  max_length : Int
}

///|
fn reverse_bits(code : Int, length : Int) -> Int {
  let mut code = code
  let mut result = 0
  for i = 0; i < length; i = i + 1 {
    result = (result << 1) | (code & 1)
    code = code >> 1
  }
  result
}

///|
fn Huffman::from_lengths(lengths : Array[Int]) -> Huffman raise AudioError {
  let mut max_length = 0
  for length in lengths {
    if length < 0 || length > 24 {
      fail("invalid Vorbis codeword length")
    }
    if length > max_length {
      max_length = length
    }
  }
  let count = Array::make(max_length + 1, 0)
  for length in lengths {
    if length > 0 {
      count[length] = count[length] + 1
    }
  }
  let next = Array::make(max_length + 1, 0)
  let mut code = 0
  for length = 1; length <= max_length; length = length + 1 {
    code = (code + count[length - 1]) << 1
    next[length] = code
  }
  let codes = Array::make(lengths.length(), { code: 0, length: 0, value: 0, })
  for i = 0; i < lengths.length(); i = i + 1 {
    let length = lengths[i]
    if length > 0 {
      codes[i] = { code: reverse_bits(next[length], length), length, value: i, }
      next[length] = next[length] + 1
    }
  }
  { codes, max_length, }
}

///|
fn Huffman::read(self : Huffman, bits : BitReader) -> Int raise AudioError {
  let mut code = 0
  for length = 1; length <= self.max_length; length = length + 1 {
    code = code | (bits.read1() << (length - 1))
    for entry in self.codes {
      if entry.length == length && entry.code == code {
        return entry.value
      }
    }
  }
  fail("invalid Vorbis Huffman code")
}
