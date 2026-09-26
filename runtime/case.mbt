// JavaScript-compatible string primitives used by PEG.js generated parsers.
//
// PEG.js parsers run on JavaScript strings: they index UTF-16 code units,
// lowercase with `String.prototype.toLowerCase` and match case-insensitive
// character classes with non-unicode `/i` regexps. The helpers below
// reproduce those semantics exactly, driven by tables captured from V8
// (see tools/gen-unicode.js).

///|
fn search_int(keys : ReadOnlyArray[Int], key : Int) -> Int? {
  for lo = 0, hi = keys.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    let k = keys[mid]
    if k == key {
      return Some(mid)
    } else if k < key {
      continue mid + 1, hi
    } else {
      continue lo, mid
    }
  } nobreak {
    None
  }
}

///|
fn in_ranges(ranges : ReadOnlyArray[Int], cp : Int) -> Bool {
  // `ranges` holds sorted inclusive [start, end] pairs.
  for lo = 0, hi = ranges.length() / 2; lo < hi; {
    let mid = lo + (hi - lo) / 2
    if cp < ranges[mid * 2] {
      continue lo, mid
    } else if cp > ranges[mid * 2 + 1] {
      continue mid + 1, hi
    } else {
      return true
    }
  } nobreak {
    false
  }
}

///|
fn is_cased(cp : Int) -> Bool {
  in_ranges(cased_ranges, cp)
}

///|
fn is_case_ignorable(cp : Int) -> Bool {
  in_ranges(case_ignorable_ranges, cp)
}

///|
/// Decodes the code point starting at code unit `i`, returning it with its
/// width in code units. Lone surrogates decode as themselves.
fn code_point_at(s : StringView, i : Int) -> (Int, Int) {
  let c = s.code_unit_at(i).to_int()
  if c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length() {
    let d = s.code_unit_at(i + 1).to_int()
    if d >= 0xDC00 && d <= 0xDFFF {
      return ((c - 0xD800) * 0x400 + (d - 0xDC00) + 0x10000, 2)
    }
  }
  (c, 1)
}

///|
/// Decodes the code point ending just before code unit `i`.
fn code_point_before(s : StringView, i : Int) -> (Int, Int) {
  let d = s.code_unit_at(i - 1).to_int()
  if d >= 0xDC00 && d <= 0xDFFF && i >= 2 {
    let c = s.code_unit_at(i - 2).to_int()
    if c >= 0xD800 && c <= 0xDBFF {
      return ((c - 0xD800) * 0x400 + (d - 0xDC00) + 0x10000, 2)
    }
  }
  (d, 1)
}

///|
/// Unicode Final_Sigma condition for the sigma occupying `[i, i + 1)`.
/// Mirrors ICU: case-ignorable characters are skipped before testing cased.
fn is_final_sigma(s : StringView, i : Int) -> Bool {
  let preceded = for j = i; j > 0; {
    let (cp, w) = code_point_before(s, j)
    if is_case_ignorable(cp) {
      continue j - w
    }
    break is_cased(cp)
  } nobreak {
    false
  }
  if !preceded {
    return false
  }
  let followed = for j = i + 1; j < s.length(); {
    let (cp, w) = code_point_at(s, j)
    if is_case_ignorable(cp) {
      continue j + w
    }
    break is_cased(cp)
  } nobreak {
    false
  }
  !followed
}

///|
/// `String.prototype.toLowerCase` as implemented by V8.
pub fn js_to_lower(s : StringView) -> String {
  let sb = StringBuilder(size_hint=s.length())
  for i = 0; i < s.length(); {
    let (cp, w) = code_point_at(s, i)
    if cp < 0x80 {
      let c = if cp >= 'A' && cp <= 'Z' { cp + 32 } else { cp }
      sb.write_char(c.unsafe_to_char())
    } else if cp == 0x3A3 {
      sb.write_char(if is_final_sigma(s, i) { '\u{3C2}' } else { '\u{3C3}' })
    } else {
      match search_int(lower_keys, cp) {
        Some(k) => sb.write_string(lower_vals[k])
        None => sb.write_char(cp.unsafe_to_char())
      }
    }
    continue i + w
  }
  sb.to_string()
}

///|
/// ES `Canonicalize(ch)` for non-unicode, ignore-case regexps.
pub fn js_canonicalize(ch : Int) -> Int {
  match search_int(canon_keys, ch) {
    Some(k) => canon_vals[k]
    None => ch
  }
}

///|
/// Inverse of `js_canonicalize`: canonical value -> code units mapping to it
/// (excluding identity mappings, which callers check directly).
let canon_inverse : Map[Int, Array[Int]] = {
  let m : Map[Int, Array[Int]] = {}
  for i, k in canon_keys {
    let v = canon_vals[i]
    match m.get(v) {
      Some(arr) => arr.push(k)
      None => m[v] = [k]
    }
  }
  m
}

///|
/// Calls `f` on every code unit whose canonical form equals that of `ch`
/// (including `ch` itself), stopping early when `f` returns `true`.
pub fn js_case_variants_any(ch : Int, f : (Int) -> Bool) -> Bool {
  let k = js_canonicalize(ch)
  if f(ch) {
    return true
  }
  if k != ch && js_canonicalize(k) == k && f(k) {
    return true
  }
  match canon_inverse.get(k) {
    Some(arr) =>
      for d in arr {
        if d != ch && f(d) {
          return true
        }
      }
    None => ()
  }
  false
}

///|
/// Lexicographic comparison by UTF-16 code units, like JavaScript's default
/// `Array.prototype.sort` and relational string operators.
pub fn js_compare(a : String, b : String) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let x = a.code_unit_at(i)
    let y = b.code_unit_at(i)
    if x != y {
      return if x < y { -1 } else { 1 }
    }
  }
  a.length().compare(b.length())
}

///|
/// Builds a string from UTF-16 code units. Unlike string literals, this can
/// produce lone surrogates, which JavaScript strings (and PEG.js grammars)
/// may contain.
pub fn string_of_code_units(units : ArrayView[Int]) -> String {
  let sb = StringBuilder(size_hint=units.length())
  for u in units {
    sb.write_char(u.unsafe_to_char())
  }
  sb.to_string()
}
