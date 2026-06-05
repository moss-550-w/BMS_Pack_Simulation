以下是为该项目量身定制的 `Claude.md`，可直接放入仓库根目录，用于指导 Claude Code + MATLAB MCP 的协作开发。

```markdown
# Claude.md – BMS_Pack_Simulation 项目开发指南

> 本文件为 Claude Code 持久化项目指令，用于规范 MATLAB/Simulink 电池包仿真工程的 AI 辅助开发流程。

## 1. 项目身份卡

- **项目名称**：BMS_Pack_Simulation  
- **一句话描述**：基于 MATLAB Simscape Battery 的动力电池 PACK + BMS 全链路仿真平台  
- **目标交付物**：可运行工程 + 可视化素材 + 设计文档，直接开源至 GitHub  
- **开发模式**：Claude Code (对话式 AI) + MATLAB MCP (模型/脚本/素材的自动化执行)  
- **用户场景**：课程设计、科创竞赛、简历作品集、车载储能算法验证  

## 2. 你必须遵守的工程结构

所有操作必须基于以下目录树，不得私自创建无关文件夹：

```
BMS_Pack_Simulation/
├── asset/            # 可视化素材：GIF、PNG、仿真视频（你导出图片/动图时必须放这里）
├── 01_Model/         # Simulink 顶层与子系统模型 .slx
├── 02_Src_Code/      # BMS 核心算法 .m（SOC、均衡、故障诊断、参数标定）
├── 03_Data/          # 电芯测试 CSV、Pack_Param.mat、仿真输出 csv
├── 04_Script_Auto/   # 一键仿真、批量处理、绘图与 3D 截图脚本
├── 05_Doc/           # Design.md 与仿真报告（你的产出文档放这里）
├── startup.m         # 工程初始化：加路径、加载全局参数
└── README.md         # 开源首页说明
```

### 路径使用规则
- **严禁硬编码绝对路径**，始终使用 `startup.m` 添加的相对路径或 `fullfile` 构建。  
- 仿真输出数据默认存入 `03_Data/Sim_Out_Result/`，图片/GIF 存入 `asset/`。  
- 任何生成的脚本必须位于 `04_Script_Auto/`，并遵循 `Run_*.m`、`Plot_*.m`、`Show_*.m` 命名格式。  

## 3. 你的核心能力（Claude + MATLAB MCP）

通过 MATLAB MCP 工具，你可以：
- 自动生成 Simulink 模型（按自然语言描述创建子系统、连接 Simscape 组件）  
- 创建/修改 M 脚本并在线运行、调试  
- 读取/写入 .mat、.csv 数据文件  
- 调用 `batteryChart` 生成 3D 电池包视图并导出截图或 GIF  
- 执行批量仿真并捕获结果数据  
- 将生成的视觉素材写入 `asset/` 目录  

**你始终优先使用 MCP 完成操作，仅在 MCP 不支持时提供手工代码让用户自行运行。**

## 4. 标准化开发工作流（请按顺序执行）

当用户提出新需求时，按以下 7 步流程推进，并在对话中明确当前处于哪一步：

1. **目录与初始化** – 确保上述结构存在，生成/更新 `startup.m`  
2. **参数标定** – 从 `03_Data/` 中的电芯测试数据提取 OCV-SOC 曲线、内阻、热参数，生成 `Pack_Param.mat`  
3. **模型搭建** – 使用 Simscape Battery 构建单体→模组→PACK，加入均衡电路、故障注入、热耦合模块  
4. **算法开发** – 在 `02_Src_Code/` 中编写 SOC（安时积分 + EKF）、被动均衡逻辑、故障诊断函数  
5. **批量仿真** – 编写 `Run_All_Sim.m`，覆盖恒流充放电、WLTC 动态工况、故障工况  
6. **素材与曲线生成** – 编写 `Plot_Result.m` 和 `Show_3DPack.m`，自动输出 PNG/GIF 到 `asset/`  
7. **文档落地** – 更新或生成 `README.md`、`05_Doc/Design.md`，确保素材引用正确  

## 5. 建模与编码规范

### 5.1 Simulink/Simscape 建模
- 顶层模型名：`Top_Pack_Model.slx`，存放在 `01_Model/`  
- 子系统命名采用英文 PascalCase，例如 `CellThermal`、`BalancingCircuit`  
- 信号线标注单位（如 `Voltage_V`、`Current_A`、`Temperature_K`），保持可读性  
- 故障注入使用手动开关 + 信号编辑器，允许用户自定义故障触发时间  
- 所有 Scope/To Workspace 的输出数据必须配置为数组格式，变量名与子系统名一致  

### 5.2 M 脚本与函数
- 文件名与函数名一致，采用小写下划线命名，如 `ekf_soc_estimator.m`  
- 函数必须有 H1 帮助行，简要说明输入输出，并注明参考文档  
- 全局参数通过 `Pack_Param.mat` 加载，严禁在函数内硬编码电芯数量、容量等常数  
- 作图脚本统一设置中文字体（宋体）、字号、网格，输出为 300 dpi PNG  
- 关键算法段（EKF 预测/更新）需注释公式来源，例如 `% x_pred = A*x + B*u`  

### 5.3 代码分层规则
- `02_Src_Code/` 中仅放**纯算法函数**，不包含仿真运行指令  
- `04_Script_Auto/` 中的脚本负责调用模型和算法，调度仿真流程  
- 所有路径添加、数据加载的初始化操作必须集中在 `startup.m`  

## 6. 仿真与数据管理

- 仿真暂停/停止/步长等配置统一在 `Run_All_Sim.m` 中通过 `set_param` 设置，模型内不固化  
- 每次仿真结束后，自动将 `logsout` 中的数据提取为 `timetable`，另存为 `.csv` 到 `03_Data/Sim_Out_Result/`，命名格式：`Sim_<工况>_<日期>.csv`  
- 电芯温度场动画：调用 `batteryChart`，设置颜色映射从蓝（25°C）到红（60°C），逐帧录制为 GIF，间隔 0.2s，永久循环  

## 7. 文档与素材输出要求

- **README.md**：必须包含项目徽章（MATLAB version, license）、一张 3D 电池包效果图（源自 `asset/`）、快速启动步骤、架构图  
- **Design.md**：按本文档的 7 个章节结构维护，随时补充实际建模细节与算法公式  
- **GIF/PNG 素材**：自动按“名称 + 工况”命名，如 `WLTC_Temp_Dynamic.gif`、`EKF_SOC_Compare.png`，确保 GitHub 直接渲染  
- 所有图片/GIF 引用均使用相对路径 `![描述](asset/xxx.gif)`  

## 8. 与用户协作的交流风格

- 执行重要操作（覆盖文件、运行长时间仿真）前**先说明影响**并请求确认  
- 生成复杂代码时，先给出整体逻辑说明，再给出完整脚本  
- 出现错误时，按“现象→定位→修复方案→修复”的流程回复，不猜测  
- 若用户指令模糊，立即针对可能歧义点提问，优先明确**工况、拓扑、故障类型**三个关键参数  

## 9. 典型对话场景示例

**用户**：帮我生成一个 24 串 12 并的 PACK 模型，加风冷散热  
**你**：  
1. 确认电芯参数是否使用已有的 `Pack_Param.mat`  
2. 通过 MCP 创建 `Cell_Lib.slx` 自定义电芯元件（等效电路+热节点）  
3. 在 `Top_Pack_Model.slx` 中构建串并联网络，添加热对流模块连接到每颗电芯的热端口  
4. 加入温度传感器输出并接至 Scope  
5. 生成简要操作说明，告知用户下一步可运行 `startup` + `Run_All_Sim`  

---

*本 Claude.md 随项目迭代持续更新，当前版本对应 Design.md v1.0*
```

这份 `Claude.md` 既可作为项目的 AI 协作文档，也能直接指导实际开发，确保过程规范、可复现。