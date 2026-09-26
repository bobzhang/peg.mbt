///|
test "code blocks see their labels through ctx, in both modes" {
  let parsers : Array[(String) -> @runtime.Value[Unit] raise] = [
    input => @codegen_regress.speed_parse(input),
    input => @codegen_regress.size_parse(input),
  ]
  for parse in parsers {
    let v = parse("ab")
    guard v is Arr([Str("a"), Str("b"), Str(marks)]) else {
      fail("unexpected result: \{v.js_string()}")
    }
    // User strings keep the private-use characters used as template markers.
    assert_eq(marks, "\u{E000}\u{E001}")
    assert_true(parse("a") is Arr([Str("a"), Null, _]))
  }
}
