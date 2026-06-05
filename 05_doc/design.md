# Design.md｜BMS_Pack_Simulation 项目设计文档

**项目**：基于 MATLAB Simscape Battery 的动力电池 PACK + BMS 全链路仿真
**开发模式**：Claude Code + MATLAB MCP 辅助工程化开发
**用途**：GitHub 开源存档、课程设计、科创竞赛、简历项目佐证
**版本**：v1.3（含 7.2 全部拓展：主动均衡 / 液冷 / 热失控 / EKF C 代码生成）｜环境：MATLAB R2025a

---

## 1. 项目概述

### 1.1 项目目标

1. 搭建圆柱锂电单体 → 模组 → 整包 PACK 多尺度电气 + 热耦合仿真模型；
2. 实现两类 SOC 算法：安时积分法、EKF 扩展卡尔曼滤波 SOC 估算并对比误差；
3. 完成被动均衡 + 故障注入仿真（过压 / 欠压 / 过温 / 电芯内短路）；
4. 实现 3D 整包温度色阶动态渲染，输出 GIF / 曲线图用于 GitHub 展示；
5. 工程规范化分层，一键启动仿真、自动出数据与报表，可直接上传 GitHub 开源。

### 1.2 技术栈

- 仿真环境：MATLAB R2025a + Simscape Battery（建模库）
- 数值内核：纯 M 函数 `pack_simulator`（电-热-故障耦合前向积分）
- 参数辨识：Optimization Toolbox `lsqcurvefit`（HPPC 一阶 RC 拟合）
- 算法：M 脚本（SOC、均衡控制、故障诊断）
- 文档：Markdown（README.md / Design.md）
- 素材资源：asset 目录存放 GIF、PNG

### 1.3 适用场景

车载储能 PACK 仿真、BMS 算法验证、电池热管理仿真、新能源课程实训、三电方向作品集。

---

## 2. 整体架构设计（分层架构）

```text
BMS_Pack_Simulation/
├─ asset/            # 可视化资源：GIF、PNG（GitHub 展示专用）
├─ 01_Model/         # Simscape 自定义库 Pack_Lib（24S12P 模组级）
├─ 02_Src_Code/      # BMS 核心算法 M 源码 + 数值仿真器
├─ 03_Data/          # 电芯 HPPC 试验数据、参数 mat、仿真输出 csv
├─ 04_Script_Auto/   # 一键仿真、绘图、3D 截图 / GIF 录制脚本
├─ 05_doc/           # 设计文档（本 Design.md 存放于此）
├─ startup.m         # 工程初始化脚本：路径添加、全局参数加载
└─ README.md         # 开源首页说明文档
```

### 分层职责说明

1. **Model 层（01_Model/）**
   - `Pack_Lib`：由 `Build_Pack_Model.m` 经 Simscape Battery Builder 生成的自定义库
   - 建模粒度：Lumped 集总等效（ParallelAssembly 12P → Module 24S）
   - 热耦合：`AmbientThermalPath = CellBasedThermalResistance`，电芯经热阻连风冷环境
   - 电芯模型：Table-Based + 一阶 RC（`prm_dyn='rc1'`）+ 热端口 + 温度依赖
2. **Src_Code 算法层（02_Src_Code/）**
   - SOC 算法组：安时积分 `coulomb_counting_soc`、EKF `ekf_soc_estimator`
   - 均衡控制组：被动均衡阈值逻辑 `passive_balancing`
   - 故障诊断组：阈值 + MAD 离群 `fault_diagnosis`
   - 参数标定：`calibrate_pack_param`；数据合成：`gen_synthetic_cell_data`
   - 数值仿真器：`pack_simulator`（电-热-故障耦合前向积分，纯函数）
3. **Data 数据层（03_Data/）**
   - `Cell_Test_Data/`：OCV-SOC、HPPC 脉冲试验 CSV
   - `Pack_Param.mat`：全局参数结构体 `PackParam`（Cell/OCV/Pack/Thermal/Geometry/BMS）
   - `Sim_Out_Result/`：各工况仿真输出 timetable CSV
4. **Script_Auto 自动化层（04_Script_Auto/）**
   - `Run_All_Sim.m`：批量四工况仿真，导出 CSV
   - `Plot_Result.m`：SOC 对比、压差收敛、温升曲线
   - `Show_3DPack.m`：3D 温度场 GIF + 封面 PNG
   - `Build_Pack_Model.m`：生成 Simscape 库
   - `test_bms_algorithms.m`：8 项算法单元测试

