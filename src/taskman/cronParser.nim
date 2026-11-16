## .. importdoc:: ./cron
## Implements a parser to convert cron strings into [Cron].
## Supports most cron syntax along with shortcuts like `@daily`

# Efficient is not a word that would be near this

import ./cron

import std/[sugar, setutils]

import pkg/[nort]

let
  # Short hand syntax
  hourly = e("@hourly").map((_) => cron(0, x, x, x, x))
  daily = e("@daily").map((_) => cron(0, 0, x, x, x))
  weekly = e("@weekly").map((_) => cron(0, 0, x, x, 0))
  monthly = e("@monthly").map((_) => cron(0, 0, 1, x, x))
  yearly = e("@yearly").map((_) => cron(0, 0, 1, 1, x))
  shortcut = hourly | daily | weekly | monthly | yearly

  sp = e' '

proc singleDigit[T](rng: typedesc[T]): Combinator[T] =
  digit().map(val => T(val))

proc valueRange[T](rng: typedesc[T]): Combinator[set[T]] =
  map(singleDigit(T) <* e('-') <*> singleDigit(T)) do (inp: tuple[left, right: T]) -> set[T]:
    {T(inp.left) .. T(inp.right)}

proc flattenSet[T](inp: seq[set[T]]): set[T] =
  ## Flattens a seqeuence of sets into a single set
  for i in inp:
    result.incl i

proc field[T](rng: typedesc[T]): Combinator[set[T]] =
  let fieldValue = valueRange(T) | singleDigit(T).map(val => {val}) | e('*').map((_) => fullSet(T))
  fieldValue.sep(e',').map(flattenSet)

let cronGrammar = field(int8)$minute * sp * field(int8)$hour * sp * field(int8)$dom * sp * field(int8)$month * sp * field(int8)$weekday

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
