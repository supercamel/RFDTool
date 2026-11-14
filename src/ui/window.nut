local GLib = import("GLib")
local Gio = import("Gio")
local Gdk = import("Gdk", "4.0")
local Gtk = import("Gtk", "4.0")
local Pango = import("Pango")
local cairo = import("cairo")

local U = import("../util.nut")
local SerialMod = import("../serial/port.nut")
local DevicesMod = import("../serial/devices.nut")
local SessionMod = import("../rfd/session.nut")
local Parser = import("../rfd/parser.nut")
local Model = import("../rfd/model.nut")
local Profile = import("../rfd/profile.nut")

local APP_NAME = "RFDTool"
local APP_ID = "com.github.supercamel.rfdtool"
local APP_ICON_NAME = APP_ID
local DESKTOP_RELAUNCH_ENV = "RFD_TOOL_DESKTOP_RELAUNCHED"

local W = {}
local State = {
    serial = null,
    session = null,
    devices = null,
    permission_pending = false,
    local_params = null,
    remote_params = null,
    local_summary = null,
    remote_summary = null,
    dirty_local = {},
    dirty_remote = {},
    unsaved_local = false,
    unsaved_remote = false,
    busy = false,
    region_locked = false,
    default_profile = "rfdtool-profile.json",
    window_closing = false,
    graph_samples = null,
    graph_rx_buffer = "",
    graph_window_seconds = 60.0,
}

function remember(key, value) {
    if (key in W) W[key] = value
    else W[key] <- value
    return value
}

function init_state() {
    State.local_params = Parser.make_parameters("", "")
    State.remote_params = Parser.make_parameters("", "")
    State.local_summary = {}
    State.remote_summary = {}
    remember("param_entries", {})
    W.param_entries["local"] <- {}
    W.param_entries["remote"] <- {}
    State.graph_samples = []
    State.graph_rx_buffer = ""
}

function path_exists(path) {
    return Gio.File.new_for_path(path).query_exists(null)
}

function add_icon_search_path(theme, path) {
    if (path == null || path == "" || !path_exists(path)) return
    theme.add_search_path(path)
}

function register_app_icon() {
    local display = Gdk.Display.get_default()
    if (display == null) return

    local theme = Gtk.IconTheme.get_for_display(display)
    add_icon_search_path(theme, GLib.build_filenamev([GLib.get_current_dir(), "images"]))
    add_icon_search_path(theme, GLib.build_filenamev([GLib.get_current_dir(), "share", "icons"]))
    add_icon_search_path(theme, GLib.build_filenamev([GLib.get_current_dir(), "usr", "share", "icons"]))

    local appdir = GLib.getenv("SQGI_APPDIR")
    if (appdir != null && appdir != "") {
        add_icon_search_path(theme, GLib.build_filenamev([appdir, "share", "icons"]))
        add_icon_search_path(theme, GLib.build_filenamev([appdir, "usr", "share", "icons"]))
    }
}

function desktop_exec_quote(value) {
    local out = "\""
    for (local i = 0; i < value.len(); i++) {
        local ch = value.slice(i, i + 1)
        if (ch == "%") out += "%%"
        else if (ch == "\\" || ch == "\"" || ch == "$" || ch == "`") out += "\\" + ch
        else out += ch
    }
    return out + "\""
}

function desktop_launch_exec(appimage) {
    return "env " + DESKTOP_RELAUNCH_ENV + "=1 " + desktop_exec_quote(appimage) + " %U"
}

function remove_owned_desktop_file(path) {
    if (!path_exists(path)) return

    try {
        local text = GLib.file_get_contents(path)
        if (text.find("RFDTool") == null) return
        if (text.find("X-RFDTool-AppImage=true") == null &&
            text.find("Icon=rfdtool") == null &&
            text.find("StartupWMClass=rfdtool") == null) return
        Gio.File.new_for_path(path).delete(null)
    } catch (e) {
        print("desktop cleanup warning: " + e + "\n")
    }
}

function maybe_relaunch_from_desktop(desktop_path) {
    if (GLib.getenv("APPIMAGE") == null || GLib.getenv("APPIMAGE") == "") return false
    if (GLib.getenv(DESKTOP_RELAUNCH_ENV) == "1") return false
    if (GLib.getenv("RFD_TOOL_DISABLE_DESKTOP_RELAUNCH") == "1") return false

    try {
        local info = Gio.DesktopAppInfo.new(APP_ID + ".desktop")
        if (info == null) info = Gio.DesktopAppInfo.new_from_filename(desktop_path)
        if (info == null) return false
        return info.launch(null, null)
    } catch (e) {
        print("desktop relaunch warning: " + e + "\n")
        return false
    }
}

// GNOME/Wayland resolves dock icons through a desktop file visible to the shell.
function install_appimage_desktop_entry(app_id) {
    if (app_id != APP_ID) return null

    local appimage = GLib.getenv("APPIMAGE")
    if (appimage == null || appimage == "") return null

    local data_dir = GLib.get_user_data_dir()
    local appdir = GLib.getenv("SQGI_APPDIR")
    if (data_dir == null || data_dir == "" || appdir == null || appdir == "") return null

    try {
        local desktop_dir = GLib.build_filenamev([data_dir, "applications"])
        local icon_dir = GLib.build_filenamev([data_dir, "icons", "hicolor", "256x256", "apps"])
        GLib.mkdir_with_parents(desktop_dir, 493)
        GLib.mkdir_with_parents(icon_dir, 493)

        local desktop_path = GLib.build_filenamev([desktop_dir, APP_ID + ".desktop"])
        local icon_path = GLib.build_filenamev([icon_dir, APP_ICON_NAME + ".png"])
        local desktop_icon = APP_ICON_NAME

        remove_owned_desktop_file(GLib.build_filenamev([desktop_dir, "rfdtool.desktop"]))

        local icon_candidates = [
            GLib.build_filenamev([appdir, "usr", "share", "icons", "hicolor", "256x256", "apps", APP_ICON_NAME + ".png"]),
            GLib.build_filenamev([appdir, APP_ICON_NAME + ".png"]),
            GLib.build_filenamev([appdir, "images", APP_ICON_NAME + ".png"]),
        ]
        foreach (src_path in icon_candidates) {
            if (!path_exists(src_path)) continue
            Gio.File.new_for_path(src_path).copy(
                Gio.File.new_for_path(icon_path),
                Gio.FileCopyFlags.overwrite,
                null,
                null
            )
            desktop_icon = icon_path
            break
        }

        local desktop =
            "[Desktop Entry]\n" +
            "Type=Application\n" +
            "Name=" + APP_NAME + "\n" +
            "Exec=" + desktop_launch_exec(appimage) + "\n" +
            "Icon=" + desktop_icon + "\n" +
            "Categories=Utility;GTK;\n" +
            "Terminal=false\n" +
            "StartupNotify=true\n" +
            "StartupWMClass=" + APP_ID + "\n" +
            "X-RFDTool-AppImage=true\n"

        GLib.file_set_contents(desktop_path, desktop, -1)
        Gio.File.new_for_path(desktop_path).set_attribute_uint32(
            "unix::mode", 493, Gio.FileQueryInfoFlags.none, null)

        return desktop_path
    } catch (e) {
        print("desktop integration warning: " + e + "\n")
    }
    return null
}

function label(text, xalign = 0.0) {
    local l = Gtk.Label.new(text)
    l.set_xalign(xalign)
    return l
}

function value_label(text) {
    local l = label(text, 0.0)
    l.set_selectable(true)
    l.set_wrap(true)
    l.set_wrap_mode(Pango.WrapMode.word_char)
    l.set_max_width_chars(48)
    return l
}

function margins(w, n) {
    w.set_margin_top(n)
    w.set_margin_bottom(n)
    w.set_margin_start(n)
    w.set_margin_end(n)
    return w
}

function hbox(spacing = 6) {
    return Gtk.Box.new(Gtk.Orientation.horizontal, spacing)
}

function vbox(spacing = 6) {
    return Gtk.Box.new(Gtk.Orientation.vertical, spacing)
}

