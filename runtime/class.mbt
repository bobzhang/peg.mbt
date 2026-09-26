///|
/// A compiled character class, equivalent to the `/^[...]/i?` regexps PEG.js
/// generates. It tests a single UTF-16 code unit.
pub struct ClassMatcher {
  priv ranges : Array[(Int, Int)]
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
  let ranges = parts.map(part => {
    match part {
      Char(c) => {
        let x = part_code(c)
        (x, x)
      }
      Range(a, b) => (part_code(a), part_code(b))
    }
  })
  { ranges, inverted, ignore_case, }
}

///|
fn ClassMatcher::contains(self : ClassMatcher, c : Int) -> Bool {
  for r in self.ranges {
    if c >= r.0 && c <= r.1 {
      return true
    }
  }
  false
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
