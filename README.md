# SysEQ
EQ 5 bandes (60/230/910/3600/14000 Hz, ±12 dB + préampli) avec module flottant déplaçable (SpringBoard).
Build : `make package` (Theos requis). Changer de schéma : `THEOS_PACKAGE_SCHEME=rootless|roothide|` (vide = rootful).
Limite : l'EQ s'applique aux apps qui rendent l'audio via RemoteIO (AudioUnit). AVPlayer / Apple Music passent par mediaserverd et ne sont pas traités.
