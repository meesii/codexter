import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Windows Job Object：关闭最后一个 handle 时结束 Job 内进程。
///
/// `flutter run` 按 Q 会直接杀掉 Dart 进程，[WindowListener.onWindowClose] 不会跑到。
/// 把 cloudflared 放进 KillOnJobClose Job 后，父进程退出时系统会一并结束子进程。
class WinKillOnCloseJob {
  WinKillOnCloseJob._(this._job);

  final int _job;

  static const _jobObjectExtendedLimitInformation = 9;
  static const _jobObjectLimitKillOnClose = 0x2000;
  static const _processTerminate = 0x0001;
  static const _processSetQuota = 0x0100;
  static const _extendedLimitInfoSize = 144;

  static DynamicLibrary? _kernel32;
  static WinKillOnCloseJob? _instance;
  static bool _boundCurrent = false;

  static bool get boundCurrentProcess => _boundCurrent;

  static DynamicLibrary get _k32 {
    return _kernel32 ??= DynamicLibrary.open('kernel32.dll');
  }

  /// 创建并缓存进程级 Job。handle 必须一直持有，直到本进程退出。
  static WinKillOnCloseJob? ensure() {
    if (!Platform.isWindows) return null;
    if (_instance != null) return _instance;

    final createJob = _k32.lookupFunction<IntPtr Function(IntPtr, IntPtr), int Function(int, int)>(
      'CreateJobObjectW',
    );
    final job = createJob(0, 0);
    if (job == 0) return null;

    final info = calloc<Uint8>(_extendedLimitInfoSize);
    try {
      (info.cast<Uint32>() + 4).value = _jobObjectLimitKillOnClose;
      final setInfo = _k32
          .lookupFunction<
            Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32),
            int Function(int, int, Pointer<Void>, int)
          >('SetInformationJobObject');
      final ok = setInfo(
        job,
        _jobObjectExtendedLimitInformation,
        info.cast(),
        _extendedLimitInfoSize,
      );
      if (ok == 0) {
        _closeHandle(job);
        return null;
      }
    } finally {
      calloc.free(info);
    }

    _instance = WinKillOnCloseJob._(job);
    return _instance;
  }

  /// 把当前 Dart 进程放进 Job，之后 [Process.start] 的子进程默认继承。
  static bool bindCurrentProcess() {
    final job = ensure();
    if (job == null) return false;
    final current = _k32.lookupFunction<IntPtr Function(), int Function()>('GetCurrentProcess');
    _boundCurrent = job._assignHandle(current());
    return _boundCurrent;
  }

  /// 把指定 PID 放进 Job。用于子进程没有继承到 Job 的情况。
  static bool assignPid(int pid) {
    if (pid <= 0) return false;
    final job = ensure();
    if (job == null) return false;

    final openProcess = _k32
        .lookupFunction<IntPtr Function(Uint32, Int32, Uint32), int Function(int, int, int)>(
          'OpenProcess',
        );
    final handle = openProcess(_processTerminate | _processSetQuota, 0, pid);
    if (handle == 0) return false;
    try {
      return job._assignHandle(handle);
    } finally {
      _closeHandle(handle);
    }
  }

  bool _assignHandle(int processHandle) {
    final assign = _k32.lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>(
      'AssignProcessToJobObject',
    );
    return assign(_job, processHandle) != 0;
  }

  static void _closeHandle(int handle) {
    final close = _k32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
    close(handle);
  }
}
