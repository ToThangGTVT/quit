# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**quit** is a macOS menu bar application that monitors running processes and lets the user force-quit them. Nó gồm hai bề mặt:

- **Popover trên thanh menu** — danh sách ứng dụng GUI + RAM/CPU, nút buộc thoát nhanh.
- **Cửa sổ "Trình quản lý Tác vụ"** — khung cửa sổ theo chuẩn macOS (menu bar hệ thống,
  thanh tab segmented trong titlebar), nội dung từng tab mô phỏng Task Manager của
  Windows 10 (7 tab, heat map, đồ thị 60 giây, chế độ "Ít chi tiết hơn").
  Mở bằng nút trong popover, hoặc mở lại app từ Finder/Dock.

- Platform: macOS 14.6+
- Language: Swift 5.0
- UI: SwiftUI with AppKit (MenuBarExtra)
- No third-party dependencies, no CocoaPods, no SPM packages

## Build Commands

Open and build in Xcode directly, or via CLI:

```bash
# Debug build
xcodebuild -project quit.xcodeproj -target quit -configuration Debug

# Release build
xcodebuild -project quit.xcodeproj -target quit -configuration Release

# Clean then build
xcodebuild -project quit.xcodeproj -target quit clean build
```

There are no test targets in this project.

## Architecture

VIPER-ish layering, one file per component:

```
quit/
  App/quitApp.swift              MenuBarExtra scene + AppDelegate (reopen -> mở Task Manager)
  App/TaskManagerCommands.swift  menu bar macOS (Tệp / Tùy chọn / View) qua SwiftUI Commands
  Entities/                      AppEntity, SystemStats + Fmt, HardwareInfo,
                                 NetworkAdapterInfo, StartupItem/ServiceItem
  Interactors/AppMonitorInteractor.swift   lấy mẫu tiến trình + hệ thống
  Interactors/StartupInteractor.swift      đọc LaunchAgents + `launchctl list`
  Interactors/GPUReader.swift              GPU qua IOAccelerator/PerformanceStatistics
  Interactors/BluetoothReader.swift        Bluetooth qua `system_profiler SPBluetoothDataType -json`
  Presenters/AppListPresenter.swift        state, cây tiến trình, lịch sử đồ thị, sắp xếp
  Presenters/TaskManagerState.swift        tab đang chọn, nhóm thu gọn, vùng chọn (chia sẻ với menu bar)
  Router/AppRouter.swift         cửa sổ, chế độ gọn, "Chạy tác vụ mới"
  Views/MenuBar/                 popover trên thanh menu
  Views/Detail/DetailWindowView.swift      khung cửa sổ Task Manager + dòng tiêu đề tab
  Router/TaskManagerToolbar.swift          NSToolbar 7 tab (kiểu macOS 26)
  Views/Win10/                   giao diện mô phỏng Task Manager Windows 10
```

**`AppMonitorInteractor`** chạy hai nhịp:

- `sampleTimer` mỗi 1 giây — chỉ số hệ thống rẻ (host_cpu_load_info, vm_statistics64,
  vm.swapusage, getifaddrs, IOBlockStorageDriver) → nuôi các đồ thị 60 giây.
- `procTimer` theo `UpdateSpeed` (Cao 1s / Bình thường 2s / Thấp 4s / Tạm dừng) — quét
  toàn bộ pid: `proc_pid_rusage` (RAM + disk I/O), `proc_pidinfo` PROC_PIDTASKINFO (CPU,
  luồng), PROC_PIDLISTFDS (số bộ mô tả tệp ≈ "handles" của Windows), PROC_PIDTBSDINFO
  (uid, ppid), và `nettop -l 1 -x -P -n` cho lưu lượng mạng theo tiến trình.

Mọi truy cập trạng thái mẫu diễn ra trên `fetchQueue` (serial), chỉ hop về main để phát output.

**Nguồn số liệu** (cùng cách exelban/Stats đo, tự viết lại bằng API công khai — Stats là
GPL-3, repo này MIT nên không chép mã):

