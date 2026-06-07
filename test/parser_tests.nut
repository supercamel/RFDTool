local Parser = import("../src/rfd/parser.nut")
local Model = import("../src/rfd/model.nut")
local Profile = import("../src/rfd/profile.nut")
local U = import("../src/util.nut")

function check(name, cond) {
    if (!cond) throw "[FAIL] " + name
    print("[PASS] " + name + "\n")
}

local fw = Parser.parse_firmware("RFD SiK 3.16 on RFD900x R1.3-AU\nOK\n")
check("firmware version", fw.version.find("RFD SiK") == 0)
check("firmware board", fw.board.find("RFD900x") == 0)
check("firmware region", fw.region == "AU")
check("firmware locked", fw.country_locked)

local table_text = @"
S0:FORMAT=25
S1:SERIAL_SPEED=57
S2:AIR_SPEED=64
S3:NETID=23
S4:TXPOWER=30
S15:ENCRYPTION_LEVEL=1
R0:TARGET_RSSI=255
OK
"
local ranges = @"
S1:SERIAL_SPEED=57 1..1000
S2:AIR_SPEED=64 2..750
S3:NETID=23 0..255
S15:ENCRYPTION_LEVEL=1 0..2
OK
"
local regs = Parser.parse_register_table(table_text)
check("parse S1", regs.S1.value == 57 && regs.S1.name == "SERIAL_SPEED")
check("parse R0", regs.R0.value == 255 && regs.R0.reg == "R")

local params = Parser.make_parameters(table_text, ranges)
check("params include fallback S8", "S8" in params)
check("params live S2", params.S2.value == 64 && params.S2.source == "live")
check("range S2", params.S2.min == 2 && params.S2.max == 750)

local v = Model.validate_value(params.S3, 44, false)
check("validate ok", v.ok)
v = Model.validate_value(params.S3, 999, false)
check("validate high fails", !v.ok)
v = Model.validate_value(params.S0, 99, false)
check("readonly fails", !v.ok)

local secret = Parser.strip_terminal_lines("AT&E=abcdef123456\nOK\n", "AT&E=abcdef123456")
check("strip secret echo", secret == "")

local prof = Profile.build(params, null, { firmware = fw.raw })
check("profile local exists", prof["local"].len() > 0)
local values = Profile.profile_to_values(prof["local"])
check("profile values roundtrip", values.S3 == 23)

local random_key = U.secure_random_hex(16)
check("random AES key length", random_key.len() == 32)
check("random AES key hex", U.is_hex_string(random_key))
check("reject non-hex AES key", !U.is_hex_string("001122zz"))

local report = Parser.parse_link_report("L/R RSSI: 40/0  L/R noise: 46/0 pkts: 7  txe=1 rxe=2 stx=3 srx=4 ecc=5/6 temp=20 dco=8")
check("link report parsed", report != null)
check("link report rssi", report.local_rssi == 40 && report.remote_rssi == 0)
check("link report noise", report.local_noise == 46 && report.remote_noise == 0)
check("link report counters", report.packets == 7 && report.txe == 1 && report.rxe == 2)
check("link report ecc/temp", report.local_ecc == 5 && report.remote_ecc == 6 && report.temp == 20)
check("ignore non-report line", Parser.parse_link_report("ATI7") == null)

print("[OK] parser/model/profile tests passed\n")
