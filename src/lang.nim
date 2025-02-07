import std/sequtils
import std/strformat
import std/strutils
import std/tables
import std/asyncdispatch
import sugar
import ./print

type
  ExprType* = enum
    exName, exStr, exList
  
  Expr* = ref object
    case kind*: ExprType
    of exName:
      nValue*: string
    of exStr:
      sValue*: string
    of exList:
      lValues*: seq[Expr]

  TokenType = enum
    ListStart, Ident, StrLit, ListEnd

  Token = object
    ty: TokenType
    value: string
    
method dbg*(self: Expr): string =
  case self.kind:
  of exName:
    fmt "Name({self.nValue})"
  of exStr:
    fmt "Str({self.sValue})"
  of exList:
    let s = self.lValues.map(proc(x: Expr): string = $x.dbg).join(", ")
    fmt "List({s})"

func lex(source: string): seq[Token] =
  var toks = newSeq[Token]()
  var i = 0
  
  while i < source.len:
    var ch = source[i]
    
    if ch == '(':
      toks.add(Token(ty: TokenType.ListStart, value: "("))
    elif ch == ')':
      toks.add(Token(ty: TokenType.ListEnd, value: ")"))
    elif ch.isAlphaNumeric:
      var ident = ""

      while i < source.len and ch.isAlphaNumeric:
        ident.add(ch)
        i.inc
        ch = source[i]

      # Since we'll have gone 1 over in our loop
      i.dec
      toks.add(Token(ty: TokenType.Ident, value: ident))
    elif ch == '"':
      var lit = ""

      # Consume quote
      i.inc
      ch = source[i]
      
      while i < source.len and ch != '"':
        lit.add(ch)
        i.inc
        ch = source[i]

      toks.add(Token(ty: TokenType.StrLit, value: lit))

    i.inc

  toks

func pop(toks: var seq[Token]): Token =
  let val = toks[0]
  toks.delete(0)
  return val
  
func parse(toks: var seq[Token]): Expr =
  var current = toks.pop()
  if current.ty == TokenType.ListStart:
    var children = newSeq[Expr]()
    var next = toks.parse
    while next != nil:
      children.add(next)
      next = toks.parse
    return Expr(kind: exList, lValues: children)
  elif current.ty == TokenType.Ident:
    return Expr(kind: exName, nValue: current.value)
  elif current.ty == TokenType.StrLit:
    return Expr(kind: exStr, sValue: current.value)
    
  return nil
  
func parseSource*(source: string): Expr =
  var toks = source.lex
  return toks.parse

type
  ValueKind* = enum
    vkList, vkString, vkIdent, vkNil, vkFunc

  LispFunc* = proc (args: seq[Value]): Future[Value]
  
  Value* = ref object
    case kind*: ValueKind
    of vkList:
      lValues*: seq[Value]
    of vkString:
      sValue*: string
    of vkIdent:
      iValue*: string
    of vkFunc:
      fn*: LispFunc
    of vkNil:
      discard

  Environment* = ref object
    parent*: Environment
    values*: Table[string, Value]

proc toString*(self: Value): string =
  case self.kind:
  of vkList:
    let items = self.lvalues.map(i => i.toString).join " "
    fmt"({items})"
  of vkString:
    # Using the double quote method causes nim to treat it as a multiline string
    # which removes the quote characters entirely, so do it the old fashioned way :^)
    '"' & self.sValue & '"'
  of vkIdent:
    self.iValue
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
  of exName:
    return Value(kind: vkIdent, iValue: base.nValue)
  of exStr:
    return Value(kind: vkString, sValue: base.sValue)
  of exList:
    let vals = base.lValues
    if vals.len == 0:
      return Value(kind: vkList, lValues: @[])

    let funcIdent = vals[0]
    case funcIdent.kind:
    of exName:
      let fn = env.get(funcIdent.nValue)
      if fn == nil:
        print "unknown func", funcIdent
        return Value(kind: vkNil)

      case fn.kind:
      of vkFunc:
        var callArgs = newSeq[Value]()
        for val in vals[1..^1]:
          callArgs.add(await interpretTree(env, val))
        return await fn.fn(callArgs)
      else:
        print "expected vkFunc got", fn
        return Value(kind: vkNil)
    else:
      print "cannot use as type for fn name", funcIdent
      return Value(kind: vkNil)

proc globalList(): Value =
  proc impl_list(args: seq[Value]): Future[Value] {.async.} =
    Value(kind: vkList, lValues: args)

  return Value(kind: vkFunc, fn: impl_list)

proc lIdent*(self: string): Value =
  Value(kind: vkIdent, iValue: self)

proc lString*(self: string): Value =
  Value(kind: vkString, sValue: self)

proc lList*(self: seq[Value]): Value =
  Value(kind: vkList, lValues: self)

let L* = "l".lIdent
let L_nil* = Value(kind: vkNil)

proc stdenv*(): Environment =
  let values = {
    "list": globalList(),
    "l": globalList()
  }.toTable

  Environment(values: values)

