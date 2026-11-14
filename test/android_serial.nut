// Integration test for the real Android JNI/GI backend. The simulated adapter
// is enabled only by sqgipkg.android-test.json, never in production APKs.
local Gtk = import("Gtk", "4.0"), Gio = import("Gio"), GLib = import("GLib")
local DevicesMod = import("../src/serial/devices.nut")
local SerialMod = import("../src/serial/port.nut")
local app = Gtk.Application.new("com.github.supercamel.rfdtool.serialtest", Gio.ApplicationFlags.flags_none)
local devices = DevicesMod.Devices(), port = SerialMod.SerialPort(), status = null
local finished = false

function check(ok, message) { if (!ok) throw message }
function finish(ok, message) {
    finished = true
    devices.cancel(); port.close()
    local result = (ok ? "RFDTOOL_ANDROID_SERIAL_PASS: " : "RFDTOOL_ANDROID_SERIAL_FAIL: ") + message
    print(result + "\n")
    status.set_text(result)
}

async function run() {
    local found = false
    foreach (device in devices.list()) if (device.path == "gserial-test://loopback") found = true
    check(found, "test adapter enumeration")
    local denied = false
    try { await devices.resolve("gserial-test://denied") } catch (e) { denied = true }
    check(denied && !devices.waiting(), "permission denial")
    sqgi.timeout_add(5, function() { devices.cancel(); return false })
    check((await devices.resolve("gserial-test://loopback")) == null, "permission cancellation")
    local path = await devices.resolve("gserial-test://loopback")
    port.open(path, 57600)
    local payload = "ATI5\r\npartial-write-test\r\n"
    check(port.write(payload) == payload.len(), "partial write completion")
    local started = GLib.get_monotonic_time()
    while (port.get_buffer().len() < payload.len()) {
        check(GLib.get_monotonic_time() - started < 5000000, "read timeout")
        await sqgi.sleep(20)
    }
    check(port.take_buffer() == payload, "JNI serial byte roundtrip")
    port.close()
    port.open(await devices.resolve("gserial-test://loopback"), 57600)
    local disconnected = false
    port.set_state_callback(function(opened) { if (!opened) disconnected = true })
    port.write("\x04") // Test backend's detach trigger.
    started = GLib.get_monotonic_time()
    while (!disconnected) {
        check(GLib.get_monotonic_time() - started < 5000000, "detach timeout")
        await sqgi.sleep(20)
    }
    check(!port.is_open(), "detach closes port")
    finish(true, "enumeration, denial, cancellation, permission grant, partial I/O, reopen, detach")
}

app.connect("activate", function() {
    local win = Gtk.ApplicationWindow.new(app)
    status = Gtk.Label.new("Testing RFDTool Android serial access")
    status.set_wrap(true); win.set_child(status); win.present()
    run().catch(function(e) { finish(false, e.tostring()) })
    sqgi.timeout_add(15000, function() {
        if (!finished) finish(false, "integration test timeout")
        return false
    })
})
app.run(["rfdtool-serial-test"])
