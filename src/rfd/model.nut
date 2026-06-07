local U = import("../util.nut")

function choice(value, label) {
    return { value = value, label = label }
}

function add_meta(dst, item) {
    local key = item.reg + item.num.tostring()
    item.key <- key
    dst[key] <- item
}

function fallback_metadata() {
    local m = {}

    add_meta(m, {
        reg = "S", num = 0, name = "FORMAT",
        description = "EEPROM format/version set by firmware.",
        min = null, max = null, readonly = true, match = false,
        category = "System"
    })
    add_meta(m, {
        reg = "S", num = 1, name = "SERIAL_SPEED",
        description = "Serial speed in one-byte form.",
        min = 1, max = 1000, match = false, category = "Serial",
        choices = [
            choice(1, "1200 bps"), choice(2, "2400 bps"),
            choice(4, "4800 bps"), choice(9, "9600 bps"),
            choice(19, "19200 bps"), choice(38, "38400 bps"),
            choice(57, "57600 bps"), choice(115, "115200 bps"),
            choice(230, "230400 bps"), choice(460, "460800 bps"),
            choice(1000, "1000000 bps")
        ],
        high_risk = true
    })
    add_meta(m, {
        reg = "S", num = 2, name = "AIR_SPEED",
        description = "Air data rate in kbit/s or one-byte form depending on firmware.",
        min = 2, max = 750, match = true, category = "Radio Link",
        choices = [
            choice(2, "2 kbit/s"), choice(4, "4 kbit/s"),
            choice(8, "8 kbit/s"), choice(12, "12 kbit/s"),
            choice(16, "16 kbit/s"), choice(19, "19 kbit/s"),
            choice(24, "24 kbit/s"), choice(32, "32 kbit/s"),
            choice(48, "48 kbit/s"), choice(56, "56 kbit/s"),
            choice(64, "64 kbit/s"), choice(96, "96 kbit/s"),
            choice(100, "100 kbit/s"), choice(125, "125 kbit/s"),
            choice(128, "128 kbit/s"), choice(188, "188 kbit/s"),
            choice(192, "192 kbit/s"), choice(200, "200 kbit/s"),
            choice(224, "224 kbit/s"), choice(250, "250 kbit/s"),
            choice(500, "500 kbit/s"), choice(750, "750 kbit/s")
        ]
    })
    add_meta(m, {
        reg = "S", num = 3, name = "NETID",
        description = "Network ID. Radios must use the same ID to link.",
        min = 0, max = 255, match = true, category = "Radio Link"
    })
    add_meta(m, {
        reg = "S", num = 4, name = "TXPOWER",
        description = "Transmit power in dBm. Obey regional certification limits.",
        min = 0, max = 30, match = false, category = "Radio Link",
        high_risk = true
    })
    add_meta(m, {
        reg = "S", num = 5, name = "ECC",
        description = "Error correction. Disabled/ignored on some newer firmware.",
        min = 0, max = 1, match = true, category = "Radio Link",
        choices = [choice(0, "Off"), choice(1, "On")]
    })
    add_meta(m, {
        reg = "S", num = 6, name = "MAVLINK",
        description = "MAVLink framing and radio-status reporting.",
        min = 0, max = 1, match = false, category = "Protocol",
        choices = [choice(0, "Off"), choice(1, "On")]
    })
    add_meta(m, {
        reg = "S", num = 7, name = "OP_RESEND",
        description = "Opportunistic resend when spare bandwidth is available.",
        min = 0, max = 1, match = false, category = "Radio Link",
        choices = [choice(0, "Off"), choice(1, "On")]
    })
    add_meta(m, {
        reg = "S", num = 8, name = "MIN_FREQ",
        description = "Minimum hopping frequency in kHz.",
        min = 865000, max = 927000, match = true, category = "Radio Link",
        high_risk = true
    })
    add_meta(m, {
        reg = "S", num = 9, name = "MAX_FREQ",
        description = "Maximum hopping frequency in kHz.",
        min = 865000, max = 928000, match = true, category = "Radio Link",
        high_risk = true
    })
    add_meta(m, {
        reg = "S", num = 10, name = "NUM_CHANNELS",
        description = "Number of frequency-hopping channels.",
        min = 1, max = 50, match = true, category = "Radio Link",
        high_risk = true
    })
    add_meta(m, {
        reg = "S", num = 11, name = "DUTY_CYCLE",
        description = "Percentage of time the radio may transmit.",
        min = 10, max = 100, match = false, category = "Radio Link"
    })
    add_meta(m, {
        reg = "S", num = 12, name = "LBT_RSSI",
        description = "Listen-before-talk RSSI threshold.",
        min = 0, max = 220, match = true, category = "Radio Link",
        high_risk = true
    })
    add_meta(m, {
        reg = "S", num = 13, name = "RTSCTS",
        description = "Ready-to-send / clear-to-send flow control register.",
        min = 0, max = 1, match = false, category = "Serial",
        choices = [choice(0, "Off"), choice(1, "On")]
    })
    add_meta(m, {
        reg = "S", num = 14, name = "MAX_WINDOW",
        description = "Maximum transit window. Can limit latency and throughput.",
        min = 20, max = 400, match = true, category = "Protocol"
    })
    add_meta(m, {
        reg = "S", num = 15, name = "ENCRYPTION_LEVEL",
        description = "Encryption level: off, 128-bit AES, or 256-bit AES where supported.",
        min = 0, max = 2, match = true, category = "Security",
        choices = [choice(0, "Off"), choice(1, "128-bit AES"), choice(2, "256-bit AES")],
        high_risk = true
    })
    add_meta(m, {
        reg = "S", num = 16, name = "GPIO1.1_RC_INPUT",
        description = "Set GPIO1.1 as PPM/RC input.",
        min = 0, max = 1, match = false, category = "GPIO",
        choices = [choice(0, "Off"), choice(1, "On")]
    })
    add_meta(m, {
        reg = "S", num = 17, name = "GPIO1.1_RC_OUTPUT",
        description = "Set GPIO1.1 as PPM/RC output.",
        min = 0, max = 1, match = false, category = "GPIO",
        choices = [choice(0, "Off"), choice(1, "On")]
    })
    add_meta(m, {
        reg = "S", num = 18, name = "GPIO1.1_SBUS_INPUT",
        description = "Set GPIO1.1 as SBUS input.",
        min = 0, max = 1, match = false, category = "GPIO",
        choices = [choice(0, "Off"), choice(1, "On")]
    })
    add_meta(m, {
        reg = "S", num = 19, name = "GPIO1.1_SBUS_OUTPUT",
        description = "Set GPIO1.1 as SBUS output mode.",
        min = 0, max = 5, match = false, category = "GPIO",
        choices = [
            choice(0, "Off"), choice(1, "SBUS1"),
            choice(2, "SBUS2 12Ch"), choice(3, "SBUS2 18Ch"),
            choice(4, "SBUS2/1"), choice(5, "SBUS1 no failsafe")
        ]
    })
    add_meta(m, {
        reg = "S", num = 20, name = "ANT_MODE",
        description = "Antenna diversity mode.",
        min = 0, max = 3, match = false, category = "Radio Link",
        choices = [
            choice(0, "Diversity"), choice(1, "Antenna 1 only"),
            choice(2, "Antenna 2 only"), choice(3, "Antenna 1 TX / 2 RX")
        ]
    })
    add_meta(m, {
        reg = "S", num = 21, name = "STATUS_LED_OUTPUT",
        description = "Mirror status LED on GPIO1.3.",
        min = 0, max = 1, match = false, category = "GPIO",
        choices = [choice(0, "Off"), choice(1, "On")]
    })
    add_meta(m, {
        reg = "S", num = 22, name = "RS485_TX_CONTROL",
        description = "DINIO/RS485 TX control output.",
        min = 0, max = 1, match = false, category = "GPIO",
        choices = [choice(0, "Off"), choice(1, "On")]
    })
    add_meta(m, {
        reg = "S", num = 23, name = "RATE_FREQ_BAND",
        description = "Certified rate/frequency band selector.",
        min = 0, max = 3, match = true, category = "Radio Link",
        high_risk = true
    })
    add_meta(m, {
        reg = "S", num = 24, name = "GPIO1.2_AUXIN",
        description = "Auxiliary serial input on GPIO1.2.",
        min = 0, max = 1, match = false, category = "GPIO",
        choices = [choice(0, "Off"), choice(1, "On")]
    })
    add_meta(m, {
        reg = "S", num = 25, name = "GPIO1.3_AUXOUT",
        description = "Auxiliary serial output on GPIO1.3.",
        min = 0, max = 1, match = false, category = "GPIO",
        choices = [choice(0, "Off"), choice(1, "On")]
    })
    add_meta(m, {
        reg = "S", num = 26, name = "RESERVED",
        description = "Reserved firmware field.",
        min = null, max = null, readonly = true, match = false, category = "System"
    })
    add_meta(m, {
        reg = "S", num = 27, name = "RESERVED",
        description = "Reserved firmware field.",
        min = null, max = null, readonly = true, match = false, category = "System"
    })
    add_meta(m, {
        reg = "S", num = 28, name = "FSFRAMELOSS",
        description = "Missing SBUS frames before failsafe timeout.",
        min = 5, max = 50, match = false, category = "Protocol"
    })
    add_meta(m, {
        reg = "R", num = 0, name = "TARGET_RSSI",
        description = "Dynamic transmit-power target RSSI or dBm threshold. 255/0 disables on firmware-dependent builds.",
        min = 0, max = 255, match = false, category = "Radio Link"
    })
    add_meta(m, {
        reg = "R", num = 1, name = "HYSTERESIS_RSSI",
        description = "Dynamic transmit-power hysteresis.",
        min = 0, max = 50, match = false, category = "Radio Link"
    })

    return m
}

