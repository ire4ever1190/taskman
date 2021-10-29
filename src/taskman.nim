import asyncdispatch
import times
import std/heapqueue

type
    ScheduleProc = proc (): Future[void] {.async}
    Task = ref object
        handler: ScheduleProc
        interval: TimeInterval
        startTime: Time

    Scheduler = ref object
        tasks: HeapQueue[Task]

proc `<`(a, b: Task): bool = a.startTime < b.startTime

func newScheduler*(): Scheduler =
    Scheduler(
        tasks: initHeapQueue[Task]()
    )

proc newTask*(handler: ScheduleProc, interval: TimeInterval): Task =
    Task(
        handler: handler,
        interval: interval,
        startTime: getTime()
    )

proc every*(scheduler: Scheduler, interval: TimeInterval, task: proc () {.async.}) =
    scheduler.tasks.push newTask(task, interval)

proc milliSecondsLeft(task: Task): int =
    ## Returns time different in seconds between now and the tasks start time
    result = int (task.startTime - getTime()).inMilliseconds

proc start*(scheduler: Scheduler) {.async.} =
    ## Starts running the tasks.
    ## Call with `asyncCheck` to make it run in the background
    while true:        
        let currTask = scheduler.tasks.pop()
        if getTime() >= currTask.startTime:
            currTask.startTime = getTime() + currTask.interval # Schedule task again
            try:
                await currTask.handler()
            except:
                echo "Error with task"
                echo getCurrentException().msg
        scheduler.tasks.push currTask
        await sleepAsync scheduler.tasks[0].milliSecondsLeft

when isMainModule:
    let tasks = newScheduler()
    template sinceLast(): Duration =
        block:
            var lastTime {.global.}: Time
            once:
                lastTime = getTime()
            let currTime = getTime()
            let sinceLast = currTime - lastTime
            lastTime = currTime
            sinceLast
            
    tasks.every(2.seconds) do () {.async.}:
        echo "tock, ", sinceLast()
        
    tasks.every(3.seconds) do () {.async.}:
        echo "tick, ", sinceLast()
        
    waitFor tasks.start()

export times
