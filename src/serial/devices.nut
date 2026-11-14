// Device discovery never opens a port or sends radio commands.
class Devices {
    manager = null
    pending = null
    generation = 0
    handler = null

    constructor(native_manager = null) {
        if (native_manager == null) {
            local GSerial = import("GSerial", "1.0")
            if (!("DeviceManager" in GSerial))
                throw "GSerial 0.3.0 or newer is required for serial device discovery"
            native_manager = GSerial.DeviceManager.new()
        }
        manager = native_manager
        local self = this
        handler = manager.connect("permission-result", function(path, granted, message) {
            if (self.pending == null || self.pending.path != path) return
            self.pending.done = true
            self.pending.granted = granted
            self.pending.message = message
        })
    }

    function list() {
        local devices = []
        foreach (device in manager.list_devices()) {
            local path = device.get_path()
            devices.append({ path = path, label = device.get_name() + " — " + path })
        }
        return devices
    }

    function waiting() { return pending != null }

    function cancel() {
        generation++
        manager.cancel_permission()
        pending = null
    }

    async function resolve(path, discovered = true) {
        if (pending != null) throw "A device permission request is already pending"
        if (path == "") throw "Select a serial device first"
        // Keep custom desktop paths (including PTYs) available. USB URIs always
        // require lookup and permission, even if typed instead of selected.
        if (!discovered && path.find("usb://") != 0 && path.find("gserial-test://") != 0)
            return path
        local device = manager.lookup(path)
        if (device == null) throw "Serial device is no longer available: " + path
        if (device.get_has_permission()) return device.get_path()

        local token = ++generation
        local request = { path = path, done = false, granted = false, message = "" }
        pending = request
        try {
            if (!manager.request_permission(path)) throw "Could not request USB permission"
            while (!request.done && token == generation) await sqgi.sleep(20)
            if (token != generation) return null
            if (!request.granted)
                throw request.message == "" ? "USB permission was denied" : request.message
            // Permission can reveal a serial number and change the URI. Never
            // substitute another adapter if this one detached or is ambiguous.
            device = manager.lookup(path)
            if (device == null || !device.get_has_permission())
                throw "Serial device is unavailable after permission was granted"
            pending = null
            return device.get_path()
        } catch (e) {
            if (token == generation) cancel()
            throw e
        }
    }
}

return { Devices = Devices }