// FlowBox reflows controls as the window rotates or changes size.
function flowbox() {
    local box = Gtk.FlowBox.new()
    box.set_selection_mode(Gtk.SelectionMode.none)
    box.set_min_children_per_line(1)
    box.set_max_children_per_line(12)
    box.set_row_spacing(4)
    box.set_column_spacing(4)
    return box
}

function add_page(nb, page, title) {
    local scroll = Gtk.ScrolledWindow.new()
    scroll.set_policy(Gtk.PolicyType.never, Gtk.PolicyType.automatic)
    scroll.set_child(page)
    nb.append_page(scroll, Gtk.Label.new(title))
}

function icon_button(icon_name, tooltip) {
    local b = Gtk.Button.new_from_icon_name(icon_name)
    b.set_tooltip_text(tooltip)
    return b
}

function text_button(icon_name, text, tooltip = "") {
    local b = Gtk.Button.new()
    local box = hbox(4)
    box.append(Gtk.Image.new_from_icon_name(icon_name))
    box.append(Gtk.Label.new(text))
    b.set_child(box)
    if (tooltip != "") b.set_tooltip_text(tooltip)
    return b
}

function set_status(text) {
    if ("status" in W) W.status.set_text(text)
}

function set_busy(is_busy, text = "") {
    State.busy = is_busy
    if ("spinner" in W) {
        if (is_busy) W.spinner.start()
        else W.spinner.stop()
    }
    if (text != "") set_status(text)
    update_connection_controls()
}

function update_connection_controls() {
    local connected = State.serial != null && State.serial.is_open()
    if ("connect_btn" in W) {
        W.connect_btn.set_label(State.permission_pending ? "Cancel" : connected ? "Disconnect" : "Connect")
        W.connect_btn.set_sensitive(!State.busy || State.permission_pending)
    }
    foreach (key in ["port_combo", "baud_entry", "scan_btn"]) {
        if (key in W) W[key].set_sensitive(!State.busy && !connected)
    }
    foreach (key in ["local_load", "remote_load"]) {
        if (key in W) W[key].set_sensitive(!State.busy && connected)
    }
    if ("notebook" in W) W.notebook.set_sensitive(!State.busy)
}

function selected_device_path() {
    local path = W.port_combo.get_active_id()
    return path == null ? U.trim(W.port_entry.get_text()) : path
}

function refresh_devices(preferred = null, report = true) {
    if (State.devices == null) State.devices = DevicesMod.Devices()
    local previous = preferred == null ? selected_device_path() : preferred
    local was_selected = W.port_combo.get_active_id() != null || preferred != null
    local devices = State.devices.list()
    W.port_combo.remove_all()
    local found = false
    foreach (device in devices) {
        W.port_combo.append(device.path, device.label)
        if (device.path == previous) found = true
    }
    if (found) W.port_combo.set_active_id(previous)
    else if (previous != "") {
        if (was_selected) {
            // Keep a removed adapter selected, so Connect reports its loss
            // instead of switching to a different attached radio.
            W.port_combo.append(previous, previous + " (unavailable)")
            W.port_combo.set_active_id(previous)
        } else W.port_entry.set_text(previous)
    } else if (devices.len()) W.port_combo.set_active(0)
    else W.port_entry.set_text("")
    if (report) set_status(devices.len() ? "Select a device and baud rate, then connect" : "No serial devices found. Attach an adapter and refresh.")
    update_connection_controls()
}

function append_terminal(text) {
    if (!("terminal_buffer" in W)) return
    local end_iter = W.terminal_buffer.get_end_iter()
    W.terminal_buffer.insert(end_iter, text, -1)
    local mark = W.terminal_buffer.get_insert()
    W.terminal_view.scroll_to_mark(mark, 0.0, false, 0.0, 0.0)
}

function append_result(title, text) {
    append_terminal("\n== " + title + " ==\n" + U.redact_secret(text) + "\n")
}

function show_error(e) {
    set_busy(false)
    local msg = e == null ? "unknown error" : e.tostring()
    set_status("Error: " + msg)
    append_result("error", msg)
}

function graph_now_seconds() {
    return GLib.get_monotonic_time().tofloat() / 1000000.0
}

function queue_graph_draw() {
    if ("rssi_graph_area" in W) W.rssi_graph_area.queue_draw()
}

function trim_graph_samples(now_sec = null) {
    if (State.graph_samples == null) return
    if (now_sec == null) now_sec = graph_now_seconds()
    while (State.graph_samples.len() > 0 &&
        now_sec - State.graph_samples[0].t > State.graph_window_seconds) {
        State.graph_samples.remove(0)
    }
}

function graph_part(parts, sample, key, label_text) {
    if (sample != null && key in sample) parts.append(label_text + " " + sample[key])
}

function update_graph_readout() {
    if (!("rssi_graph_status" in W)) return
    trim_graph_samples()
    if (State.graph_samples == null || State.graph_samples.len() == 0) {
        W.rssi_graph_status.set_text("No link samples")
        return
    }
    local sample = State.graph_samples.top()
    local parts = []
    graph_part(parts, sample, "local_rssi", "L RSSI")
    graph_part(parts, sample, "remote_rssi", "R RSSI")
    graph_part(parts, sample, "local_noise", "L noise")
    graph_part(parts, sample, "remote_noise", "R noise")
    graph_part(parts, sample, "packets", "pkts")
    graph_part(parts, sample, "txe", "txe")
    graph_part(parts, sample, "rxe", "rxe")
    graph_part(parts, sample, "temp", "temp")
    W.rssi_graph_status.set_text(parts.len() == 0 ? "No link samples" : U.join(parts, "   "))
}

function clear_graph_samples() {
    if (State.graph_samples != null) State.graph_samples.clear()
    State.graph_rx_buffer = ""
    update_graph_readout()
    queue_graph_draw()
}

function add_graph_sample(parsed) {
    if (State.graph_samples == null) State.graph_samples = []
    parsed.t <- graph_now_seconds()
    State.graph_samples.append(parsed)
    trim_graph_samples(parsed.t)
    update_graph_readout()
    queue_graph_draw()
}

function consume_graph_line(line) {
    local parsed = Parser.parse_link_report(line)
    if (parsed != null) add_graph_sample(parsed)
}

function consume_graph_rx(data) {
    if (data == null || data.len() == 0) return
    for (local i = 0; i < data.len(); i++) {
        local ch = data.slice(i, i + 1)
        if (ch == "\r" || ch == "\n") {
            local line = U.trim(State.graph_rx_buffer)
            State.graph_rx_buffer = ""
            if (line != "") consume_graph_line(line)
        } else {
            State.graph_rx_buffer += ch
            if (State.graph_rx_buffer.len() > 4096) {
                State.graph_rx_buffer = State.graph_rx_buffer.slice(State.graph_rx_buffer.len() - 2048)
            }
        }
    }
}

function graph_metric_visible(key) {
    local slots = {
        local_rssi = "graph_local_rssi",
        remote_rssi = "graph_remote_rssi",
        local_noise = "graph_local_noise",
        remote_noise = "graph_remote_noise",
    }
    if (!(key in slots) || !(slots[key] in W)) return true
    return W[slots[key]].get_active()
}

function graph_y(top, height, value) {
    local v = value.tofloat()
    if (v < 0.0) v = 0.0
    if (v > 255.0) v = 255.0
    return top + height - ((v / 255.0) * height)
}

function draw_graph_series(cr, now_sec, left, top, width, height, key, r, g, b, alpha) {
    if (!graph_metric_visible(key)) return
    local started = false
    foreach (sample in State.graph_samples) {
        if (!(key in sample)) continue
        local age = now_sec - sample.t
        if (age < 0.0 || age > State.graph_window_seconds) continue
        local x = left + ((State.graph_window_seconds - age) / State.graph_window_seconds) * width
        local y = graph_y(top, height, sample[key])
        if (!started) {
            cr.move_to(x, y)
            started = true
        } else {
            cr.line_to(x, y)
        }
    }
    if (started) {
        cr.set_source_rgba(r, g, b, alpha)
        cr.set_line_width(2.0)
        cr.stroke()
    }
}

