import asyncdispatch
import times
import std/heapqueue

type
    Task = object
        handler: TaskHandler
        startTime: Time
        case oneShot: bool # Whether the task runs repeatedly or only once
        of false:
          interval: TimeInterval
        of true: discard

    TaskHandler = proc (): Future[void] {.async.}

    Scheduler = ref object
        tasks: HeapQueue[Task]

    RemoveTaskException = CatchableError

using scheduler: Scheduler

proc `<`(a, b: Task): bool {.inline.} = a.startTime < b.startTime

proc `==`(a, b: Task): bool {.inline.} =
  a.handler == b.handler

func newScheduler*(): Scheduler =
    Scheduler(
        tasks: initHeapQueue[Task]()
    )

func len*(scheduler): int {.inline.} = 
  ## Returns number of tasks in the scheduler
  scheduler.tasks.len

proc newTask*(interval: TimeInterval, handler: TaskHandler): Task =
    ## Creates a new task which can be added to a scheduler.
    ## This task will run every `interval`
    Task(
        handler: handler,
        interval: interval,
        startTime: getTime(),
        oneShot: false
    )

proc newTask*(time: DateTime, handler: TaskHandler): Task =
    ## Creates a new task which can be added to a scheduler.
    ## This task will only run once
    Task(
      handler: handler,
      startTime: time.toTime(),
      oneshot: true
    )

proc add*(scheduler; task: Task) {.inline.} =
    ## Adds a task to the scheduler.
    scheduler.tasks.push task

proc every*(scheduler; interval: TimeInterval, task: TaskHandler) =
    ## Runs a task every time the interval happens.
    runnableExamples:
        let tasks = newScheduler()

        tasks.every(5.seconds) do () {.async.}:
            echo "5 seconds has passed, see you again in 5 seconds"

        tasks.every(2.hours) do () {.async.}:
            echo "2 hours has passed, see you again in 2 hours"

    scheduler &= newTask(interval, task)

proc at*(scheduler; time: DateTime, task: TaskHandler) =
    ## Runs a task at a certain time (only runs once).
    runnableExamples:
        let tasks = newScheduler()

        tasks.at("2077-03-06".parse("yyyy-MM-dd")) do () {.async.}:
            echo "The date is now 2077-03-06"

    scheduler &= newTask(time, task)

proc wait*(scheduler; interval: TimeInterval, task: TaskHandler) =
    ## Waits `interval` amount of time and then runs task (only runs once).
    runnableExamples:
        import std/httpclient
        let tasks = newScheduler()
        let client = newAsyncHttpClient()
        # I need to send message reminder in a few minutes
        tasks.wait(5.minutes) do () {.async.}:
            asyncCheck client.post("http://notificationurl.com", "Your reminder message")

    scheduler.at(now() + interval, task)

proc milliSecondsLeft(task: Task): int =
    ## Returns time different in milliseconds between now and the tasks start time
    result = int((task.startTime - getTime()).inMilliseconds)

proc del*(scheduler; task: Task) =
    ## Removes a task from the scheduler
    runnableExamples:
      # Create task that echos "hello" every 5 seconds 
      let tasks = newScheduler()
      let task = newTask(5.seconds) do () {.async.}:
        echo "hello"
      tasks &= task
      # Run scheduler in background, do other stuff
      tasks.del task
      doAssert tasks.len == 0
    let index = scheduler.tasks.find task
    scheduler.tasks.del index

proc removeTask*() =
    ## Is used in a running task to make it not be called again.
    ## (Two tasks are considered equal if they have the same handler proc even if the times are different so this might cause issues)
    runnableExamples:
        let tasks = newScheduler()
        var i = 0
        tasks.every(5.seconds) do () {.async.}:
            if i == 5:
                # Stop the task after the fifth time it has ran and never run it again
                removeTask()
            else:
                # Do important stuff
                inc i
    raise newException(RemoveTaskException, "")

template onlyRun*(times: int) =
  ## Make task only run a certain number of times
  runnablesExamples:
    let tasks = newScheduler()
    tasks.every(5.seconds) do {.async.}:
      onlyRun(5) # This is like the example in removeTask
  var timesRan {.global.} = 0
  defer:
    if timesRan == times:
        removeTask()
    else:
        inc timesRan

proc start*(scheduler) {.async.} =
    ## Starts running the tasks.
    ## Call with `asyncCheck` to make it run in the background
    while scheduler.len > 0:        
        await sleepAsync scheduler.tasks[0].milliSecondsLeft
        var currTask = scheduler.tasks.pop()
        if getTime() >= currTask.startTime:
            if not currTask.oneShot:
                # Schedule task again
                currTask.startTime = getTime() + currTask.interval
                scheduler &= currTask

            try:
                await currTask.handler()
            except RemoveTaskException:
                scheduler.del currTask
            except:
                echo "Error with task"
                echo getCurrentException().msg
        else:
          # Add task back so it can be waited on again
          scheduler &= currTask


when isMainModule:
    let tasks = newScheduler()

            
    # tasks.every(2.seconds) do () {.async.}:
    #     echo "tock, ", sinceLast()
    #
    # tasks.every(3.seconds) do () {.async.}:
    #     echo "tick, ", sinceLast()
    let now = now()
    tasks.wait(5.seconds) do () {.async.}:
        echo "Hello"
        echo (now() - now).inSeconds

    waitFor tasks.start()

export times
export asyncdispatch
