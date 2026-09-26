///|
/// Results of semantic predicates: `Bool`, or a `Value` judged by JavaScript
/// truthiness (as in PEG.js).
pub(open) trait Truthy {
  fn truthy(Self) -> Bool
}

///|
pub impl Truthy for Bool with fn truthy(self) {
  self
}

///|
pub impl[T] Truthy for Value[T] with fn truthy(self) {
  Value::truthy(self)
}

///|
/// The truthiness of a predicate result.
pub fn[R : Truthy] truthy(result : R) -> Bool {
  result.truthy()
}

///|
/// Runs one parse the way PEG.js' `peg$parse` does, shared by the bytecode
/// interpreter and generated parsers:
///
/// 1. selects the start rule from `options["startRule"]` (raising
///    `InvalidStartRule` if it is not allowed);
/// 2. sets up tracing (`tracer`, else the default tracer or a no-op one);
/// 3. creates the parse state and calls `run(state, start_rule)`, which must
///    run the initializer, call `state.begin()` and parse the start rule;
/// 4. checks that all input was consumed, raising `SyntaxError` otherwise.
pub fn[T] drive(
  input : String,
  options : Map[String, Value[T]],
  tracer : Tracer[T]?,
  allowed_start_rules~ : ArrayView[String],
  trace~ : Bool,
  features~ : Features,
  run~ : (State[T], String) -> Slot[T] raise,
) -> Value[T] raise {
  let start = match options.get("startRule") {
    Some(Str(name)) =>
      if allowed_start_rules.contains(name) {
        name
      } else {
        raise InvalidStartRule(name)
      }
    Some(other) => raise InvalidStartRule(other.js_string())
    None => allowed_start_rules[0]
  }
  let tracer = if trace {
    match tracer {
      Some(t) => Some(t)
      None =>
        if features.default_tracer {
          Some(Tracer::default())
        } else {
          Some(Tracer::{ trace: _ => (), })
        }
    }
  } else {
    None
  }
  let state = State::new(input, options~, features~, tracer?)
  let result = run(state, start)
  state.finish(result)
}
