local U = import("../util.nut")
local Model = import("model.nut")

function first_word(s) {
    local words = U.split_words(s)
    return words.len() == 0 ? "" : words[0]
}

function clean_token(s) {
    local t = U.trim(s)
    while (t.len() > 0) {
        local ch = t.slice(t.len() - 1, t.len())
        if (ch == "," || ch == ";" || ch == ")" || ch == "]") {
            t = t.slice(0, t.len() - 1)
        } else {
            break
        }
    }
    while (t.len() > 0) {
        local ch = t.slice(0, 1)
        if (ch == "(" || ch == "[") {
            t = t.slice(1)
        } else {
            break
        }
    }
    return t
}

function find_last(s, needle) {
    local at = null
    local start = 0
    while (true) {
        local p = s.find(needle, start)
        if (p == null) break
        at = p
        start = p + 1
    }
    return at
}

function parse_region_from_firmware(line) {
    local p = find_last(line, "-")
    if (p == null || p + 3 > line.len()) return "unlocked"
    local suffix = line.slice(p + 1)
    if (suffix.len() < 2) return "unlocked"
    local region = suffix.slice(0, 2).toupper()
    foreach (known in ["AU", "NZ", "US", "EU", "IN"]) {
        if (region == known) return region
    }
    return "unlocked"
}

function parse_firmware(text) {
    local lines = U.split_lines(text)
    local fw = {
        raw = U.trim(text),
        version = "",
        board = "",
        region = "unknown",
        country_locked = false,
    }

    foreach (line in lines) {
        if (line == "OK" || line == "ERROR") continue
        if (U.starts_with(line, "ATI")) continue
        fw.raw = line
        fw.region = parse_region_from_firmware(line)
        fw.country_locked = fw.region != "unlocked"

        local on_pos = line.find(" on ")
        if (on_pos != null) {
            fw.version = U.trim(line.slice(0, on_pos))
            fw.board = U.trim(line.slice(on_pos + 4))
        } else {
            fw.version = line
        }
        break
    }
    return fw
}

function parse_number_prefix(line) {
    if (line.len() < 2) return null
    local first = line.slice(0, 1).toupper()
    local reg
    local start
    if (first == "S" || first == "R") {
        // SiK/RFD firmware that prefixes registers with the bank letter, e.g. "S4:TXPOWER=20".
        reg = first
        start = 1
    } else if (first >= "0" && first <= "9") {
        // Older SiK firmware (e.g. RFD900A SiK 1.13) emits bare register numbers
        // with no bank letter, e.g. " 4:TXPOWER=20". Treat these as S registers.
        reg = "S"
        start = 0
    } else {
        return null
    }
    local i = start
    while (i < line.len()) {
        local ch = line.slice(i, i + 1)
        if (ch < "0" || ch > "9") break
        i++
    }
    if (i == start) return null
    return { reg = reg, num = line.slice(start, i).tointeger(), rest = U.trim(line.slice(i)) }
}

function parse_range(rest) {
    local out = { min = null, max = null }

    local p = rest.find("..")
    if (p != null) {
        local left = U.trim(rest.slice(0, p))
        local right = U.trim(rest.slice(p + 2))
        local left_words = U.split_words(left)
        local right_words = U.split_words(right)
        if (left_words.len() > 0 && right_words.len() > 0) {
            local a = clean_token(left_words.top())
            local b = clean_token(right_words[0])
            if (U.looks_int(a) && U.looks_int(b)) {
                out.min = a.tointeger()
                out.max = b.tointeger()
                return out
            }
        }
    }

    local words = U.split_words(rest)
    local ints = []
    foreach (w in words) {
        local t = clean_token(w)
        if (U.looks_int(t)) ints.append(t.tointeger())
    }
    if (ints.len() >= 2 && rest.find("min") != null && rest.find("max") != null) {
        out.min = ints[0]
        out.max = ints[1]
    }
    return out
}

function parse_register_line(line) {
    local clean = U.trim(U.strip_comment(line))
    if (clean.len() == 0 || clean == "OK" || clean == "ERROR") return null
    local pref = parse_number_prefix(clean)
    if (pref == null) return null

    local rest = pref.rest
    if (U.starts_with(rest, ":")) rest = U.trim(rest.slice(1))

    local key = pref.reg + pref.num.tostring()
    local name = key
    local value = null
    local desc = rest
    local range = parse_range(rest)

    if (U.starts_with(rest, "=")) {
        local token = first_word(rest.slice(1))
        value = clean_token(token)
    } else {
        local eq = rest.find("=")
        if (eq != null) {
            name = U.trim(rest.slice(0, eq))
            local value_part = U.trim(rest.slice(eq + 1))
            value = clean_token(first_word(value_part))
            desc = name
        } else {
            local words = U.split_words(rest)
            if (words.len() > 0) {
                if (U.looks_int(clean_token(words[0]))) {
                    value = clean_token(words[0])
                } else {
                    name = clean_token(words[0])
                    for (local i = 1; i < words.len(); i++) {
                        local token = clean_token(words[i])
                        if (U.looks_int(token)) {
                            value = token
                            break
                        }
                    }
                }
            }
        }
    }

    local iv = Model.int_value(value)
    local meta = {
        key = key,
        reg = pref.reg,
        num = pref.num,
        name = name == "" ? key : name,
        description = desc,
        live_line = line,
    }
    if (range.min != null) meta.min <- range.min
    if (range.max != null) meta.max <- range.max
    if (iv != null) meta.value <- iv
    return meta
}

