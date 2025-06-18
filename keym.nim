import std/[monotimes]
import rtthread, jill/ringbuffer, jill/os, keym/codes, jacket
from posix import Timeval, Timespec, clock_gettime, CLOCK_MONOTONIC

type
  RawKeyboardEvent {.packed.} = object
    time: Timeval
    kind: uint16
    scancode: uint16
    value: int32
  InputEventKind = enum
    Note,
    State
    Housekeeping
  StateTransition = enum
    SemitoneUp,
    SemitoneDown,
    OctaveUp,
    OctaveDown
  HousekeepingAction = enum
    AllNotesOff
  InputEvent {.packed.} = object
    usec: int64
    case kind: InputEventKind
    of Note:
      note: int8
      on: bool
    of State:
      transition: StateTransition
    of Housekeeping:
      action: HousekeepingAction

let
  EVIOCSCLOCKID* {.importc, header: "<linux/input.h>".}: culong

const
  latencyPeriods = 2
  eventPriority = 98
  keyboardPath = "/dev/input/event3"

  transposeMin = -60'i8
  transposeMax = 60'i8
  
  noteOn = 0x90'u8
  noteOff = 0x80'u8
  control = 0xb0'u8

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

proc newInputEvent(rawEvent: RawKeyboardEvent): InputEvent =
  # echo "> ", scancode
  result = case rawEvent.scancode:

  # lower row
  of KEY_Z:
    InputEvent(kind: Note, note: 60)
  of KEY_S:
    InputEvent(kind: Note, note: 61)
  of KEY_X:
    InputEvent(kind: Note, note: 62)
  of KEY_D:
    InputEvent(kind: Note, note: 63)
  of KEY_C:
    InputEvent(kind: Note, note: 64)
  of KEY_V:
    InputEvent(kind: Note, note: 65)
  of KEY_G:
    InputEvent(kind: Note, note: 66)
  of KEY_B:
    InputEvent(kind: Note, note: 67)
  of KEY_H:
    InputEvent(kind: Note, note: 68)
  of KEY_N:
    InputEvent(kind: Note, note: 69)
  of KEY_J:
    InputEvent(kind: Note, note: 70)
  of KEY_M:
    InputEvent(kind: Note, note: 71)
  of KEY_COMMA:
    InputEvent(kind: Note, note: 72)
  of KEY_L:
    InputEvent(kind: Note, note: 73)
  of KEY_DOT:
    InputEvent(kind: Note, note: 74)
  of KEY_SEMICOLON:
    InputEvent(kind: Note, note: 75)
  of KEY_SLASH:
    InputEvent(kind: Note, note: 76)

  # upper row
  of KEY_Q:
    InputEvent(kind: Note, note: 72)
  of KEY_2:
    InputEvent(kind: Note, note: 73)
  of KEY_W:
    InputEvent(kind: Note, note: 74)
  of KEY_3:
    InputEvent(kind: Note, note: 75)
  of KEY_E:
    InputEvent(kind: Note, note: 76)
  of KEY_R:
    InputEvent(kind: Note, note: 77)
  of KEY_5:
    InputEvent(kind: Note, note: 78)
  of KEY_T:
    InputEvent(kind: Note, note: 79)
  of KEY_6:
    InputEvent(kind: Note, note: 80)
  of KEY_Y:
    InputEvent(kind: Note, note: 81)
  of KEY_7:
    InputEvent(kind: Note, note: 82)
  of KEY_U:
    InputEvent(kind: Note, note: 83)
  of KEY_I:
    InputEvent(kind: Note, note: 84)
  of KEY_9:
    InputEvent(kind: Note, note: 85)
  of KEY_O:
    InputEvent(kind: Note, note: 86)
  of KEY_0:
    InputEvent(kind: Note, note: 87)
  of KEY_P:
    InputEvent(kind: Note, note: 88)
  of KEY_LEFTBRACE:
    InputEvent(kind: Note, note: 89)
  of KEY_EQUAL:
    InputEvent(kind: Note, note: 90)
  of KEY_RIGHTBRACE:
    InputEvent(kind: Note, note: 91)
  
  # transpose

  of KEY_LEFT:
    InputEvent(kind: State, transition: SemitoneDown)
  of KEY_RIGHT:
    InputEvent(kind: State, transition: SemitoneUp)
  of KEY_UP:
    InputEvent(kind: State, transition: OctaveUp)
  of KEY_DOWN:
    InputEvent(kind: State, transition: OctaveDown)

  # safety
  of KEY_ESC:
    InputEvent(kind: Housekeeping, action: AllNotesOff)

  # ignore other keys
  else:
    raise newException(ValueError, "unknown key")

  result.usec = rawEvent.time.toUsec

  let on = rawEvent.value.bool
  if result.kind == Note:
    result.on = on
  else:
    if not on:
      raise newException(ValueError, "keyup ignored")

