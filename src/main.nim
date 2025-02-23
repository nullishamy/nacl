import ./agent
import ./server
import ./lang/std
import ./lang/parse
import ./lang/runtime
import ./util
import argparse
import std/net
import std/strutils
import std/strformat

var p = newParser:
  command("server"):
    option("--config-path")
    run:
      runServer(opts.configPath)
  command("agent"):
    option("--config-path")
    run:
      runAgent(opts.configPath)
  command("client"):
    option("--config-path")
    run:
      runAgent(opts.configPath)
  command("exec"):
    arg("value")
    run:
      let socket = newSocket()
      socket.connect("localhost", Port(6969))
      echo "Connected to server"
      
      let parsed = parseSource(opts.value)
      socket.send(parsed.toString.lenPrefixed)
    
      let returnLen = socket.recv(4)
      let returned = socket.recv(parseInt(returnLen))
      echo &"Recv {returned}"
  command("status"):
    run:
      let socket = newSocket()
      socket.connect("localhost", Port(6969))
      echo "Connected to server"
      let msg = @["status".lIdent].lList.toString.lenPrefixed
  
      echo &"Send: {msg}"
      socket.send(msg)
    
      let returnLen = socket.recv(4)
      let returned = socket.recv(parseInt(returnLen))
      echo &"Recv {returned}"
  
try:
  p.run(commandLineParams())
except UsageError:
  stderr.writeLine getCurrentExceptionMsg()
  quit(1)
