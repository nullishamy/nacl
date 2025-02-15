#!/usr/bin/env nu

# Change into the root
cd ($env.CURRENT_FILE | path dirname)
nim --passL:-static --out=bin/suite --opt:speed compile src/test/suite.nim
./bin/suite