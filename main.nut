local GLib = import("GLib")

function arg_value(name, fallback) {
    foreach (a in vargv) {
        if (a.find(name + "=") == 0) return a.slice(name.len() + 1)
    }
    return fallback
}

function has_arg(name) {
    foreach (a in vargv) {
        if (a == name) return true
    }
    return false
}

function print_help() {
    print("RFDTool\n")
    print("  sqgi main.nut                 launch GTK4 utility\n")
    print("  sqgi main.nut --self-test     run parser/session tests\n")
    print("  sqgi main.nut --probe         read local ATI/ATI5 from the modem\n")
    print("  sqgi main.nut --refresh-local exercise the same read path as the GTK refresh button\n")
    print("  sqgi main.nut --gtk-refresh-local-test run Connect + Refresh Local in the GTK window\n")
    print("  sqgi main.nut --gtk-edit-param-test run GTK refresh, then edit local S4/TXPOWER\n")
    print("  sqgi main.nut --gtk-apply-local-test run GTK refresh, edit local S4/TXPOWER, then Apply Local\n")
    print("  sqgi main.nut --gtk-save-reboot-local-test run GTK refresh, edit local S4/TXPOWER, then Save + Reboot local\n")
    print("  sqgi main.nut --probe --device=/dev/ttyUSB0 --baud=57600\n")
}

if (has_arg("--help") || has_arg("-h")) {
    print_help()
    return 0
}

if (has_arg("--self-test")) {
    import("test/parser_tests.nut")
    import("test/session_tests.nut")
    print("[OK] all self-tests passed\n")
    return 0
}

if (has_arg("--probe") || has_arg("--refresh-local")) {
    local SerialMod = import("src/serial/port.nut")
    local SessionMod = import("src/rfd/session.nut")

    local device = arg_value("--device", "/dev/ttyUSB0")
    local baud = arg_value("--baud", "57600").tointeger()
    local loop = GLib.MainLoop.new(null, false)
    local probe_serial = null

    async function probe() {
        probe_serial = SerialMod.SerialPort()
        probe_serial.set_log_callback(function(entry) {
            print("[" + entry.time + "] " + entry.direction + " " + entry.text + "\n")
        })
        if (!probe_serial.open(device, baud)) throw "failed to open " + device

        local session = SessionMod.RfdSession(probe_serial)
        await session.enter_command_mode()
        if (has_arg("--refresh-local")) {
            local data = await session.load_side("local")
            if ("firmware" in data.summary) {
                print("\nFirmware:\n" + data.summary.firmware.raw + "\n")
            }
            print("\nLoaded parameters: " + data.params.len() + "\n")
            print("\nATI5:\n" + data.raw.I5 + "\n")
        } else {
            local fw = await session.command("local", "I")
            print("\nFirmware:\n" + fw.body + "\n")
            local params = await session.command("local", "I5")
            print("\nParameters:\n" + params.body + "\n")
        }
        await session.leave_command_mode()
        probe_serial.close()
        probe_serial = null
        await SerialMod.drain_retired_ports()
        loop.quit()
    }

    probe().catch(function(e) {
        async function cleanup_error() {
            if (probe_serial != null) {
                probe_serial.close()
                probe_serial = null
                await SerialMod.drain_retired_ports()
            }
            print("probe error: " + e + "\n")
            loop.quit()
        }
        cleanup_error()
    })
    loop.run()
    return 0
}

local UI = import("src/ui/window.nut")
local app
if (has_arg("--gtk-refresh-local-test") || has_arg("--gtk-edit-param-test") ||
    has_arg("--gtk-apply-local-test") || has_arg("--gtk-save-reboot-local-test")) {
    local test_app_id = "au.com.rfdesign.rfdtool.refresh-test"
    if (has_arg("--gtk-edit-param-test")) test_app_id = "au.com.rfdesign.rfdtool.edit-test"
    if (has_arg("--gtk-apply-local-test")) test_app_id = "au.com.rfdesign.rfdtool.apply-test"
    if (has_arg("--gtk-save-reboot-local-test")) test_app_id = "au.com.rfdesign.rfdtool.save-reboot-test"

    app = UI.create_app({
        app_id = test_app_id,
        auto_refresh_local = true,
        auto_edit_param = has_arg("--gtk-edit-param-test") || has_arg("--gtk-apply-local-test") ||
            has_arg("--gtk-save-reboot-local-test"),
        auto_apply_local = has_arg("--gtk-apply-local-test") || has_arg("--gtk-save-reboot-local-test"),
        auto_save = has_arg("--gtk-save-reboot-local-test"),
        auto_reboot = has_arg("--gtk-save-reboot-local-test"),
        edit_key = arg_value("--edit-key", "S4"),
        edit_value = arg_value("--edit-value", "29"),
        device = arg_value("--device", "/dev/ttyUSB0"),
        baud = arg_value("--baud", "57600").tointeger(),
    })
} else {
    app = UI.create_app()
}
return app.run(0, null)
