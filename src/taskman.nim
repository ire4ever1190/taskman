import std/asyncdispatch
export asyncdispatch

import std/[
  times,
  heapqueue,
  os,
  macros,
  monotimes
]

import taskman/cron

##
## This package can be used for simple tasks that need to run on an interval or at a certain time.
##
## It has both an async and non-async api (They are similar, only difference being in creation of scheduler)
##
## Making tasks
## ============
##
## The main procs for creating tasks are
##
## * every_ When you want a task to run on an interval (First run is when start() is called)
## * at_ When you want the task to run once at a certain date (Runs once)
## * wait_ When you want to wait a certain amount of time and then run the task (Runs once)
##

runnableExamples "-r:off":
  let tasks = newAsyncScheduler() # or newScheduler if you don't want to use async

  tasks.every(5.minutes) do () {.async.}:
    echo "This will run every 5 minutes"

  tasks.at("2077-01-1".parse("yyyy-mm-dd")) do () {.async.}:
    echo "This will run on the 1st of janurary in 2077"

  tasks.wait(10.hours) do () {.async.}:
    echo "This will run after 10 hours"

  # Block the thread and run tasks when needed
  # asyncCheck could be used instead e.g. so you can have a web server running also
  # You could also put it onto another thread
  waitFor tasks.start()

## By default the scheduler will end when all tasks are finished (i.e. every `at` and `wait` task has completed). It also will run tasks late if
## they are added while the scheduler is sleeping while waiting for a tasks start time. To change this behaviour you can add a `periodicCheck` parameter
## to the start function which will make the scheduler check every `periodicCheck` seconds for which task it should be waiting on

runnableExamples "-r:off":
  let tasks = newAsyncScheduler()

  proc main() {.async.} =
    tasks.every(10.minutes) do () {.async.}:
      echo "10 minutes has passed"
    asyncCheck tasks.start(100) # The scheduler will check every 100 milliseconds for new tasks

    # If we didn't have the periodicCheck passed before then this task would only run after
    # the 10 minutes task before has ran
    tasks.wait(5.seconds) do () {.async.}:
      echo "5 seconds has passed"

  waitFor main()


## Deleting Tasks
## ==============
##
## Tasks can be directly removed using del_

runnableExamples:
  let
    tasks = newScheduler()
    taskA = newTask[TaskHandler](5.seconds, proc () = echo "hello")

  tasks &= taskA
  tasks.every(1.days, (proc () = echo "A new dawn appears"), name = "newDay")
  assert tasks.len == 2

  # Tasks can be deleted either with their name or using the original task obj
  tasks.del taskA
  tasks.del "newDay"
  assert tasks.len == 0

## If inside a task, then removeTask_ can be used to remove the current task (This is just a helper to raise RemoveTaskException_).
## onlyRun_ is another helper which calls removeTask_ after a task has run a certain number of times
runnableExamples:
  let tasks = newScheduler()

  tasks.every(1.milliseconds) do ():
    if true:
      echo "I don't want to run anymore"
      removeTask() #

  tasks.every(1.milliseconds) do ():
    if not false:
      raise (ref RemoveTaskException)()

  var i = 1
  tasks.every(1.nanoseconds) do ():
    onlyRun(3)
    # This task will only run three times (Terminates at the end of the 3 run)
    echo i
    inc i

  assert tasks.len == 3
  tasks.start() # Tasks will be deleted when ran in this scenario
  assert tasks.len == 0


## Cron
## ====
##
## For more advanced intervals you can instead use cron timers
##
runnableExamples:
  let tasks = newScheduler()

  # Just like * * * * *
  tasks.every(cron(x, x, x, x, x)) do ():
    echo "Minute has passed"

  tasks.every(cron(5, 10, x, x, x)) do ():
    echo "It is the 5th minute of the 10th hour"

## See the `cron module <taskman/cron.html>`_ for more info on the syntax

type
  TimerKind = enum
    Interval
    OneShot
    Cron

  TaskBase*[T: HandlerTypes] = ref object
    ## * **handler**: The proc that handles the task being called
    ## * **startTime**: The time that the task should be called
    ## * **name**: The name of the task, useful for debugging with error messages (default is defaultTaskName_)
    ## * **oneShot**: Whether the task only runs once (true) or runs continuiously (false)
    handler*: T
    startTime*: Time
    name*: string
    case kind*: TimerKind
    of Interval:
      interval*: TimeInterval
    of Cron:
      cronFormat*: Cron
    of OneShot: discard

  AsyncTaskHandler* = proc (): Future[void]
    ## Proc that runs in an async scheduler
    ##
    ## .. Note::When using `--threads:on` the proc must be gcsafe

  TaskHandler* = proc ()
    ## Proc that runs in a normal scheduler
    ##
    ## .. Note::When using `--threads:on` the proc must be gcsafe


  ErrorHandler*[T] = proc (s: SchedulerBase[T], task: TaskBase[T], exception: ref Exception)
    ## The error handler will be called when a task raises an exception.
    ## Can be used to do things like reschedule a proc to be called earlier or to just ignore errors

  HandlerTypes* = AsyncTaskHandler | TaskHandler

  SchedulerBase*[T: HandlerTypes] = ref object
    tasks*: HeapQueue[TaskBase[T]]
    running: bool
    errorHandler*: ErrorHandler[T]
    when T is AsyncTaskHandler:
      timer: tuple[finishAt: MonoTime, fut: Future[void]]

  Scheduler* = SchedulerBase[TaskHandler]
  AsyncScheduler* = SchedulerBase[AsyncTaskHandler]

  Task* = TaskBase[TaskHandler]
  AsyncTask* = TaskBase[AsyncTaskHandler]

  RemoveTaskException* = object of CatchableError
    ## Throw this within a task to remove it from the scheduler


