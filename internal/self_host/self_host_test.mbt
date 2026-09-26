///|
/// The parser generated from PEG.js' own grammar (with MoonBit code blocks)
/// must behave exactly like PEG.js on every grammar-parser fixture.
test "generated grammar parser matches PEG.js" {
  let mut failures = 0
  for i, c in @fixture.meta_cases {
    let (input, extract_comments, expected_text) = c
    let expected = @json.parse(expected_text)
    let actual : Json = try
      @self_host.parse_grammar(input, extract_comments~)
    catch {
      @runtime.SyntaxError(_) as e => { "error": e.to_json() }
      e => { "error": { "name": "unexpected", "message": "\{e}" } }
    } noraise {
      g => { "ok": g.to_json() }
    }
    let actual = @fixture.normalize(actual)
    if actual != expected {
      failures += 1
      if failures <= 3 {
        println("case \{i} differs: \{input}")
        println("  expected: \{expected.stringify()}")
        println("  actual:   \{actual.stringify()}")
      }
    }
  }
  assert_eq(failures, 0)
}
