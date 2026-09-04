# VibeJoyBar v0.9.4: 虚拟控制器物理机械灵动动效研发方案

## 🎯 目标与范围
为 VibeJoyBar 控制面板赋予真实的“任天堂机械玩具质感（Nintendo Delight & Tactile Feedback）”，实现按键按压下沉与弹性弹起（Spring Physics）、摇杆 3D 偏转偏移与实时视觉联动。

### 核心设计指标
1. **按键物理下陷与阻尼回弹 (Key Travel & Spring Bounce)**：
   - 交互/按下时：按钮沿 2.5D 深度下沉 2~3pt，外围投影与光圈紧贴收拢（`.scaleEffect(0.95)`, `.offset(y: 2)`）；
   - 释放/弹起时：带有 Apple Spring 阻尼物理弹性（`response: 0.22, dampingFraction: 0.52`）“啵”地弹起复位，手感极其拟真。
2. **摇杆 3D 偏转与轴向拉伸 (3D Stick Deflection & Perspective Tilt)**：
   - 当摇杆被推向上下左右或任意角度时，摇杆帽整体沿受力方向进行立体位移；
   - 凹槽内边缘阴影随推杆方向动态反向拉长，刻画出立体的物理球窝机构感；
   - 摇杆下压点击（Stick Click）时，垂直微幅下陷并伴随同心光环微脉冲。
3. **性能与功耗控制**：
   - 纯 GPU 硬件加速图层（SwiftUI Metal Canvas / DrawingGroup），面板打开时流畅 60fps/120fps ProMotion，面板收起/关闭时 0% CPU 消耗。
