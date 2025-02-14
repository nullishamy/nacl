import ../lang
import ../stdlib
import std/strformat
import std/asyncdispatch
import std/typeinfo
import std/terminal

type
  Test* = object
    name: string
    interpreted: Future[Value]
    
proc getSource(self: Test): Expr =
  let input = readFile("./inputs/{self.name}".fmt)
  parseSource(input)

proc testFrom*(name: string): Test =
  var t = Test(name: name)
  styledEcho styleBright, fgCyan, "[START] ", resetStyle, t.name
  let ast = t.getSource
  
  let env = stdenv()
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