---

## 3. 功能模块详细设计

### 3.1 电池本体建模模块

**电芯**：18650 圆柱锂电，一阶 Thevenin 等效（R0 + R1∥C1）+ 集总热模型。

**拓扑**：24 串 12 并（24S12P）。`pack_simulator` 中每串等效为 12 并集总单体，串组容量 `Cap_str = Np × Cap_cell = 36 Ah`，整包串联组成 24S 模组。

**电气方程**（每串 j，放电电流 I>0）：

```
V_j      = OCV(SOC_j) − I_str·R0_j(T) − Vrc_j
Vrc_j(k+1) = a·Vrc_j + R1·(1−a)·I_str,   a = exp(−dt/(R1·C1))
SOC_j(k+1) = SOC_j − I_str·dt/(3600·Cap_str)
I_str    = I_load + I_bal + I_isc
```

**内阻温度修正**：`R0(T) = R0·(1 + kR·(T − Tref))`，kR = −0.005 /°C。

**热方程**（每串 j，集总热容）：

```
Cth·dT_j/dt = Q_ohm + Q_bal + Q_isc + Q_cond − Q_conv
Q_ohm  = I_str²·R0(T) + I_load²·R1        （欧姆 + 极化发热）
Q_cond = k_cond·(相邻串温差)               （一维热传导，端串单侧）
Q_conv = (T_j − T_amb)/Rth                 （风冷对流散热）
```

并联组热容 `Cth = mass·Cp·Np`，对环境热阻 `Rth = Rth_cell/Np`。

### 3.2 BMS 算法模块

**1) SOC 估算**

- **安时积分**（对照组）：`SOC(k+1) = SOC(k) − I(k)·dt/(3600·Cap)`，纯积分无反馈，初值误差不收敛。
- **EKF**（一阶 Thevenin）：状态 `x = [SOC; Vrc]`
  - 状态方程：`SOC(k+1) = SOC − dt/(3600·Cap)·I`；`Vrc(k+1) = a·Vrc + R1·(1−a)·I`
  - 观测方程：`V = OCV(SOC) − R0·I − Vrc`
  - 雅可比：`A = [1 0; 0 a]`，`C = [dOCV/dSOC, −1]`（OCV 导数用中心差分数值求取）
  - 噪声整定：`Q = diag([1e-7, 1e-6])`，`R = 4e-6`，`P0 = diag([1e-2, 1e-2])`
  - 参考：Plett, *Battery Management Systems, Vol.2*, Ch.3

**2) 被动均衡**：以组内电压均值为基准，对高于 `(mean + threshold)` 的单体投入耗散电阻（阈值 50 mV），带迟滞（默认 threshold/5）防止阈值附近频繁通断。均衡电流 `I_bal = V/R_bal`，产生均衡放电与发热。

**3) 故障诊断**（单步逐单体）：

- 阈值类：OV（>4.25V）、UV（<2.5V）、OT（>60°C）、UT（<−10°C）
- 内短路：基于中位数 + MAD 鲁棒离群，判据 `(median(V) − V) > k·1.4826·MAD(V)` 且压降 > 最小绝对阈值（k=5，min_dV=0.1V），识别异常自放电单体。

### 3.3 可视化输出模块

1. **静态曲线**（300 dpi 宋体）：`EKF_SOC_Compare.png`、`Cell_dV_Balance.png`、`Thermal_ISC_Rise.png`、`OCV_SOC_Calibration.png`
2. **3D 动态**：`ISC_Temp_Dynamic.gif`（24 串排 4×6 圆柱阵列，温度蓝 25°C → 红 60°C，61 帧，0.2s/帧永久循环）+ 封面 `Pack_3D_Thermal.png`
3. **输出路径**：全部写入 `asset/`，README 相对路径引用。

---

## 4. 参数标定结果（实测）

HPPC 脉冲数据经一阶 RC 辨识（`lsqcurvefit` 拟合完整端电压 `V(t)=OCV(SOC(t))−I·R0−Vrc`，前向积分扣除放电段 OCV 漂移，避免高估 R1）：

