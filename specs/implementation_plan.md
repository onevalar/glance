# 轻量级 Lightroom 功能演进计划：图像选图管理与非破坏性裁剪

## 当前验证进度（2026-10-08）

- macOS 主体流程已验证：目录导入、最近位置、三级标记与筛选、多图比较、非破坏性裁剪的比例切换、重置、取消、完成及重新打开。裁剪保存元数据，原图文件保持不变；浅色与深色均已检查。
- iOS 26.2 的独立 iPhone 17 Pro 模拟器已通过完整构建，使用测试相册验证读取照片、缩略图切换、保留/丢弃后自动前进、筛选、筛选为空时返回全部，以及应用重启后丢弃标记保留。浅色和深色均已检查。
- 模拟器验证不覆盖真实双指缩放、触控手势和 iPad 实机表现。这些仍需相应设备验证；没有用用户照片进行本轮测试。

为了将「过目」（Glance）演进为轻量级 "Lightroom"，本项目将聚焦于**图像选图管理（筛选、三级评分、多选、网格同步比对）**以及**非破坏性裁剪功能**。

在通过 `/grill-me` 进行设计评审后，我们对交互和细节作出了以下最终设计决策：

---

## 🎨 评审通过的设计与交互规范

### 1. 📊 多图平铺比对 (Compare Mode)
* **自动平铺网格**：当选中图片数量 $\ge 2$ 时，主界面自动平铺为类似会议软件的自适应网格（2张图 1x2，4张图 2x2 等）。
* **轴心同步联动 (Relative Zoom Anchor)**：
  - **同步逻辑**：采用**相对百分比位置对齐（方案 A）**。当用户缩放/拖拽其中任意一个窗口内的图像时，所有子视图均同步更新到相同的缩放倍率，且平移偏移量会以**操作点相对于图片的百分比比例**在所有窗口中完全对齐。这允许像素级对比多张照片同一部位（如人眼）的画质与焦点。

### 2. 🚩 极简“三级评分”与“快速筛选” (Rating & Filter)
* **状态定义**：
  - `.keep`（保留）
  - `.undecided`（不确定，默认状态）
  - `.discard`（丢弃）
* **快捷键映射**：
  - 数字键 `1` 或 字母键 `X` $\rightarrow$ 标记为 **丢弃**
  - 数字键 `2` 或 字母键 `U` $\rightarrow$ 标记为 **不确定**
  - 数字键 `3` 或 字母键 `P` $\rightarrow$ 标记为 **保留**
* **即时视觉反馈 (Toolbar HUD)**：
  - 不采用屏幕中央的大遮挡 HUD，而是使用**轻量边缘提示（方案 B）**。按下快捷键评分时，仅在工具栏或图片边缘状态栏位置，使对应标识产生一个短暂的亮起呼吸灯/淡入淡出动效。
* **侧边栏视觉反馈**：
  - `.discard`（丢弃）的图片缩略图变为 **40% 半透明**，并打上红色 “X” 或删除标识。
  - `.keep`（保留）的图片缩略图显示明显的白色或绿色旗帜标志。
* **一键批量清空 (Bulk Clear)**：
  - 侧边栏顶部工具栏提供一个“一键清空丢弃”按钮。点击后，弹窗让用户二次确认，确认后将当前目录下所有状态为 `.discard` 的图片一次性批量移入系统的废纸篓（Trash）。

### 3. 🖱️ 侧边栏多选鼠标手势 (Multi-Select Gestures)
* **手势定义**：
  - 默认单击：选中单张，清除其他选中。
  - `Cmd + 点击`：切换单张图片的多选状态（增减）。
  - `Shift + 点击`：以当前主选择和上一次点击位置为首尾，进行连续范围选中。
* **侧边栏控制**：完全由用户控制（方案 B），不强制在进入对比或裁剪时自动收起，用户可随时通过原有的折叠按钮自行手动控制折叠或展开。

### 4. ✂️ 非破坏性裁剪编辑 (Non-Destructive Crop)
* **裁剪模式 (`R` 键触发)**：
  - 按下 `R` 进入/退出单张图片的裁剪状态。
* **辅助构图三分线 (Dynamic Grid)**：
  - 采用**动态显示（方案 A）**。只有在用户点击或正在拖拽裁剪框边框/手柄时，三分线辅助网格才会平滑淡入显现；静止操作时，三分线自动隐去。
  - 裁剪区域外的冗余图片区域将覆盖一层半透明的暗黑色遮罩，使视觉聚焦在裁剪范围内。

---

## Proposed Changes

我们将分为两个阶段（组件）进行设计：

### 阶段 1：选图管理组件（多选、三级评分与网格同步比对）

