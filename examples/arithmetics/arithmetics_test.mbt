///|
test "evaluates arithmetic expressions" {
  debug_inspect(@arithmetics.parse("2 * (3 + 4)"), content="Num(14)")
  debug_inspect(@arithmetics.parse(" 1 + 2 * 3 - 4 / 2"), content="Num(5)")
}

///|
fn error_message(input : String) -> String {
  try @arithmetics.parse(input) catch {
    @runtime.SyntaxError(message~, ..) => message
    e => "unexpected: \{e}"
  } noraise {
    _ => "parsed"
  }
}

///|
test "reports syntax errors like PEG.js" {
  inspect(
    error_message("2 * (3 + "),
    content=(
      #|Expected "(" or integer but end of input found.
    ),
  )
  inspect(
    error_message("1 + 2 "),
    content=(
      #|Expected "*", "+", "-", or "/" but end of input found.
    ),
  )
}