function draw_graph_legend(cr, x, y, text, r, g, b, active) {
    cr.set_source_rgba(r, g, b, active ? 1.0 : 0.25)
    cr.rectangle(x, y - 8, 16, 3)
    cr.fill()
    cr.set_source_rgba(0.12, 0.13, 0.15, active ? 0.86 : 0.35)
    cr.move_to(x + 20, y)
    cr.show_text(text)
}

function draw_rssi_graph(area, cr, w, h) {
    local now_sec = graph_now_seconds()
    trim_graph_samples(now_sec)

    cr.set_source_rgba(0.965, 0.970, 0.975, 1.0)
    cr.rectangle(0, 0, w, h)
    cr.fill()

    local left = 52.0
    local top = 18.0
    local right = 18.0
    local bottom = 34.0
    local plot_w = w.tofloat() - left - right
    local plot_h = h.tofloat() - top - bottom
    if (plot_w < 20.0 || plot_h < 20.0) return

    cr.set_source_rgba(1.0, 1.0, 1.0, 1.0)
    cr.rectangle(left, top, plot_w, plot_h)
    cr.fill()

    cr.select_font_face("Sans", 0, 0)
    cr.set_font_size(11)

    foreach (v in [0, 64, 128, 192, 255]) {
        local y = graph_y(top, plot_h, v)
        cr.set_source_rgba(0.50, 0.54, 0.59, v == 0 ? 0.45 : 0.22)
        cr.set_line_width(v == 0 ? 1.2 : 1.0)
        cr.move_to(left, y)
        cr.line_to(left + plot_w, y)
        cr.stroke()
        cr.set_source_rgba(0.16, 0.18, 0.20, 0.72)
        cr.move_to(8, y + 4)
        cr.show_text(v.tostring())
    }

    foreach (spec in [
        { age = 60, label = "-60s" },
        { age = 30, label = "-30s" },
        { age = 0, label = "now" },
    ]) {
        local x = left + ((State.graph_window_seconds - spec.age.tofloat()) / State.graph_window_seconds) * plot_w
        cr.set_source_rgba(0.50, 0.54, 0.59, spec.age == 0 ? 0.40 : 0.18)
        cr.set_line_width(1.0)
        cr.move_to(x, top)
        cr.line_to(x, top + plot_h)
        cr.stroke()
        cr.set_source_rgba(0.16, 0.18, 0.20, 0.70)
        cr.move_to(x - 12, top + plot_h + 20)
        cr.show_text(spec.label)
    }

    draw_graph_series(cr, now_sec, left, top, plot_w, plot_h, "local_rssi", 0.08, 0.37, 0.80, 1.0)
    draw_graph_series(cr, now_sec, left, top, plot_w, plot_h, "remote_rssi", 0.03, 0.58, 0.43, 1.0)
    draw_graph_series(cr, now_sec, left, top, plot_w, plot_h, "local_noise", 0.84, 0.36, 0.13, 0.78)
    draw_graph_series(cr, now_sec, left, top, plot_w, plot_h, "remote_noise", 0.55, 0.24, 0.70, 0.78)

    cr.set_source_rgba(0.22, 0.24, 0.27, 0.65)
    cr.set_line_width(1.0)
    cr.rectangle(left, top, plot_w, plot_h)
    cr.stroke()

    if (State.graph_samples == null || State.graph_samples.len() == 0) {
        cr.set_source_rgba(0.16, 0.18, 0.20, 0.62)
        cr.select_font_face("Sans", 0, 1)
        cr.set_font_size(14)
        cr.move_to(left + 18, top + 34)
        cr.show_text(w < 420 ? "Waiting for reports" : "Waiting for RSSI/TDM reports")
    }

    cr.select_font_face("Sans", 0, 0)
    cr.set_font_size(11)
    draw_graph_legend(cr, left + 8, top + 16, "L RSSI", 0.08, 0.37, 0.80, graph_metric_visible("local_rssi"))
    draw_graph_legend(cr, left + 92, top + 16, "R RSSI", 0.03, 0.58, 0.43, graph_metric_visible("remote_rssi"))
    local narrow = plot_w < 370
    draw_graph_legend(cr, left + (narrow ? 8 : 176), top + (narrow ? 32 : 16), "L noise", 0.84, 0.36, 0.13, graph_metric_visible("local_noise"))
    draw_graph_legend(cr, left + (narrow ? 100 : 270), top + (narrow ? 32 : 16), "R noise", 0.55, 0.24, 0.70, graph_metric_visible("remote_noise"))
}

function run_task(task) {
    if (State.busy || State.window_closing) return
    task().catch(function(e) {
        if (!State.window_closing) show_error(e)
    })
}

function get_params(scope) {
    return scope == "remote" ? State.remote_params : State.local_params
}

function get_dirty(scope) {
    return scope == "remote" ? State.dirty_remote : State.dirty_local
}

function has_unsaved(scope) {
    return scope == "remote" ? State.unsaved_remote : State.unsaved_local
}

function set_unsaved(scope, value) {
    if (scope == "remote") State.unsaved_remote = value
    else State.unsaved_local = value
}

function write_all_enabled() {
    return ("apply_all_settings" in W) && W.apply_all_settings.get_active()
}

function firmware_for(scope) {
    local summary = scope == "remote" ? State.remote_summary : State.local_summary
    if (summary != null && "firmware" in summary) return summary.firmware
    return null
}

function clear_children(container) {
    local child = container.get_first_child()
    while (child != null) {
        container.remove(child)
        child = container.get_first_child()
    }
}

function range_text(p) {
    if (p == null) return ""
    if (p.choices != null) {
        local labels = []
        foreach (c in p.choices) labels.append(c.value + ":" + c.label)
        return U.join(labels, ", ")
    }
    if (p.min != null && p.max != null) return p.min + ".." + p.max
    return ""
}

function value_text(p) {
    if (p == null || p.value == null) return ""
    return p.value.tostring()
}

function parameter_supported(p) {
    return p != null && ("source" in p) && p.source == "live"
}

function support_text(p) {
    if (p == null) return "not loaded"
    return parameter_supported(p) ? "reported" : "not reported"
}

function collect_apply_values(scope, include_unchanged = false) {
    local out = {}
    if (!include_unchanged) {
        local dirty = get_dirty(scope)
        foreach (key, value in dirty) out[key] <- value
        return out
    }

    local params = get_params(scope)
    if (params == null) return out
    foreach (key in Model.sorted_keys(params)) {
        local p = params[key]
        if (!parameter_supported(p) || p.readonly || p.value == null) continue
        out[key] <- p.value
    }
    return out
}

function supported_count(params) {
    local n = 0
    if (params == null) return n
    foreach (k, p in params) {
        if (parameter_supported(p)) n++
    }
    return n
}

function scope_label(scope) {
    return scope == "remote" ? "Remote" : "Local"
}

function stage_value(scope, key, text) {
    local params = get_params(scope)
    if (params == null || !(key in params)) return false
    local p = params[key]
    if (!parameter_supported(p)) {
        p.error = "Not reported by this modem"
        set_status(scope_label(scope) + " " + key + ": " + p.error)
        rebuild_apply_preview()
        return false
    }
    local raw = U.trim(text)
    if (raw == "") {
        p.error = "Blank values are not valid"
        set_status(p.key + ": " + p.error)
        return false
    }
    local validation = Model.validate_value(p, raw, State.region_locked)
    if (!validation.ok) {
        p.error = validation.message
        set_status(p.key + ": " + validation.message)
        rebuild_apply_preview()
        return false
    }
    local iv = Model.int_value(raw)
    p.value = iv
    p.error = validation.message
    p.dirty = p.original == null || p.original != iv
    local dirty = get_dirty(scope)
    if (p.dirty) {
        dirty[key] <- iv
        set_status(scope_label(scope) + " " + key + " staged")
    } else if (key in dirty) {
        dirty.rawdelete(key)
        set_status(scope_label(scope) + " " + key + " restored")
    }
    rebuild_apply_preview()
    return true
}

function all_parameter_keys() {
    local merged = {}
    if (State.local_params != null) {
        foreach (k, v in State.local_params) merged[k] <- true
    }
    if (State.remote_params != null) {
        foreach (k, v in State.remote_params) merged[k] <- true
    }
    return Model.sorted_keys(merged)
}