function parse_register_table(text) {
    local out = {}
    foreach (line in U.split_lines(text)) {
        local r = parse_register_line(line)
        if (r != null) out[r.key] <- r
    }
    return out
}

function make_parameters(values_text, ranges_text = "") {
    local fallback = Model.fallback_metadata()
    local live_ranges = parse_register_table(ranges_text)
    local meta = Model.merge_meta(fallback, live_ranges)
    local live_values = parse_register_table(values_text)
    local params = {}

    foreach (key, m in meta) {
        local v = null
        if (key in live_values && "value" in live_values[key]) v = live_values[key].value
        params[key] <- Model.make_parameter(m, v, key in live_values ? "live" : "fallback")
    }

    foreach (key, vmeta in live_values) {
        if (!(key in params)) {
            params[key] <- Model.make_parameter(vmeta, "value" in vmeta ? vmeta.value : null, "live")
        } else if ("value" in vmeta) {
            params[key].value = vmeta.value
            params[key].original = vmeta.value
            params[key].source = "live"
        }
    }
    return params
}

function strip_terminal_lines(raw, command = "") {
    local out = []
    foreach (line in U.split_lines(raw)) {
        local t = U.trim(line)
        if (t == "" || t == "OK" || t == "ERROR") continue
        if (command != "" && t == command) continue
        out.append(t)
    }
    return U.join(out, "\n")
}

function response_ok(raw) {
    foreach (line in U.split_lines(raw)) {
        if (U.trim(line) == "OK") return true
    }
    return false
}

function response_error(raw) {
    foreach (line in U.split_lines(raw)) {
        if (U.trim(line) == "ERROR") return true
    }
    return false
}

function parse_single_register(raw) {
    local parsed = parse_register_table(raw)
    foreach (k, v in parsed) {
        if ("value" in v) return { key = k, value = v.value, meta = v }
    }
    local clean = strip_terminal_lines(raw)
    if (U.looks_int(U.trim(clean))) return { key = "", value = U.trim(clean).tointeger(), meta = null }
    return null
}

function token_after_label(line, label_text) {
    local p = line.tolower().find(label_text.tolower())
    if (p == null) return null
    local rest = U.trim(line.slice(p + label_text.len()))
    local words = U.split_words(rest)
    if (words.len() == 0) return null
    return clean_token(words[0])
}

function parse_pair_after(line, label_text) {
    local token = token_after_label(line, label_text)
    if (token == null) return null
    local parts = U.split_char(token, "/")
    if (parts.len() < 2) return null
    local left = clean_token(parts[0])
    local right = clean_token(parts[1])
    if (!U.looks_int(left) || !U.looks_int(right)) return null
    return { left = left.tointeger(), right = right.tointeger() }
}

function parse_value_after(line, label_text) {
    local token = token_after_label(line, label_text)
    if (token == null || !U.looks_int(token)) return null
    return token.tointeger()
}

function parse_link_report(line) {
    local clean = U.trim(line)
    if (clean == "") return null
    local lower = clean.tolower()
    if (lower.find("rssi") == null && lower.find("noise") == null) return null

    local out = { raw = clean }
    local rssi = parse_pair_after(clean, "RSSI:")
    if (rssi != null) {
        out.local_rssi <- rssi.left
        out.remote_rssi <- rssi.right
    }
    local noise = parse_pair_after(clean, "noise:")
    if (noise != null) {
        out.local_noise <- noise.left
        out.remote_noise <- noise.right
    }
    local ecc = parse_pair_after(clean, "ecc=")
    if (ecc != null) {
        out.local_ecc <- ecc.left
        out.remote_ecc <- ecc.right
    }

    foreach (spec in [
        { key = "packets", label = "pkts:" },
        { key = "txe", label = "txe=" },
        { key = "rxe", label = "rxe=" },
        { key = "stx", label = "stx=" },
        { key = "srx", label = "srx=" },
        { key = "temp", label = "temp=" },
        { key = "dco", label = "dco=" },
    ]) {
        local value = parse_value_after(clean, spec.label)
        if (value != null) out[spec.key] <- value
    }

    if (!("local_rssi" in out) && !("remote_rssi" in out) &&
        !("local_noise" in out) && !("remote_noise" in out)) {
        return null
    }
    return out
}

return {
    parse_firmware = parse_firmware,
    parse_region_from_firmware = parse_region_from_firmware,
    parse_register_line = parse_register_line,
    parse_register_table = parse_register_table,
    make_parameters = make_parameters,
    strip_terminal_lines = strip_terminal_lines,
    response_ok = response_ok,
    response_error = response_error,
    parse_single_register = parse_single_register,
    parse_link_report = parse_link_report,
}
