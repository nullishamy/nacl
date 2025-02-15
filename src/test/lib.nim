import ../lang
import ../stdlib
import std/strformat
import std/asyncdispatch
import std/typeinfo
import std/terminal
import std/tables

type
  Test* = object
    name: string
    interpreted: Future[Value]
    
proc getSource(self: Test): Expr =
  let input = readFile("./inputs/{self.name}".fmt)
  parseSource(input)

proc testFn(): Value =
  proc impl_test(args: seq[Value], ctx: Any): Future[Value] {.async.} =
    return @[L, args.lList].lList
    
  Value(kind: vkFunc, fn: FuncValue(fn: impl_test, name: "test"))
  
proc testFrom*(name: string): Test =
  var t = Test(name: name)
  styledEcho styleBright, fgCyan, "[START] ", resetStyle, t.name
  let ast = t.getSource

  let values = {
    "test": testFn()
  }.toTable
  
  let env = Environment(parent: stdenv(), values: values)
  var ctx = 0

  t.interpreted = interpretTree(env, ast, toAny(ctx))
  
  t

proc evaluatesTo*(self: Test, lisp: string): Future[Test] {.async.} =
  let v = self.interpreted.await
  let isSame = (v.toString == lisp)
  assert isSame, "'{v.toString}' != '{lisp}'".fmt
  self

proc run*(test: Future[Test]) =
  let t = waitFor test
  styledEcho styleBright, fgGreen, "[OK] ", resetStyle, t.name

