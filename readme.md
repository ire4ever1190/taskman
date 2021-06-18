A simple async only scheduling library based on [nim-schedules](https://github.com/soasme/nim-schedules) which is an
amazing library but requires threads (and sometimes I like to be dirty and use globals without a care ;) ).

Since this is more built for personal use, so it is light on features and isn't robust

TODO

```nim
import asyncdispatch
import taskman
let tasks = newScheduler()
tasks.every(2.seconds) do () {.async.}:
    echo "tock"
waitFor tasks.start()
runForever()
```