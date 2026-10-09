# maw-rs บน Windows native — กรณีศึกษาหนูดี

ทดสอบบน Windows 10 ด้วย Codex และ psmux โดยไม่ใช้ WSL วันที่ 9 ตุลาคม 2026
fork: https://github.com/tacha-hash/maw-rs/tree/windows-native
ฐานโค้ด `bd8c1787bf1ec0fa1fe6288faa6673735f9185d6` ตรงกับฝูง Mac/PC
`maw-rs v26.8.18-alpha.1524` เป็นรุ่นฐาน ส่วน build ที่มี patch อาจแสดง `-dirty`
เอกสารนี้เป็นบันทึกการทดลอง ไม่ใช่การรับรองทุกคำสั่งบน Windows

## แก้อะไร และทำไม

1. `generate_peer_key()` เปิด `/dev/urandom` ซึ่งไม่มีบน Windows ทำให้
   `maw hey` ล้มด้วย `failed to open random peer key source`
   เพิ่มเฉพาะ `cfg(windows)` ใช้ `rand::rngs::OsRng` ที่มี dependency อยู่แล้ว
   ระบบอื่นยังใช้เส้นทางเดิม ไม่ใช้เวลา/PID เป็น signing key
2. maw เรียก executable ชื่อ `tmux` จึงใช้ `tmux.exe` compatibility executable
   ที่มาพร้อม psmux วางไว้ต้น PATH ไม่ใช้ tmux Windows port ตัวเก่า
   wrapper `scripts/windows/maw.ps1` ตั้ง PATH, TERM และ UTF-8
3. แยก state ด้วย `MAW_HOME` และกำหนด binary ผ่าน `MAW_EXE`
   `init-config.ps1` สร้าง JSON แบบ UTF-8 ไม่มี BOM และไม่เขียนทับ config เดิม
   ไม่ฝัง username หรือ drive ของหนูดีในสคริปต์ที่นำไปใช้ต่อ
4. `start-serve.ps1` เปิด serve แบบซ่อนหน้าต่างและตรวจ `/info`
   รุ่นนี้ `/api/config` ตอบ 404 จึงใช้เป็น readiness check ไม่ได้
   installer สร้าง firewall และ Scheduled Task ตอน user logon

## วิธี build บน Windows

ใช้ Git, Rust GNU toolchain `1.97.1-x86_64-pc-windows-gnu` และ Zig
หนูดีใช้ Zig 0.17.0; core/dev build ไม่เปิด feature `wasm-host`
ไม่ติดตั้ง dependency เพิ่มหรืออัปเดต toolchain อัตโนมัติในสคริปต์เหล่านี้

```powershell
git clone https://github.com/tacha-hash/maw-rs.git
Set-Location maw-rs
git switch windows-native
rustup toolchain install 1.97.1-x86_64-pc-windows-gnu --profile minimal --component rustfmt --component clippy
rustup target add wasm32-unknown-unknown --toolchain 1.97.1-x86_64-pc-windows-gnu
```

ติดตั้ง Zig แยกไว้บน drive ที่มีพื้นที่ กำหนด path ให้ตรงเครื่อง สร้าง wrapper
`zig-cc.cmd` และ `zig-ar.cmd` ในโฟลเดอร์เครื่องมือที่อยู่นอก git:

```bat
@echo off
"D:\Tools\zig\zig.exe" cc %*
```

```bat
@echo off
"D:\Tools\zig\zig.exe" ar %*
```

Rust GNU ต้องหา `dlltool.exe` ได้ด้วย หนูดีใช้ executable wrapper ที่เรียก
`zig dlltool` ตาม source นี้ (เปลี่ยน path แล้ว compile ด้วย rustc):

```rust
use std::process::{Command, exit};
fn main() {
    let status = Command::new(r"D:\Tools\zig\zig.exe")
        .arg("dlltool").args(std::env::args_os().skip(1))
        .status().expect("zig dlltool");
    exit(status.code().unwrap_or(1));
}
```

```powershell
rustc +1.97.1-x86_64-pc-windows-gnu D:\Tools\dlltool-wrapper.rs -o D:\Tools\native-bin\dlltool.exe
$env:PATH = 'D:\Tools\native-bin;' + $env:PATH
$env:CC = 'D:\Tools\native-bin\zig-cc.cmd'
$env:AR = 'D:\Tools\native-bin\zig-ar.cmd'
$env:CFLAGS = '--target=x86_64-windows-gnu -fno-sanitize=all'
$env:CARGO_TARGET_DIR = 'D:\Build\maw-windows'
cargo +1.97.1-x86_64-pc-windows-gnu build -p maw-cli --locked -j 2
$env:MAW_EXE = 'D:\Build\maw-windows\debug\maw-rs.exe'
& $env:MAW_EXE --version
```

