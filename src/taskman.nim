import asyncdispatch
import std/[
  times,
  heapqueue,
  os,
]

when compileOption("threads"):
  type TaskHandler* = proc () {.gcsafe.}
else:
  type TaskHandler* = proc ()

type
    Task[T: HandlerTypes] = ref object
      handler*: T
      startTime*: Time
      name*: string
      case oneShot*: bool # Whether the task runs repeatedly or only once
      of false:
        interval*: TimeInterval
      of true: discard
        
    AsyncTaskHandler* = proc (): Future[void] {.async.}

    ErrorHandler*[T]  = proc (task: var Task[T], exception: ref Exception)
      ## The error handler will be called when a task raises an exception.
      ## Can be used to reschedule a proc earlier or to just ignore errors
    HandlerTypes*     = AsyncTaskHandler | TaskHandler

    SchedulerBase[T: HandlerTypes] = ref object
      tasks*: HeapQueue[Task[T]]
      errorHandler*: ErrorHandler[T]
        
    Scheduler* = SchedulerBase[TaskHandler]
    AsyncScheduler* = SchedulerBase[AsyncTaskHandler]

    RemoveTaskException* = CatchableError

const defaultTaskName* {.strdefine.} = "task" ## Default name for a task

proc `<`(a, b: Task): bool {.inline.} = a.startTime < b.startTime

proc `==`(a, b: Task): bool {.inline.} =
  a.handler == b.handler

proc defaultErrorHandler*[T](task: var Task[T], exception: ref Exception) =
  ## Default error handler, just raises the error also
  raise exception

func newScheduler(kind: typedesc[HandlerTypes]): SchedulerBase[kind] =
  SchedulerBase[kind](
    tasks: initHeapQueue[Task[kind]](),
    errorHandler: defaultErrorHandler
  )

func newScheduler*(): Scheduler = 
  ## Creates a sync version of Scheduler_
  newScheduler(TaskHandler)
  
func newAsyncScheduler*(): AsyncScheduler = 
  ## Creates an async version of Scheduler_
  newScheduler(AsyncTaskHandler)

func len*[T: HandlerTypes](scheduler: SchedulerBase[T]): int {.inline.} =
  ## Returns number of tasks in the scheduler
  scheduler.tasks.len

proc newTask*[T: HandlerTypes](interval: TimeInterval, handler: T, name = defaultTaskName): Task[T] =
  ## Creates a new task which can be added to a scheduler.
  ## This task will run every `interval`
  Task[T](
      handler: handler,
      interval: interval,
      startTime: getTime(),
      oneShot: false,
      name: name
  )

proc newTask*[T: HandlerTypes](time: DateTime, handler: T, name = defaultTaskName): Task[T] =
  ## Creates a new task which can be added to a scheduler.
  ## This task will only run once (will run at **time**)
  Task[T](
    handler: handler,
    startTime: time.toTime(),
    oneshot: true,
    name: name
  )

proc add*[T](scheduler: SchedulerBase[T], task: Task[T]) {.inline.} =
  ## Adds a task to the scheduler.
  scheduler.tasks.push task

proc every*[T](scheduler: SchedulerBase[T]; interval: TimeInterval, handler: T, name = defaultTaskName) =
  ## Runs a task every time the interval occurs.
  runnableExamples:
    let tasks = newAsyncScheduler()

    tasks.every(5.seconds) do () {.async.}:
      echo "5 seconds has passed, see you again in 5 seconds"

    tasks.every(2.hours) do () {.async.}:
      echo "2 hours has passed, see you again in 2 hours"

  scheduler &= newTask(interval, handler, name)

proc at*[T](scheduler: SchedulerBase[T], time: DateTime, handler: T, name = defaultTaskName) =
  ## Runs a task at a certain date/time (only runs once).
  runnableExamples:
    let tasks = newAsyncScheduler()

    tasks.at("2077-03-06".parse("yyyy-MM-dd")) do () {.async.}:
      echo "The date is now 2077-03-06"

  scheduler &= newTask(time, handler, name)

proc wait*[T](scheduler: SchedulerBase[T], interval: TimeInterval, handler: T, name = defaultTaskName) =
  ## Waits `interval` amount of time and then runs task (only runs once).
  runnableExamples:
    import std/httpclient
    let tasks = newAsyncScheduler()
    let client = newAsyncHttpClient()
    # I need to send message reminder in a few minutes
    tasks.wait(5.minutes) do () {.async.}:
      asyncCheck client.post("http://notificationurl.com", "Your reminder message")

  scheduler.at(now() + interval, handler, name)

proc milliSecondsLeft[T](task: Task[T]): int =
  ## Returns time different in milliseconds between now and the tasks start time
  result = int((task.startTime - getTime()).inMilliseconds)

proc del*[T](scheduler: SchedulerBase[T], task: Task[T]) =
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

proc del*[T](scheduler: SchedulerBase[T], task: string) =
  ## Removes a task from the scheduler (via its name).
  ## If there are multiple tasks with the same name then the first task is deleted
  runnableExamples:
    let tasks = newScheduler()
    tasks.every(5.minutes, name = "time pass") do ():
      echo "Time has passed"
    tasks.del "time pass"
    doAssert tasks.len == 0

  for i in 0..<scheduler.len:
    if scheduler.tasks[i].name == task:
      scheduler.tasks.del i

proc removeTask*() =
  ## Is used in a running task to make it not be called again.
  ## (Two tasks are considered equal if they have the same handler proc even if the times are different so this might cause issues)
  runnableExamples:
    let tasks = newScheduler()
    var i = 0
    tasks.every(5.seconds) do ():
      if i == 5:
        # Stop the task after the fifth time it has ran and never run it again
        removeTask()
      else:
        # Do important stuff
        inc i

  raise newException(RemoveTaskException, "")

template onlyRun*(times: int) =
  ## Make task only run a certain number of times
  runnableExamples:
    let tasks = newScheduler()
    tasks.every(5.seconds) do:
      onlyRun(5) # This is like the example in removeTask

  var timesRan {.global.} = 0
  defer:
    if timesRan == times:
      removeTask()
    else:
      inc timesRan

proc start*(scheduler: AsyncScheduler | Scheduler) {.multisync.} =
  ## Starts running the tasks.
  ## Call with `asyncCheck` to make it run in the background
  const isAsync = scheduler is AsyncScheduler
  while scheduler.len > 0:
    when isAsync: # Check if in async
      await sleepAsync scheduler.tasks[0].milliSecondsLeft
    else:
      sleep scheduler.tasks[0].milliSecondsLeft
    var currTask = scheduler.tasks.pop()
    if getTime() >= currTask.startTime:
      if not currTask.oneShot:
        # Schedule task again
        currTask.startTime = getTime() + currTask.interval
        scheduler &= currTask

      try:
        # TODO: Add ability to spawn task in seperate thread for non async version
        await currTask.handler()
      except RemoveTaskException:
        scheduler.del currTask
      except Exception as e:
        echo "Error with task"
        e.msg = "Error with task '" & currTask.name & "': " & e.msg
        scheduler.errorHandler(currTask, e)
    else:
      # Add task back so it can be waited on again
      scheduler &= currTask


when isMainModule:
  let tasks = newAsyncScheduler()

  let now = now()
  tasks.every(1.seconds) do () {.async.}:
    echo "Hello"
    echo (now() - now).inSeconds

  waitFor tasks.start()

export times
export asyncdispatch