| Chỉ số | API |
|---|---|
| CPU tổng / kernel | `host_statistics(HOST_CPU_LOAD_INFO)`, tách `cpu_ticks.system` |
| CPU từng lõi | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` |
| Cụm P/E | `IODeviceTree:/cpus` → `cluster-type` theo đúng thứ tự lõi logic; hiển thị nhãn "CPU n" + huy hiệu P/E dưới mỗi ô lõi |
| RAM | `host_statistics64(HOST_VM_INFO64)`, used = active+inactive+speculative+wired+compressed−purgeable−external (bằng Activity Monitor) |
| Swap | `sysctl vm.swapusage` |
| GPU | IORegistry lớp `IOAccelerator` → `PerformanceStatistics` (Device/Renderer/Tiler %, In use/Alloc system memory), `gpu-core-count` |
| Đĩa | IORegistry `IOBlockStorageDriver` → `Statistics` |
| Mạng | `getifaddrs` + `SCDynamicStore` + `nettop` cho từng tiến trình |
| Bluetooth | `system_profiler SPBluetoothDataType -json` |

⚠️ Không gọi thẳng `IOBluetooth.pairedDevices()`: trên macOS hiện tại nó chạm TCC và **crash**
tiến trình nếu Info.plist chưa khai báo quyền Bluetooth.
⚠️ `GPUReader` không được đụng `HardwareInfo.current` (HardwareInfo khởi tạo GPUReader trong
`dispatch_once` → deadlock).

**`AppListPresenter`** giữ `ProcessTree`: mỗi ứng dụng GUI (`activationPolicy == .regular`)
là một hàng cha có giá trị **cộng gộp** cả cây con (theo ppid), các tiến trình con bị loại
khỏi nhóm "Tiến trình nền"/"hệ thống" — đúng cách Task Manager nhóm Chrome/Xcode.
Presenter cũng nuôi các mảng lịch sử 60 mẫu cho đồ thị và thang đo động cho mạng/đĩa.

**Giao diện `Views/Win10/`** mô phỏng Task Manager Windows 10:

- Nút ở chân cửa sổ ("Kết thúc tác vụ"...) dùng push button mặc định của macOS; phần còn
  lại của nội dung mới theo bảng màu Win10.
- `W10Theme` — bảng màu Win10, phông (dùng "Segoe UI" nếu máy có), và **heat map**
  (`heat(_:)` nội suy 7 điểm vàng→đỏ, `pow(v, 0.62)` làm mượt) cho ô CPU/Bộ nhớ/Đĩa/Mạng.
- `W10Grid` — list-view generic: tiêu đề hai dòng (phần trăm tổng + tên, có tô nhiệt),
  sắp xếp theo cột, nhóm thu gọn được, hàng cha mở/đóng cây con, chọn nhiều bằng ⌘.
  Tiêu đề nằm **trong** ScrollView dạng pinned header để cột luôn khớp với thân bảng.
- `W10Graph` / `W10GraphPanel` / `W10CompositionBar` — đồ thị 60 giây vẽ bằng `Canvas`.
- `PerformanceTab` có menu chuột phải như Task Manager: Đổi đồ thị thành (tổng thể / từng
  bộ xử lý logic), Hiện thời gian nhân, Chế độ đồ thị tóm tắt, Xem ▸ tài nguyên, Sao chép
  (đổ số liệu ngăn hiện tại ra clipboard dạng text). Dữ liệu từng lõi lấy bằng
  `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`, phần kernel tách từ `cpu_ticks.system`.
- 7 tab: `ProcessesTab`, `PerformanceTab` (CPU/Bộ nhớ/Đĩa/Mạng), `AppHistoryTab`,
  `StartupTab`, `UsersTab`, `DetailsTab`, `ServicesTab`.
- `FlowLayout` — khối số liệu ở tab Hiệu suất tự xuống dòng; cột thông tin phần cứng bên
  phải bị ẩn khi ngăn hẹp hơn 620pt, sidebar thu còn 150pt khi cửa sổ hẹp hơn 760pt.
  Bề rộng tối thiểu của cửa sổ là 780 vì tab Chi tiết cần ~730pt cho các cột cố định.

**Khung macOS.** Menu bar phải đi qua `.commands { TaskManagerCommands(...) }` — SwiftUI dựng
lại `NSApp.mainMenu` liên tục cho scene `MenuBarExtra`, nên mọi cách gán `NSApp.mainMenu` thủ
công đều bị ghi đè. Menu bar chỉ hiển thị khi app ở activation policy `.regular`, vì vậy
`AppRouter` chuyển `.regular` khi mở cửa sổ và về `.accessory` khi đóng (khi cửa sổ mở sẽ có
icon Dock — đây là đánh đổi bắt buộc). Thanh tab là `NSToolbar` (`toolbarStyle = .unifiedCompact`,
tiêu đề hiện bên trái, `displayMode = .iconOnly`, icon dồn phải bằng một `.flexibleSpace` ở đầu,
chọn qua `selectedItemIdentifier`, mọi icon dùng chung một `NSImage.SymbolConfiguration`
14pt để không cái to cái nhỏ — tên tab hiện ở dòng tiêu đề đầu vùng nội dung
(`DetailWindowView.contentHeader`), ở tooltip và menu Xem ⌘1…⌘7) — macOS 26 tự vẽ các mục
thành nút bo tròn kiểu glass kèm nhãn; ẩn toolbar ở chế độ gọn. Vì tab còn đổi được từ menu
(⌘1…⌘7), `TaskManagerToolbar` dùng `withObservationTracking` tự đăng ký lại để đồng bộ ngược. Trạng thái tab/vùng chọn nằm ở `TaskManagerState` để cả menu
bar lẫn cửa sổ cùng đọc ghi.

Cửa sổ bị ép giao diện sáng (`window.appearance = .aqua` + `environment(\.colorScheme, .light)`)
vì bảng màu Win10 là màu sáng cố định.

**Đa ngôn ngữ (Việt / Anh).** Không dùng `.strings`/String Catalog vì phần lớn chuỗi đi qua
struct (tiêu đề cột, tên tab, nhãn entity) nên `Text("literal")` không tự dịch được. Thay vào
đó có `L.t("tiếng Việt", "English")` đọc `L10n.shared.language`; `L10n` là `@Observable` nên
mọi view gọi `L.t` trong body tự vẽ lại khi đổi ngôn ngữ — **không cần khởi động lại**.
Lựa chọn lưu ở UserDefaults `AppLanguage`, mặc định theo `Locale.preferredLanguages`.
Đổi trong menu **Tùy chọn ▸ Ngôn ngữ**.

Phần AppKit không tự cập nhật: tiêu đề cửa sổ (`AppRouter.observeLanguage`) và nhãn/tooltip
toolbar (`TaskManagerToolbar.refreshLabels`) phải gán lại qua `withObservationTracking`.

## Key Technical Details

- `Bridging-Header.h` bridges `<libproc.h>`, `<sys/proc_info.h>`, `<sys/sysctl.h>`, `<ifaddrs.h>`, `<net/if.h>`, `<pwd.h>` cho phần introspection tiến trình.
- App Sandbox is **disabled** (required for cross-process memory inspection).
- Hardened Runtime is enabled; code signing uses automatic with team `J299H8YWF8`.
- Gộp nhóm tiến trình đi theo quan hệ **ppid**: `AppListPresenter.buildTree` gom toàn bộ
  con cháu của mỗi ứng dụng GUI vào hàng cha (RAM/CPU/đĩa/mạng/luồng đều cộng gộp).
- Tiến trình của user khác (root...) trả về 0 MB / 0 luồng vì `proc_pid_rusage` bị chặn
  khi không chạy quyền root — đây là giới hạn của macOS, không phải lỗi.
- `nettop` được spawn mỗi nhịp quét tiến trình; đó là phần tốn CPU nhất của app, nên
  `UpdateSpeed` mặc định là 2 giây.
