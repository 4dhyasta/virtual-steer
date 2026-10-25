# virtual-steer

Turn your iPhone into a steering wheel for your PC.

> [!CAUTION]
> **Compatibility Notice:** This project currently only works on Windows 10 or later and iOS 16 or later.

## Requirements

- A Windows 10 (or later) PC and an iPhone running iOS 16 or later
- A USB cable
- [iTunes](https://www.apple.com/itunes/) or the **Apple Devices** app (Microsoft Store). This installs the Apple USB driver the PC needs to talk to your iPhone.
- Python 3. If `start.bat` reports a missing module, run `pip install vgamepad`.

## Tutorial

1. Download the `.zip` file from the [**Release Page**](https://github.com/4dhyasta/virtual-steer/releases/latest).
2. Extract the `.zip` file.
3. Install the `.ipa` file from the extracted folder onto your iPhone using [Sideloadly](https://sideloadly.io/), [SideStore](https://sidestore.io/), or [AltStore](https://altstore.io/).
   - Turn on **Developer Mode** (Settings > Privacy & Security) and trust the developer profile (Settings > General > VPN & Device Management).
   - Apps installed with a free Apple ID expire after 7 days. Reinstall the `.ipa` when that happens.
4. Connect your iPhone to your PC using a USB cable and tap **Trust** on the iPhone.
5. Launch `start.bat` on your PC.
6. Launch the `VirtualSteer` app on your iPhone. The text "Waiting for PC over USB..." should disappear once it is connected.
7. Enjoy! Your iPhone should now be detected by your PC as an **Xbox 360 controller (XInput)**.

## Additional

- **Controller mapping:** Steering = left stick X, Throttle = RT, Brake = LT, Gear Up = RB, Gear Down = LB, Handbrake = X. Bind them in your game's controls menu.
- **Layout 1 (default):** From left to right — Brake Slider, Gear Down, Gear Up, Throttle Slider. Steering uses the gyro, so hold your iPhone horizontally like a steering wheel.
- **Layout 2:** An on-screen drift-style steering wheel on the bottom left, Gear Down and Gear Up buttons at the top corners, a Handbrake button next to the wheel, and the Brake and Throttle sliders on the right. Steering is done by turning the on-screen wheel, and the gyro is not used.
- **Centering the axis (Layout 1):** Hold your iPhone horizontally in your hands, then press both gear buttons simultaneously.
- **Opening the menu:** Press and hold both gear buttons simultaneously for about a second. From the menu you can:
  - Switch between Layout 1 and Layout 2
  - Set the gyro rotation range and reverse the steering direction (Layout 1)
  - Set how far the on-screen wheel turns for full lock (Layout 2)

## Troubleshooting

- **"iPhone not detected over USB":** Plug in the cable, unlock the iPhone, tap **Trust**, and make sure iTunes or Apple Devices is installed.
- **"Virtual Steer app is not open on the iPhone":** Open the VirtualSteer app, then run `start.bat` again.
- **Steering is reversed:** Open the menu and turn on "Reverse direction".
