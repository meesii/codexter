// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'downstream_mcp_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DownstreamMcpEntryAdapter extends TypeAdapter<DownstreamMcpEntry> {
  @override
  final int typeId = 3;

  @override
  DownstreamMcpEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DownstreamMcpEntry(
      name: fields[0] as String,
      transportJson: fields[1] as String,
      enabled: fields[2] as bool,
      source: fields[3] as String,
      startupTimeoutMs: fields[4] as int?,
      toolTimeoutMs: fields[5] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, DownstreamMcpEntry obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.transportJson)
      ..writeByte(2)
      ..write(obj.enabled)
      ..writeByte(3)
      ..write(obj.source)
      ..writeByte(4)
      ..write(obj.startupTimeoutMs)
      ..writeByte(5)
      ..write(obj.toolTimeoutMs);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownstreamMcpEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
