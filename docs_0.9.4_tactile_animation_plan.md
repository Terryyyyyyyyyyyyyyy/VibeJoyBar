# VibeJoyBar v0.9.4: 虚拟控制器物理机械灵动动效研发方案

## 🎯 目标与范围
为 VibeJoyBar 控制面板赋予真实的“任天堂机械玩具质感（Nintendo Delight & Tactile Feedback）”，实现按键按压下沉与弹性弹起（Spring Physics）、摇杆 3D 偏转偏移与实时视觉联动。

### 核心设计指标
1. **按键物理下陷与阻尼回弹 (Key Travel & Spring Bounce)**：
   - 交互/按下时：按钮沿 2.5D 深度下沉 2.0~2.2pt，外围投影与光圈紧贴收拢（`.scaleEffect(0.94~0.95)`, `.offset(y: 2.0~2.2)`）；
   - 触觉反馈：按下瞬间触发 macOS 精准轻触对齐触觉震动（`NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)`）；
   - 释放/弹起时：带有 Apple Spring 阻尼物理弹性（`response: 0.22, dampingFraction: 0.52`）“啵”地弹起复位，手感极其拟真。
2. **摇杆 3D 偏转与轴向拉伸 (3D Stick Deflection & Perspective Tilt)**：
   - 当摇杆被推向上下左右或任意角度时，摇杆帽整体沿受力方向进行立体位移（最大 14pt 阻尼向量限幅）；
   - 摇杆帽 3D 透视倾斜（Pitch & Roll 最大 18°，基于 X/Y 轴 3D 矩阵旋转与透视近大远小）；
   - 凹槽内边缘阴影随推杆方向动态反向拉长（`dynamicSocketShadowOffset`），刻画出立体的物理球窝机构感；
   - 摇杆下压点击（Stick Click）时，垂直微幅下陷（2.5pt）并伴随同心光环微脉冲（0.6x -> 1.6x 扩散淡出）。
3. **性能与功耗控制**：
   - 纯 GPU 硬件加速图层，面板打开时流畅 60fps/120fps ProMotion，面板收起/关闭时 0% CPU 消耗。

---

## 🛠 实现架构与交付成果

### 1. `TactilePhysics.swift` (物理动力学与触觉模型)
- 动画物理常量：
  - `appleSpring = Animation.spring(response: 0.22, dampingFraction: 0.52)`
  - `hoverSpring = Animation.spring(response: 0.28, dampingFraction: 0.65)`
- 几何与力学限幅：
  - `maxStickDeflection: CGFloat = 14.0`
  - `maxStickTiltDegrees: Double = 18.0`
- 核心算法：
  - `clampDeflection(offset:maxRadius:)`: 矢量模长限制在球窝物理边缘之内。
  - `calculateTilt(offset:maxRadius:maxTilt:)`: 计算 (pitch, roll) 空间角度并安全截断至 `[-maxTilt, maxTilt]`。
  - `dynamicSocketShadowOffset(deflection:)`: 依推杆方向生成逆向内阴影位移矢量（`-0.45 * deflection`）。
  - `directionForOffset(_:deadzone:)`: 5.0pt 死区过滤，根据主轴输出精确的方向映射（up/down/left/right）。
  - `offsetForDirection(_:distance:)`: 方向转偏转位移。
- 触觉按键样式：
  - `TactileHotspotButtonStyle`: 正面按键与摇杆方向箭头下陷 2.2pt、缩放 0.94、光影收紧与 Haptics。
  - `TactileCapsuleButtonStyle`: 肩键（R/ZR/L/ZL）胶囊下陷 2.0pt、缩放 0.95 与 Haptics。

### 2. `InteractiveJoyConStickView.swift` (3D 机械拟真摇杆组件)
- **球窝底座 (Socket Base)**: 76pt 径向暗黑底座 + 动态逆向内阴影 + 罗盘虚线背板。
- **光环脉冲 (Click Pulse)**: 摇杆点击时同心扩散光环。
- **机械摇杆帽 (Stick Cap)**: 52pt 哑光防滑圈 + 12/3/6/9 点钟 4 处握持凸点 (Grip Nubs) + 凹面指腹槽 + 3D 透视倾斜 + 2D 位移 + 原生拖拽手势 + 单击 Stick Click 深度下沉与脉冲。
- **4 轴方向指示热区 (Direction Hotspots)**: 环形排列于球窝边缘，统一应用 `TactileHotspotButtonStyle`。

### 3. `ControllerIllustrationView.swift` (插图与热区整合)
- 全面引入 `InteractiveJoyConStickView` 替换原分散的热区散点与静态罗盘底图。
- 完美自适应右手（R-Stick 坐标 `0.677, 0.540`）与左手（L-Stick 坐标 `0.461, 0.302`）。
- **真实左手柄 4 枚独立圆形方向键形态复刻**：严格遵循 Switch 双人分体共享设计规范，告别十字键错误，无痕重绘红色外壳基底，像素级还原 4 枚独立圆形方向键（▲、▼、◀、▶）。
- **真实肩部硬件按键解耦与机械下沉**：彻底移除中央悬浮胶囊指示器，整枚真实黑色肩部硬件按键作为独立可交互物理层。静止状态 100% 还原官方原画，点击时真实垂直下沉（ZL/ZR 6.5pt，L/R 4.8pt）沉入深黑色腔体槽。
- 按键均集成 Apple Spring 弹簧阻尼与 120ms 触觉停留保障，告别轻点无感。

### 4. 自动化测试与质量验证 (`TactilePhysicsTests.swift`)
- 10 个独立物理动力学测试用例全绿通过（限幅逻辑、3D Tilt 边界、动态阴影逆向位移、死区判定、方向映射）。
- `VibeJoyBarPackageTests` 26 个测试用例全部通过。

---

## 📌 版本状态
- **Status**: ✅ Completed (v0.9.4 / Build 5)
