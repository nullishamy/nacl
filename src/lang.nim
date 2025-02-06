import std/sequtils
import std/strformat
import std/strutils

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

