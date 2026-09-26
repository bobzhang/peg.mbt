// Emission of MoonBit literals.

///|
fn has_lone_surrogate(s : String) -> Bool {
  for i = 0; i < s.length(); {
    let c = s.code_unit_at(i).to_int()
    if c >= 0xD800 && c <= 0xDBFF {
      if i + 1 < s.length() {
        let d = s.code_unit_at(i + 1).to_int()
        if d >= 0xDC00 && d <= 0xDFFF {
          continue i + 2
        }
      }
      return true
    }
    if c >= 0xDC00 && c <= 0xDFFF {
      return true
    }
    continue i + 1
  }
  false
}

///|
/// A MoonBit expression of type `String` whose value is `s`. Strings with
/// lone surrogates (valid in JavaScript and PEG.js grammars, but not in
/// MoonBit literals) are built from code units.
pub fn string_literal(s : String) -> String {
  let sb = StringBuilder()
  if has_lone_surrogate(s) {
    sb.write_string("@runtime.string_of_code_units([")
    for i in 0..<s.length() {
      if i > 0 {
        sb.write_string(", ")
      }
      sb.write_string("0x")
      sb.write_string(s.code_unit_at(i).to_int().to_string(radix=16))
    }
    sb.write_string("])")
    return sb.to_string()
  }
  sb.write_char('"')
  for c in s {
    match c {
      '\\' => sb.write_string("\\\\")
      '"' => sb.write_string("\\\"")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      _ => {
        let cp = c.to_int()
        if cp < 0x20 || cp >= 0x7F {
          sb.write_string("\\u{")
          sb.write_string(cp.to_string(radix=16))
          sb.write_char('}')
        } else {
          sb.write_char(c)
        }
      }
    }
  }
  sb.write_char('"')
  sb.to_string()
}

///|
fn bool_literal(b : Bool) -> String {
  if b {
    "true"
  } else {
    "false"
  }
}

///|
fn class_parts_literal(parts : Array[@runtime.ClassPart]) -> String {
  let items = parts.map(part => {
    match part {
      Char(c) => "Char(" + string_literal(c) + ")"
      Range(a, b) =>
        "Range(" + string_literal(a) + ", " + string_literal(b) + ")"
    }
  })
  "[" + items.join(", ") + "]"
}

///|
fn expectation_literal(e : @runtime.Expectation) -> String {
  match e {
    Literal(text~, ignore_case~) =>
      "@runtime.Expectation::Literal(text=" +
      string_literal(text) +
      ", ignore_case=" +
      bool_literal(ignore_case) +
      ")"
    Class(parts~, inverted~, ignore_case~) =>
      "@runtime.Expectation::Class(parts=" +
      class_parts_literal(parts) +
      ", inverted=" +
      bool_literal(inverted) +
      ", ignore_case=" +
      bool_literal(ignore_case) +
      ")"
    Any => "@runtime.Expectation::Any"
    End => "@runtime.Expectation::End"
    Other(description~) =>
      "@runtime.Expectation::Other(description=" +
      string_literal(description) +
      ")"
    Not(inner) =>
      "@runtime.Expectation::Not(" + expectation_literal(inner) + ")"
  }
}

///|
fn int_array_literal(xs : Array[Int]) -> String {
  "[" + xs.map(x => x.to_string()).join(", ") + "]"
}

///|
/// Indents every non-empty line of `code` by `n` spaces.
fn indent(code : String, n : Int) -> String {
  let pad = " ".repeat(n)
  code
  .split("\n")
  .map(line => if line.is_empty() { "" } else { pad + line.to_owned() })
  .join("\n")
}
