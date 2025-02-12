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
      raise (ref CatchableError)(msg: "Working")

test "Inserting tasks while running works":
  proc main() {.async.} =
    let
      tasks = newAsyncScheduler()
      start = now()
    var finish: DateTime
    tasks.wait(5.seconds) do () {.async.}: discard
    asyncCheck tasks.start()
    await sleepAsync(1000)
    tasks.wait(1.seconds) do () {.async.}: finish = now()

    await sleepAsync(5000)
    # Check that it only took 2 seconds (1 second sleep, 1 second wait task)
    let diff = (finish - start).inMilliseconds - 2000
    check diff in -10..10

  waitFor main()

test "Scheduler won't break when ran out of tasks with check":
  proc main() {.async.} =
    let tasks = newAsyncScheduler()
    asyncCheck tasks.start(5)
    # Check it doesn't error when it has no tasks
    await sleepAsync(100)

  waitFor main()

test "Test issue with timer not being found":
  # If this runs with no errors then its fine
  proc main() {.async.} =
    let tasks = newAsyncScheduler()

    tasks.every(1.seconds) do () {.async.}:
      discard

    tasks.every(2.hours) do () {.async.}:
      discard
    asyncCheck tasks.start()
    await sleepAsync 100
  waitFor main()

test "Can use a closure":
  let tasks = newAsyncScheduler()
  let x = "hello"
  tasks.every(1.seconds) do () {.async.}:
    echo x

test "Can work gcsafe":
  proc mustBeSafe() {.gcsafe.} =
    let tasks = newSchedulerBase[proc () {.gcsafe.}]()
    # let tasks = newScheduler()

    tasks.every(1.seconds) do () {.gcsafe.}:
      discard
    if false:
      tasks.start()

  mustBeSafe()

when defined(testCron):
  # Since it takes minimum 1 for a cron task to run we will put it behind a flag
  suite "Cron":
    test "* * * * *":
      # TODO: Wait til start of minute to start running test
      checkTakes 5 * 60:
        tasks.every(cron(x, x, x, x, x)) do ():
          echo "Minute has passed"
          onlyRun(5)

