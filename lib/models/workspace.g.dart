// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class WorkspaceAdapter extends TypeAdapter<Workspace> {
  @override
  final int typeId = 1;

  @override
  Workspace read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Workspace(
      uuid: fields[0] as String,
      name: fields[1] as String,
      projectRoot: fields[2] as String,
      autoStart: fields[3] as bool,
      createdAt: fields[4] as DateTime,
      lastActiveAt: fields[5] as DateTime,
      enabled: fields[6] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Workspace obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.uuid)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.projectRoot)
      ..writeByte(3)
      ..write(obj.autoStart)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.lastActiveAt)
      ..writeByte(6)
      ..write(obj.enabled);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
