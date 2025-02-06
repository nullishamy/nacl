import ./agent
import ./server
import argparse
import std/net
import ./rpc
import std/strutils
import std/strformat

var p = newParser:
  command("server"):
    run:
      runServer()
  command("agent"):
    run:
      runAgent()
  command("client"):
    run:
      runAgent()
  command("status"):
    run:
        let socket = newSocket()
        echo "Connected to server"
        socket.connect("localhost", Port(6969))
        let msg = Message(kind: rqStatus, id: 1).serialise
        
        echo &"Send: {msg}"
        socket.send(msg)
    
        let returnLen = socket.recv(4)
        let returned = socket.recv(parseInt(returnLen))
        echo &"Recv {returned}"
  command("exec"):
    run:
        let socket = newSocket()
        echo "Connected to server"
        socket.connect("localhost", Port(6969))
        let msg = Message(kind: rqExec, id: 1).serialise
        
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
