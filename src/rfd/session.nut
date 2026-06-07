local GLib = import("GLib")
local U = import("../util.nut")
local Parser = import("parser.nut")
local Model = import("model.nut")

function at_command(scope, suffix) {
    return (scope == "remote" ? "RT" : "AT") + suffix
}

function raw_has_line(raw, expected) {
    foreach (line in U.split_lines(raw)) {
        if (U.trim(line) == expected) return true
    }
    return false
}

class RfdSession {
    serial = null
    in_command_mode = false
    busy = false
    default_timeout_ms = 2500
    remote_timeout_ms = 5000

    constructor(serial_port) {
        serial = serial_port
    }

    function ensure_open() {
        if (serial == null || !serial.is_open()) throw "serial port is not open"
    }

    async function wait_for_terminal(timeout_ms, allow_quiet = false, quiet_ms = 450, label = "radio response") {
        local start_us = GLib.get_monotonic_time()
        local last_len = -1
        local last_change_us = start_us
        while (true) {
            local raw = serial.get_buffer()
            if (Parser.response_error(raw)) throw "radio returned ERROR"
            if (Parser.response_ok(raw)) return raw
            if (raw.len() != last_len) {
                last_len = raw.len()
                last_change_us = GLib.get_monotonic_time()
            }
            local elapsed = (GLib.get_monotonic_time() - start_us) / 1000
            local quiet = (GLib.get_monotonic_time() - last_change_us) / 1000
            if (allow_quiet && raw.len() > 0 && quiet >= quiet_ms) return raw
            if (elapsed > timeout_ms) {
                local detail = raw.len() > 0 ? " after partial response: " + U.redact_secret(raw) : ""
                throw "timeout waiting for " + label + detail
            }
            await sqgi.sleep(20)
        }
    }

    async function enter_command_mode() {
        ensure_open()
        if (in_command_mode) return true

        local last_error = "failed to enter command mode"
        for (local attempt = 0; attempt < 3; attempt++) {
            try {
                local at_probe = await send_raw("AT", 900, false)
                if (at_probe.ok) {
                    in_command_mode = true
                    return true
                }
            } catch (probe_error) {
            }

            serial.clear_buffer()
            await sqgi.sleep(attempt == 0 ? 1200 : 1700)
            serial.write("+++")
            try {
                local raw = await wait_for_terminal(default_timeout_ms, false, 450, "command-mode guard response")
                if (Parser.response_ok(raw)) {
                    in_command_mode = true
                    return true
                }
                last_error = "failed to enter command mode"
            } catch (e) {
                last_error = e
                // If the modem is already in command mode, "+++" is treated as
                // ordinary input and may only be echoed. Probe with ATI before
                // declaring failure.
                try {
                    local probe = await send_raw("ATI", 1800, true)
                    if (probe.body.find("RFD") != null || probe.body.find("SiK") != null) {
                        in_command_mode = true
                        return true
                    }
                } catch (probe_error) {
                }
            }
            await sqgi.sleep(500)
        }
        throw last_error
    }

    async function leave_command_mode() {
        if (!in_command_mode) return true
        try {
            await send_raw("ATO", default_timeout_ms, true)
        } catch (e) {
            // Legacy SiK builds often echo ATO and return to transparent mode
            // without a trailing OK. Treat timeout as non-fatal for shutdown.
        }
        in_command_mode = false
        return true
    }

    async function send_raw(command, timeout_ms = null, allow_quiet = false) {
        ensure_open()
        if (timeout_ms == null) timeout_ms = default_timeout_ms
        serial.clear_buffer()
        serial.write(command + "\r\n")
        local raw = await wait_for_terminal(timeout_ms, allow_quiet, timeout_ms > 4500 ? 750 : 450, command)
        return {
            command = command,
            raw = raw,
            body = Parser.strip_terminal_lines(raw, command),
            ok = Parser.response_ok(raw),
        }
    }

    async function send_echo_control(command, timeout_ms = null) {
        ensure_open()
        if (timeout_ms == null) timeout_ms = default_timeout_ms
        serial.clear_buffer()
        serial.write(command + "\r\n")
        local start_us = GLib.get_monotonic_time()
        while (true) {
            local raw = serial.get_buffer()
            if (Parser.response_error(raw)) throw "radio returned ERROR"
            if (Parser.response_ok(raw) || raw_has_line(raw, command)) {
                return {
                    command = command,
                    raw = raw,
                    body = Parser.strip_terminal_lines(raw, command),
                    ok = Parser.response_ok(raw),
                }
            }
            local elapsed = (GLib.get_monotonic_time() - start_us) / 1000
            if (elapsed > timeout_ms) {
                local detail = raw.len() > 0 ? " after partial response: " + U.redact_secret(raw) : ""
                throw "timeout waiting for " + command + " echo" + detail
            }
            await sqgi.sleep(20)
        }
    }

