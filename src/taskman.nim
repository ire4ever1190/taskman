import asyncdispatch
import std/[
  times,
  heapqueue,
  os,
]

when compileOption("threads"):
  {.pragma: threadsafe, gcsafe.}
else:
  {.pragma: threadsafe.}

##
## This package can be used for simple tasks that need to run on an interval or at a certain time.
##

type
    TaskBase*[T: HandlerTypes] = ref object
      ## * **handler**: The proc that handles the task being called
      ## * **startTime**: The time that the task should be called
      ## * **name**: The name of the task, useful for debugging with error messages (default is defaultTaskName_)
      ## * **oneShot**: Whether the task only runs once (true) or runs continuiously (false)
      handler*: T
      startTime*: Time
      name*: string
      case oneShot*: bool # Whether the task runs repeatedly or only once
      of false:
        interval*: TimeInterval
      of true: discard
        
    AsyncTaskHandler* = proc (): Future[void] {.threadsafe.}
      ## Proc that runs in an async scheduler
      ##
      ## .. Note::When using `--threads:on` the proc must be gcsafe

    TaskHandler* = proc () {.threadsafe.}
      ## Proc that runs in a normal scheduler
      ##
      ## .. Note::When using `--threads:on` the proc must be gcsafe


    ErrorHandler*[T] = proc (s: SchedulerBase[T], task: TaskBase[T], exception: ref Exception) {.threadsafe.}
      ## The error handler will be called when a task raises an exception.
      ## Can be used to do things like reschedule a proc to be called earlier or to just ignore errors

    HandlerTypes* = AsyncTaskHandler | TaskHandler

    SchedulerBase*[T: HandlerTypes] = ref object
      tasks*: HeapQueue[TaskBase[T]]
      errorHandler*: ErrorHandler[T]

    Scheduler* = SchedulerBase[TaskHandler]
    AsyncScheduler* = SchedulerBase[AsyncTaskHandler]

    Task* = TaskBase[TaskHandler]
    AsyncTask* = TaskBase[AsyncTaskHandler]

    RemoveTaskException* = CatchableError

const defaultTaskName* {.strdefine.} = "task"
  ## Default name for a task

proc `<`[T: HandlerTypes](a, b: TaskBase[T]): bool {.inline.} = a.startTime < b.startTime

proc `==`[T: HandlerTypes](a, b: TaskBase[T]): bool {.inline.} =
  a.handler == b.handler

proc defaultErrorHandler[T: HandlerTypes](tasks: SchedulerBase[T], task: TaskBase[T],  exception: ref Exception) =
  ## Default error handler, just raises the error further up the stack
  raise exception

proc newSchedulerBase[T: HandlerTypes](errorHandler: ErrorHandler[T]): SchedulerBase[T] =
  SchedulerBase[T](
    tasks: initHeapQueue[TaskBase[T]](),
    errorHandler: errorHandler
  )

proc newScheduler*(errorHandler: ErrorHandler[TaskHandler] = defaultErrorHandler[TaskHandler]): Scheduler =
  ## Creates a sync version of Scheduler_
  runnableExamples:
    # By default exceptions are raised
    let tasks = newScheduler()
    # But it can be overridden
    let tasksError = newScheduler() do (s: Scheduler, task: Task, exception: ref Exception):
      ## Echo exception and then reschedule the task to run in 5 seconds
      # Scheduler is passed so that the error handler can be its own proc
      # and used in multiple schedulers and also be gcsafe
      echo exception.msg
      task.startTime = getTime() + 5.seconds

  newSchedulerBase[TaskHandler](errorHandler)
  
proc newAsyncScheduler*(errorHandler: ErrorHandler[AsyncTaskHandler] = defaultErrorHandler[AsyncTaskHandler]): AsyncScheduler =
  ## Creates an async version of Scheduler_.
  ## See newScheduler_ for more details
  newSchedulerBase[AsyncTaskHandler](errorHandler)

proc len*[T: HandlerTypes](scheduler: SchedulerBase[T]): int {.inline.} =
  ## Returns number of tasks in the scheduler
  scheduler.tasks.len

