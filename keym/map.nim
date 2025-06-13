
proc getNote(keyCode: cint): int =
  case keyCode:
  of KEY_Z: 0
  of KEY_X: 2
  of KEY_C: 3
  default:
    0

