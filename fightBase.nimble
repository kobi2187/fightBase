import std/[os, strutils]

# Package

version       = "0.2.0"
author        = "FightBase Team"
description   = "Martial arts simulation engine and exact self-defense equilibrium solver"
license       = "MIT"
srcDir        = "src"
bin           = @["fightBase", "fightsolve"]

# Dependencies

requires "nim >= 2.0.0"
requires "db_connector >= 0.1.0"   # SQLite storage used by the simulator and game tree

# Tasks

task test, "Run the test suite":
  for f in listFiles("tests"):
    if f.endsWith(".nim") and f.extractFilename.startsWith("test_"):
      exec "nim c -r --hints:off " & f

task checkall, "Type-check every module and example":
  for dir in ["src", "examples"]:
    for f in listFiles(dir):
      if f.endsWith(".nim"):
        exec "nim check --hints:off " & f

task playbook, "Regenerate the static self-defense playbook in docs/playbook":
  exec "nim c -d:release --hints:off -o:bin/fightsolve src/fightsolve.nim"
  exec "bin/fightsolve playbook"

task deep, "Run the full deep analysis (hours; all cores; resumable) into docs/playbook":
  exec "nim c -d:release --hints:off -o:bin/fightsolve src/fightsolve.nim"
  exec "bin/fightsolve deep"
