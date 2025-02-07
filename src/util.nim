import std/strformat
import std/strutils

const PREFIX_LEN = 4
const PREFIX_PAD = '0'

proc lenPrefixed*(self: string): string =
   align(intToStr(self.len), PREFIX_LEN, PREFIX_PAD) & self
