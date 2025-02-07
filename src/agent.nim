import std/net
import std/os
import std/osproc
import std/strformat
import std/strutils
import std/asyncdispatch
import argparse
import std/tables
import ./util
import ./print
import ./lang

proc execCmd(): Value =
  proc impl_execCmd(args: seq[Value]): Future[Value] {.async.} =
    let name = args[0]
    case name.kind:
    of vkString:
      let cmd = name.sValue
      let cmdArgs = args[1]
      var builtArgs = newSeq[string]()
      case cmdArgs.kind:
      of vkList:
        for arg in cmdArgs.lValues:
          case arg.kind:
          of vkString:
            builtArgs.add(arg.sValue)
          else:
            print "invalid arg", arg
            return Value(kind: vkNil)
      else:
        print "invalid args", args
        return Value(kind: vkNil)

      let argstr = builtArgs.join(" ")
      echo "\n"
      var result = execCmdEx(&"{cmd} {argstr}")
      return result[0].lString
    else:
      print "invalid name", name
      
    return "exec finished".lString
  Value(kind: vkFunc, fn: impl_execCmd)
  
proc mainLoop {.async.} =
  let socket = newSocket()
  echo "Connected to server"
  socket.connect("localhost", Port(6969))
  let env = Environment(parent: stdenv(), values: {
    "exec": execCmd()
  }.toTable)

  while true:
    let source = socket.recv(parseInt(socket.recv(4)))
    print source
    var expr = parseSource(source)
    let res = await interpretTree(env, expr)
    echo &"Recv {res.toString}"
  
proc runAgent* =
  waitFor mainLoop()