function row_label(text, width = 12) {
    local l = label(text, 0.0)
    l.set_width_chars(width)
    return l
}

function remember_param_control(scope, key, widget, kind) {
    if ("param_entries" in W && scope in W.param_entries) {
        W.param_entries[scope][key] <- { widget = widget, kind = kind }
    }
}

function make_param_dropdown(scope, key, p) {
    local combo = Gtk.ComboBoxText.new()
    combo.set_size_request(160, -1)
    foreach (c in p.choices) {
        combo.append(c.value.tostring(), c.label)
    }

    if (p.value != null) combo.set_active_id(p.value.tostring())
    local supported = parameter_supported(p)
    combo.set_sensitive(supported && !p.readonly)
    combo.set_tooltip_text(scope_label(scope) + " " + key + ": " + support_text(p))
    combo.connect("changed", function() {
        if (State.busy) return
        local active_id = combo.get_active_id()
        if (active_id != null) stage_value(scope, key, active_id)
    })
    remember_param_control(scope, key, combo, "choice")
    return combo
}

function make_param_entry(scope, key) {
    local params = get_params(scope)
    local p = params != null && key in params ? params[key] : null
    if (p != null && p.choices != null && (key == "S2" || key == "S20")) {
        return make_param_dropdown(scope, key, p)
    }

    local e = Gtk.Entry.new()
    e.set_width_chars(8)
    e.set_max_width_chars(8)
    e.set_text(value_text(p))
    local supported = parameter_supported(p)
    e.set_sensitive(supported && !p.readonly)
    if (!supported) e.set_placeholder_text("n/a")
    e.set_tooltip_text(scope_label(scope) + " " + key + ": " + support_text(p))
    e.connect("activate", function() {
        stage_value(scope, key, e.get_text())
        rebuild_parameter_list()
    })
    e.connect("changed", function() {
        if (State.busy) return
        stage_value(scope, key, e.get_text())
    })
    remember_param_control(scope, key, e, "entry")
    return e
}

function rebuild_parameter_list() {
    if (!("param_list" in W)) return
    remember("param_entries", {})
    W.param_entries["local"] <- {}
    W.param_entries["remote"] <- {}
    clear_children(W.param_list)

    local filter = "filter_entry" in W ? U.trim(W.filter_entry.get_text()).tolower() : ""
    local supported_only = ("supported_only" in W) && W.supported_only.get_active()
    foreach (key in all_parameter_keys()) {
        local lp = State.local_params != null && key in State.local_params ? State.local_params[key] : null
        local rp = State.remote_params != null && key in State.remote_params ? State.remote_params[key] : null
        local base_param = lp != null ? lp : rp
        local local_supported = parameter_supported(lp)
        local remote_supported = parameter_supported(rp)
        if (supported_only && !local_supported && !remote_supported) continue
        local hay = (key + " " + base_param.name + " " + base_param.category + " " + base_param.description).tolower()
        if (filter != "" && hay.find(filter) == null) continue

        local row_box = vbox(4)
        local name = value_label(key + "  " + base_param.name)
        name.set_tooltip_text(base_param.description)
        row_box.append(name)
        local values = flowbox()
        foreach (scope in ["local", "remote"]) {
            local field = hbox(6)
            field.append(label(scope_label(scope)))
            field.append(make_param_entry(scope, key))
            values.append(field)
        }
        row_box.append(values)
        local rt = range_text(base_param)
        local rlabel = value_label(rt)
        rlabel.set_tooltip_text(rt)
        row_box.append(rlabel)

        local notes = []
        if (base_param.readonly) notes.append("read-only")
        if (base_param.match) notes.append("match")
        if (base_param.high_risk) notes.append("radio-critical")
        if (lp != null && !local_supported) notes.append("local not reported")
        if (rp != null && !remote_supported) notes.append("remote not reported")
        if (lp != null && lp.dirty) notes.append("local dirty")
        if (rp != null && rp.dirty) notes.append("remote dirty")
        if (lp != null && lp.error != "") notes.append(lp.error)
        if (rp != null && rp.error != "") notes.append(rp.error)
        local nlabel = value_label(U.join(notes, ", "))
        nlabel.set_tooltip_text(base_param.description)
        row_box.append(nlabel)

        local row = Gtk.ListBoxRow.new()
        row.set_selectable(false)
        row.set_child(margins(row_box, 3))
        W.param_list.append(row)
    }
}

function automated_edit_param(scope, key, value) {
    if (!("param_entries" in W)) throw "parameter entry table is not ready"
    if (!(scope in W.param_entries) || !(key in W.param_entries[scope])) {
        throw "parameter entry not found: " + scope + " " + key
    }

    local control = W.param_entries[scope][key]
    local e = control.widget
    e.grab_focus()
    if (control.kind == "choice") {
        local id = value.tostring()
        if (!e.set_active_id(id)) throw "choice value not found: " + scope + " " + key + "=" + id
        stage_value(scope, key, id)
        return
    }
    e.set_text("")
    local text = value.tostring()
    for (local i = 0; i < text.len(); i++) {
        e.set_text(e.get_text() + text.slice(i, i + 1))
    }
}

function set_overview_line(scope, fw, raw) {
    local title = scope_label(scope)
    local lines = []
    if (fw != null) {
        lines.append(title + " firmware: " + fw.raw)
        lines.append(title + " version: " + fw.version)
        lines.append(title + " board: " + fw.board)
        lines.append(title + " region: " + fw.region)
    } else {
        lines.append(title + " firmware: not loaded")
    }
    if (raw != null) {
        foreach (k in ["I1", "I2", "I3", "I4", "I8", "I9"]) {
            if (k in raw && raw[k] != "") lines.append(title + " " + k + ": " + raw[k])
        }
    }
    append_result(title + " overview", U.join(lines, "\n"))
}

function rebuild_overview() {
    if (!("overview_buffer" in W)) return
    local lines = []
    foreach (scope in ["local", "remote"]) {
        local fw = firmware_for(scope)
        if (fw == null) {
            lines.append(scope_label(scope) + ": not loaded")
        } else {
            lines.append(scope_label(scope) + ": " + fw.raw)
            lines.append("  Version: " + fw.version)
            lines.append("  Board: " + fw.board)
            lines.append("  Region: " + fw.region + (fw.country_locked ? " (certified/locked)" : ""))
        }
    }
    lines.append("")
    lines.append("Port: " + (State.serial != null && State.serial.is_open() ? State.serial.path : selected_device_path()))
    lines.append("Baud: " + W.baud_entry.get_text())
    lines.append("Local reported settings: " + supported_count(State.local_params) + " / " +
        (State.local_params == null ? 0 : State.local_params.len()))
    lines.append("Remote reported settings: " + supported_count(State.remote_params) + " / " +
        (State.remote_params == null ? 0 : State.remote_params.len()))
    lines.append("Local staged changes: " + State.dirty_local.len())
    lines.append("Remote staged changes: " + State.dirty_remote.len())
    lines.append("Local unsaved applied changes: " + (State.unsaved_local ? "yes" : "no"))
    lines.append("Remote unsaved applied changes: " + (State.unsaved_remote ? "yes" : "no"))
    W.overview_buffer.set_text(U.join(lines, "\n"), -1)
}

function quick_entry(scope, key) {
    local box = vbox(4)
    local params = get_params(scope)
    local p = params != null && key in params ? params[key] : null
    box.append(value_label(key + " " + (p == null ? "" : p.name)))
    local fields = flowbox()
    local e = make_param_entry(scope, key)
    fields.append(e)
    local note_text = p == null ? "" : range_text(p)
    if (p != null && !parameter_supported(p)) {
        note_text = note_text == "" ? "not reported" : note_text + " (not reported)"
    }
    local note = value_label(note_text)
    note.set_hexpand(true)
    fields.append(note)
    box.append(fields)
    return box
}

