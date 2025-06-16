
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