const defaultTaskName* {.strdefine.} = "task"
  ## Default name for a task. Will be shown in error messages

func running*(tasks: SchedulerBase): bool {.inline.} =
  ## Returns true if the scheduler is running
  tasks.running

proc wakeUp[T](tasks: SchedulerBase[T]) =
  ## Wakes up the scheduler so that it can check if it is still sleeping on
  ## the earliest task. Only does stuff if async scheduler, noop if not
  when T is AsyncTaskHandler:
    if tasks.timer.fut == nil:
      # We aren't sleeping
      return
    let p = getGlobalDispatcher()
    # First delete it from the dispatcher so it won't try and complete the future again
    let timerIndex = p.timers.find(tasks.timer)
    if timerIndex != -1: # If its -1 then the timer has already been completed
      p.timers.del(timerIndex)
      # Complete the sleep
      tasks.timer.fut.complete()
      # Disarm the timer
      tasks.timer.fut = nil
  else:
    discard

func `<`(a, b: TaskBase[HandlerTypes]): bool {.inline.} = a.startTime < b.startTime
func `==`(a, b: TaskBase[HandlerTypes]): bool {.inline.} = a.handler == b.handler

proc defaultErrorHandler[T: HandlerTypes](tasks: SchedulerBase[T], task: TaskBase[T],  exception: ref Exception) =
  ## Default error handler, just raises the error further up the stack
  raise exception

proc newSchedulerBase*[T: HandlerTypes](errorHandler: ErrorHandler[T] = defaultErrorHandler[T]): SchedulerBase[T] =
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
  #==#
  newSchedulerBase[TaskHandler](errorHandler)

proc newAsyncScheduler*(errorHandler: ErrorHandler[AsyncTaskHandler] = defaultErrorHandler[AsyncTaskHandler]): AsyncScheduler =
  ## Creates an async version of Scheduler_.
  ## See newScheduler_ for more details
  newSchedulerBase[AsyncTaskHandler](errorHandler)

proc len*(scheduler: SchedulerBase): int {.inline.} =
  ## Returns number of tasks in the scheduler
  scheduler.tasks.len

proc newTask*[T: HandlerTypes](interval: TimeInterval, handler: T, name = defaultTaskName): TaskBase[T] =
  ## Creates a new task which can be added to a scheduler.
  ## This task will run every `interval`
  TaskBase[T](
      kind: Interval,
      handler: handler,
      interval: interval,
      startTime: getTime(),
      name: name
  )

proc newTask*[T: HandlerTypes](time: DateTime, handler: T, name = defaultTaskName): TaskBase[T] =
  ## Creates a new task which can be added to a scheduler.
  ## This task will only run once (will run at **time**)
  TaskBase[T](
    kind: OneShot,
    handler: handler,
    startTime: time.toTime(),
    name: name
  )

proc newTask*[T: HandlerTypes](cron: Cron, handler: T, name = defaultTaskName): TaskBase[T] =
  ## Creates a new task which can be added to a scheduler.
  TaskBase[T](
    kind: Cron,
    handler: handler,
    startTime: now().next(cron).toTime(),
    cronFormat: cron,
    name: name
  )

proc add*[T: HandlerTypes](scheduler: SchedulerBase[T], task: TaskBase[T]) {.inline.} =
  ## Adds a task to the scheduler.
  scheduler.tasks.push task
  scheduler.wakeUp()

proc every*[T: HandlerTypes](scheduler: SchedulerBase[T]; interval: TimeInterval, handler: T, name = defaultTaskName) =
  ## Runs a task every time the interval occurs.
  runnableExamples:
    let tasks = newAsyncScheduler()

    tasks.every(5.seconds) do () {.async.}:
      echo "5 seconds has passed, see you again in 5 seconds"

    tasks.every(2.hours) do () {.async.}:
      echo "2 hours has passed, see you again in 2 hours"
  #==#
  scheduler &= newTask(interval, handler, name)


proc every*[T: HandlerTypes](scheduler: SchedulerBase[T], cron: Cron, handler: T, name = defaultTaskName) =
  ## Runs a task every time a cron timer is valid
  runnableExamples:
    let tasks = newAsyncScheduler()

    tasks.every(cron(x, x, x, x, x)) do () {.async.}:
      echo "A minute has passed"
  #==#
  scheduler &= newTask(cron, handler, name)

