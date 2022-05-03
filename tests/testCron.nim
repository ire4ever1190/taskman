import taskman
import std/unittest


test "Range counting":
  check everyWeekDay / 2 == {dMon, dWed, dFri, dSun} 
  check everyMonth / 1 == everyMonth



suite "Cron macro":
  test "* * * * *":
    check cron(x, x, x, x, x) == initCron()

  test "5 * * * *":
    check cron(5, x, x, x, x) == initCron(minutes = {5.MinuteRange})

  test "5-10 * * * *":
    check cron(5 - 10, x, x, x, x) == initCron(minutes = {5.MinuteRange .. 10})

  test "*/10 * * * *":
    check cron(x / 10, x, x, x, x) == initCron(minutes = everyMinute / 10)

  test "5-20 / 10 * * * *":
    check cron((5 - 20) / 10, x, x, x, x) == initCron(minutes = {5.MinuteRange .. 20} / 10)

  test "1,2,3,4 * * * *":
    check cron({1, 2, 3, 4}) == initCron(minutes = {1.MinuteRange, 2, 3, 4})

  test "1,2,3,4 / 2 * * * *":
    check cron({1, 2, 3, 4} / 2) == initCron(minutes = {1.MinuteRange, 2, 3, 4} / 2)

  test "1 8 * * wed":
    check cron(1, 8, weekDays = dWed) == initCron(minutes = {1.MinuteRange}, hours = {8.HourRange}, weekDays = {dWed})

  test "* * * feb,may *":
    check cron(months = {mFeb, mMay}) == initCron(months = {mFeb, mMay})

  test "* * * feb - dec *":
    check cron(months = mFeb - mDec) == initCron(months = {mFeb .. mDec})

# Tests taken from https://github.com/soasme/nim-schedules/blob/master/tests/test_cron.nim

const dateFormat = "yyyy-MM-dd hh:mm:ss"

template check(cron: Cron, start, endDate: string) =
  let act = start.parse(dateFormat).next(cron)
  let exp = endDate.parse(dateFormat)
  check act == exp

