///|
/// Implementation of an action or semantic predicate code block. Predicates
/// return a value whose JavaScript truthiness decides the match.
pub type ActionFn[T] = (ActionContext[T]) -> Value[T] raise

///|
/// Implementation of a grammar's initializer block. It runs once per parse
/// (after the start rule is validated) and returns bindings that take
/// precedence over the statically supplied ones, so actions can share
/// per-parse state by closing over it.
pub type InitFn[T] = (ActionContext[T]) -> Map[String, ActionFn[T]] raise
