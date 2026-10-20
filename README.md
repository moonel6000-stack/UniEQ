# SysEQ
EQ 5 bandes + module flottant déplaçable + page dans Réglages (PreferenceLoader).
Build : `make package` (Theos). Réglages : activer, afficher le module, mode (toutes sauf / seulement la sélection), choix des apps.
Principe : SpringBoard lit les préférences et diffuse l'état via notifyd ; chaque app s'abonne et applique l'EQ sur sa sortie audio (RemoteIO, post-render).
Limite : apps qui passent par mediaserverd (AVPlayer, Musique, Safari/YouTube) non couvertes.
