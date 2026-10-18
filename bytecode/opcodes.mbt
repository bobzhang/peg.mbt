///|
/// Bytecode instruction opcodes (`lib/compiler/opcodes.js`).
///
/// A `Session` may carry a different numbering; generated programs record
/// the table they were produced with.
pub(all) struct Opcodes {
  push_empty_string : Int32
  push_undefined : Int32
  push_null : Int32
  push_failed : Int32
  push_empty_array : Int32
  push_curr_pos : Int32
  pop : Int32
  pop_curr_pos : Int32
  pop_n : Int32
  nip : Int32
  append : Int32
  wrap : Int32
  text : Int32
  pluck : Int32
  if_ : Int32
  if_error : Int32
  if_not_error : Int32
  while_not_error : Int32
  match_any : Int32
  match_string : Int32
  match_string_ic : Int32
  match_class : Int32
  accept_n : Int32
  accept_string : Int32
  expect : Int32
  load_saved_pos : Int32
  update_saved_pos : Int32
  call : Int32
  rule : Int32
  silent_fails_on : Int32
  silent_fails_off : Int32
  expect_ns_begin : Int32
  expect_ns_end : Int32
} derive(Eq, Debug)

///|
/// The standard PEG.js opcode numbering.
pub let default_opcodes : Opcodes = {
  push_empty_string: 0,
  push_undefined: 1,
  push_null: 2,
  push_failed: 3,
  push_empty_array: 4,
  push_curr_pos: 5,
  pop: 6,
  pop_curr_pos: 7,
  pop_n: 8,
  nip: 9,
  append: 10,
  wrap: 11,
  text: 12,
  pluck: 41,
  if_: 13,
  if_error: 14,
  if_not_error: 15,
  while_not_error: 16,
  match_any: 17,
  match_string: 18,
  match_string_ic: 19,
  match_class: 20,
  accept_n: 21,
  accept_string: 22,
  expect: 23,
  load_saved_pos: 24,
  update_saved_pos: 25,
  call: 26,
  rule: 27,
  silent_fails_on: 28,
  silent_fails_off: 29,
  expect_ns_begin: 38,
  expect_ns_end: 39,
}
