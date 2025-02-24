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
    option("--config-path", required=true)
    run:
      runServer(opts.configPath)
  command("agent"):
    option("--config-path", required=true)
    run:
      runAgent(opts.configPath)
  command("exec"):
    arg("shaker-path")
    run:
      let socket = newSocket()
      socket.connect("localhost", Port(6969))
      echo "Connected to server"

      socket.send(@["hello".lIdent, @["list".lIdent, "cli".lString, 1.lNumeric].lList].lList.toString.lenPrefixed)
      
      let clientId = parseInt(socket.recv(parseInt(socket.recv(4))))
      echo "Our client ID is {clientId}".fmt

      let logReader = newSocket()
      logReader.connect("localhost", Port(6969))
      logReader.send(@["enable-logging".lIdent, clientId.lNumeric].lList.toString.lenPrefixed)
      
      let parsed = readFile(opts.shakerPath)
      socket.send(parsed.lenPrefixed)

      while true:
        let log = logReader.recv(parseInt(logReader.recv(4)))
        if log == "<close>":
          break
        
        echo log
    
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
