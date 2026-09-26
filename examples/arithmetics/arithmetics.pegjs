// Simple arithmetic expressions, with MoonBit actions.
{
  fn num(v : PegValue) -> Double {
    match v {
      Num(n) => n
      _ => 0.0
    }
  }
}

Expression
  = head:Term tail:(_ @("+" / "-") _ @Term)* {
      let mut result = num(head)
      for element in tail.as_arr().unwrap() {
        let pair = element.as_arr().unwrap()
        if pair[0] is Str("+") {
          result = result + num(pair[1])
        } else {
          result = result - num(pair[1])
        }
      }
      Num(result)
    }

Term
  = head:Factor tail:(_ @("*" / "/") _ @Factor)* {
      let mut result = num(head)
      for element in tail.as_arr().unwrap() {
        let pair = element.as_arr().unwrap()
        if pair[0] is Str("*") {
          result = result * num(pair[1])
        } else {
          result = result / num(pair[1])
        }
      }
      Num(result)
    }

Factor
  = "(" _ @Expression _ ")"
  / Integer

Integer "integer"
  = _ [0-9]+ &{ ctx.text().length() < 10 } { Num(@string.parse_double(ctx.text().trim().to_owned())) }

_ "whitespace"
  = [ \t\n\r]*
