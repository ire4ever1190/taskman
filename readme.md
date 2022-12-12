## Taskman

A simple and lightweight async/sync scheduling library for running tasks at certain times.

Supports
- Running on an interval e.g. every 5 minutes, every 2.5 seconds
- Running on a set date
- Run after an amount of time e.g. run after 10 hours
- Run on cron format e.g. `10 4 * * *` (Run on the 10th minute of the 4th hour everyday)

Go to the [docs here](https://tempdocs.netlify.app/taskman/stable) for more information and examples

### Installation
Either run `nimble install taskman`
or add `requires "taskman"` to your .nimble file

### Examples

Every day get the IP address of the computer
```nim
import std/[httpclient, json]

let tasks = newAsyncScheduler()

var ip = ""

tasks.every(1.days) do () {.async.}:
  let client = newAsyncHttpClient()
  defer: client.close()
  ip = client
    .getContent("https://httpbin.org/ip")
    .parseJson()["origin"]
    .getStr()

waitFor tasks.start()
```

When the client first connects they get added to a queue and after 5 mins they are
allowed to see the actual page
```nim
import src/taskman
import std/asynchttpserver
import std/sets

let tasks = newAsyncScheduler()


var allowed: HashSet[string]

proc cb(req: Request) {.async, gcsafe.} =
  if req.hostname notin allowed:
    # Add the client to the wait list
    tasks.wait(5.minutes) do () {.async.}:
      # Once the wait is over, allow them in
      allowed.incl req.hostname
    await req.respond(Http200, "You can join in 5 minutes")
  else:
    await req.respond(Http200, "Hello again!")

# This is NOT how you should be using asyncHttpServer
# This is just a basic example
var server = newAsyncHttpServer()
server.listen 8080.Port
echo "Running on port 8080"
while true:
  waitFor server.acceptRequest(cb)
```
