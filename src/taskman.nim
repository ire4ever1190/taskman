
# Check which async to use
const asyncBackend {.strdefine.} = ""
when asyncBackend == "chronos":
  import chronos
  export chronos
else:
  import std/asyncdispatch
  export asyncdispatch
  
import std/[
  times,
  heapqueue,
  os,
  macros
]

when compileOption("threads"):
  {.pragma: threadsafe, gcsafe.}
else:
  {.pragma: threadsafe.}

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
## * every_ When you want a task to run on an interval
## * at_ When you want the task to run once at a certain date (Runs once)
## * wait_ When you want to wait a certain amount of time and then run the task (Runs once)
##

runnableExamples "-r:off":
  let tasks = newScheduler() # or newAsyncScheduler if your tasks are async

  tasks.every(5.minutes) do ():
    echo "This will run every 5 minutes"

  tasks.at("2077-01-1".parse("yyyy-mm-dd")) do ():
    echo "This will run on the 1st of janurary in 2077"

  tasks.wait(10.hours) do ():
    echo "This will run after 10 hours"

  # Block the thread and run tasks when needed
  # Async scheduler can run in background with asyncCheck if you want to run other stuff (e.g. website)
  tasks.start()


type
  # CronPartType = enum

  CronRanges = MinuteRange or HourRange or MonthDayRange or Month or WeekDay
  
  TaskType = enum
    Interval
    OneShot
    CronTask

  Cron* = object
    ## The five star (*) values of a cronjob
    minutes*: set[MinuteRange]
    hours*: set[HourRange]
    monthDays*: set[MonthDayRange]
    months*: set[Month]
    weekDays*: set[WeekDay]
    
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

  RemoveTaskException* = object of CatchableError
    ## Throw this within a task to remove it from the scheduler

  InfiniteCronTask* = object of CatchableError
    ## Gets thrown when a cron task keeps looping
    # TODO: remove, this shouldn't happen ever

const 
  defaultTaskName* {.strdefine.} = "task"
    ## Default name for a task. Will be shown in error messages
  everyMinute* = {0.MinuteRange .. 59}
    ## Use with cron task to run every minute
  everyHour* = {0.HourRange .. 23}
    ## Use with cron task to run every hour
  everyMonthDay* = {1.MonthDayRange .. 31}
    ## use with cron task to run every day in the month
  everyMonth* = {mJan .. mDec}
    ## Use with cron task to run every month
  everyWeekDay* = {dMon .. dSun}
    ## Use with cron task to run every day in the week
  

func min[T](s: set[T]): int =
  ## Returns smallest element that is in set[T]
  for i in s:
    return i.ord

func max[T](s: set[T]): T =
  ## Returns largest element that is in set[T]
  result = T.high
  while result >= T.low:
    if result in s:
      break
    dec result



func `/`*[T: CronRanges](a: set[T], inc: int): set[T] =
  ## Returns a range of values that count up by inc
  runnableExamples:
    # Set of values to run every second day
    assert everyWeekDay / 2 == {dMon, dWed, dFri, dSun} 
    # Only use every third hour in our range
    assert {5.HourRange .. 15} / 4 == {5.HourRange, 9, 13}

  var curr = a.min
    # Highest value that is currently in the set, don't go past it
  let max = a.max.ord

  while curr <= max:
    if T(curr) in a:
      result.incl T(curr)
    let next = curr.int + inc
    # Check if the next value is valid in the full range
    if next >= T.low.int and next <= T.high.int:
      curr = curr.int + inc
    else:
      break


func incField[T: CronRanges](s: set[T], curr: T): int =
  ## Returns the value needed to increment a field to the next value.
  ## If the value wraps around then it returns a large enough value to cause that wrap around
  for item in s:
    if item >= curr:
      return item.ord - curr.ord
  return (T.high.int - curr.ord) + s.min
  
func monthDays(d: DateTime): set[MonthDayRange] =
  {1.MonthDayRange .. d.month.getDaysInMonth(d.year)}

func initCron*(minutes = everyMinute, hours = everyHour, monthDays = everyMonthDay, months = everyMonth, weekDays = everyWeekDay): Cron =
  ## Makes a new cron timer
  runnableExamples:
    let everySecondSecond = initCron(minutes = {0.MinuteRange})
  template res(field: untyped) =
    ## Updates field in result with parameter of same name 
    doAssert field.len > 0, "Can't have no valid values in set"
    result.field = field
  res minutes
  res hours
  res monthDays
  res months
  res weekDays


proc translateCronNode(nodes: NimNode, every: NimNode): NimNode =
  ## Translates the DSL into actual NimNode
  let rangeType = every.getTypeImpl[1]
  
  case nodes.kind:
  of nnkIdent, nnkSym:
    if nodes.eqIdent("x"):
      result = every
    else:
      result = nnkCurly.newTree nodes
  of nnkIntLit:
    result = nnkCurly.newTree(
        nnkCast.newTree(rangeType, nodes)
    )
  of nnkInfix:
    case nodes[0].strVal:
    of "-": # Range
      if nodes[2].kind == nnkInfix:
        "Both values in range must be numbers. If combining with `/` then make sure range is in brackets e.g. (5-10) / 2".error(nodes)

      result = nnkCurly.newTree(
        nnkInfix.newTree(
          ident "..",
          nnkCast.newTree(rangeType, nodes[1]),
          nnkCast.newTree(rangeType, nodes[2])
        )
      )
    of "/": # Count
      result = nnkInfix.newTree(
        ident "/",
        translateCronNode(if nodes[1].kind != nnkPar: nodes[1] else: nodes[1][0], every),
        nodes[2]
      )
    else:
      "Invalid operator only - , / are allowed".error(nodes)
  of nnkCurly: # Set 
    result = nodes
    if nodes.len > 0:
      nodes[0] = nnkCast.newTree(rangeType, nodes[0])
    else:
      "Empty set doesn't make sense".error(nodes)
  else:
    "Invalid syntax, check docs for how to use cron macro".error(nodes)  

