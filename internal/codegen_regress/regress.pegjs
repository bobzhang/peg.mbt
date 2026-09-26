// Regression grammar for code generation: ctx.label in code blocks, and
// private-use characters (used internally as template markers) in user code.
start
  = x:"a" &{ ctx.label("x") is Str("a") } y:"b"? {
      Arr([ctx.label("x"), ctx.label("y"), Str("")])
    }
