import std/[monotimes]
import rtthread, jill/ringbuffer, jill/os, keym/codes, jacket
from posix import Timeval, Timespec, clock_gettime, CLOCK_MONOTONIC

type
  RawKeyboardEvent {.packed.} = object
    time: Timeval
    kind: uint16
    code: uint16
    value: int32
  KeyboardEvent {.packed.} = object
    usec: int64
    note: int8
    on: bool

let
  EVIOCSCLOCKID* {.importc, header: "<linux/input.h>".}: culong

const latencyPeriods = 2

proc toUsec(t: Timeval): int64 =
  ## older linux kernel time format with microseconds
  ## used by event subsystem
  t.tv_sec.int64 * 1_000_000 + t.tv_usec.int64

proc toUsec(t: Timespec): int64 =
  ## newer linux kernel time format with nanoseconds
  ## used to retrieve system time
  t.tv_sec.int64 * 1_000_000 + t.tv_nsec.int64 div 1000

proc getSysTime(): int64 =
  var ts {.noinit.}: Timespec
  discard clock_gettime(CLOCK_MONOTONIC, ts)
  ts.toUsec

proc ioctl(f: FileHandle, request: culong, arg: pointer): cint {.importc: "ioctl", header: "<sys/ioctl.h>".}
  ## std/posix ioctl signature doesn't match

proc openDevice(path: string): File =
  result = open(path)
  var clk = CLOCK_MONOTONIC
  assert ioctl(result.getOSFileHandle, EVIOCSCLOCKID, clk.addr) == 0, "Could not set input subsystem to monotonic time"

proc scancodeToNote(scancode: uint16, note: var int8): bool =
  # echo "> ", scancode
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

const
  keyboardEventPriority = 96
  keyboardPath = "/dev/input/event3"

var
  keyboardEventThread:Thread[void]
  signalThread:Thread[void]
  keyboardEventBuffer = newRingBuffer[KeyboardEvent](2048)
  terminating = false
  midiPort: Port
  midiWriterClient: Client
  midiWriterStatus: cint

let
  keyboardDevice = openDevice(keyboardPath)

proc keyboardEventHandler() =
  while not terminating:
    var rawKeyboardEvent:RawKeyboardEvent
    if keyboardDevice.readBuffer(rawKeyboardEvent.addr, sizeof RawKeyboardEvent) != sizeof RawKeyboardEvent:
      # skip oddly-sized reads- should not happen
      continue
    if rawKeyboardEvent.kind == 1'u16:  # ensure keyboard events only
      case rawKeyboardEvent.value
      of 0'i32, 1'i32:  # press and release only
        var keyboardEvent:KeyboardEvent
        keyboardEvent.usec = rawKeyboardEvent.time.toUsec
        if not scancodeToNote(rawKeyboardEvent.code, keyboardEvent.note):
          # undefined code, ignore
          continue
        keyboardEvent.on = rawKeyboardEvent.value.bool
        keyboardEventBuffer.push(keyboardEvent)
      else:
        # ignore repeat (which would be 2'i32)
        discard

const
  noteOn = 0x90'u8
  noteOff = 0x80'u8

proc `[]=`(s: ptr MidiData; i: int8; x: uint8) =
  cast[ptr UncheckedArray[MidiData]](s)[i] = x

proc `[]`(s: ptr MidiData; i: int8): uint8 =
  cast[ptr UncheckedArray[MidiData]](s)[i]

proc midiWriter*(numFrames: NFrames, arg: pointer): cint {.cdecl.} =
  let
    jackTime = getTime().int64
    sysTime = getSysTime()
    timeOffset = sysTime - jackTime

    midiOutBuffer = portGetBuffer(midiPort, numFrames)
  
  var
    currentEvent: KeyboardEvent

  while keyboardEventBuffer.peek(currentEvent):
    let
      frameTime = midiWriterClient.lastFrameTime()
      nextFrameTime = midiWriterClient.lastFrameTime()
      currentEventJackTime = currentEvent.usec - timeOffset
      currentEventFrame = midiWriterClient.timeToFrames(currentEventJackTime.uint64)
      currentEventFrameFromLastFrameTime = currentEventFrame.int64 - frameTime.int64
      latency = latencyPeriods * numFrames
    var
      scheduledFrame = currentEventFrameFromLastFrameTime + latency.int
    # echo (frameTime, currentEventFrame, currentEventFrameFromLastFrameTime)
    if scheduledFrame < 0:
      scheduledFrame = 0
      stderr.write "Warning: event was late"
    elif scheduledFrame >= numFrames.int:
      break
    stdout.write $scheduledFrame & " "
    midiOutbuffer.midiClearBuffer()
    var data = midiOutBuffer.midiEventReserve(NFrames scheduledFrame, 3)
    assert not data.isNil, "could not reserve MIDI data"
    if currentEvent.on:
      data[0] = noteOn
      data[1] = currentEvent.note.uint8
      data[2] = 64'u8  # play nice with other controllers with sensitivity
    else:
      data[0] = noteOff
      data[1] = currentEvent.note.uint8
      data[2] = 0'u8  # quick release
    keyboardEventBuffer.readAdvance()
    echo data[0], " ", data[1], " ", data[2]

createThread signalThread, proc() {.thread.} =
  waitSignals(SIGABRT, SIGHUP, SIGINT, SIGQUIT, SIGTERM):
    terminating = true

blockSignals(SIGABRT, SIGHUP, SIGINT, SIGQUIT, SIGTERM)

midiWriterClient = clientOpen("keym", NoStartServer or UseExactName, midiWriterStatus.addr)
assert not midiWriterClient.isNil, "Could not create jack client, jack may not be running"
midiPort = midiWriterClient.portRegister("out", JackDefaultMidiType, PortIsOutput, 0)
assert midiWriterClient.setProcessCallback(midiWriter) == 0, "could not set process callback"

assert midiWriterClient.activate() == 0, "Could not connect jack"

createRealtimeThread(keyboardEventThread, keyboardEventHandler, priority=98)
joinThread(keyboardEventThread)  # exit when input thread does, it's simpler not to have to kill it

midiWriterClient.deactivate
midiWriterClient.clientClose