suite "Cron timing":
  test "* * * * *":
    initCron().check(
      "2000-01-01 00:00:00",
      "2000-01-01 00:01:00"
    )
  test "* * 1-6 * *":
    initCron(months={mJan, mJun}).check(
      "1999-12-01 00:00:00",
      "2000-01-01 00:00:00"
    )


  test "* * 10-13 1-6 *":
    initCron(months={mJan, mJun}, monthDays = {10.MonthDayRange .. 13}).check(
      "1999-12-01 00:00:00",
      "2000-01-10 00:00:00"
    )


  test "* 8-10 * feb-dec * 2000":
    initCron(hours={8.HourRange .. 10}, months={mFeb, mDec}).check(
      "2000-01-01 00:00:00",
      "2000-02-01 08:00:00",
    )


  test "5 4 * * *":
    initCron(minutes={5.MinuteRange}, hours={4.HourRange}).check(
      "2020-01-01 00:00:00",
      "2020-01-01 04:05:00",
    )


  test "5 0 * 8 *":
    initCron(minutes={5.MinuteRange}, hours={0.HourRange}, months={mAug}).check(
      "2000-01-01 00:00:00",
      "2000-08-01 00:05:00"
    )


  test "15 14 1 * *":
    initCron(minutes={15.MinuteRange}, hours={14.HourRange}, monthDays={1.MonthDayRange}).check(
      "2000-01-01 14:15:00",
      "2000-01-01 14:15:00"
    )


  test "0 22 * * 1-5":
    initCron(minutes={0.MinuteRange}, hours={22.HourRange}, weekDays={dMon..dThu}).check(
      "2000-01-01 00:00:00",
      "2000-01-03 22:00:00",
    )


  test "0 22 * * tue-sat":
    initCron(minutes={0.MinuteRange}, hours={22.HourRange}, weekDays={dTue, dSat}).check(
      "2000-01-01 00:00:00",
      "2000-01-01 22:00:00",
    )


  test "0 22 * * tue-thu":
    initCron(minutes={0.MinuteRange}, hours={22.HourRange}, weekDays={dTue, dThu}).check(
      "2000-01-01 00:00:00",
      "2000-01-04 22:00:00",
    )


  test "23 0-20/2 * * *":
    initCron(minutes={23.MinuteRange}, hours={0.HourRange .. 20}/2).check(
      "2000-01-01 13:00:00",
      "2000-01-01 14:23:00",
    )

  test "23 1/3 * * *":
    let cron = initCron(minutes={23.MinuteRange}, hours={1.HourRange .. 23.HourRange}/3)
    cron.check(
      "2000-01-01 13:00:00",
      "2000-01-01 13:23:00",
    )
    cron.check(
      "2000-01-01 13:23:00",
      "2000-01-01 13:23:00",
    )
    cron.check(
      "2000-01-01 13:23:01",
      "2000-01-01 16:23:00",
    )


  test "0 0,12 1 */2 *":
    let cron = initCron(
      minutes = {0.MinuteRange},
      hours = {0.HourRange, 12},
      monthDays = {1.MonthDayRange},
      months = everyMonth / 2,
    )

    cron.check(
      "2000-01-01 00:00:00",
      "2000-01-01 00:00:00",
    )
    cron.check(
      "2000-01-01 01:00:00",
      "2000-01-01 12:00:00",
    )
    cron.check(
      "2000-01-02 00:00:00",
      "2000-03-01 00:00:00",
    )


  test "0 4 8-14 * *":
    initCron(
      minutes = {0.MinuteRange},
      hours = {4.HourRange},
      monthDays = {8.MonthDayRange .. 14},
    ).check(
      "2000-01-01 00:00:00",
      "2000-01-08 04:00:00"
    )


  test "0 0 1,15 * Thu":
    let cron = initCron(
      minutes = {0.MinuteRange},
      hours = {0.HourRange},
      monthDays = {1.MonthDayRange .. 15},
      weekDays = {dThu},
    )
    cron.check(
      "2000-01-01 00:00:00",
      "2000-01-06 00:00:00",
    )
    cron.check(
      "2000-01-02 00:00:00",
      "2000-01-06 00:00:00",
    )


  test "* * 5-13 1/3 *":
    let cron = initCron(
      months = {mJan},
      monthDays = {5.MonthDayRange .. 13},
    )
    cron.check(
      "2008-12-01 00:00:00",
      "2009-01-05 00:00:00",
    )
    cron.check(
      "2009-10-14 00:00:00",
      "2010-01-05 00:00:00",
    )


  test "*/1 * * * *":
    let cron = initCron(
      minutes = everyMinute / 1
    )
    cron.check(
      "2000-01-01 00:00:00",
      "2000-01-01 00:00:00",
    )
    cron.check(
      "2000-01-01 00:00:01",
      "2000-01-01 00:01:00",
    )
    cron.check(
      "2000-01-01 00:00:59",
      "2000-01-01 00:01:00",
    )
    cron.check(
      "2000-01-01 00:01:00",
      "2000-01-01 00:01:00",
    )
    cron.check(
      "1999-12-31 23:59:59",
      "2000-01-01 00:00:00",
    )


  test "*/5 * * * *":
    let cron = initCron(
      minutes = everyMinute / 5
    )
    echo 1
    cron.check(
      "2000-01-01 00:00:00",
      "2000-01-01 00:00:00",
    )
    echo 2
    cron.check(
      "2000-01-01 00:00:01",
      "2000-01-01 00:05:00",
    )
    echo 3
    cron.check(
      "2000-01-01 00:04:59",
      "2000-01-01 00:05:00",
    )
    echo "1999-12-31 23:55:01".parse(dateFormat).next(cron).format(dateFormat)
    cron.check(
      "1999-12-31 23:55:01",
      "2000-01-01 00:00:00",
    )



  test "0 */1 * * *":
    let cron = initCron(minutes = {0.MinuteRange}, hours = everyHour/1)
    cron.check(
      "1999-12-31 23:59:59",
      "2000-01-01 00:00:00",
    )
    cron.check(
      "2000-01-01 00:00:00",
      "2000-01-01 00:00:00",
    )
    cron.check(
      "2000-01-01 00:00:01",
      "2000-01-01 01:00:00",
    )
    cron.check(
      "2000-01-01 00:59:59",
      "2000-01-01 01:00:00",
    )



  test "0 */3 * * *":
    let cron = initCron(minutes = {0.MinuteRange}, hours = everyHour / 3)
    cron.check(
      "1999-12-31 23:59:59",
      "2000-01-01 00:00:00",
    )
    cron.check(
      "2000-01-01 00:00:00",
      "2000-01-01 00:00:00",
    )
    cron.check(
      "2000-01-01 00:00:01",
      "2000-01-01 03:00:00",
    )
    cron.check(
      "2000-01-01 02:59:59",
      "2000-01-01 03:00:00",
    )


  test "0 0 */3 * *":
    let cron = initCron(minutes = {0.MinuteRange}, hours = {0.HourRange}, monthDays = everyMonthDay/3)
    cron.check(
      "1999-12-31 23:59:59",
      "2000-01-01 00:00:00",
    )
    cron.check(
      "2000-01-01 00:00:00",
      "2000-01-01 00:00:00",
    )
    cron.check(
      "2000-01-01 00:00:01",
      "2000-01-04 00:00:00",
    )
    cron.check(
      "2000-01-03 23:59:59",
      "2000-01-04 00:00:00",
    )
    cron.check(
      "2000-02-27 00:00:00",
      "2000-02-28 00:00:00",
    )
    cron.check(
      "2000-02-28 00:00:01",
      "2000-03-01 00:00:00",
    )


  test "5 4 * * sun":
    initCron(minutes = {5.MinuteRange}, hours = {4.HourRange}, weekDays = {dSun}).check(
      "2000-01-01 00:00:00",
      "2000-01-02 04:05:00",
    )


  test "5 4 1 * sun":
    let cron = cron(5, 4, 1, x, dSun)
    cron.check(
      "2000-01-01 12:00:00",
      "2000-10-01 04:05:00",
    )
    cron.check(
      "2000-01-02 12:00:00",
      "2000-10-01 04:05:00",
    )
