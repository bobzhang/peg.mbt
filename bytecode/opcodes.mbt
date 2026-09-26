///|
/// Bytecode instruction opcodes (`lib/compiler/opcodes.js`).
///
/// A `Session` may carry a different numbering; generated programs record
/// the table they were produced with.
pub(all) struct Opcodes {
  push_empty_string : Int
  push_undefined : Int
  push_null : Int
  push_failed : Int
  push_empty_array : Int
  push_curr_pos : Int
  pop : Int
  pop_curr_pos : Int
  pop_n : Int
  nip : Int
  append : Int
  wrap : Int
  text : Int
  pluck : Int
  if_ : Int
  if_error : Int
  if_not_error : Int
  while_not_error : Int
  match_any : Int
  match_string : Int
  match_string_ic : Int
  match_class : Int
  accept_n : Int
  accept_string : Int
  expect : Int
  load_saved_pos : Int
  update_saved_pos : Int
  call : Int
  rule : Int
  silent_fails_on : Int
  silent_fails_off : Int
  expect_ns_begin : Int
  expect_ns_end : Int
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
