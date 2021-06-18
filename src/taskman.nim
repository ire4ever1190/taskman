import asyncdispatch
import times

type
    ScheduleProc = proc (): Future[void] {.async}
    Task = ref object
        handler: ScheduleProc
        interval: TimeInterval
        startTime: Time

    Scheduler = ref object
        tasks: seq[Task]
        futures: seq[Future[void]] # Store the futures so there are still things registered

func newScheduler*(): Scheduler =
    Scheduler(
        tasks: newSeq[Task]()
    )

proc newTask*(handler: ScheduleProc, interval: TimeInterval): Task =
    Task(
        handler: handler,
        interval: interval,
        startTime: getTime()
    )

proc idle(self: Scheduler) {.async.} =
  ## Idle the scheduler. It prevents the scheduler from shutdown when no beats is running.
  while true:
    await sleepAsync(1000)

proc every*(scheduler: Scheduler, interval: TimeInterval, task: proc () {.async.}) =
    scheduler.tasks &= newTask(task, interval)

proc millisecondsLeft(task: Task): int =
    ## Returns time different in seconds between now and the tasks start time
    result = int (task.startTime - getTime()).inMilliseconds

proc run*(task: Task) {.async.} =
    ## Starts the task in the background
    while true:
        if getTime() >= task.startTime:
            task.startTime = getTime() + task.interval
            try:
                await task.handler()
            except:
                echo "Error with task"
                echo getCurrentException().msg
        await sleepAsync task.milliSecondsLeft

proc start*(scheduler: Scheduler) {.async.} =
    ## Runs all the tasks in the background
    for task in scheduler.tasks:
        let future = task.run()
        scheduler.futures.add future
        asyncCheck future

when isMainModule:
    let tasks = newScheduler()
    tasks.every(2.seconds) do () {.async.}:
        echo "tock"
    waitFor tasks.start()
    runForever()

export times