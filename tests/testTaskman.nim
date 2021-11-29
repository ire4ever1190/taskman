import taskman
import std/[unittest, asyncdispatch]
import std/os

template sinceLast(): Duration =
  ## Returns time since it was last called (technically not called since it is a template but you get the idea)
  block:
    var lastTime {.global.}: Time
    once:
        lastTime = getTime()
    let currTime = getTime()
    let sinceLast = currTime - lastTime
    lastTime = currTime
    sinceLast

template checkTakes(seconds: int): typed =
  ## Checks that the code following this only takes a certain number of seconds
  let start = now()
  defer:
    waitFor tasks.start()
    check (now() - start).inSeconds == seconds

let tasks = newScheduler()

test "Run every interval":
  checkTakes(25)
  tasks.every(5.seconds) do () {.async.}:
    onlyRun(5)
    echo sinceLast.inSeconds()

test "Run at certain time":
  let time = now() + 10.seconds
  sleep 5000
  checkTakes 5
  tasks.at(time) do () {.async.}: discard

test "Run in a certain amount of time":
  checkTakes 5
  tasks.wait(5.seconds) do () {.async.}: discard