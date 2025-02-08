import std/sequtils
import std/strformat
import std/strutils
import std/tables
import std/asyncdispatch
import sugar
import ./print

type
  ExprType* = enum
    exIdent, exStr, exList, exNumeric
  
  Expr* = ref object
    case kind*: ExprType
    of exIdent:
      ident*: string
    of exStr:
      sValue*: string
    of exNumeric:
      num*: int
    of exList:
      lValues*: seq[Expr]

  TokenType = enum
    tkListStart, tkIdent, tkStr, tkListEnd, tkNumeric

  Token = object
    case kind*: TokenType
    of tkListStart, tkListEnd:
      discard
    of tkIdent:
      ident: string
    of tkStr:
      str: string
    of tkNumeric:
      num: int
    
method dbg*(self: Expr): string =
  case self.kind:
  of exIdent:
    fmt "Ident({self.ident})"
  of exStr:
    fmt "Str({self.sValue})"
  of exNumeric:
    fmt "Num({self.num})"
  of exList:
    let s = self.lValues.map(proc(x: Expr): string = $x.dbg).join(", ")
    fmt "List({s})"

func lex(source: string): seq[Token] =
  var toks = newSeq[Token]()
  var i = 0
  
  while i < source.len:
    var ch = source[i]
    
    if ch == '(':
      toks.add(Token(kind: tkListStart))
    elif ch == ')':
      toks.add(Token(kind: tkListEnd))
    elif ch.isDigit:
      # Starts with number = numeric, taking priority over idents below
      var numeric = ""

      while i < source.len and ch.isDigit:
        numeric.add(ch)
        i.inc
        ch = source[i]

      # Since we'll have gone 1 over in our loop
      i.dec
      toks.add(Token(kind: tkNumeric, num: parseInt(numeric)))
    elif ch.isAlphaNumeric:
      var ident = ""

      while i < source.len and ch.isAlphaNumeric:
        ident.add(ch)
        i.inc
        ch = source[i]

      # Since we'll have gone 1 over in our loop
      i.dec
      toks.add(Token(kind: tkIdent, ident: ident))
    elif ch == '"':
      var lit = ""

      # Consume quote
      i.inc
      ch = source[i]
      
      while i < source.len and ch != '"':
        lit.add(ch)
        i.inc
        ch = source[i]

      toks.add(Token(kind: tkStr, str: lit))

    i.inc

  toks

func pop(toks: var seq[Token]): Token =
  let val = toks[0]
  toks.delete(0)
  return val
  
func parse(toks: var seq[Token]): Expr =
  var current = toks.pop()
  if current.kind == tkListStart:
    var children = newSeq[Expr]()
    var next = toks.parse
    while next != nil:
      children.add(next)
      next = toks.parse
    return Expr(kind: exList, lValues: children)
  elif current.kind == tkIdent:
    return Expr(kind: exIdent, ident: current.ident)
  elif current.kind == tkStr:
    return Expr(kind: exStr, sValue: current.str)
  elif current.kind == tkNumeric:
    return Expr(kind: exNumeric, num: current.num)
  else:
    print "unrecognised tok", current
    
  return nil
  
func parseSource*(source: string): Expr =
  var toks = source.lex
  return toks.parse

type
  ValueKind* = enum
    vkList, vkString, vkIdent, vkNil, vkFunc, vkNumeric

  LispFunc* = proc (args: seq[Value], ctx: void*): Future[Value]

  ListValue* = ref object
    values*: seq[Value]
  StringValue* = ref object
    str*: string
  IdentValue* = ref object
    ident*: string
  NumericValue* = ref object
    num*: int
  FuncValue* = ref object
    fn*: LispFunc
    
  Value* = ref object
    case kind*: ValueKind
    of vkList:
      list*: ListValue
    of vkString:
      str*: StringValue
    of vkIdent:
      ident*: IdentValue
    of vkNumeric:
      num*: NumericValue
    of vkFunc:
      fn*: FuncValue
    of vkNil:
      discard

  Environment* = ref object
    parent*: Environment
    values*: Table[string, Value]

