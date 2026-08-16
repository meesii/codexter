// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'global_config.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class GlobalConfigAdapter extends TypeAdapter<GlobalConfig> {
  @override
  final int typeId = 0;

  @override
  GlobalConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GlobalConfig(
      domain: fields[0] as String,
      host: fields[1] as String,
      port: fields[2] as int,
      useCloudflared: fields[3] as bool,
      tunnelId: fields[4] as String?,
      tunnelName: fields[5] as String,
      cloudflaredBin: fields[6] as String?,
      firstRunCompleted: fields[7] as bool,
      darkMode: fields[8] as bool?,
      closeToTray: fields[9] as bool? ?? true,
      notificationsEnabled: fields[10] as bool? ?? true,
      notificationSound: fields[11] as bool? ?? true,
      sidebarWidth: (fields[12] as num?)?.toDouble() ?? 236,
      closeActionRemembered: fields[13] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, GlobalConfig obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.domain)
      ..writeByte(1)
      ..write(obj.host)
      ..writeByte(2)
      ..write(obj.port)
      ..writeByte(3)
      ..write(obj.useCloudflared)
      ..writeByte(4)
      ..write(obj.tunnelId)
      ..writeByte(5)
      ..write(obj.tunnelName)
      ..writeByte(6)
      ..write(obj.cloudflaredBin)
      ..writeByte(7)
      ..write(obj.firstRunCompleted)
      ..writeByte(8)
      ..write(obj.darkMode)
      ..writeByte(9)
      ..write(obj.closeToTray)
      ..writeByte(10)
      ..write(obj.notificationsEnabled)
      ..writeByte(11)
      ..write(obj.notificationSound)
      ..writeByte(12)
      ..write(obj.sidebarWidth)
      ..writeByte(13)
      ..write(obj.closeActionRemembered);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlobalConfigAdapter && runtimeType == other.runtimeType && typeId == other.typeId;
}
