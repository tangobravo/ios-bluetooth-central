# ios-bluetooth-central

Quick CoreBluetooth central implementation to read data from either a GATT Characteristic updates or an L2CAP channel, or both.

Choose which routes to enable by commenting the defines at the top of ViewController.m

Assumes the https://github.com/tangobravo/ios-bluetooth-peripheral app is running on another iOS device.

Part of investigating some delays in receiving characteristic updates on some iOS devices.

See https://developer.apple.com/forums/thread/713800 for more details.