#### [NEW] [ImageMetadata.swift](file:///Users/anvalar/Documents/%E5%BC%80%E6%BA%90%E4%BA%A7%E5%93%81/Glance/Sources/Glance/Models/ImageMetadata.swift)
- 定义数据结构 `ImageMetadata: Codable`：
  - `status: ImageStatus` (枚举：`.discard`, `.undecided`, `.keep`，默认为 `.undecided`)
  - `cropRect: CGRect?` (规范化的裁剪范围，例如 `x: 0.1, y: 0.1, width: 0.8, height: 0.8`)
- 提供 `MetadataManager`：
  - 管理图片 URL 到 `ImageMetadata` 的映射。
  - 使用本地沙盒 JSON 文件或 UserDefaults 持久化。

#### [MODIFY] [AppState.swift](file:///Users/anvalar/Documents/%E5%BC%80%E6%BA%90%E4%BA%A7%E5%93%81/Glance/Sources/Glance/AppState.swift)
- 扩展状态：
  - `@Published var selectedImageIndices: Set<Int> = []`：支持多选图片的索引集合。
  - `@Published var activeFilter: PhotoFilter = .all`：当前的筛选状态（全部 / 保留 / 不确定 / 丢弃）。
  - 提供方法以便批量操作选中的图片、单张修改、以及清空丢弃照片。
  - 处理键盘快捷键分发。

#### [MODIFY] [ThumbnailSidebar.swift](file:///Users/anvalar/Documents/%E5%BC%80%E6%BA%90%E4%BA%A7%E5%93%81/Glance/Sources/Glance/Views/ThumbnailSidebar.swift)
- 升级侧边栏以支持多选手势与状态展示：
  - 绑定并渲染多选状态，传递点击事件修饰键状态给 AppState。
  - 顶部新增筛选器分段控件（All / Keep / ? / Discard）。
  - 侧边栏顶部增加“一键清空丢弃（垃圾桶图标）”按钮。
  - 渲染被丢弃图片的 40% 不透明度和红叉；保留图片的旗帜标。

#### [MODIFY] [ImageThumbnailView.swift](file:///Users/anvalar/Documents/%E5%BC%80%E6%BA%90%E4%BA%A7%E5%93%81/Glance/Sources/Glance/Views/ImageThumbnailView.swift)
- 增加徽标渲染与半透明控制。
- 优化多选下的高亮状态。

#### [NEW] [ImageCompareView.swift](file:///Users/anvalar/Documents/%E5%BC%80%E6%BA%90%E4%BA%A7%E5%93%81/Glance/Sources/Glance/Views/ImageCompareView.swift)
- 采用网格布局承载多个 `GlanceImageView`。
- 侦听各个子视图的 pan/zoom 事件，并统一把 shared 缩放与 shared 相对坐标广播至所有网格图片。

---

### 阶段 2：非破坏性裁剪组件

#### [NEW] [CropOverlayView.swift](file:///Users/anvalar/Documents/%E5%BC%80%E6%BA%90%E4%BA%A7%E5%93%81/Glance/Sources/Glance/Views/CropOverlayView.swift)
- 在普通图层上绘制裁剪外边框与 8 个方向的拖拽手柄。
- 支持手势拖拽，拖拽时淡入 Rule of Thirds 三分线，静止时隐去。
- 提供裁剪确认、取消条以及锁定比例菜单（1:1, 4:3, 16:9, 2:3, Free）。

#### [MODIFY] [ZoomableImageView.swift](file:///Users/anvalar/Documents/%E5%BC%80%E6%BA%90%E4%BA%A7%E5%93%81/Glance/Sources/Glance/Views/ZoomableImageView.swift)
- 支持裁剪后局部的无损放大展示（裁剪不写入图片文件，而是基于 `cropRect` 进行图像渲染裁剪）。
- 支持进入裁剪编辑模式。

#### [MODIFY] [ContentView.swift](file:///Users/anvalar/Documents/%E5%BC%80%E6%BA%90%E4%BA%A7%E5%93%81/Glance/Sources/Glance/Views/ContentView.swift)
- 融合多图对比模式与单图裁剪模式的渲染选择。

---

## Verification Plan

### Automated Tests
- `MetadataManagerTests` 验证评分（保留、不确定、丢弃）和 `cropRect` 数据的序列化保存。
- 测试过滤逻辑。

### Manual Verification
1. **多选手势**：Cmd+点击多选，Shift+点击连续多选，确认选中背景样式。
2. **平铺联动**：多选 2-4 张图，在一张图上滚动缩放或拖动，观察所有网格是否完全像素对齐运动。
3. **评分与过滤**：按 `1` / `X` 变灰打叉，按 `3` / `P` 显示旗帜。顶栏切换分类筛选，一键清空丢弃移入废纸篓。
4. **裁剪交互**：按 `R` 进入，拖拉裁剪手柄时三分线平滑显现，松开隐藏，未选部分变暗。应用裁剪后，原图文件未改，但预览只显示裁剪内容。
