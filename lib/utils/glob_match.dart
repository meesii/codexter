/// glob 模式匹配。原实现先把 * 换成 [^/]* 导致 ** 永远失效，这里按字符扫描
class GlobMatch {
    const GlobMatch._();

    static final _cache = <String, RegExp>{};

    static RegExp compile(String pattern) {
        final cached = _cache[pattern];
        if (cached != null) return cached;
        final regex = RegExp('^${_translate(pattern)}\$', caseSensitive: false);
        _cache[pattern] = regex;
        return regex;
    }

    static bool matches(String pattern, String path) {
        return compile(pattern).hasMatch(path.replaceAll('\\', '/'));
    }

    /// 只给了扩展名或裸文件名时补成 **/ 前缀，方便 include: "*.dart" 之类的用法
    static String normalize(String pattern) {
        final cleaned = pattern.replaceAll('\\', '/').trim();
        if (cleaned.isEmpty) return '**';
        if (cleaned.startsWith('**')) return cleaned;
        if (!cleaned.contains('/')) return '**/$cleaned';
        return cleaned;
    }

    static String _translate(String pattern) {
        final source = pattern.replaceAll('\\', '/');
        final out = StringBuffer();
        var index = 0;

        while (index < source.length) {
            final char = source[index];

            if (char == '*') {
                final isDoubleStar = index + 1 < source.length && source[index + 1] == '*';
                if (isDoubleStar) {
                    final hasSlash = index + 2 < source.length && source[index + 2] == '/';
                    if (hasSlash) {
                        out.write('(?:.*/)?');
                        index += 3;
                    } else {
                        out.write('.*');
                        index += 2;
                    }
                    continue;
                }
                out.write('[^/]*');
                index += 1;
                continue;
            }

            if (char == '?') {
                out.write('[^/]');
                index += 1;
                continue;
            }

            if (char == '{') {
                final closeIndex = source.indexOf('}', index);
                if (closeIndex > index) {
                    final options = source.substring(index + 1, closeIndex).split(',');
                    out.write('(?:${options.map(_translate).join('|')})');
                    index = closeIndex + 1;
                    continue;
                }
            }

            if ('.+^\$()[]|\\'.contains(char)) {
                out.write('\\$char');
                index += 1;
                continue;
            }

            out.write(char);
            index += 1;
        }

        return out.toString();
    }
}