function merge_meta(defaults, live) {
    local out = U.clone_table(defaults)
    foreach (key, value in live) {
        if (key in out) {
            local merged = U.clone_table(out[key])
            foreach (k, v in value) merged[k] <- v
            out[key] = merged
        } else {
            out[key] <- value
        }
    }
    return out
}

function make_parameter(meta, value = null, source = "fallback") {
    local p = U.clone_table(meta)
    p.value <- value
    p.original <- value
    p.remote_value <- null
    p.source <- source
    p.dirty <- false
    p.error <- ""
    if (!("readonly" in p)) p.readonly <- false
    if (!("match" in p)) p.match <- false
    if (!("category" in p)) p.category <- "Other"
    if (!("description" in p)) p.description <- ""
    if (!("choices" in p)) p.choices <- null
    if (!("high_risk" in p)) p.high_risk <- false
    return p
}

function int_value(v) {
    if (typeof(v) == "integer") return v
    if (typeof(v) == "float") return v.tointeger()
    if (typeof(v) == "string" && U.looks_int(U.trim(v))) return U.trim(v).tointeger()
    return null
}

function choice_label(meta, value) {
    if (!("choices" in meta) || meta.choices == null) return value == null ? "" : value.tostring()
    local iv = int_value(value)
    foreach (c in meta.choices) {
        if (c.value == iv) return c.label
    }
    return value == null ? "" : value.tostring()
}