proc every*[T: HandlerTypes](scheduler: SchedulerBase[T], often: TimeInterval | Cron, name: string, handler: T) =
  ## Sugar that allows you to have name and lambda
  scheduler.every(often, handler, name)

proc at*[T: HandlerTypes](scheduler: SchedulerBase[T], time: DateTime, handler: T, name = defaultTaskName) =
  ## Runs a task at a certain date/time (only runs once).
  runnableExamples:
    let tasks = newAsyncScheduler()

    tasks.at("2077-03-06".parse("yyyy-MM-dd")) do () {.async.}:
      echo "The date is now 2077-03-06"
  #==#
  scheduler &= newTask(time, handler, name)

proc at*[T: HandlerTypes](scheduler: SchedulerBase[T], interval: TimeInterval, name: string, handler: T) =
  ## Sugar that allows you to have name and lambda
  scheduler.at(interval, handler, name)

proc wait*[T: HandlerTypes](scheduler: SchedulerBase[T], interval: TimeInterval, handler: T, name = defaultTaskName) =
  ## Waits `interval` amount of time and then runs task (only runs once).
  runnableExamples "--threads:off":
    import std/httpclient
    let tasks = newAsyncScheduler()
    let client = newAsyncHttpClient()
    # I need to send message reminder in a few minutes
    tasks.wait(5.minutes) do () {.async.}:
      asyncCheck client.post("http://notificationurl.com", "Your reminder message")
  #==#
  scheduler.at(now() + interval, handler, name)

proc wait*[T: HandlerTypes](scheduler: SchedulerBase[T], interval: TimeInterval, name: string, handler: T) =
  ## Sugar that allows you to have name and lambda
  scheduler.wait(interval, handler, name)

proc milliSecondsLeft(task: TaskBase[HandlerTypes]): int =
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
  #==#
  let index = scheduler.tasks.find task
  scheduler.tasks.del index

proc del*(scheduler: SchedulerBase[HandlerTypes], task: string) =
  ## Removes a task from the scheduler (via its name).
  ## If there are multiple tasks with the same name then the first task is deleted
  runnableExamples:
    let tasks = newScheduler()
    proc handler() =
      echo "Time has passed"
    tasks.every(5.minutes, handler, name = "time pass")
    tasks.del "time pass"
    doAssert tasks.len == 0
  #==#
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
  #==#
  raise newException(RemoveTaskException, "")

proc next*(task: TaskBase): Time {.raises: [TooFarAheadCron].} =
  ## Returns the next date that a task will run at (If it ran now).
  ## If the task is a oneShot then it just returns its start time
  case task.kind
  of OneShot: discard
  of Interval:
    result = getTime() + task.interval
  of Cron:
    result = now().next(task.cronFormat).toTime()

template onlyRun*(times: int) =
  ## Make task only run a certain number of times
  runnableExamples:
    let tasks = newScheduler()
    tasks.every(5.seconds) do ():
      onlyRun(5) # This is like the example in removeTask

  var timesRan {.global.} = 1
  defer:
    if timesRan == times:
      removeTask()
    else:
      inc timesRan

proc start*(scheduler: AsyncScheduler | Scheduler, periodicCheck = 0) =
  ## Starts running the tasks.
  ## Call with `asyncCheck` to make it run in the background
  ##
  ## * **periodicCheck**: This prevents the scheduler from fulling stopping and specifies how many milliseconds to poll for new tasks. Also use this with non async scheduler to allow you to add new tasks in that might be shorter than current running one
  const isAsync = scheduler is AsyncScheduler
  scheduler.running = true
  while scheduler.len > 0 or periodicCheck > 0:
    if scheduler.len == 0:
      when not isAsync:
        await sleepAsync(periodicCheck)
      else:
        sleep periodicCheck
      continue # Run loop again to check if stuff has been added while sleeping

    let sleepTime = scheduler.tasks[0].milliSecondsLeft
    when isAsync:
      # This is more or less copy and pasted from async dispatch.
      # But we make a few modifications so that we can effectively cancel the sleeping.
      # This enables us to force the scheduler to check for new tasks when they get added (Instead of needing to poll with periodicCheck)
      var retFuture = newFuture[void]("start")
      let
        p = getGlobalDispatcher()
      scheduler.timer = (getMonoTime() + initDuration(milliseconds = sleepTime), retFuture)
      p.timers.push(scheduler.timer)
      await retFuture
    else:
      # We can't do any fancy sleep cancelling so we need to do this
      if periodicCheck == 0:
        sleep sleepTime
      else:
        sleep periodicCheck
    if scheduler.len > 0:
      var currTask = scheduler.tasks.pop()
      if getTime() >= currTask.startTime:
        if currTask.kind != OneShot:
          # Schedule task again
          currTask.startTime = currTask.next()
          scheduler &= currTask
        try:
          await currTask.handler()
        except RemoveTaskException:
          scheduler.del currTask
        except CatchableError as e:
          e.msg = "Error with task '" & currTask.name & "': " & e.msg
          scheduler.errorHandler(scheduler, currTask, e)
      else:
        # Add task back so it can be waited on again
        scheduler &= currTask

  scheduler.running = false

export times
export cron