    async function command(scope, suffix, timeout_ms = null) {
        await enter_command_mode()
        if (timeout_ms == null) timeout_ms = scope == "remote" ? remote_timeout_ms : default_timeout_ms
        return await send_raw(at_command(scope, suffix), timeout_ms)
    }

    async function query(scope, suffix, timeout_ms = null) {
        await enter_command_mode()
        if (timeout_ms == null) timeout_ms = scope == "remote" ? remote_timeout_ms : default_timeout_ms
        return await send_raw(at_command(scope, suffix), timeout_ms, true)
    }

    async function load_side(scope) {
        local summary = {}
        local raw = {}
        local info_cmds = ["I", "I1", "I2", "I3", "I4", "I6", "I7", "I8", "I9"]
        foreach (suffix in info_cmds) {
            try {
                local res = await query(scope, suffix)
                raw[suffix] <- res.body
                if (suffix == "I") summary.firmware <- Parser.parse_firmware(res.body)
            } catch (e) {
                raw[suffix] <- "unavailable: " + e
            }
        }

        local values = await query(scope, "I5", scope == "remote" ? 8000 : 3500)
        local ranges = null
        try {
            ranges = await query(scope, "I5?", scope == "remote" ? 8000 : 3500)
        } catch (e) {
            ranges = { body = "" }
            raw["I5?"] <- "unavailable: " + e
        }
        raw["I5"] <- values.body
        if (!("I5?" in raw)) raw["I5?"] <- ranges.body

        local params = Parser.make_parameters(values.body, ranges.body)
        return {
            scope = scope,
            summary = summary,
            raw = raw,
            params = params,
        }
    }

    async function query_register(scope, reg, num) {
        local res = await query(scope, reg + num + "?")
        return Parser.parse_single_register(res.body)
    }

    async function set_register(scope, meta, value) {
        local validation = Model.validate_value(meta, value, false)
        if (!validation.ok) throw validation.message
        local suffix = meta.reg + meta.num + "=" + value
        local timeout_ms = scope == "remote" ? remote_timeout_ms : 3500
        local res = await send_raw(at_command(scope, suffix), timeout_ms, true)
        if (res.ok) return res

        local expected = Model.int_value(value)
        try {
            local current = await query_register(scope, meta.reg, meta.num)
            if (current != null && Model.int_value(current.value) == expected) {
                return res
            }
        } catch (verify_error) {
        }
        throw "radio did not confirm " + at_command(scope, suffix)
    }

    async function save(scope) {
        return await command(scope, "&W", scope == "remote" ? 8000 : 3500)
    }

    async function reboot(scope) {
        await enter_command_mode()
        local command_text = at_command(scope, "Z")
        local res = null
        try {
            res = await send_raw(command_text, scope == "remote" ? 8000 : 3500, true)
        } catch (e) {
            local raw = serial.get_buffer()
            if (Parser.response_error(raw)) throw e
            res = {
                command = command_text,
                raw = raw,
                body = Parser.strip_terminal_lines(raw, command_text),
                ok = false,
                warning = e,
            }
        }
        in_command_mode = false
        return res
    }

    async function factory_reset(scope) {
        return await command(scope, "&F", scope == "remote" ? 8000 : 3500)
    }

    async function diagnostics(scope, mode) {
        if (mode == "rssi") return await debug_report(scope, "RSSI")
        if (mode == "tdm") return await debug_report(scope, "TDM")
        if (mode == "stop") return await debug_report(scope, null)
        if (mode == "info6") return await query(scope, "I6", 3500)
        if (mode == "info7") return await query(scope, "I7", 3500)
        throw "unknown diagnostic mode: " + mode
    }

    async function debug_report(scope, report) {
        await enter_command_mode()
        local suffix = report == null ? "&T" : "&T=" + report
        return await send_echo_control(at_command(scope, suffix), scope == "remote" ? remote_timeout_ms : 2500)
    }

    async function gpio(scope, command_name, a = null, b = null) {
        if (command_name == "print") return await query(scope, "PP", 3000)
        if (command_name == "input") return await command(scope, "PI=" + a, 3000)
        if (command_name == "output") return await command(scope, "PO=" + a, 3000)
        if (command_name == "mirror") return await command(scope, "PM=" + a, 3000)
        if (command_name == "read") return await query(scope, "PR=" + a, 3000)
        if (command_name == "write") return await command(scope, "PC=" + a + "," + b, 3000)
        throw "unknown GPIO command: " + command_name
    }

    async function encryption(scope, key = null) {
        if (key == null || key == "") return await command(scope, "&E?", 3500)
        return await command(scope, "&E=" + key, scope == "remote" ? 8000 : 3500)
    }

    function preview_change(scope, meta, value) {
        return at_command(scope, meta.reg + meta.num + "=" + value)
    }

    function preview_save(scope) {
        return at_command(scope, "&W")
    }

    function preview_reboot(scope) {
        return at_command(scope, "Z")
    }
}

return {
    RfdSession = RfdSession,
    at_command = at_command,
}
