///|
/// One part of a character class: a single code unit or an inclusive range.
pub(all) enum ClassPart {
  Char(String)
  Range(String, String)
} derive(Eq, Debug)

///|
pub impl ToJson for ClassPart with fn to_json(self) {
  match self {
    Char(c) => c.to_json()
    Range(a, b) => [a.to_json(), b.to_json()]
  }
}

///|
/// Something the parser expected at the failure position.
pub(all) enum Expectation {
  Literal(text~ : String, ignore_case~ : Bool)
  Class(parts~ : Array[ClassPart], inverted~ : Bool, ignore_case~ : Bool)
  Any
  End
  Other(description~ : String)
  Not(Expectation)
} derive(Eq, Debug)

///|
pub impl ToJson for Expectation with fn to_json(self) {
  match self {
    Literal(text~, ignore_case~) =>
      {
        "type": "literal",
        "text": text.to_json(),
        "ignoreCase": ignore_case.to_json(),
      }
    Class(parts~, inverted~, ignore_case~) =>
      {
        "type": "class",
        "parts": parts.to_json(),
        "inverted": inverted.to_json(),
        "ignoreCase": ignore_case.to_json(),
      }
    Any => { "type": "any" }
    End => { "type": "end" }
    Other(description~) =>
      { "type": "other", "description": description.to_json() }
    Not(e) => { "type": "not", "expected": e.to_json() }
  }
}

///|
fn hex_upper(c : Int) -> String {
  let digits = "0123456789ABCDEF"
  if c < 16 {
    digits[c:c + 1].to_owned()
  } else {
    let sb = StringBuilder()
    let mut started = false
    for shift = 12; shift >= 0; shift = shift - 4 {
      let d = (c >> shift) & 0xF
      if d != 0 || started {
        started = true
        sb.write_view(digits[d:d + 1])
      }
    }
    sb.to_string()
  }
}

///|
/// Shared tail of `literalEscape` / `classEscape` in the generated parser.
fn escape_controls(sb : StringBuilder, c : Int) -> Unit {
  match c {
    0 => sb.write_string("\\0")
    9 => sb.write_string("\\t")
    10 => sb.write_string("\\n")
    13 => sb.write_string("\\r")
    _ =>
      if c <= 0x0F {
        sb.write_string("\\x0")
        sb.write_string(hex_upper(c))
      } else if c <= 0x1F || (c >= 0x7F && c <= 0x9F) {
        sb.write_string("\\x")
        sb.write_string(hex_upper(c))
      } else {
        sb.write_char(c.unsafe_to_char())
      }
  }
}

///|
fn literal_escape(s : String) -> String {
  let sb = StringBuilder()
  for i in 0..<s.length() {
    let c = s.code_unit_at(i).to_int()
    match c {
      '\\' => sb.write_string("\\\\")
      '"' => sb.write_string("\\\"")
      _ => escape_controls(sb, c)
    }
  }
  sb.to_string()
}

///|
fn class_escape(s : String) -> String {
  let sb = StringBuilder()
  for i in 0..<s.length() {
    let c = s.code_unit_at(i).to_int()
    match c {
      '\\' => sb.write_string("\\\\")
      ']' => sb.write_string("\\]")
      '^' => sb.write_string("\\^")
      '-' => sb.write_string("\\-")
      _ => escape_controls(sb, c)
    }
  }
  sb.to_string()
}

///|
/// Human-readable description of an expectation, as in `describeExpectation`.
pub fn Expectation::describe(self : Expectation) -> String {
  match self {
    Literal(text~, ..) => "\"" + literal_escape(text) + "\""
    Class(parts~, inverted~, ..) => {
      // JS coerces the escaped-parts array to a string, joining with ",".
      let escaped = parts.map(part => {
        match part {
          Char(c) => class_escape(c)
          Range(a, b) => class_escape(a) + "-" + class_escape(b)
        }
      })
      "[" + (if inverted { "^" } else { "" }) + escaped.join(",") + "]"
    }
    Any => "any character"
    End => "end of input"
    Other(description~) => description
    Not(e) => "not " + e.describe()
  }
}

///|
fn describe_expected(expected : Array[Expectation]) -> String {
  let descriptions = expected.map(Expectation::describe)
  descriptions.sort_by(js_compare)
  let unique : Array[String] = []
  for d in descriptions {
    if unique.last() is Some(prev) && prev == d {
      continue
    }
    unique.push(d)
  }
  match unique.length() {
    1 => unique[0]
    2 => unique[0] + " or " + unique[1]
    // With no descriptions JS yields `", or undefined"`; keep that quirk.
    0 => ", or undefined"
    n => unique[:n - 1].join(", ") + ", or " + unique[n - 1]
  }
}

///|
/// `peg$SyntaxError.buildMessage(expected, found)`.
pub fn build_message(expected : Array[Expectation], found : String?) -> String {
  let found_desc = match found {
    Some(f) if f != "" => "\"" + literal_escape(f) + "\""
    _ => "end of input"
  }
  "Expected " + describe_expected(expected) + " but " + found_desc + " found."
}

///|
pub extend ClassPart with ToJson::{to_json}

///|
pub extend Expectation with ToJson::{to_json}