function rebuild_quick_pages() {
    if (!("radio_box" in W)) return
    clear_children(W.radio_box)
    clear_children(W.serial_box)
    clear_children(W.security_box)

    foreach (scope in ["local", "remote"]) {
        W.radio_box.append(label(scope_label(scope), 0.0))
        foreach (key in ["S3", "S2", "S4", "S8", "S9", "S10", "S11", "S12", "S20", "S5", "S6", "S7", "S23"]) {
            W.radio_box.append(quick_entry(scope, key))
        }
        W.serial_box.append(label(scope_label(scope), 0.0))
        foreach (key in ["S1", "S13", "S24", "S25"]) W.serial_box.append(quick_entry(scope, key))
        W.security_box.append(label(scope_label(scope), 0.0))
        W.security_box.append(quick_entry(scope, "S15"))
    }

    local key_row = vbox(6)
    key_row.append(row_label("AES key", 12))
    remember("key_entry", Gtk.Entry.new())
    W.key_entry.set_visibility(true)
    W.key_entry.set_hexpand(true)
    W.key_entry.set_width_chars(12)
    W.key_entry.set_placeholder_text("32 hex chars for 128-bit, 64 hex chars for 256-bit")
    key_row.append(W.key_entry)
    local random_128_btn = text_button("media-playlist-shuffle-symbolic", "Random 128", "Generate a random 128-bit AES key")
    random_128_btn.connect("clicked", function() {
        W.key_entry.set_text(U.secure_random_hex(16))
        set_status("Generated random 128-bit AES key")
    })
    local random_buttons = flowbox()
    random_buttons.append(random_128_btn)
    local random_256_btn = text_button("media-playlist-shuffle-symbolic", "Random 256", "Generate a random 256-bit AES key")
    random_256_btn.connect("clicked", function() {
        W.key_entry.set_text(U.secure_random_hex(32))
        set_status("Generated random 256-bit AES key")
    })
    random_buttons.append(random_256_btn)
    key_row.append(random_buttons)
    W.security_box.append(key_row)

    local action_row = flowbox()
    action_row.append(row_label("AES target", 12))
    local local_key_btn = text_button("dialog-password-symbolic", "Set Local", "Write encryption key to local modem")
    local_key_btn.connect("clicked", function() {
        run_task(function() { return set_encryption_key("local") })
    })
    action_row.append(local_key_btn)
    local remote_key_btn = text_button("dialog-password-symbolic", "Set Remote", "Write encryption key to remote modem")
    remote_key_btn.connect("clicked", function() {
        run_task(function() { return set_encryption_key("remote") })
    })
    action_row.append(remote_key_btn)
    local both_key_btn = text_button("object-select-symbolic", "Set Both", "Write the same AES key to remote and local modems")
    both_key_btn.connect("clicked", function() {
        run_task(function() { return set_encryption_key_both() })
    })
    action_row.append(both_key_btn)
    W.security_box.append(action_row)
}

function rebuild_apply_preview() {
    if (!("apply_buffer" in W)) return
    local lines = []
    local include_unchanged = write_all_enabled()
    foreach (scope in ["remote", "local"]) {
        local values = collect_apply_values(scope, include_unchanged)
        if (values.len() == 0 && !has_unsaved(scope)) continue
        lines.append(scope_label(scope) + (include_unchanged ? " loaded settings for Apply:" : " staged commands:"))
        local params = get_params(scope)
        foreach (key in Model.sorted_keys(values)) {
            if (params != null && key in params) {
                local p = params[key]
                lines.append("  " + SessionMod.at_command(scope, p.reg + p.num + "=" + values[key]))
                if (p.match) lines.append("    warning: must match the other radio")
                if (p.high_risk) lines.append("    warning: radio-critical or region-sensitive")
                if (p.error != "") lines.append("    note: " + p.error)
            }
        }
        if (has_unsaved(scope)) {
            lines.append("  # applied changes are not saved to EEPROM yet")
        }
        if (!include_unchanged) {
            lines.append("  " + SessionMod.at_command(scope, "&W") + "    # only when Save is selected")
        }
        lines.append("")
    }
    if (lines.len() == 0) lines.append(include_unchanged ? "No loaded writable settings." : "No staged changes.")
    W.apply_buffer.set_text(U.join(lines, "\n"), -1)
    rebuild_overview()
}

function update_after_load(scope, data) {
    if (scope == "remote") {
        State.remote_params = data.params
        State.remote_summary = data.summary
    } else {
        State.local_params = data.params
        State.local_summary = data.summary
        if ("firmware" in data.summary) {
            State.region_locked = data.summary.firmware.country_locked
        }
    }
    rebuild_parameter_list()
    rebuild_quick_pages()
    rebuild_apply_preview()
    rebuild_overview()
    set_overview_line(scope, "firmware" in data.summary ? data.summary.firmware : null, data.raw)
}

async function connect_port() {
    if (State.serial != null && State.serial.is_open()) {
        set_busy(true, "Disconnecting")
        await sqgi.sleep(0)
        State.serial.close()
        await SerialMod.drain_retired_ports()
        State.session = null
        State.unsaved_local = false
        State.unsaved_remote = false
        set_busy(false, "Disconnected")
        refresh_devices(null, false)
        return
    }
    local baud_text = U.trim(W.baud_entry.get_text())
    if (baud_text == "") throw "Enter a baud rate"
    foreach (ch in baud_text) if (ch < 48 || ch > 57) throw "Baud rate must be a positive integer"
    local baud = baud_text.tointeger()
    if (baud <= 0 || baud > 4000000) throw "Baud rate must be between 1 and 4000000"
    if (State.devices == null) State.devices = DevicesMod.Devices()
    local path = selected_device_path()
    local discovered = W.port_combo.get_active_id() != null
    State.permission_pending = true
    set_busy(true, "Checking device access; allow USB permission if prompted")
    try {
        path = await State.devices.resolve(path, discovered)
    } catch (e) {
        State.permission_pending = false
        set_busy(false)
        throw e
    }
    State.permission_pending = false
    if (State.window_closing) return
    if (path == null) { set_busy(false, "Connection cancelled"); return }
    if (discovered || path.find("usb://") == 0) refresh_devices(path, false)
    set_busy(true, "Opening serial port")
    clear_graph_samples()
    State.serial = SerialMod.SerialPort()
    State.serial.set_log_callback(function(entry) {
        append_terminal("[" + entry.time + "] " + entry.direction + " " + entry.text + "\n")
    })
    State.serial.set_data_callback(function(data) {
        consume_graph_rx(data)
    })
    State.serial.set_state_callback(function(connected) {
        if (State.window_closing) return
        if (!connected) {
            if (State.session != null) State.session.in_command_mode = false
            State.session = null
            set_status("Disconnected")
        }
        update_connection_controls()
    })
    try {
        State.serial.open(path, baud)
        State.session = SessionMod.RfdSession(State.serial)
        State.unsaved_local = false
        State.unsaved_remote = false
        await State.session.enter_command_mode()
    } catch (e) {
        State.serial.close()
        await SerialMod.drain_retired_ports()
        State.serial = null
        State.session = null
        set_busy(false)
        throw e
    }
    set_busy(false, "Connected, command mode")
}

async function load_scope(scope) {
    if (State.session == null) throw "not connected"
    set_busy(true, "Loading " + scope_label(scope))
    local data = await State.session.load_side(scope)
    update_after_load(scope, data)
    set_busy(false, "Loaded " + scope_label(scope))
}

async function apply_scope(scope, do_save = false, do_reboot = false, include_unchanged = false) {
    if (State.session == null) throw "not connected"
    local values = collect_apply_values(scope, include_unchanged)
    local dirty = get_dirty(scope)
    local write_count = values.len()
    local needs_save = do_save && (write_count > 0 || has_unsaved(scope))
    local needs_reboot = do_reboot && (write_count > 0 || has_unsaved(scope))
    if (write_count == 0 && !needs_save && !needs_reboot) {
        set_status("No " + scope_label(scope) + (include_unchanged ? " loaded settings to apply" : " changes to apply"))
        return
    }
    set_busy(true, include_unchanged ? "Applying all " + scope_label(scope) + " settings" : "Applying " + scope_label(scope))
    local params = get_params(scope)
    foreach (key in Model.sorted_keys(values)) {
        local p = params[key]
        await State.session.set_register(scope, p, values[key])
        p.original = values[key]
        p.value = values[key]
        p.dirty = false
    }
    if (write_count > 0 && !do_save) set_unsaved(scope, true)
    if (needs_save) {
        set_busy(true, "Saving " + scope_label(scope))
        await State.session.save(scope)
        set_unsaved(scope, false)
    }
    if (do_reboot) {
        set_busy(true, "Rebooting " + scope_label(scope))
        await State.session.reboot(scope)
        if (scope == "remote") {
            set_busy(true, "Waiting for Remote reboot")
            await State.session.wait_remote_ready()
        } else {
            await sqgi.sleep(2500)
            await State.session.enter_command_mode()
        }
    }
    dirty.clear()
    await load_scope(scope)
    set_busy(false, "Applied " + scope_label(scope))
}

