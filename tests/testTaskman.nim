import taskman
import std/unittest
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


template checkTakes(seconds: int, body: untyped): untyped =
  ## Checks that the code following this only takes a certain number of seconds
  ## range: The range in milliseconds that the duration can differ by
  when not declared(tasks):
    let tasks {.inject.} = newScheduler()
  body
  let 
    start = now()
    expectedMilliseconds = seconds * 1000

  tasks.start()
  let diff = (now() - start).inMilliseconds - expectedMilliseconds
  check diff in -2.. 2


test "Run every interval":
  checkTakes 25:
    tasks.every(5.seconds) do ():
      onlyRun(5 + 1) # Plus 1 since it runs initially without wait

test "Run at certain time":
  let time = now() + 10.seconds
  sleep 5000
  checkTakes 5:
    tasks.at(time) do (): discard

test "Run in a certain amount of time":
  checkTakes 5:
    tasks.wait(5.seconds) do (): discard

test "Only run certain number of times":
  checkTakes 2: # Should only take two seconds since it runs initially
    tasks.every(1.seconds) do ():
      onlyRun 3

test "Error handler can reschedule":
  let tasks = newScheduler() do (tasks: Scheduler, task: Task, exception: ref Exception):
    # Echo exception and then reschedule the task to run in 5 seconds
    task.startTime = getTime() + 5.seconds
  checkTakes 5:
    tasks.every(5.minutes) do ():
      onlyRun 2
      raise (ref Exception)(msg: "Working")


when defined(testCron): 
  # Since it takes minimum 1 for a cron task to run we will put it behind a flag
  suite "Cron":
    test "* * * * *":
      checkTakes 5 * 60:
        tasks.every(cron(x, x, x, x, x)) do ():
          onlyRun(5)
          