| 参数 | 值 | 参数 | 值 |
|---|---|---|---|
| R0（内阻） | 25.2 mΩ | R1（极化） | 15.1 mΩ |
| C1（极化电容） | 2053 F | τ = R1·C1 | 31.1 s |
| 电芯容量 | 3.0 Ah | OCV 查表 | 21 点 / 3.105–4.164 V |

**PACK 规格**：24S12P｜容量 36 Ah｜标称 86.4 V｜范围 60.0–100.8 V｜能量 ~3.11 kWh。

**热参数**（18650 工程经验值）：质量 45 g，比热 900 J/(kg·K)，风冷换热系数 25 W/(m²·K)，环境 25°C，内阻温度系数 −0.005 /°C。

辨识方法参考：Plett, *Battery Management Systems, Vol.1*, HPPC 辨识。

---

## 5. 仿真工况设计与实测指标

四类工况由 `Run_All_Sim.m` 批量调度，EKF 初值故意偏置 −10% 以检验修正能力。

| 工况 | 描述 | 时长/步长 | EKF RMSE | 安时积分 RMSE | 关键现象 |
|---|---|---|---|---|---|
| **CC** | 恒流放电 0.5C | 1h / 1s | 2.70% | ~10% | 温升 25→35.1°C，压差 38→26 mV |
| **WLTC** | 车载动态工况 | 30min / 1s | 1.43% | ~10% | 1507s 触发欠压，峰值 39.3°C |
| **ISC** | 第 12 串 600s 注入内短路 | 30min / 1s | 1.86% | 9.83% | 1038s 检出内短路，峰值 57.9°C，压差升至 237 mV |
| **Balance** | 静置被动均衡 | 10h / 10s | 0.22% | 9.41% | 压差收敛 183→128 mV |

**WLTC 电流剖面**：四段（低/中/高/超高速）放电倍率 0.3/0.6/0.9/1.2C，叠加正弦加减速波动与偶发制动回馈（负电流）。

**结论**：初值偏置下安时积分误差恒定不收敛，EKF 凭端电压观测快速修正至 <3%，SOC 算法优势清晰。内短路工况复现局部热点 → 相邻串热传导 → 风冷平衡的完整热蔓延过程。

仿真结果以 timetable 导出 CSV 至 `03_Data/Sim_Out_Result/`，命名 `Sim_<工况>_<日期>.csv`。

---

## 6. 开发流程（Claude + MCP 标准化流程）

1. **目录构建**：生成全量文件夹 + `startup.m`（相对路径、全局 `BMS_PATHS`）；
2. **参数标定**：导入电芯试验数据，OCV-SOC 拟合 + HPPC 辨识 → `Pack_Param.mat`；
3. **模型搭建**：`Build_Pack_Model` 生成 Simscape 库 + `pack_simulator` 数值内核；
4. **算法开发**：SOC / 均衡 / 故障诊断 M 代码，MCP 在线运行调错，8 项单元测试；
5. **批量仿真**：`Run_All_Sim` 一键四工况，自动保存 CSV；
6. **素材生成**：`Plot_Result` + `Show_3DPack` 自动导出曲线图与 GIF 至 asset；
7. **文档落地**：README.md + Design.md，本地预览后推送 GitHub。

> 当前状态：1–7 全部完成。

---

## 7. 交付产物清单与拓展方向

### 7.1 交付产物

1. 完整可运行 MATLAB 工程（算法 + 仿真器 + 自动化脚本）；
2. asset 展示素材：3D 温度场 GIF + 4 张曲线图；
3. README.md、Design.md 两份文档；
4. 四工况仿真原始数据 CSV + 8 项单元测试。

### 7.2 拓展能力（已实现）

三方向已在 `pack_simulator` 内核实现（新增 `opt` 字段默认保持原行为，向下兼容，原 4 工况回归不变），由 `Run_Extended_Sim` 调度，`Plot_Extended` / `Show_Runaway` 出图，15 项单元测试覆盖。

**① DC-DC 主动均衡**（`active_balancing.m`，集中式电荷转移）

```
dev_j = SOC_j - mean(SOC)
放电（dev>死区）: I_dis_j = min(I_max, kp*dev_j)            （+，高 SOC 串）
充电（dev<-死区）: I_chg ∝ -缺额比例, Σ充入 = eff*Σ放出      （-，低 SOC 串）
发热: 仅 (1-eff) DC-DC 变换损耗（计在放电侧），无大量耗散热
```

