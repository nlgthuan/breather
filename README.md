# Breather

A small macOS menu bar app that reminds you to rest your eyes, breathe and stretch.

- **Eyes** every 20 min (20-20-20 rule + slow blinks), **Breathe** every 45 min (1 min guided), **Stretch** every 60 min (3 rotating stretches).
- Counts only active time. Idle 2+ min pauses the timers; away or locked 5+ min counts as a natural break.
- Waits while the camera or microphone is on, or a full-screen app is in front, and for a pause in typing.
- Gentle first (edge glow + small card), then a calm full-screen overlay if ignored. "5 min later" works twice per break.
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
open build/Breather.app --args --break stretch                  # show a break right away
defaults write com.thuanngo.Breather debugSecondsPerMinute -int 2  # 1 "minute" = 2 s
defaults delete com.thuanngo.Breather debugSecondsPerMinute        # back to normal
```