async function apply_both(do_save = false, do_reboot = false, include_unchanged = false) {
    local remote_values = collect_apply_values("remote", include_unchanged)
    local local_values = collect_apply_values("local", include_unchanged)
    local remote_needed = remote_values.len() > 0 || (do_save && State.unsaved_remote) || (do_reboot && State.unsaved_remote)
    local local_needed = local_values.len() > 0 || (do_save && State.unsaved_local) || (do_reboot && State.unsaved_local)
    if (!remote_needed && !local_needed) {
        set_busy(false, include_unchanged ? "No loaded settings to apply" : "No changes to apply")
        return
    }
    if (remote_needed) await apply_scope("remote", do_save, do_reboot, include_unchanged)
    if (local_needed) await apply_scope("local", do_save, do_reboot, include_unchanged)
    set_busy(false, "Apply complete")
}

function revert_changes() {
    State.dirty_local.clear()
    State.dirty_remote.clear()
    foreach (params in [State.local_params, State.remote_params]) {
        if (params == null) continue
        foreach (k, p in params) {
            p.value = p.original
            p.dirty = false
            p.error = ""
        }
    }
    rebuild_parameter_list()
    rebuild_quick_pages()
    rebuild_apply_preview()
    set_status("Staged changes reverted")
}

async function factory_reset(scope) {
    if (State.session == null) throw "not connected"
    set_busy(true, "Factory reset " + scope_label(scope))
    await State.session.factory_reset(scope)
    await State.session.save(scope)
    set_unsaved(scope, false)
    rebuild_apply_preview()
    set_busy(false, scope_label(scope) + " factory defaults staged and saved")
}

async function set_encryption_key(scope) {
    if (State.session == null) throw "not connected"
    local key = validate_aes_key()
    set_busy(true, "Writing " + scope_label(scope) + " encryption key")
    local res = await State.session.encryption(scope, key)
    append_result(scope_label(scope) + " encryption", res.body)
    set_unsaved(scope, true)
    rebuild_apply_preview()
    set_busy(false, "Encryption key sent; remember to save both radios")
}

function validate_aes_key() {
    local key = U.trim(W.key_entry.get_text()).toupper()
    if (key.len() != 32 && key.len() != 64) throw "AES key must be 32 or 64 hex characters"
    if (!U.is_hex_string(key)) throw "AES key must contain only hex characters"
    return key
}

async function set_encryption_key_both() {
    if (State.session == null) throw "not connected"
    local key = validate_aes_key()
    set_busy(true, "Writing AES key to both radios")
    local remote_res = await State.session.encryption("remote", key)
    append_result("Remote encryption", remote_res.body)
    local local_res = await State.session.encryption("local", key)
    append_result("Local encryption", local_res.body)
    set_unsaved("remote", true)
    set_unsaved("local", true)
    rebuild_apply_preview()
    set_busy(false, "Same AES key sent to both radios; remember to save both")
}

async function run_diag(scope, mode) {
    if (State.session == null) throw "not connected"
    set_busy(true, "Running " + mode)
    local res = await State.session.diagnostics(scope, mode)
    local body = res.body
    if (body == "") {
        if (mode == "stop") body = "Debug reporting stopped."
        else if (mode == "rssi" || mode == "tdm") body = mode.toupper() + " debug reporting started. Incoming report lines will appear in the terminal log."
    }
    append_result(scope_label(scope) + " " + mode, body)
    set_busy(false, mode == "stop" ? "Diagnostic stopped" : "Diagnostic command sent")
}

async function run_gpio(command_name) {
    if (State.session == null) throw "not connected"
    local scope = W.gpio_remote.get_active() ? "remote" : "local"
    local pin = U.trim(W.gpio_pin.get_text())
    local state = U.trim(W.gpio_state.get_text())
    if (command_name != "print" && pin == "") throw "GPIO pin is required"
    if (command_name == "write" && state == "") throw "GPIO state is required"
    set_busy(true, "GPIO " + command_name)
    local res = await State.session.gpio(scope, command_name, pin, state)
    append_result(scope_label(scope) + " GPIO " + command_name, res.body)
    set_busy(false, "GPIO command complete")
}

async function terminal_send() {
    if (State.session == null) throw "not connected"
    local text = U.trim(W.terminal_entry.get_text())
    if (text == "") return
    W.terminal_entry.set_text("")
    set_busy(true, "Sending terminal command")
    local res
    if (text == "+++") {
        await State.session.enter_command_mode()
        append_result("terminal", "entered command mode")
    } else {
        res = await State.session.send_raw(text, 3500, true)
        append_result(text, res.body)
    }
    set_busy(false, "Terminal command complete")
}

function export_profile() {
    local summary = {
        local_firmware = firmware_for("local") == null ? "" : firmware_for("local").raw,
        remote_firmware = firmware_for("remote") == null ? "" : firmware_for("remote").raw,
    }
    local prof = Profile.build(State.local_params, State.remote_params, summary)
    local path = U.trim(W.profile_entry.get_text())
    if (path == "") path = State.default_profile
    local bytes = Profile.save(path, prof)
    set_status("Exported profile to " + path + " (" + bytes + " bytes)")
}

function import_profile() {
    local path = U.trim(W.profile_entry.get_text())
    if (path == "") path = State.default_profile
    local prof = Profile.load(path)
    foreach (scope in ["local", "remote"]) {
        local slot = scope == "remote" ? "remote" : "local"
        local items = slot in prof ? prof[slot] : []
        local values = Profile.profile_to_values(items)
        foreach (key, value in values) {
            local params = get_params(scope)
            if (params != null && key in params) stage_value(scope, key, value.tostring())
        }
    }
    rebuild_parameter_list()
    rebuild_quick_pages()
    rebuild_apply_preview()
    set_status("Imported profile from " + path)
}

function make_textview(monospaced = true) {
    local view = Gtk.TextView.new()
    view.set_editable(false)
    view.set_cursor_visible(false)
    view.set_wrap_mode(Gtk.WrapMode.word_char)
    view.set_monospace(monospaced)
    local scroll = Gtk.ScrolledWindow.new()
    scroll.set_policy(Gtk.PolicyType.never, Gtk.PolicyType.automatic)
    scroll.set_min_content_height(120)
    scroll.set_child(view)
    scroll.set_vexpand(true)
    scroll.set_hexpand(true)
    return { view = view, scroll = scroll, buffer = view.get_buffer() }
}

