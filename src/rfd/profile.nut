local GLib = import("GLib")
local Gio = import("Gio")
local U = import("../util.nut")
local Model = import("model.nut")

function params_to_profile(params) {
    local out = []
    if (params == null) return out
    foreach (key in Model.sorted_keys(params)) {
        local p = params[key]
        out.append({
            key = key,
            reg = p.reg,
            num = p.num,
            name = p.name,
            value = p.value,
        })
    }
    return out
}

function profile_to_values(profile) {
    local values = {}
    if (profile == null) return values
    foreach (item in profile) {
        if ("key" in item && "value" in item) values[item.key] <- item.value
    }
    return values
}

function build(local_params, remote_params, summary) {
    local out = {
        app = "RFDTool",
        version = "0.1.0",
        exported_at = U.now_stamp(),
        summary = summary == null ? {} : summary,
        remote = params_to_profile(remote_params),
    }
    out["local"] <- params_to_profile(local_params)
    return out
}

function save(path, profile) {
    local text = sqgi.json.stringify(profile, 2)
    GLib.file_set_contents(path, text, -1)
    return text.len()
}

function load(path) {
    local f = Gio.File.new_for_path(path)
    local result = f.load_contents(null)
    local data = result[1]
    return sqgi.json.parse(data)
}

return {
    params_to_profile = params_to_profile,
    profile_to_values = profile_to_values,
    build = build,
    save = save,
    load = load,
}
