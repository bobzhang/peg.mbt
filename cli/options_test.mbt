///|
test "extra option objects replace earlier ones" {
  let command = @cli.parse_args(
    [
      "--extra-options", "{\"features\": {\"text\": false}}", "--extra-options",
      "{\"features\": {\"offset\": false}}", "g.pegjs",
    ],
    read_file=_ => "",
  )
  guard command is Generate(options) else { fail("expected Generate") }
  assert_eq(options.features.get("text"), None)
  assert_eq(options.features.get("offset"), Some(false))
  assert_eq(options.output_file, Some("g.mbt"))
}

///|
test "rejects JavaScript-specific options" {
  let message = try @cli.parse_args(["-f", "es"], read_file=_ => "") catch {
    @cli.CliError(message) => message
  } noraise {
    _ => "accepted"
  }
  inspect(
    message,
    content="The -f option is JavaScript-specific and not supported.",
  )
}
