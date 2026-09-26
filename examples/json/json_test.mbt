///|
test "parses JSON documents" {
  let v = @json.parse(
    (
      #|{ "name": "peg.mbt", "tags": ["peg", "parser"], "stars": 4.5e1,
      #|  "ok": true, "none": null, "esc": "a\"bA\n" }
    ),
  )
  guard v is Obj(m) else { fail("expected an object") }
  debug_inspect(m.get("name"), content="Some(Str(\"peg.mbt\"))")
  debug_inspect(
    m.get("tags"),
    content="Some(Arr([Str(\"peg\"), Str(\"parser\")]))",
  )
  debug_inspect(m.get("stars"), content="Some(Num(45))")
  debug_inspect(m.get("ok"), content="Some(Bool(true))")
  debug_inspect(m.get("none"), content="Some(Null)")
  debug_inspect(m.get("esc"), content="Some(Str(\"a\\\"bA\\n\"))")
}

///|
test "agrees with @json on round trips" {
  let text = "[1, -2.5, {\"a\": [true, false, null]}, \"x\"]"
  let ours = @json.parse(text).to_json_with(_ => Json::null())
  let theirs = @core_json.parse(text)
  assert_eq(ours, theirs)
}

///|
test "reports errors like PEG.js" {
  let message = try @json.parse("[1, 2,]") catch {
    @runtime.SyntaxError(message~, ..) => message
    e => "\{e}"
  } noraise {
    _ => "parsed"
  }
  inspect(
    message,
    content=(
      #|Expected "[", "false", "null", "true", "{", number, string, or whitespace but "]" found.
    ),
  )
}