var
  eventThread:Thread[void]
  signalThread:Thread[void]
  eventBuffer = newRingBuffer[InputEvent](2048)
  terminating = false
  midiPort: Port
  midiWriterClient: Client
  midiWriterStatus: cint
 

  # midiwriter State
  # global for convenience, not thread safe
  # to create new ways to modify it, use input events
  # so it is done in the correct order
  # use only one variable for octave and transpose
  # because transposing twelve semitones down
  # is conceptually the same as one octave
  # (the opposite view exists but is irrelevant in practice)
  transpose = 0'i8

  # MIDI channel
  channel = 0'i8

let
  keyboardDevice = openDevice(keyboardPath)

proc eventHandler() =
  while not terminating:
    var rawEvent:RawKeyboardEvent
    if keyboardDevice.readBuffer(rawEvent.addr, sizeof RawKeyboardEvent) != sizeof RawKeyboardEvent:
      # skip oddly-sized reads- should not happen
      continue
    if rawEvent.kind == 1'u16:  # ensure keyboard events only
      case rawEvent.value
      of 0'i32, 1'i32:  # press and release only
        try:
          eventBuffer.push(newInputEvent(rawEvent))
        except ValueError:
          discard
      else:
        # ignore repeat (which would be 2'i32)
        discard

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
 
  midiOutbuffer.midiClearBuffer()

  for event in eventBuffer.pop():

    # calculate sample (jack "frame") for event to occur

    let
      frameTime = midiWriterClient.lastFrameTime()
      #nextFrameTime = midiWriterClient.lastFrameTime()
      eventJackTime = event.usec - timeOffset
      eventFrame = midiWriterClient.timeToFrames(eventJackTime.uint64)
      eventFrameFromLastFrameTime = eventFrame.int64 - frameTime.int64
      latency = latencyPeriods * numFrames
    var
      scheduledFrame = eventFrameFromLastFrameTime + latency.int
    # echo (frameTime, eventFrame, eventFrameFromLastFrameTime)
    if scheduledFrame < 0:
      scheduledFrame = 0
      stderr.write "Warning: event was late"
    elif scheduledFrame >= numFrames.int:
      break
    #stdout.write $scheduledFrame & " "

    case event.kind
    of Note:
      var data = midiOutBuffer.midiEventReserve(NFrames scheduledFrame, 3)
      assert not data.isNil, "could not reserve MIDI data"
      if event.on:
        data[0] = noteOn
        data[1] = (event.note + transpose).uint8
        data[2] = 64'u8  # half velocity, play nice with other MIDI streams
      else:
        data[0] = noteOff
        data[1] = (event.note + transpose).uint8
        data[2] = 0'u8  # signify quick release by MIDI conventions

    of State:

      # can just change the state here- scheduled events that rely
      # on the state have no more use for it at this point because
      # /dev/input events are guaranteed to arrive in order

      case event.transition:
      of SemitoneUp:
        transpose = min(60, transpose + 1)
      of SemitoneDown:
        transpose = max(-60, transpose - 1)
        # leave as is if out of range
        # (avoid unexpected and hard-to-correct key change that just limiting it would hae)
      of OctaveUp:
        transpose += 12
        if transpose > transposeMax:
          transpose -= 12  # not thread safe but doesn't need to be
      of OctaveDown:
        transpose -= 12
        if transpose < transposeMin:
          transpose += 12

    of Housekeeping:
      var data = midiOutBuffer.midiEventReserve(NFrames scheduledFrame, 3)
      assert not data.isNil, "could not reserve MIDI data"
      data[0] = control
      data[1] = 123'u8
      data[2] = 0'u8

createThread signalThread, proc() {.thread.} =
  waitSignals(SIGABRT, SIGHUP, SIGINT, SIGQUIT, SIGTERM):
    terminating = true

blockSignals(SIGABRT, SIGHUP, SIGINT, SIGQUIT, SIGTERM)

midiWriterClient = clientOpen("keym", NoStartServer or UseExactName, midiWriterStatus.addr)
assert not midiWriterClient.isNil, "Could not create jack client, jack may not be running"
midiPort = midiWriterClient.portRegister("out", JackDefaultMidiType, PortIsOutput, 0)
assert midiWriterClient.setProcessCallback(midiWriter) == 0, "could not set process callback"

eventBuffer.lock()

assert midiWriterClient.activate() == 0, "Could not connect jack"

createRealtimeThread(eventThread, eventHandler, priority=98)
joinThread(eventThread)  # exit when input thread does, it's simpler not to have to kill it

midiWriterClient.deactivate
midiWriterClient.clientClose