function build_header(root) {
    local header = margins(vbox(6), 6)
    local device_row = hbox(6)

    remember("port_combo", Gtk.ComboBoxText.new_with_entry())
    remember("port_entry", W.port_combo.get_child())
    W.port_entry.set_placeholder_text("Select a device or enter a path")
    W.port_entry.set_width_chars(18)
    W.port_entry.set_max_width_chars(18)
    W.port_entry.set_tooltip_text("Serial device path or Android USB URI")
    W.port_combo.set_hexpand(true)
    device_row.append(W.port_combo)
    remember("scan_btn", icon_button("view-refresh-symbolic", "Refresh serial devices"))
    W.scan_btn.connect("clicked", function() {
        try { refresh_devices() } catch (e) { show_error(e) }
    })
    device_row.append(W.scan_btn)
    header.append(device_row)

    local bar = flowbox()
    local baud_field = hbox(6)
    baud_field.append(label("Baud"))
    remember("baud_entry", Gtk.Entry.new())
    W.baud_entry.set_text("57600")
    W.baud_entry.set_width_chars(8)
    W.baud_entry.set_max_width_chars(8)
    W.baud_entry.set_tooltip_text("Serial baud")
    baud_field.append(W.baud_entry)
    bar.append(baud_field)

    remember("connect_btn", Gtk.Button.new_with_label("Connect"))
    W.connect_btn.connect("clicked", function() {
        if (State.permission_pending) {
            State.devices.cancel()
            State.permission_pending = false
            update_connection_controls()
        } else run_task(function() { return connect_port() })
    })
    bar.append(W.connect_btn)

    local local_load = icon_button("view-refresh-symbolic", "Refresh local modem")
    remember("local_load", local_load)
    local_load.connect("clicked", function() { run_task(function() { return load_scope("local") }) })
    bar.append(local_load)

    local remote_load = icon_button("emblem-synchronizing-symbolic", "Refresh remote modem")
    remember("remote_load", remote_load)
    remote_load.connect("clicked", function() { run_task(function() { return load_scope("remote") }) })
    bar.append(remote_load)

    remember("spinner", Gtk.Spinner.new())
    bar.append(W.spinner)
    header.append(bar)

    remember("status", label("Disconnected", 0.0))
    W.status.set_hexpand(true)
    W.status.set_wrap(true)
    W.status.set_wrap_mode(Pango.WrapMode.word_char)
    W.status.set_max_width_chars(60)
    header.append(W.status)

    root.append(header)
}

function build_overview_page(nb) {
    local page = vbox(6)
    margins(page, 8)
    local tv = make_textview(true)
    remember("overview_buffer", tv.buffer)
    page.append(tv.scroll)
    add_page(nb, page, "Overview")
}

function build_parameters_page(nb) {
    local page = vbox(6)
    margins(page, 8)
    local top = flowbox()
    remember("filter_entry", Gtk.Entry.new())
    W.filter_entry.set_placeholder_text("Filter register, name, category")
    W.filter_entry.set_hexpand(true)
    W.filter_entry.connect("changed", function() { rebuild_parameter_list() })
    top.append(W.filter_entry)
    remember("supported_only", Gtk.CheckButton.new_with_label("Reported only"))
    W.supported_only.set_active(true)
    W.supported_only.connect("toggled", function() { rebuild_parameter_list() })
    top.append(W.supported_only)
    local revert = icon_button("edit-undo-symbolic", "Revert staged changes")
    revert.connect("clicked", function() { revert_changes() })
    top.append(revert)
    page.append(top)

    remember("param_list", Gtk.ListBox.new())
    W.param_list.set_selection_mode(Gtk.SelectionMode.none)
    local scroll = Gtk.ScrolledWindow.new()
    scroll.set_policy(Gtk.PolicyType.never, Gtk.PolicyType.automatic)
    scroll.set_child(W.param_list)
    scroll.set_vexpand(true)
    page.append(scroll)
    nb.append_page(page, Gtk.Label.new("Parameters"))
}

function build_quick_page(nb, title, slot_name) {
    local page = vbox(6)
    margins(page, 8)
    remember(slot_name, vbox(4))
    local scroll = Gtk.ScrolledWindow.new()
    scroll.set_policy(Gtk.PolicyType.never, Gtk.PolicyType.automatic)
    scroll.set_child(W[slot_name])
    scroll.set_vexpand(true)
    page.append(scroll)
    nb.append_page(page, Gtk.Label.new(title))
}

function build_gpio_page(nb) {
    local page = vbox(6)
    margins(page, 8)
    local controls = flowbox()
    remember("gpio_remote", Gtk.CheckButton.new_with_label("Remote"))
    controls.append(W.gpio_remote)
    remember("gpio_pin", Gtk.Entry.new())
    W.gpio_pin.set_placeholder_text("Pin")
    W.gpio_pin.set_width_chars(8)
    controls.append(W.gpio_pin)
    remember("gpio_state", Gtk.Entry.new())
    W.gpio_state.set_placeholder_text("State")
    W.gpio_state.set_width_chars(8)
    controls.append(W.gpio_state)
    foreach (spec in [
        { name = "print", icon = "view-list-symbolic", label = "Print" },
        { name = "input", icon = "go-previous-symbolic", label = "Input" },
        { name = "output", icon = "go-next-symbolic", label = "Output" },
        { name = "mirror", icon = "view-dual-symbolic", label = "Mirror" },
        { name = "read", icon = "document-open-symbolic", label = "Read" },
        { name = "write", icon = "document-save-symbolic", label = "Write" },
    ]) {
        local command_name = spec.name
        local b = text_button(spec.icon, spec.label, "Run GPIO " + command_name)
        b.connect("clicked", function(name = command_name) { run_task(function() { return run_gpio(name) }) })
        controls.append(b)
    }
    page.append(controls)
    local tv = make_textview(true)
    page.append(tv.scroll)
    add_page(nb, page, "GPIO")
}

function build_diagnostics_page(nb) {
    local page = vbox(6)
    margins(page, 8)
    local controls = flowbox()
    remember("diag_remote", Gtk.CheckButton.new_with_label("Remote"))
    controls.append(W.diag_remote)
    foreach (spec in [
        { mode = "info6", icon = "dialog-information-symbolic", label = "ATI6" },
        { mode = "info7", icon = "dialog-information-symbolic", label = "ATI7" },
        { mode = "rssi", icon = "network-wireless-signal-excellent-symbolic", label = "RSSI" },
        { mode = "tdm", icon = "media-playback-start-symbolic", label = "TDM" },
        { mode = "stop", icon = "media-playback-stop-symbolic", label = "Stop" },
    ]) {
        local diag_mode = spec.mode
        local b = text_button(spec.icon, spec.label, "Run " + diag_mode)
        b.connect("clicked", function(mode = diag_mode) {
            local scope = W.diag_remote.get_active() ? "remote" : "local"
            run_task(function() { return run_diag(scope, mode) })
        })
        controls.append(b)
    }
    page.append(controls)

    local graph_controls = flowbox()
    remember("graph_local_rssi", Gtk.CheckButton.new_with_label("L RSSI"))
    W.graph_local_rssi.set_active(true)
    W.graph_local_rssi.connect("toggled", function() { queue_graph_draw() })
    graph_controls.append(W.graph_local_rssi)
    remember("graph_remote_rssi", Gtk.CheckButton.new_with_label("R RSSI"))
    W.graph_remote_rssi.set_active(true)
    W.graph_remote_rssi.connect("toggled", function() { queue_graph_draw() })
    graph_controls.append(W.graph_remote_rssi)
    remember("graph_local_noise", Gtk.CheckButton.new_with_label("L noise"))
    W.graph_local_noise.set_active(true)
    W.graph_local_noise.connect("toggled", function() { queue_graph_draw() })
    graph_controls.append(W.graph_local_noise)
    remember("graph_remote_noise", Gtk.CheckButton.new_with_label("R noise"))
    W.graph_remote_noise.set_active(true)
    W.graph_remote_noise.connect("toggled", function() { queue_graph_draw() })
    graph_controls.append(W.graph_remote_noise)
    local clear = icon_button("edit-clear-symbolic", "Clear graph samples")
    clear.connect("clicked", function() { clear_graph_samples() })
    graph_controls.append(clear)
    remember("rssi_graph_status", value_label("No link samples"))
    W.rssi_graph_status.set_hexpand(true)
    page.append(graph_controls)
    page.append(W.rssi_graph_status)

    remember("rssi_graph_area", Gtk.DrawingArea.new())
    W.rssi_graph_area.set_size_request(280, 240)
    W.rssi_graph_area.set_hexpand(true)
    W.rssi_graph_area.set_vexpand(true)
    W.rssi_graph_area.set_draw_func(draw_rssi_graph, null, function(_) {})
    page.append(W.rssi_graph_area)
    sqgi.timeout_add(1000, function() {
        if (State.window_closing) return false
        update_graph_readout()
        queue_graph_draw()
        return true
    })
    add_page(nb, page, "Diagnostics")
}

