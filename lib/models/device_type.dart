/// Represents the type / operating system of a device in the Clipboard Sharer network.
enum DeviceType {
  windows,
  android,
  ios,
  androidTv,
  macos;

  String toJson() {
    switch (this) {
      case DeviceType.windows:
        return 'windows';
      case DeviceType.android:
        return 'android';
      case DeviceType.ios:
        return 'ios';
      case DeviceType.androidTv:
        return 'android_tv';
      case DeviceType.macos:
        return 'macos';
    }
  }

  static DeviceType fromJson(String value) {
    switch (value.toLowerCase()) {
      case 'windows':
        return DeviceType.windows;
      case 'android':
        return DeviceType.android;
      case 'ios':
        return DeviceType.ios;
      case 'android_tv':
      case 'androidtv':
      case 'tv':
        return DeviceType.androidTv;
      case 'macos':
        return DeviceType.macos;
      default:
        return DeviceType.android;
    }
  }

  bool get isTv => this == DeviceType.androidTv;
  bool get isMobile => this == DeviceType.android || this == DeviceType.ios;
  bool get isDesktop => this == DeviceType.windows || this == DeviceType.macos;
}
