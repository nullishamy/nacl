import std/net
import std/os
import std/osproc
import std/strformat
import std/strutils
import argparse
import ./print
import ./lang
import ./rpc

proc runAgent* =
  let socket = newSocket()
  echo "Connected to server"
  socket.connect("localhost", Port(6969))
  let msg = Message(kind: rqHello, id: 1).serialise
  
  echo &"Send: {msg}"
  socket.send(msg)
  
  var returnLen = socket.recv(4)
  var returned = socket.recv(parseInt(returnLen))
  echo &"Recv {returned}"
  
  returnLen = socket.recv(4)
  returned = socket.recv(parseInt(returnLen))
  echo &"Recv from server {returned}"