实测（静置 10h）：压差 183→**15 mV**（被动 →128 mV）；SOC 离散度 16%→1.2%；峰温仅 +0.35°C；损耗致 SOC 均值降 0.193%（即 (1-eff) 转移损耗）。

**② 液冷热管理**（`cooling='liquid'`，沿流向冷却液节点链）

```
Q_cool_j = (T_j - Tc_{j-1})/Rth_cool        电芯 j 散入冷却液
Tc_j     = Tc_{j-1} + Q_cool_j/(mdot*Cp)    冷却液沿程升温（准稳态）
```

冷却液从入口 Tin 沿串号 1→Ns 流动逐节点吸热升温，下游散热条件变差呈梯度。实测（0.5C 1h）：峰温 35.1°C(风冷)→30.6°C(液冷 0.05 kg/s)；沿流向梯度 1.8°C(0.05)/4.4°C(0.02)；流量越低梯度越大。

**③ Arrhenius 热失控**（`arrhenius_heat.m`，温度正反馈 + 反应物自限）

```
反应速率   k(T,c) = A*c^m*exp(-Ea/(Rgas*T_K))
产热功率   q       = H_total*k
反应物消耗 dc/dt   = -k,  c∈[0,1]
数值稳定：以反应物消耗驱动产热并限幅 dc ≤ min(请求, 剩余c, dc_cap)，
          保证 ∫释放=H_total、温升不过冲；热推进采用子步。
```

参数：A=2e10 /s，Ea=1.0e5 J/mol，H=25 kJ/单体（绝热温升 ~617 K）。实测（第 12 串内短路 R=0.05Ω）：线性产热稳定 **136°C** vs Arrhenius 失控 **748°C**；约 49 s/串 自触发串向两端**对称链式蔓延**全包；触发串反应物耗尽 c→0 自限；峰温物理有界、无数值发散。

**④ EKF C 代码生成对接 STM32**（`ekf_soc_step_cg.m` → Embedded Coder）

面向 ARM Cortex-M 的嵌入式部署，对 EKF 做 codegen 兼容改造并生成可移植 C 源码：

```
改造要点：
  1) OCV 查表 pchip → linear（MATLAB Coder 不支持 pchip；dOCV/dSOC 取线段斜率）
  2) 单步调用 + persistent 保持状态 x=[SOC;Vrc] 与协方差 P（契合 MCU 周期采样）
  3) 定长内存：SOC_bp/OCV_bp 固定 21 点，标量 I/O，无 emxArray/malloc
  4) lib 配置 + GenCodeOnly：仅产 C 源（不依赖主机编译器），SupportNonFinite=false
入口：void ekf_soc_step_cg(double I_k, V_k, dt, prm*, reset, *soc, *vrc, *vhat)
```

生成产物：`02_Src_Code/codegen_ekf/ekf_soc_step_cg.c/.h`（纯静态内存，~186 行），可直接集成进 STM32 工程（Keil / STM32CubeIDE，Cortex-M4F/M7 带 FPU 直接用 double）。

**等价性验证**（`Verify_EKF_Ccode`，PIL 算法层替代）：真 PIL 需目标硬件 + 硬件支持包，当前环境无硬件 / 无主机 C 编译器（仅 32 位 MinGW，MEX 需 64 位），故 SIL/MEX 不可执行，改以 MATLAB 层数值等价性佐证：

| 版本 | vs 真值 RMSE | 说明 |
|---|---|---|
| 原版 pchip（浮点参考） | 0.369% | `ekf_soc_estimator` |
| codegen 批处理 linear | 0.532% | `ekf_soc_estimator_cg` |
| codegen 单步 linear（同源 C） | 0.532% | `ekf_soc_step_cg`，单步与批处理位级一致 |

linear 查表致最大瞬态偏差 2.04%（仅 OCV 拐点），稳态收敛后≈0——嵌入式查表的合理取舍，精度仍远优于安时积分（~10%）。定点优化（Fixed-Point Designer）与真 PIL 留待有硬件时迭代。

---

*本 Design.md 随项目迭代持续更新，当前版本 v1.3 对应已完成的 7 步开发流程 + 7.2 全部拓展（主动均衡 / 液冷 / 热失控 / EKF C 代码生成）。*
