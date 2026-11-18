## .. importdoc:: ./cron
## Implements a parser to convert cron strings into [Cron].
## Supports most cron syntax along with shortcuts like `@daily`

# Efficient is not a word that would be near this

import ./cron

import std/[sugar, setutils]

import pkg/[nort]

proc mapsTo[T](input: Combinator, val: T): Combinator[T] =
  input.map((_) => val)

let
  # Short hand syntax
  shortcut = map {
    -e("@hourly"): cron(0, x, x, x, x),
    -e("@daily"): cron(0, 0, x, x, x),
    -e("@weekly"): cron(0, 0, x, x, 0),
    -e("@monthly"): cron(0, 0, 1, x, x),
    -e("@yearly"): cron(0, 0, 1, 1, x)
  }
  sp = e' '

  singleDigit = digit().map(val => int8(val))

  valueRange = map(singleDigit <* e('-') <*> singleDigit) do (inp: tuple[left, right: int8]) -> set[int8]:
    {inp.left .. inp.right}

proc value(T: typedesc): Combinator[set[int8]] =
  valueRange |
    singleDigit.map(val => {val}) |
    e('*').mapsTo({T.low.int8 .. T.high.int8})

proc flattenSet[T](inp: seq[set[T]]): set[T] =
  ## Flattens a seqeuence of sets into a single set
  for i in inp:
    result.incl i

proc values(T: typedesc): Combinator[set[int8]] =
  value(T).sep(e',').map(flattenSet)

proc stepInterval(T: typedesc): Combinator[set[int8]] =
  ## Parses the `/` operator
  map(values(T) <* e('/') <*> singleDigit) do (inp: tuple[left: set[int8], right: int8]) -> set[int8]:
    let min = block:
      var smallest = T.high
      for i in T.low .. T.high:
        if i.int8 in inp.left and i < smallest:
          smallest = i
      smallest

    for i in countup(min.int8, T.high.int8, inp.right):
      if i in inp.left:
        result.incl(i)

proc field(T: typedesc): Combinator[set[int8]] =
  stepInterval(T) | values(T)

let cronGrammar = field(MinuteRange)$minute * sp * field(HourRange)$hour * sp * field(MonthDayRange)$dom * sp * field(Month)$month * sp * field(Weekday)$weekday

proc parseCron*(input: string): Cron =
  ## Parses a cron string into a structured string
  runnableExamples:
    discard parseCron("@daily")
    discard parseCron("10 * * * *")

  let res = cronGrammar.match(input)
  if res.isNone():
    raise (ref ValueError)(msg: "Failed to parse: " & input)
  let (minute, hour, dom, month, weekday) = res.get()
  # Ran into https://github.com/nim-lang/Nim/issues/24714
  # Everything needed to be the same type inside the combinators, now we convert it
  # in the worst way possible
  proc changeSet[T](inp: set[int8], typ: typedesc[T]): set[T] =
     for i in inp:
       if i in T.low.ord .. T.high.ord:
         result.incl(T(i))

  return initCron(minute.changeSet(MinuteRange), hour.changeSet(HourRange), dom.changeSet(MonthDayRange), month.changeSet(Month), weekday.changeSet(Weekday))
