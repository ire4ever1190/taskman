import taskman
import std/[unittest, asyncdispatch]
import std/os
import std/monotimes

template sinceLast(): Duration =
  ## Returns time since it was last called (technically not called since it is a template but you get the idea)
  block:
    var lastTime {.global.}: MonoTime
    once:
        lastTime = getMonoTime()
    let currTime = getMonoTime()
    let sinceLast = currTime - lastTime
    lastTime = currTime
    sinceLast

template checkTakes(seconds: int, range = -50..50): untyped =
  ## Checks that the code following this only takes a certain number of seconds
  ## range: The range in milliseconds that the duration can differ by
  let start = now()
  defer:
    tasks.start()
    let diff = (now() - start).inMilliseconds - (seconds * 1000)
    echo diff
    check diff in range

let tasks = newScheduler()

test "Run every interval":
  checkTakes(25)
  tasks.every(5.seconds) do ():
    onlyRun(5)

test "Run at certain time":
  let time = now() + 10.seconds
  sleep 5000
  checkTakes 5
  tasks.at(time) do (): discard

test "Run in a certain amount of time":
  checkTakes 5
  tasks.wait(5.seconds) do (): discard
