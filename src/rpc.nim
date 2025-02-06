import std/strformat
import std/strutils

type
  MessageKind* = enum
    rqHello, rsAck, rqClose, rqStatus, rqExec
  
  Message* = object
    id*: int
    kind*: MessageKind
    params*: seq[string] = @[]

proc kindName(self: MessageKind): string =
  case self 
  of rqHello: "hello"
  of rsAck: "ack"
  of rqClose: "close"
  of rqStatus: "status"
  of rqExec: "exec"
  
const PREFIX_LEN = 4
const PREFIX_PAD = '0'

proc lenPrefixed*(self: string): string =
  align(intToStr(self.len), PREFIX_LEN, PREFIX_PAD) & self
  
proc serialise*(self: Message): string =
  (&"({self.kind.kindName})").lenPrefixed
  
proc serialiseNoPrefix*(self: Message): string =
  &"({self.kind.kindName})"

