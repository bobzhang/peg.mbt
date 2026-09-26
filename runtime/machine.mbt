// Primitive operations of the parsing machine, shared by the bytecode
// interpreter and generated parsers.

///|
/// The value in a stack slot; aborts on `Failed` / `Pos` (a compiler bug).
pub fn[T] slot_value(slot : Slot[T]) -> Value[T] {
  match slot {
    Val(v) => v
    Failed => abort("unexpected FAILED marker used as a value")
    Pos(_) => abort("unexpected position used as a value")
  }
}

///|
/// The saved position in a stack slot; aborts otherwise (a compiler bug).
pub fn[T] slot_pos(slot : Slot[T]) -> Int {
  match slot {
    Pos(p) => p
    _ => abort("expected a saved position on the stack")
  }
}

///|
/// `APPEND`: pushes `value` onto the array held by `target`.
pub fn[T] slot_append(target : Slot[T], value : Slot[T]) -> Unit {
  match target {
    Val(Arr(arr)) => arr.push(slot_value(value))
    _ => abort("APPEND target is not an array")
  }
}

///|
/// Whether `lit` occurs in `input` at code-unit offset `pos`
/// (`input.substr(pos, lit.length) === lit`).
pub fn starts_with_at(input : String, pos : Int, lit : String) -> Bool {
  if pos + lit.length() > input.length() {
    return false
  }
  for i in 0..<lit.length() {
    if input.code_unit_at(pos + i) != lit.code_unit_at(i) {
      return false
    }
  }
  true
}

///|
/// Whether the code unit at `pos` is `unit` (`input.charCodeAt(pos) === unit`).
pub fn code_unit_is(input : String, pos : Int, unit : Int) -> Bool {
  pos < input.length() && input.code_unit_at(pos).to_int() == unit
}

///|
/// JavaScript `input.substr(pos, n)` for non-negative `pos` and `n`.
pub fn js_substr(input : String, pos : Int, n : Int) -> String {
  let end = if pos + n > input.length() { input.length() } else { pos + n }
  if pos >= end {
    ""
  } else {
    input.unsafe_substring(start=pos, end~)
  }
}

///|
/// Case-insensitive literal test: `lower(input.substr(pos, lit.length)) ===
/// lit`, where `lit` is already lowercased.
pub fn matches_ignore_case_at(input : String, pos : Int, lit : String) -> Bool {
  js_to_lower(js_substr(input, pos, lit.length())) == lit
}