var x: int # We need some symbol to exist for the default value
macro cron*(minutes, hours, monthDays, months, weekDays: untyped = x): Cron =
  ## Macro to simplify creating cron formats. 
  ## Syntax is similar to cron
  ##
  ## * `/`: Define count
  ## * `{}`: Provide list of values
  ## * `-`: Define range
  ## * `x`: Specify any value
  runnableExamples:
    assert cron(x, x, x, x, x) == initCron() # * * * * *
    assert cron(minutes = 5) == initCron(minutes = {5.MinuteRange}) # 5 * * * *

    # Do between minutes of 5 and 10 during either 1 am or 5 am
    # do this every second day of the month
    assert cron(5 - 10, {1, 5}, x / 2, x, x) == initCron(
      {5.MinuteRange .. 10},
      {1.HourRange, 5}, 
      everyMonthDay / 2
    )
    
  result = nnkCall.newTree bindSym("initCron")
  result &= translateCronNode(minutes, bindSym("everyMinute"))
  result &= translateCronNode(hours, bindSym("everyHour"))
  result &= translateCronNode(monthDays, bindSym("everyMonthDay"))
  result &= translateCronNode(months, bindSym("everyMonth"))
  result &= translateCronNode(weekDays, bindSym("everyWeekDay"))
  
func matches(date: DateTime, format: Cron): bool =
  ## Returns true if date matches for format
  date.minute in format.minutes and 
  date.hour in format.hours and 
  date.monthDay in format.monthDays and 
  date.month in format.months and 
  date.weekday in format.weekDays

var doPrint* = false

func possibleDays(allowedDays: set[WeekDay], date: DateTime): set[MonthDayRange] =
  for monthDay in date.monthDays:
    let day = monthDay.getDayOfWeek(date.month, date.year)
    if day in allowedDays:
      result.incl monthDay

# From https://github.com/soasme/nim-schedules/blob/master/src/schedules/cron/cron.nim#L201
proc ceil(dt: DateTime): DateTime =
  result = dt
  # Round to next second
  if dt.nanosecond > 0:
    result -= initTimeInterval(nanoseconds=dt.nanosecond)
    result += initTimeInterval(seconds=1)
  # Round to next minute
  if dt.second > 0:
    result += initTimeInterval(seconds=(60 - dt.second))

const maxYears {.intdefine.} = 3 # Max years to search ahead to find cron time
proc next*(now: DateTime, format: Cron): DateTime =
  ## Returns next date that a cron would run from now
  # Implementation from here
  # https://github.com/robfig/cron/blob/master/spec.go#L58
  # Idea is to 
  # * Go through each field from largest (month) to smallest (minute)
  #   and If the field doesnt match the format then reset the other fields to zero (only if not zeroed before) and increment to next
  #   valid value
  # * Continiously do this until the format matches

  var zerod = false
  let maxYear = now.year + maxYears
  result = now

  # If the format currently matches the date then increment
  # it to the next minute.
  if result.matches(format):
    result += 1.minutes
    # Truncate the smaller values so it doesn't get ceiled.
    # For some reason putting the ceil in an else block breaks stuff
    result -= result.nanosecond.nanoseconds
    result -= result.second.seconds
    
  result = result.ceil()
  while not result.matches(format) and now.year <= maxYear:
    block wrap:
      # TODO: Optimise, be smarter in finding next value instead of looping
      while (result.month notin format.months):
        if not zerod:
          zerod = true
          result = dateTime(result.year, result.month, 1)
        result += 1.months
        if result.month == mJan:
          break wrap
          
      while (result.monthDay notin format.monthDays or result.weekDay notin format.weekDays):
        if not zerod:
          zerod = true
          result = dateTime(result.year, result.month, result.monthDay)
        result += 1.days
        if result.monthDay == 1:
          break wrap

      while (result.hour notin format.hours):
        if not zerod:
          zerod = true
          result = dateTime(result.year, result.month, result.monthDay, result.hour)
        result += 1.hours
        if result.hour == 0:
          break wrap

      while (result.minute notin format.minutes):
        if not zerod:
          zerod = true
        result += 1.minutes
        if result.minute == 0:
          break wrap
          

func `<`(a, b: TaskBase[HandlerTypes]): bool {.inline.} = a.startTime < b.startTime
func `==`(a, b: TaskBase[HandlerTypes]): bool {.inline.} = a.handler == b.handler

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

proc len*(scheduler: SchedulerBase[HandlerTypes]): int {.inline.} =
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

  
export times
when isMainModule:
  let s = {1.MonthDayRange, 10, 12}
  echo s.incField(13)
