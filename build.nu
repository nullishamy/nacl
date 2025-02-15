#!/usr/bin/env nu

# Change into the root
cd ($env.CURRENT_FILE | path dirname)
nim --passL:-static --out=bin/nacl --opt:speed compile src/main.nim