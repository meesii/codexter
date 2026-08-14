// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'skill_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SkillEntryAdapter extends TypeAdapter<SkillEntry> {
  @override
  final int typeId = 2;

  @override
  SkillEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SkillEntry(
      name: fields[0] as String,
      description: fields[1] as String,
      source: fields[2] as String,
      rootPath: fields[3] as String?,
      enabled: fields[4] as bool,
      createdAt: fields[5] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, SkillEntry obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.description)
      ..writeByte(2)
      ..write(obj.source)
      ..writeByte(3)
      ..write(obj.rootPath)
      ..writeByte(4)
      ..write(obj.enabled)
      ..writeByte(5)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
