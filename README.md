# Breather

A small macOS menu bar app that reminds you to rest your eyes, breathe and stretch.

- **Eyes** every 20 min (20-20-20 rule + slow blinks), **Breathe** every 45 min (1 min guided), **Stretch** every 60 min (2 min, any movement).
- Breaks open as a black island that grows out of the MacBook notch (top centre on other screens), with a soft glowing edge. No full-screen takeover, no "start?" step.
- The island takes keyboard focus: Return = done/next, L = later (twice per break), Esc = skip.
- Counts only active time. Idle 2+ min pauses the timers; away or locked 5+ min counts as a natural break.
- Waits while the camera or microphone is on, or a full-screen app is in front, and for a pause in typing.
- Strict mode hides Skip; holding Esc for 3 seconds is always an emergency exit.

## Build

Needs only the Xcode Command Line Tools (macOS 14+).

```bash
./build.sh            # builds build/Breather.app
./build.sh --run      # builds and starts it
./build.sh --install  # copies to /Applications and starts it
```

## Testing

```bash
open build/Breather.app --args --break stretch                  # a break as if taken from the menu
open build/Breather.app --args --auto-break eyes                # a break as if the schedule started it
build/Breather.app/Contents/MacOS/Breather --snapshot /tmp/snaps  # render every state to PNG
defaults write com.thuanngo.Breather debugSecondsPerMinute -int 2  # 1 "minute" = 2 s
defaults delete com.thuanngo.Breather debugSecondsPerMinute        # back to normal
```
