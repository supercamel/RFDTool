// Exercise the real GTK allocations, including rotation and every notebook page.
// This entry also runs unchanged inside the Android layout-test APK.
local Gtk = import("Gtk", "4.0")
local GLib = import("GLib")
local UI = import("../src/ui/window.nut")
local failure = null
local android = GLib.getenv("ANDROID_ROOT") != null

function check(ok, message) { if (!ok) throw message }

async function wait_for_allocation(win) {
    local started = GLib.get_monotonic_time()
    local last_width = 0, last_height = 0, stable = 0
    while (GLib.get_monotonic_time() - started < 10000000) {
        await sqgi.sleep(100)
        local width = win.get_width(), height = win.get_height()
        if (win.get_mapped() && width > 0 && height > 0 &&
            width == last_width && height == last_height) stable++
        else stable = 0
        if (stable >= 3) return
        last_width = width
        last_height = height
    }
    throw "window did not receive a stable allocation within 10 seconds"
}

function check_widths(widget, width) {
    if (!widget.get_mapped()) return
    check(widget.get_width() <= width + 1,
        "widget exceeds viewport: " + widget.get_name() + " width=" + widget.get_width() + " viewport=" + width)
    local child = widget.get_first_child()
    while (child != null) {
        check_widths(child, width)
        child = child.get_next_sibling()
    }
}

local app = UI.create_app({
    app_id = "com.github.supercamel.rfdtool.layouttest",
    width = 360, height = 640,
    on_ready = function(w) {
        async function run() {
            w.supported_only.set_active(false)
            // Long adapter identities and status messages must not widen a phone.
            w.port_combo.append("usb://long-device-identity/0", "USB Serial adapter with a long name — usb://long-device-identity/0")
            w.port_combo.set_active_id("usb://long-device-identity/0")
            w.status.set_text("Select a device and baud rate, then connect. USB permission is requested only when connecting.")
            local sizes = android ? [[0, 0]] : [[360, 640], [320, 568], [640, 360], [800, 1280], [1280, 800]]
            foreach (size in sizes) {
                if (!android) w.win.set_default_size(size[0], size[1])
                // A cold Android renderer can take longer than a fixed delay
                // to map its first surface. Never use a zero-sized viewport.
                await wait_for_allocation(w.win)
                local width = w.win.get_width()
                if (!android) check(width <= size[0], "window cannot fit requested width " + size[0] + ": " + width)
                if (!android) check(w.win.get_height() <= size[1], "window cannot fit requested height " + size[1])
                for (local page = 0; page < w.notebook.get_n_pages(); page++) {
                    w.notebook.set_current_page(page)
                    await sqgi.sleep(150)
                    check(w.notebook.get_height() > 80, "navigation leaves no room for page content")
                    check_widths(w.win.get_child(), width)
                    print("[layout] " + width + "x" + w.win.get_height() + " page=" + page + " OK\n")
                }
            }
            print("RFDTOOL_LAYOUT_PASS\n")
            w.win.close()
        }
        run().catch(function(e) {
            failure = e
            print("RFDTOOL_LAYOUT_FAIL: " + e + "\n")
            w.win.close()
        })
    }
})
app.run(["rfdtool-layout-test"])
if (failure != null) throw failure