proc newTask*[T: HandlerTypes](interval: TimeInterval, handler: T, name = defaultTaskName): TaskBase[T] =
  ## Creates a new task which can be added to a scheduler.
  ## This task will run every `interval`
  TaskBase[T](
      handler: handler,
      interval: interval,
      startTime: getTime(),
      oneShot: false,
      name: name
  )

proc newTask*[T: HandlerTypes](time: DateTime, handler: T, name = defaultTaskName): TaskBase[T] =
  ## Creates a new task which can be added to a scheduler.
  ## This task will only run once (will run at **time**)
  TaskBase[T](
    handler: handler,
    startTime: time.toTime(),
    oneshot: true,
    name: name
  )

proc add*[T: HandlerTypes](scheduler: SchedulerBase[T], task: TaskBase[T]) {.inline.} =
  ## Adds a task to the scheduler.
  scheduler.tasks.push task

proc every*[T: HandlerTypes](scheduler: SchedulerBase[T]; interval: TimeInterval, handler: T, name = defaultTaskName) =
  ## Runs a task every time the interval occurs.
  runnableExamples:
    let tasks = newAsyncScheduler()

    tasks.every(5.seconds) do () {.async.}:
      echo "5 seconds has passed, see you again in 5 seconds"

    tasks.every(2.hours) do () {.async.}:
      echo "2 hours has passed, see you again in 2 hours"

  scheduler &= newTask(interval, handler, name)

proc at*[T: HandlerTypes](scheduler: SchedulerBase[T], time: DateTime, handler: T, name = defaultTaskName) =
  ## Runs a task at a certain date/time (only runs once).
  runnableExamples:
    let tasks = newAsyncScheduler()

    tasks.at("2077-03-06".parse("yyyy-MM-dd")) do () {.async.}:
      echo "The date is now 2077-03-06"

  scheduler &= newTask(time, handler, name)

proc wait*[T: HandlerTypes](scheduler: SchedulerBase[T], interval: TimeInterval, handler: T, name = defaultTaskName) =
  ## Waits `interval` amount of time and then runs task (only runs once).
  runnableExamples:
    import std/httpclient
    let tasks = newAsyncScheduler()
    let client = newAsyncHttpClient()
    # I need to send message reminder in a few minutes
    tasks.wait(5.minutes) do () {.async.}:
      asyncCheck client.post("http://notificationurl.com", "Your reminder message")

  scheduler.at(now() + interval, handler, name)

proc milliSecondsLeft[T: HandlerTypes](task: TaskBase[T]): int =
  ## Returns time different in milliseconds between now and the tasks start time
  result = int((task.startTime - getTime()).inMilliseconds)

proc del*[T: HandlerTypes](scheduler: SchedulerBase[T], task: TaskBase[T]) =
  ## Removes a task from the scheduler
  runnableExamples:
    import std/sugar
    # Create task that echos "hello" every 5 seconds
    let tasks = newScheduler()
    proc sayHello() =
      echo "Hello"
    let task = newTask[TaskHandler](5.seconds, sayHello, name = "Hello world")
    tasks &= task
    # Run scheduler in background, do other stuff
    # Then the task can be deleted anytime later
    tasks.del task
    doAssert tasks.len == 0

  let index = scheduler.tasks.find task
  scheduler.tasks.del index

proc del*[T: HandlerTypes](scheduler: SchedulerBase[T], task: string) =
  ## Removes a task from the scheduler (via its name).
  ## If there are multiple tasks with the same name then the first task is deleted
  runnableExamples:
    let tasks = newScheduler()
    proc handler() =
      echo "Time has passed"
    tasks.every(5.minutes, handler, name = "time pass")
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
    tasks.every(5.seconds) do ():
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
        await currTask.handler()
      except RemoveTaskException:
        scheduler.del currTask
      except Exception as e:
        e.msg = "Error with task '" & currTask.name & "': " & e.msg
        scheduler.errorHandler(scheduler, currTask, e)
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
