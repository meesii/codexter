/// 固定上限的输出缓冲，超限时丢弃最旧内容
class RollingBuffer {
    final int maxChars;
    final StringBuffer _buffer = StringBuffer();
    bool _truncated = false;

    RollingBuffer(this.maxChars);

    int get length => _buffer.length;

    bool get truncated => _truncated;

    String get text => _buffer.toString();

    /// 返回值表示本次写入是否触发了截断
    bool append(String chunk) {
        if (chunk.isEmpty) return false;
        _buffer.write(chunk);
        if (_buffer.length <= maxChars) return false;
        _truncated = true;
        trimTo(maxChars);
        return true;
    }

    bool trimTo(int limit) {
        if (_buffer.length <= limit) return false;
        final current = _buffer.toString();
        final kept = current.substring(current.length - limit);
        _buffer.clear();
        _buffer.write(kept);
        return true;
    }

    void clear() {
        _buffer.clear();
        _truncated = false;
    }
}