proc isNil*(self: Value): bool =
  if self == nil:
    return false
    
  case self.kind:
  of vkNil:
    true
  else:
    false

proc asList*(self: Value): ListValue =
  if self == nil:
    return nil
    
  case self.kind:
  of vkList:
    self.list
  else:
    nil

proc asString*(self: Value): StringValue =
  if self == nil:
    return nil
    
  case self.kind:
  of vkString:
    self.str
  else:
    nil

proc asIdent*(self: Value): IdentValue =
  if self == nil:
    return nil
    
  case self.kind:
  of vkIdent:
    self.ident
  else:
    nil

proc asNumeric*(self: Value): NumericValue =
  if self == nil:
    return nil
    
  case self.kind:
  of vkNumeric:
    self.num
  else:
    nil

proc asFunc*(self: Value): FuncValue =
  if self == nil:
    return nil
    
  case self.kind:
  of vkFunc:
    self.fn
  else:
    nil
    
proc toString*(self: Value): string =
  case self.kind:
  of vkList:
    let items = self.list.values.map(i => i.toString).join " "
    fmt"({items})"
  of vkString:
    # Using the double quote method causes nim to treat it as a multiline string
    # which removes the quote characters entirely, so do it the old fashioned way :^)
    '"' & self.str.str & '"'
  of vkIdent:
    self.ident.ident
  of vkNumeric:
    intToStr(self.num.num)
  of vkFunc:
    "<func>"
  of vkNil:
    "nil"

proc get(self: Environment, key: string): Value =
  if self.values.hasKey(key):
    return self.values[key]

  if self.parent != nil:
     return self.parent.get(key)
     
  return nil
  
proc interpretTree*(env: Environment, base: Expr): Future[Value] {.async.} =
  case base.kind:
  of exIdent:
    return Value(kind: vkIdent, ident: IdentValue(ident: base.ident))
  of exStr:
    return Value(kind: vkString, str: StringValue(str: base.sValue))
  of exNumeric:
    return Value(kind: vkNumeric, num: NumericValue(num: base.num))
  of exList:
    let vals = base.lValues
    if vals.len == 0:
      return Value(kind: vkList, list: ListValue())

    let funcIdent = vals[0]
    case funcIdent.kind:
    of exIdent:
      let fn = env.get(funcIdent.ident)
      if fn == nil:
        print "unknown func", funcIdent
        return Value(kind: vkNil)

      case fn.kind:
      of vkFunc:
        var callArgs = newSeq[Value]()
        for val in vals[1..^1]:
          callArgs.add(await interpretTree(env, val))
        return await fn.fn.fn(callArgs)
      else:
        print "expected vkFunc got", fn
        return Value(kind: vkNil)
    else:
      print "cannot use as type for fn name", funcIdent
      return Value(kind: vkNil)

proc globalList(): Value =
  proc impl_list(args: seq[Value]): Future[Value] {.async.} =
    Value(kind: vkList, list: ListValue(values: args))

  return Value(kind: vkFunc, fn: FuncValue(fn: impl_list))

proc lIdent*(self: string): Value =
  Value(kind: vkIdent, ident: IdentValue(ident: self))

proc lString*(self: string): Value =
  Value(kind: vkString, str: StringValue(str: self))

proc lList*(self: seq[Value]): Value =
  Value(kind: vkList, list: ListValue(values: self))

let L* = "l".lIdent
let L_nil* = Value(kind: vkNil)

proc stdenv*(): Environment =
  let values = {
    "list": globalList(),
    "l": globalList()
  }.toTable

  Environment(values: values)

proc test() {.async.} =
  let input = readFile("./inputs/test.lisp")
  let parsed = parseSource(input)
  let env = stdenv()
  print await interpretTree(env, parsed)


