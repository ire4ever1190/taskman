import std/[
  times,
  macros,
  sequtils
]

##
## This module implements the cron format for the scheduler.
## Cron formats are defined either with the cron_ macro or initCron_
runnableExamples:
  # * * * * *
  # Default value for each field is every val
  # The cron macro uses x in place of *
  assert initCron() == cron(x, x, x, x, x)

  # 4 10 * * *
  assert initCron({4.MinuteRange}, {10.HourRange}) == cron(4, 10, x, x, x)

  # 4-10 4,5,6 * * sun,mon
  assert initCron(
    {4.MinuteRange .. 10},
    {4.HourRange, 5, 6}, 
    weekDays = {dSun, dMon}
  ) == cron(4 - 10, {4, 5, 6}, weekDays = {dSun, dMon})

  # every second minute
  assert initCron(everyMinute / 2) == cron(minutes = x / 2)

## This implements cron in a slightly non standard way in that both `monthDays` and `weekDays` are checked e.g.
runnableExamples:
  let 
    start = dateTime(2000, mJan, 1)
    form  = cron(x, x, 10, x, dSun)
  # In normal cron it would match 2000-01-10 (Which is a monday)
  assert start.next(form) == dateTime(2000, mSep, 10)

type
  CronRanges = MinuteRange or HourRange or MonthDayRange or Month or WeekDay

  Cron* = object
    ## The five star (*) values of a cronjob
    minutes*: set[MinuteRange]
    hours*: set[HourRange]
    monthDays*: set[MonthDayRange]
    months*: set[Month]
    weekDays*: set[WeekDay]

  TooFarAheadCron* = object of CatchableError
    ## Called in the rare case that a cron job cannot find a next available date
    # TODO: Find a test case for this

const maxYears* {.intdefine.} = 3 # Max years to search ahead to find valid cron time

const 
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

# From https://github.com/soasme/nim-schedules/blob/master/src/schedules/cron/cron.nim#L201
proc ceil(dt: DateTime): DateTime {.raises: [].} =
  result = dt
  # Round to next second
  if dt.nanosecond > 0:
    result -= initTimeInterval(nanoseconds=dt.nanosecond)
    result += initTimeInterval(seconds=1)
  # Round to next minute
  if dt.second > 0:
    result += initTimeInterval(seconds=(60 - dt.second))

func min[T](s: set[T]): int {.raises: [].} =
  ## Returns smallest element that is in set[T]
  for i in s:
    return i.ord

func max[T](s: set[T]): T {.raises: [].} =
  ## Returns largest element that is in set[T]
  result = T.high
  while result >= T.low:
    if result in s:
      break
    dec result

func matches(date: DateTime, format: Cron): bool {.raises: [].}=
  ## Returns true if date matches for format
  date.minute in format.minutes and 
  date.hour in format.hours and 
  date.monthDay in format.monthDays and 
  date.month in format.months and 
  date.weekday in format.weekDays

func isValid*(format: Cron): bool {.raises: [].} =
  ## Checks that a format is valid (Just checks it has no empty sets).
  runnableExamples:
    assert not Cron(minutes: {}).isValid
  #==#
  result = true
  for field in format.fields():
    if field.len == 0:
      return false

func monthDays(d: DateTime): set[MonthDayRange] {.raises: [].} =
  ## Get range of month days for current month of date
  {1.MonthDayRange .. d.month.getDaysInMonth(d.year)}

func possibleDays(allowedDays: set[WeekDay], date: DateTime): set[MonthDayRange] {.raises: [].}=
  ## Returns all days in month that are in allowed days
  for monthDay in date.monthDays:
    let day = monthDay.getDayOfWeek(date.month, date.year)
    if day in allowedDays:
      result.incl monthDay  

func `/`*[T: CronRanges](values: set[T], n: int): set[T] {.raises: [].} =
  ## Returns every nth value starting from the first value in values
  runnableExamples:
    # Set of values to run every second day
    assert everyWeekDay / 2 == {dMon, dWed, dFri, dSun} 
    # Only use every third hour in our range
    assert {5.HourRange .. 15} / 4 == {5.HourRange, 9, 13}
    # It only does every second value
    assert {dMon, dWed, dSun} / 2 == {dMon, dSun}
  #==#
  let possibleValues = toSeq(values)
  for i in countup(0, possibleValues.len - 1, n):
    result.incl possibleValues[i]

func incField[T: CronRanges](s: set[T], curr: T): int {.raises: [].} =
  ## Returns the value needed to increment a field to the next value.
  ## If the value wraps around then it returns a large enough value to cause that wrap around
  for item in s:
    if item >= curr:
      return item.ord - curr.ord
  return (T.high.int - curr.ord) + s.min

proc next*(now: DateTime, format: Cron): DateTime {.raises: [TooFarAheadCron].} =
  ## Returns next date that a cron would run from now
  # Implementation from here
  # https://github.com/robfig/cron/blob/master/spec.go#L58
  assert format.isValid, $format & " is not a valid format"
  
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

    if result.year > maxYear:
      raise (ref TooFarAheadCron)(msg: "Could not find next valid date for " & $format)
          
func initCron*(minutes = everyMinute, hours = everyHour, 
               monthDays = everyMonthDay, months = everyMonth, 
               weekDays = everyWeekDay): Cron {.raises: [].} =
  ## Makes a new cron format.
  ## Sets passed in cannot be empty (Since that wouldn't make sense)
  runnableExamples:
    let everySecondMinute = initCron(minutes = everyMinute / 2)
    let weekendMornings = initCron(hours = {8.HourRange}, weekDays = {dSat, dSun})
  #==#
  template res(field: untyped) =
    ## Updates field in result with parameter of same name 
    result.field = field
  res minutes
  res hours
  res monthDays
  res months
  res weekDays
  assert result.isValid, "Cron format isn't valid"

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

export times
