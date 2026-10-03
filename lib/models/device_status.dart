/// Represents the status of a known or discovered device.
enum DeviceStatus {
  online,
  offline,
  paired,
  unpaired;

  String toJson() => name;

  static DeviceStatus fromJson(String value) {
    return DeviceStatus.values.firstWhere(
      (e) => e.name.toLowerCase() == value.toLowerCase(),
      orElse: () => DeviceStatus.unpaired,
    );
  }

  bool get isOnline => this == DeviceStatus.online || this == DeviceStatus.paired;
  bool get isPaired => this == DeviceStatus.paired;
}
