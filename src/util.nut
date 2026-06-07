local GLib = import("GLib")

function starts_with(s, prefix) {
    return s != null && prefix != null && s.find(prefix) == 0
}

function ends_with(s, suffix) {
    if (s == null || suffix == null) return false
    if (s.len() < suffix.len()) return false
    return s.slice(s.len() - suffix.len()) == suffix
}

function contains(s, needle) {
    if (s == null || needle == null) return false
    return s.find(needle) != null
}

function is_space(ch) {
    return ch == " " || ch == "\t" || ch == "\r" || ch == "\n"
}

function trim(s) {
    if (s == null) return ""
    local a = 0
    local b = s.len()
    while (a < b && is_space(s.slice(a, a + 1))) a++
    while (b > a && is_space(s.slice(b - 1, b))) b--
    return s.slice(a, b)
}

function strip_comment(s) {
    local p = s.find("#")
    if (p == null) return s
    return s.slice(0, p)
}

function split_char(s, ch) {
    local out = []
    local start = 0
    for (local i = 0; i < s.len(); i++) {
        if (s.slice(i, i + 1) == ch) {
            out.append(s.slice(start, i))
            start = i + 1
        }
    }
    out.append(s.slice(start))
    return out
}

function split_lines(s) {
    local raw = split_char(s == null ? "" : s, "\n")
    local out = []
    foreach (line in raw) {
        local t = trim(line)
        if (t.len() > 0) out.append(t)
    }
    return out
}

function split_words(s) {
    local out = []
    local current = ""
    for (local i = 0; i < s.len(); i++) {
        local ch = s.slice(i, i + 1)
        if (is_space(ch)) {
            if (current.len() > 0) {
                out.append(current)
                current = ""
            }
        } else {
            current += ch
        }
    }
    if (current.len() > 0) out.append(current)
    return out
}

function replace_all(s, needle, replacement) {
    if (needle.len() == 0) return s
    local out = ""
    local start = 0
    while (true) {
        local p = s.find(needle, start)
        if (p == null) {
            out += s.slice(start)
            break
        }
        out += s.slice(start, p) + replacement
        start = p + needle.len()
    }
    return out
}

function join(parts, sep) {
    local out = ""
    for (local i = 0; i < parts.len(); i++) {
        if (i > 0) out += sep
        out += parts[i].tostring()
    }
    return out
}

function table_get(t, key, fallback = null) {
    if (t == null) return fallback
    return key in t ? t[key] : fallback
}

function clone_table(t) {
    local out = {}
    foreach (k, v in t) out[k] <- v
    return out
}

function string_or_empty(v) {
    return v == null ? "" : v.tostring()
}

function to_int_or_null(v) {
    if (v == null) return null
    try {
        return v.tointeger()
    } catch (e) {
        return null
    }
}

function looks_int(s) {
    if (s == null || s.len() == 0) return false
    local i = 0
    if (s.slice(0, 1) == "-" || s.slice(0, 1) == "+") i = 1
    if (i >= s.len()) return false
    for (; i < s.len(); i++) {
        local ch = s.slice(i, i + 1)
        if (ch < "0" || ch > "9") return false
    }
    return true
}

function is_hex_string(s) {
    if (s == null || s.len() == 0) return false
    for (local i = 0; i < s.len(); i++) {
        local ch = s.slice(i, i + 1)
        local hex = (ch >= "0" && ch <= "9") ||
            (ch >= "A" && ch <= "F") ||
            (ch >= "a" && ch <= "f")
        if (!hex) return false
    }
    return true
}

function secure_random_hex(byte_count) {
    if (byte_count <= 0) throw "random byte count must be positive"
    local f = null
    try {
        f = ::file("/dev/urandom", "rb")
        local out = ""
        for (local i = 0; i < byte_count; i++) {
            out += format("%02X", f.readn(98))
        }
        f.close()
        return out
    } catch (e) {
        if (f != null) {
            try { f.close() } catch (close_error) {}
        }
        throw e
    }
}

function redact_secret(s) {
    if (s == null) return ""
    local out = s
    foreach (prefix in ["AT&E=", "RT&E="]) {
        local p = out.find(prefix)
        if (p != null) {
            local start = p + prefix.len()
            local end = start
            while (end < out.len()) {
                local ch = out.slice(end, end + 1)
                local hex = (ch >= "0" && ch <= "9") ||
                    (ch >= "A" && ch <= "F") ||
                    (ch >= "a" && ch <= "f")
                if (!hex) break
                end++
            }
            if (end > start) {
                out = out.slice(0, start) + "<redacted>" + out.slice(end)
            }
        }
    }
    return out
}

function now_stamp() {
    local dt = GLib.DateTime.new_now_local()
    return dt.format("%Y-%m-%d %H:%M:%S")
}

return {
    starts_with = starts_with,
    ends_with = ends_with,
    contains = contains,
    trim = trim,
    strip_comment = strip_comment,
    split_char = split_char,
    split_lines = split_lines,
    split_words = split_words,
    replace_all = replace_all,
    join = join,
    table_get = table_get,
    clone_table = clone_table,
    string_or_empty = string_or_empty,
    to_int_or_null = to_int_or_null,
    looks_int = looks_int,
    is_hex_string = is_hex_string,
    secure_random_hex = secure_random_hex,
    redact_secret = redact_secret,
    now_stamp = now_stamp,
}