function validate_value(meta, value, region_locked = false) {
    if (meta == null) return { ok = false, message = "Unknown parameter" }
    if ("readonly" in meta && meta.readonly) {
        return { ok = false, message = "Read-only/reserved register" }
    }
    local iv = int_value(value)
    if (iv == null) return { ok = false, message = "Value must be an integer" }
    if ("min" in meta && meta.min != null && iv < meta.min) {
        return { ok = false, message = "Value below minimum " + meta.min }
    }
    if ("max" in meta && meta.max != null && iv > meta.max) {
        return { ok = false, message = "Value above maximum " + meta.max }
    }
    if ("choices" in meta && meta.choices != null) {
        local found = false
        foreach (c in meta.choices) {
            if (c.value == iv) found = true
        }
        if (!found) return { ok = false, message = "Value is not one of the documented choices" }
    }
    if (region_locked && "high_risk" in meta && meta.high_risk) {
        return { ok = true, message = "Region-certified/radio-critical setting; confirm legal limits" }
    }
    return { ok = true, message = "" }
}

function command_for(scope, meta, value) {
    local prefix = scope == "remote" ? "RT" : "AT"
    return prefix + meta.reg + meta.num + "=" + value
}

function query_for(scope, reg, num) {
    local prefix = scope == "remote" ? "RT" : "AT"
    return prefix + reg + num + "?"
}

function sorted_keys(params) {
    local keys = params.keys()
    keys.sort(function(a, b) {
        local ra = a.slice(0, 1)
        local rb = b.slice(0, 1)
        if (ra != rb) return ra < rb ? -1 : 1
        local na = a.slice(1).tointeger()
        local nb = b.slice(1).tointeger()
        if (na < nb) return -1
        if (na > nb) return 1
        return 0
    })
    return keys
}

return {
    fallback_metadata = fallback_metadata,
    merge_meta = merge_meta,
    make_parameter = make_parameter,
    validate_value = validate_value,
    command_for = command_for,
    query_for = query_for,
    choice_label = choice_label,
    int_value = int_value,
    sorted_keys = sorted_keys,
}