`--target=x86_64-windows-gnu` ใน CFLAGS แก้ target spelling ของ Zig:
ค่า `x86_64-pc-windows-gnu` ที่ cc-rs ส่งมาก่อนหน้านี้ทำให้ Zig ตอบ
`UnknownOperatingSystem`; flag ที่ตามหลังใช้ spelling ที่ Zig รองรับ
`-fno-sanitize=all` ป้องกัน undefined sanitizer symbols ตอน link ring
ใช้ `-j 2` บนเครื่อง RAM 16 GB และแยก target dir ต่อ agent
ถ้าตั้ง `CARGO_HOME`/`RUSTUP_HOME` เอง ให้คงค่าเหล่านี้ตลอด build และ gates

## psmux, path และ config

หนูดีทดสอบ psmux 3.3.8; ใช้ binary จากแหล่งที่ตรวจสอบแล้ว
โฟลเดอร์ต้องมีทั้ง `psmux.exe` และ `tmux.exe` ของ psmux รุ่นเดียวกัน
ตรวจ `maw ls --json` และ `maw peek suea:oracle` ว่าเห็น session เดียวกับจอจริง
session หนูดีคือ `suea`, window `oracle`, pane `0`: target `suea:oracle.0`
รัน serve และ interactive psmux ด้วย user คนเดียวกัน

```powershell
$env:MAW_HOME = 'D:\MawState'
$env:MAW_PSMUX_DIR = 'D:\Tools\psmux'
$env:MAW_EXE = 'D:\Build\maw-windows\debug\maw-rs.exe'
.\scripts\windows\init-config.ps1 -MawHome $env:MAW_HOME -Node nudee -Oracle suea
.\scripts\windows\maw.ps1 --version
.\scripts\windows\maw.ps1 ls --json
```

config อยู่ที่ `$env:MAW_HOME\config\maw.config.json` ต้องมี:

```json
{
  "node": "nudee",
  "oracle": "suea",
  "agents": {"suea": "nudee"},
  "sessions": {"suea": "suea"},
  "bind": "0.0.0.0",
  "port": 3458,
  "defaultEngine": "codex"
}
```

เติม `federationToken` ที่ตรงกับฝูงผ่านช่องทางปลอดภัยนอก repository
อย่าแสดงค่าใน terminal log, chat, issue, commit หรือ screenshot
ตัวอย่าง config นี้จงใจไม่มี token และไม่คัดลอก peer-key จากเครื่องอื่น
`maw hey` จะสร้าง signing key ใน `$env:MAW_HOME\peer-key`
จำกัด ACL ของ key และ config ให้ user เจ้าของกับ SYSTEM เท่านั้น
รวมถึงสำเนา backup ที่มี token อย่าเก็บไว้ใต้ git
ห้ามเปลี่ยน shared token โดยไม่ประสานอีกสองเครื่อง

## serve, firewall และ logon task

บน PowerShell administrator ของ user ที่จะใช้ psmux:

```powershell
.\scripts\windows\install-logon-task.ps1 -MawHome 'D:\MawState' -PsmuxDirectory 'D:\Tools\psmux' -MawExe 'D:\Build\maw-windows\debug\maw-rs.exe'
```

installer เปิด inbound TCP 3458 เฉพาะ `100.64.0.0/10` ทุก firewall profile
และรันแบบ Interactive/RunLevel Limited ตอน logon ของ user ปัจจุบัน
ใช้ account เดียวกับที่รัน Codex; ไม่ใช่ service ตอน boot ก่อน login
Scheduled Task เริ่ม serve แต่ไม่ได้สร้าง session หรือเปิด Codex ให้เอง
เมื่อย้าย checkout หรือ binary ต้องติดตั้ง task ใหม่ให้ path ตรง

```powershell
.\scripts\windows\start-serve.ps1
.\scripts\windows\maw.ps1 peers add mac "http://<mac-host>.<tailnet>.ts.net:3458" --node mac --oracle le-mac
.\scripts\windows\maw.ps1 peers add pc "http://<pc-host>.<tailnet>.ts.net:3458" --node pc --oracle le
```

Mac/PC ต้อง add หนูดีกลับด้วย URL `http://<windows-host>.<tailnet>.ts.net:3458`
ใช้ MagicDNS ไม่ hardcode IP; เมื่อ le-pc ย้าย Windows ให้ปรับชื่อ DNS/URL
ตามเครื่องจริง ให้ตรง topology ใหม่
หลังเปลี่ยน token, peer identity หรือ key ให้ restart serve ทุกเครื่องที่เกี่ยวข้อง
ตรวจ PID และ executable ก่อนหยุดเฉพาะ process serve ของตัวเอง

```powershell
.\scripts\windows\maw.ps1 peers probe-all
.\scripts\windows\maw.ps1 peers info mac
.\scripts\windows\maw.ps1 peers info pc
```

