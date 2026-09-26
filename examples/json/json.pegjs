// JSON Grammar (MoonBit code blocks)
// ==================================
//
// Port of PEG.js' examples/json.pegjs; values are `PegValue`s.
//
// Based on the grammar from RFC 7159 [1].
//
// Note that JSON is also specified in ECMA-262 [2], ECMA-404 [3], and on the
// JSON website [4] (somewhat informally). The RFC seems the most authoritative
// source, which is confirmed e.g. by [5].
//
// [1] http://tools.ietf.org/html/rfc7159
// [2] http://www.ecma-international.org/publications/standards/Ecma-262.htm
// [3] http://www.ecma-international.org/publications/standards/Ecma-404.htm
// [4] http://json.org/
// [5] https://www.tbray.org/ongoing/When/201x/2014/03/05/RFC7159-JSON

// ----- 2. JSON Grammar -----

JSON_text
  = ws value:value ws { value }

begin_array     = ws "[" ws
begin_object    = ws "{" ws
end_array       = ws "]" ws
end_object      = ws "}" ws
name_separator  = ws ":" ws
value_separator = ws "," ws

ws "whitespace" = [ \t\n\r]*

// ----- 3. Values -----

value
  = false
  / null
  / true
  / object
  / array
  / number
  / string

false = "false" { Bool(false) }
null  = "null"  { Null }
true  = "true"  { Bool(true) }

// ----- 4. Objects -----

object
  = begin_object
    members:(
      head:member
      tail:(value_separator m:member { m })*
      {
        let result : Map[String, PegValue] = Map([])
        for element in [head, ..items(tail)] {
          let pair = items(element)
          result[text_of(pair[0])] = pair[1]
        }
        Obj(result)
      }
    )?
    end_object
    { if members is Null { Obj(Map([])) } else { members } }

member
  = name:string name_separator value:value { Arr([name, value]) }

// ----- 5. Arrays -----

array
  = begin_array
    values:(
      head:value
      tail:(value_separator v:value { v })*
      { Arr([head, ..items(tail)]) }
    )?
    end_array
    { if values is Null { Arr([]) } else { values } }

// ----- 6. Numbers -----

number "number"
  = minus? int frac? exp? { Num(@string.parse_double(ctx.text())) }

decimal_point
  = "."

digit1_9
  = [1-9]

e
  = [eE]

exp
  = e (minus / plus)? DIGIT+

frac
  = decimal_point DIGIT+

int
  = zero / (digit1_9 DIGIT*)

minus
  = "-"

plus
  = "+"

zero
  = "0"

// ----- 7. Strings -----

string "string"
  = quotation_mark chars:char* quotation_mark { Str(items(chars).map(text_of).join("")) }

char
  = unescaped
  / escape
    sequence:(
        '"'
      / "\\"
      / "/"
      / "b" { Str("\u{8}") }
      / "f" { Str("\u{c}") }
      / "n" { Str("\n") }
      / "r" { Str("\r") }
      / "t" { Str("\t") }
      / "u" digits:$(HEXDIG HEXDIG HEXDIG HEXDIG) {
          Str(@runtime.string_of_code_units([@string.parse_int(text_of(digits), base=16)]))
        }
    )
    { sequence }

escape
  = "\\"

quotation_mark
  = '"'

unescaped
  = [^\0-\x1F\x22\x5C]

// ----- Core ABNF Rules -----

// See RFC 4234, Appendix B (http://tools.ietf.org/html/rfc4234).
DIGIT  = [0-9]
HEXDIG = [0-9a-f]i
