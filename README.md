# Breather

A small macOS menu bar app that reminds you to rest your eyes, breathe and stretch.

- **Eyes** every 25 min (look far away + slow blinks), **Water** and **Stretch** every 50 min (a few sips; 2 min of any movement), **Breathe** every 75 min (1 min guided). All on a 25-minute rhythm, so they line up.
- Breaks open as a black island that grows out of the MacBook notch (top centre on other screens), with a soft glowing edge. No full-screen takeover, no "start?" step.
- The island takes keyboard focus: L = later (back in 5 min, always available), Esc = skip. A break ends by itself when its timer runs out ("Nice work"; Return closes that right away).
- Water on its own is a quiet nudge: a smaller island that doesn't take focus and slides away after 8 s. Ignored nudges don't count as skipped.
- The menu bar panel follows the system's light/dark mode, or can be set to Light or Dark in Settings. Motion follows the system's Reduce Motion by default, or can be set to Full or Reduced in Settings (reduced: fades instead of springs, a still glow).
- Reminders never land back to back: ones due within 5 min share a single card ("Stand up, grab some water"), and there are always at least 25 min between reminders.
- Counts only active time. Idle 2+ min pauses the timers; away or locked 15+ min counts as a natural break.
- Waits for a pause in typing. In a call or watching something? Pause it from the menu bar.
- Strict mode hides Skip; holding Esc for 3 seconds is always an emergency exit.

## Build

Needs only the Xcode Command Line Tools (macOS 14+).

```bash
./build.sh            # builds build/Breather.app
./build.sh --run      # builds and starts it
./build.sh --install  # copies to /Applications and starts it
```

The app icon is drawn by `swift tools/make-icon.swift`, which writes `Resources/AppIcon.icns`.

## Testing

```bash
open build/Breather.app --args --break stretch                  # a break as if taken from the menu
open build/Breather.app --args --auto-break eyes                # a break as if the schedule started it
open build/Breather.app --args --auto-break hydrate             # the water nudge
build/Breather.app/Contents/MacOS/Breather --snapshot /tmp/snaps  # render every state to PNG
defaults write com.thuanngo.Breather debugSecondsPerMinute -int 2  # 1 "minute" = 2 s
defaults delete com.thuanngo.Breather debugSecondsPerMinute        # back to normal
```
