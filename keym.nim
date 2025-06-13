import std/[monotimes]
import rtthread, jill, jill/ringbuffer, jill/os, keym/codes, jacket

type
  KernelTime {.packed.} = object
    sec: int64
    nsec: int64
  RawKeyboardEvent {.packed.} = object
    time: KernelTime
    kind: uint16
    code: uint16
    value: int32

  KeyboardEvent {.packed.} = object
    usec: uint64
    note: int8
    on: bool

proc scancodeToNote(scancode: uint16, note: var int8): bool =
  #echo "> ", scancode
  note = case scancode:
  
  # lower row
  of KEY_Z:
    60
  of KEY_S:
    61
  of KEY_X:
    62
  of KEY_D:
    63
  of KEY_C:
    64
  of KEY_V:
    65
  of KEY_G:
    66
  of KEY_B:
    67
  of KEY_H:
    68
  of KEY_N:
    69
  of KEY_J:
    70
  of KEY_M:
    71
  of KEY_COMMA:
    72
  of KEY_L:
    73
  of KEY_DOT:
    74
  of KEY_SEMICOLON:
    75
  of KEY_SLASH:
    76

  # upper row
  of KEY_Q:
    72
  of KEY_2:
    73
  of KEY_W:
    74
  of KEY_3:
    75
  of KEY_E:
    76
  of KEY_R:
    77
  of KEY_5:
    78
  of KEY_T:
    79
  of KEY_6:
    80
  of KEY_Y:
    81
  of KEY_7:
    82
  of KEY_U:
    83
  of KEY_I:
    84
  of KEY_9:
    85
  of KEY_O:
    86
  of KEY_0:
    87
  of KEY_P:
    88
  of KEY_LEFTBRACE:
    89
  of KEY_EQUAL:
    90
  of KEY_RIGHTBRACE:
    91

  # ignore other keys
  else:
    return false
  true

proc toUsec(t: KernelTime): uint64 =
  uint64(t.sec * 1_000_000 + t.nsec div 1000)

const
  keyboardEventPriority = 96
  keyboardPath = "/dev/input/event3"

var
  keyboardEventThread:Thread[void]
  signalThread:Thread[void]
  keyboardEventBuffer = newRingBuffer[KeyboardEvent](2048)
  terminating = false
  jackTimeUsec = 0#jacket.getTime()
  sysTimeUsec = uint64(getMonoTime().ticks div 1000)

let
  keyboardDevice = open(keyboardPath)

proc keyboardEventHandler() =
  while not terminating:
    var rawKeyboardEvent:RawKeyboardEvent
    if keyboardDevice.readBuffer(rawKeyboardEvent.addr, sizeof RawKeyboardEvent) != sizeof RawKeyboardEvent:
      # skip oddly-sized reads
      continue
    if rawKeyboardEvent.kind == 1'u16:  # ensure keyboard events only
      case rawKeyboardEvent.value
      of 0'i32, 1'i32:  # press and release only
        echo rawKeyboardEvent
        var keyboardEvent:KeyboardEvent
        if not scancodeToNote(rawKeyboardEvent.code, keyboardEvent.note):
          # undefined code, ignore
          continue
        keyboardEvent.usec = rawKeyboardEvent.time.toUsec
        keyboardEvent.on = rawKeyboardEvent.value.bool
        echo keyboardEvent
        keyboardEventBuffer.push(keyboardEvent)
      else:
        # ignore repeat (which would be 2'i32)
        discard

createThread signalThread, proc() {.thread.} =
  waitSignals(SIGABRT, SIGHUP, SIGINT, SIGQUIT, SIGTERM):
    terminating = true

blockSignals(SIGABRT, SIGHUP, SIGINT, SIGQUIT, SIGTERM)

createRealtimeThread(keyboardEventThread, keyboardEventHandler)

#setSignalProc(signalHandler, SIGABRT, SIGHUP, SIGINT, SIGQUIT, SIGTERM)

withJack (), (foo), defaultClientName(), false:
  var
    currentEvent: KeyboardEvent
    frames: uint32
    nextFrameUsec: uint64
    currentFrameUsec: uint64
    period: float32
  if getCycleTimes(client, frames.addr, currentFrameUsec.addr, nextFrameUsec.addr, period.addr) == 0:
    discard keyboardEventBuffer.pop(currentEvent)
    #echo "> ",$currentEvent
    while currentEvent.usec < nextFrameUsec:
      if currentEvent.usec >= currentFrameUsec:
        echo $currentEvent
      discard keyboardEventBuffer.pop(currentEvent)
      for i in 0..<64:
        foo[i] = 0.0
joinThread(keyboardEventThread)

#proc calculateFrame(event: KeyboardEvent, frameZeroTime: Time, numFrames: int): int =

#proc apply(samples: var openArray[SomeFloat], events: openArray[KeyboardEvent], frameZeroTime: Time) =