function build_terminal_page(nb) {
    local page = vbox(6)
    margins(page, 8)
    local tv = make_textview(true)
    remember("terminal_view", tv.view)
    remember("terminal_buffer", tv.buffer)
    page.append(tv.scroll)
    local input = hbox(6)
    remember("terminal_entry", Gtk.Entry.new())
    W.terminal_entry.set_placeholder_text("AT command")
    W.terminal_entry.set_hexpand(true)
    W.terminal_entry.set_width_chars(10)
    W.terminal_entry.connect("activate", function() { run_task(function() { return terminal_send() }) })
    input.append(W.terminal_entry)
    local send = icon_button("mail-send-symbolic", "Send command")
    send.connect("clicked", function() { run_task(function() { return terminal_send() }) })
    input.append(send)
    local clear = icon_button("edit-clear-symbolic", "Clear terminal")
    clear.connect("clicked", function() { W.terminal_buffer.set_text("", -1) })
    input.append(clear)
    page.append(input)
    add_page(nb, page, "Terminal")
}

function build_apply_page(nb) {
    local page = vbox(6)
    margins(page, 8)
    local actions = flowbox()
    foreach (spec in [
        { label = "Apply Remote", icon = "go-up-symbolic", scope = "remote", save = false, reboot = false },
        { label = "Apply Local", icon = "go-down-symbolic", scope = "local", save = false, reboot = false },
        { label = "Save Both", icon = "document-save-symbolic", scope = "both", save = true, reboot = false },
        { label = "Save + Reboot", icon = "system-reboot-symbolic", scope = "both", save = true, reboot = true },
    ]) {
        local b = text_button(spec.icon, spec.label, spec.label)
        local apply_scope_name = spec.scope
        local apply_save = spec.save
        local apply_reboot = spec.reboot
        b.connect("clicked", function(scope = apply_scope_name, save = apply_save, reboot = apply_reboot) {
            local include_unchanged = !save && !reboot && write_all_enabled()
            if (scope == "both") run_task(function() { return apply_both(save, reboot, include_unchanged) })
            else run_task(function() { return apply_scope(scope, save, reboot, include_unchanged) })
        })
        actions.append(b)
    }
    local revert = text_button("edit-undo-symbolic", "Revert", "Drop staged changes")
    revert.connect("clicked", function() { revert_changes() })
    actions.append(revert)
    page.append(actions)

    remember("apply_all_settings", Gtk.CheckButton.new_with_label("Write all loaded settings"))
    W.apply_all_settings.set_tooltip_text("Make Apply Local and Apply Remote write every reported writable setting, including unchanged values")
    W.apply_all_settings.connect("toggled", function() { rebuild_apply_preview() })
    page.append(W.apply_all_settings)

    local profile_row = vbox(6)
    remember("profile_entry", Gtk.Entry.new())
    W.profile_entry.set_text(State.default_profile)
    W.profile_entry.set_hexpand(true)
    profile_row.append(W.profile_entry)
    local export_btn = text_button("document-save-as-symbolic", "Export", "Export JSON profile")
    export_btn.connect("clicked", function() {
        try { export_profile() } catch (e) { show_error(e) }
    })
    local profile_buttons = flowbox()
    profile_buttons.append(export_btn)
    local import_btn = text_button("document-open-symbolic", "Import", "Import JSON profile and stage values")
    import_btn.connect("clicked", function() {
        try { import_profile() } catch (e) { show_error(e) }
    })
    profile_buttons.append(import_btn)
    profile_row.append(profile_buttons)
    page.append(profile_row)

    local reset_row = flowbox()
    local reset_local = text_button("edit-delete-symbolic", "Factory Local", "Factory-reset local modem")
    reset_local.connect("clicked", function() { run_task(function() { return factory_reset("local") }) })
    reset_row.append(reset_local)
    local reset_remote = text_button("edit-delete-symbolic", "Factory Remote", "Factory-reset remote modem")
    reset_remote.connect("clicked", function() { run_task(function() { return factory_reset("remote") }) })
    reset_row.append(reset_remote)
    page.append(reset_row)

    local tv = make_textview(true)
    remember("apply_buffer", tv.buffer)
    page.append(tv.scroll)
    add_page(nb, page, "Apply")
}

function create_app(options = null) {
    init_state()
    local app_id = options != null && ("app_id" in options) ? options.app_id : APP_ID
    GLib.set_prgname(app_id)
    GLib.set_application_name(APP_NAME)
    Gtk.Window.set_default_icon_name(APP_ICON_NAME)
    local desktop_path = install_appimage_desktop_entry(app_id)
    if (desktop_path != null && maybe_relaunch_from_desktop(desktop_path)) return null

    local app = Gtk.Application.new(app_id, Gio.ApplicationFlags.flags_none)
    app.connect("shutdown", function() {
        State.window_closing = true
        if (State.devices != null) State.devices.cancel()
        if (State.serial != null) State.serial.close()
    })
    app.connect("activate", function() {
        register_app_icon()

        local win = Gtk.ApplicationWindow.new(app)
        win.set_title(APP_NAME)
        win.set_icon_name(APP_ICON_NAME)
        win.set_default_size(options != null && "width" in options ? options.width : 1000,
            options != null && "height" in options ? options.height : 760)
        remember("win", win)
        win.connect("close-request", function() {
            if (State.window_closing) return false
            State.window_closing = true
            if (State.devices != null) State.devices.cancel()
            sqgi.timeout_add(0, function() {
                async function cleanup_and_quit() {
                    if (State.serial != null) {
                        State.serial.close()
                        await SerialMod.drain_retired_ports()
                        State.serial = null
                        State.session = null
                    }
                    app.quit()
                }
                cleanup_and_quit().catch(function(e) {
                    print("window cleanup error: " + e + "\n")
                    app.quit()
                })
                return false
            })
            return true
        })

        local root = vbox(0)
        local viewport = Gtk.ScrolledWindow.new()
        viewport.set_policy(Gtk.PolicyType.never, Gtk.PolicyType.automatic)
        viewport.set_child(root)
        win.set_child(viewport)
        build_header(root)

        local nb = Gtk.Notebook.new()
        remember("notebook", nb)
        nb.set_scrollable(true)
        nb.set_hexpand(true)
        nb.set_vexpand(true)
        root.append(nb)
        build_overview_page(nb)
        build_parameters_page(nb)
        build_quick_page(nb, "Radio Link", "radio_box")
        build_quick_page(nb, "Serial", "serial_box")
        build_quick_page(nb, "Security", "security_box")
        build_gpio_page(nb)
        build_diagnostics_page(nb)
        build_terminal_page(nb)
        build_apply_page(nb)

        rebuild_parameter_list()
        rebuild_quick_pages()
        rebuild_apply_preview()
        rebuild_overview()

        win.present()
        try { refresh_devices() } catch (e) { show_error(e) }
        if (options != null && "on_ready" in options) options.on_ready(W)

        if (options != null && ("auto_refresh_local" in options) && options.auto_refresh_local) {
            sqgi.timeout_add(100, function() {
                if ("device" in options) {
                    W.port_combo.set_active(-1)
                    W.port_entry.set_text(options.device)
                }
                if ("baud" in options) W.baud_entry.set_text(options.baud.tostring())
                async function drive() {
                    try {
                        print("[gtk-test] connecting\n")
                        await connect_port()
                        print("[gtk-test] loading local\n")
                        await load_scope("local")
                        if (("auto_edit_param" in options) && options.auto_edit_param) {
                            local key = "edit_key" in options ? options.edit_key : "S4"
                            local value = "edit_value" in options ? options.edit_value : "29"
                            print("[gtk-test] editing local " + key + "=" + value + "\n")
                            automated_edit_param("local", key, value)
                            print("[gtk-test] edit complete\n")
                            if (("auto_apply_local" in options) && options.auto_apply_local) {
                                print("[gtk-test] applying local\n")
                                local auto_save = ("auto_save" in options) && options.auto_save
                                local auto_reboot = ("auto_reboot" in options) && options.auto_reboot
                                await apply_scope("local", auto_save, auto_reboot)
                                print("[gtk-test] apply local complete\n")
                            }
                        }
                        set_status("Automated local refresh finished")
                    } catch (e) {
                        print("[gtk-test] error: " + e + "\n")
                        show_error(e)
                    }
                    await sqgi.sleep(300)
                    if ("win" in W) W.win.close()
                }
                run_task(function() { return drive() })
                return false
            })
        }
    })
    return app
}

return {
    create_app = create_app,
}
