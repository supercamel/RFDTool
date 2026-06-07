local GSerial = import("GSerial", "1.0")
local U = import("../util.nut")

local retired_native_ports = []

function retire_native_port(native_port, handlers = null) {
    if (native_port == null) return
    local item = {
        port = native_port,
        handlers = handlers == null ? [] : handlers,
    }
    retired_native_ports.append(item)
}

async function drain_retired_ports(delay_ms = 100) {
    if (retired_native_ports.len() == 0) return
    await sqgi.sleep(delay_ms)
    retired_native_ports.clear()
}

class SerialPort {
    port = null
    path = ""
    baud = 57600
    buffer = ""
    log = null
    connected = false
    on_log = null
    on_data = null
    on_state = null
    closing = false
    generation = 0

    constructor() {
        log = []
    }

    function set_log_callback(cb) {
        on_log = cb
    }

    function set_data_callback(cb) {
        on_data = cb
    }

    function set_state_callback(cb) {
        on_state = cb
    }

    function emit_state() {
        if (on_state != null) on_state(connected)
    }

    function append_log(direction, text) {
        if (closing) return
        local entry = {
            time = U.now_stamp(),
            direction = direction,
            text = U.redact_secret(text),
        }
        log.append(entry)
        if (log.len() > 1200) log.remove(0)
        if (on_log != null) on_log(entry)
    }

    function open(device_path, baud_rate = 57600) {
        close()
        path = device_path
        baud = baud_rate
        buffer = ""
        closing = false
        generation++
        local token = generation
        port = GSerial.Port.new()
        port.set_baud(baud)
        port.set_timeout(100)

        if (!port.open(path)) {
            append_log("error", "failed to open " + path)
            retire_native_port(port)
            port = null
            connected = false
            emit_state()
            return false
        }
        connected = true
        append_log("status", "connected " + path + " @" + baud)
        emit_state()
        start_polling(token)
        return true
    }

    function start_polling(token) {
        local self = this
        sqgi.timeout_add(20, function() {
            if (self.closing || token != self.generation) return false
            if (self.port == null || !self.port.is_open()) return false
            local available = self.port.bytes_available()
            if (available > 0) self.handle_data(available)
            return true
        })
    }

    function close(immediate_disconnect = true) {
        if (port != null) {
            local native_port = port
            generation++
            closing = true
            if (native_port.is_open()) {
                native_port.close()
            }
            retire_native_port(native_port)
        }
        port = null
        connected = false
        closing = false
        emit_state()
    }

    function is_open() {
        return port != null && port.is_open()
    }

    function handle_data(available) {
        if (port == null || available <= 0) return
        local data = port.read_string(available)
        if (data == null || data.len() == 0) return
        buffer += data
        append_log("rx", data)
        if (on_data != null) on_data(data)
    }

    function write(text) {
        if (!is_open()) throw "serial port is not open"
        append_log("tx", text)
        local written = port.write_string(text)
        if (written < text.len()) throw "short serial write"
        return written
    }

    function clear_buffer() {
        buffer = ""
    }

    function get_buffer() {
        return buffer
    }

    function take_buffer() {
        local out = buffer
        buffer = ""
        return out
    }

    function get_log_text() {
        local lines = []
        foreach (e in log) {
            lines.append("[" + e.time + "] " + e.direction + " " + U.redact_secret(e.text))
        }
        return U.join(lines, "\n")
    }
}

return {
    SerialPort = SerialPort,
    drain_retired_ports = drain_retired_ports,
}