คำว่า `OK` จาก probe-all แสดง liveness; ดู `authOk: true` ด้วย
อย่าสรุปว่า `delivered` แปลว่าคนรับอ่านแล้ว ต้องมี ACK จากอีกฝั่ง

## ผลทดสอบ NUDEE-PEER-01

- Mac ส่งข้อความถึง Codex หนูดีผ่าน maw โดยตรง เห็นผู้ส่ง `[mac:le-mac]`
- หนูดีส่ง `maw hey mac:le-mac "ACK NUDEE-PEER-01"` ด้วย native binary
- le-mac ยืนยันว่าได้รับ ACK พร้อมป้าย `[nudee:suea]` ไม่ผ่าน PC relay
- หนูดีตรวจ Mac และ PC ได้ `authOk: true` ทั้งคู่
- le-mac ยืนยันว่า Mac/PC probe หนูดีได้ OK
- firewall และ Scheduled Task ติดตั้งสำเร็จ; ยังไม่ได้ทดสอบ reboot/logon จริง
- หลักฐานยืนยันผู้รับ:
  https://github.com/tacha-hash/nudee-oracle/pull/1#issuecomment-6079401100

## ข้อที่ยังไม่ได้รับรอง

- wake/attach ข้ามเครื่องและการเปิด Codex เมื่อไม่มี session ยังไม่ได้ทดสอบ
- plugins/wasm-host และทุก verb ของ maw ยังไม่ได้รับรองบน Windows
- activity classifier เคยรายงาน session ว่า stale แม้ pane ใช้งานได้
- SSH receiver เดิมยังมีปัญหา regex `›`/encoding ใน PowerShell 5.1;
  อย่าถือว่าการทดสอบ native peer แก้ receiver เดิมแล้ว
- โค้ดสุ่ม pending-id ใน `send_acl_gate.rs` ยังใช้ `/dev/urandom`
  และมี fallback; patch นี้แก้ signing key เท่านั้น
- ยังไม่มี official Windows release หรือ packaged installer
- Git Bash ใช้ช่วยรัน gate ได้ แต่ runtime ของ maw/psmux ไม่ต้องใช้ WSL

## เมื่อฝูงอัปเวอร์ชัน

ตกลง commit/version พร้อมกันทั้งสามเครื่องก่อนอัปเดต อย่าคิดว่า CLI ชื่อเหมือนกัน
แล้ว identity/auth protocol จะเข้ากัน รุ่นฐานนี้เคยมีปัญหาจับคู่ identity ต่างรุ่น
พกเฉพาะ patch Windows ไปฐานใหม่ และตรวจว่าต้นทางแก้ OsRng แล้วหรือยัง
backup state/key/token อย่างปลอดภัย ไม่ regenerate key โดยไม่แจ้ง peers
หลัง build ตรวจ `/info`, `/api/identity`, `authOk`, ส่ง–รับ ACK และป้ายชื่อจริง
ให้ SSH fallback อยู่จนทดสอบครบ อย่า push หรือเปิด PR เข้าต้นทางโดยอัตโนมัติ

## การตรวจ source ก่อนเผยแพร่

ใช้ `scripts/gate.sh quick` ตามกติกา repository; full gate ก่อน merge/promote
Windows core smoke test ไม่แทน full gate ข้าม platform
ผลตรวจ branch นี้: PowerShell ทั้งสี่ไฟล์ parse ผ่าน, config ไม่มี BOM/ข้อมูลลับ,
wrapper ส่ง `--version` และ `ls --json` ผ่าน, ตรวจ serve เดิมผ่าน,
launcher ที่สร้างมีสอง statement และ parse ผ่าน
`cargo test -p maw-cli windows_peer_key_uses_os_entropy --lib --locked --no-fail-fast -j 2`
ผ่าน 1 test; ต้องใช้ `--lib` เพราะ implementation อยู่ใน library ไม่ใช่ binary
เพิ่ม cfg Unix ให้ fixture process_engine ที่ใช้ POSIX shell/chmod และ test
permission denied ใน serve_identity เพื่อให้ test library compile บน Windows
ยังไม่มี Windows fixture ทดแทนชุด POSIX ที่ไม่ได้รัน
`scripts/gate.sh quick` ผ่าน fmt แต่ยังไม่ผ่าน clippy `-D warnings`:
Windows fallback ใน `channel_chmod`, `set_owner_only`, `update_mark_executable`
เจอ unnecessary_wraps และ Unix fixture อื่นมี unused variable/helper
จึงยังไม่อ้างว่า full test/gate ผ่าน และไม่ได้ merge/promote รุ่นนี้
ตรวจ staged diff, รายชื่อไฟล์ และ git history ว่าไม่มี token/key/password
commit เฉพาะ source/scripts/docs ที่ระบุชัด ไม่ใช้ `git add .`
ไม่ commit runtime binary, logs, state, local config หรือ launcher ที่สร้างขึ้น
