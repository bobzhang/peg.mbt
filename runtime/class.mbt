///|
/// A compiled character class, equivalent to the `/^[...]/i?` regexps PEG.js
/// generates. It tests a single UTF-16 code unit.
pub struct ClassMatcher {
  /// Sorted, merged, inclusive code-unit ranges.
  priv ranges : Array[(Int, Int)]
  /// Membership of the ASCII code units, one bit per unit.
  priv ascii : FixedArray[UInt64]
  priv inverted : Bool
  priv ignore_case : Bool
}

///|
fn part_code(s : String) -> Int {
  if s.length() == 0 {
    -1
  } else {
    s.code_unit_at(0).to_int()
  }
}

///|
pub fn ClassMatcher::new(
  parts : ArrayView[ClassPart],
  inverted~ : Bool,
  ignore_case~ : Bool,
) -> ClassMatcher {
  let raw = parts.map(part => {
    match part {
      Char(c) => {
        let x = part_code(c)
        (x, x)
      }
      Range(a, b) => (part_code(a), part_code(b))
    }
  })
  raw.sort_by_key(r => r.0)
  let ranges : Array[(Int, Int)] = []
  for r in raw {
    if r.0 > r.1 {
      continue
    }
    match ranges.last() {
      Some(last) if r.0 <= last.1 + 1 =>
        if r.1 > last.1 {
          ranges[ranges.length() - 1] = (last.0, r.1)
        }
      _ => ranges.push(r)
    }
  }
  let ascii : FixedArray[UInt64] = FixedArray::make(2, 0)
  for r in ranges {
    let start = if r.0 < 0 { 0 } else { r.0 }
    for c = start; c <= r.1 && c < 128; c = c + 1 {
      ascii[c >> 6] = ascii[c >> 6] | (1UL << (c & 63))
    }
  }
  { ranges, ascii, inverted, ignore_case, }
}

///|
fn ClassMatcher::contains(self : ClassMatcher, c : Int) -> Bool {
  if c >= 0 && c < 128 {
    return ((self.ascii[c >> 6] >> (c & 63)) & 1UL) != 0UL
  }
  let ranges = self.ranges
  for lo = 0, hi = ranges.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    let r = ranges[mid]
    if c < r.0 {
      continue lo, mid
    } else if c > r.1 {
      continue mid + 1, hi
    } else {
      return true
    }
  } nobreak {
    false
  }
}

///|
/// Tests the code unit `c`.
pub fn ClassMatcher::matches(self : ClassMatcher, c : Int) -> Bool {
  let found = if self.ignore_case {
    js_case_variants_any(c, d => self.contains(d))
  } else {
    self.contains(c)
  }
  found != self.inverted
}

///|
/// Tests the code unit at `pos` of `input`; fails at end of input (like
/// testing a regexp against `input.charAt(pos)`, which is then `""`).
pub fn ClassMatcher::matches_at(
  self : ClassMatcher,
  input : String,
  pos : Int,
) -> Bool {
  pos < input.length() && self.matches(input.code_unit_at(pos).to_int())
}
