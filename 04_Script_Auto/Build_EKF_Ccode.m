function Build_EKF_Ccode()
%BUILD_EKF_CCODE 将单步 EKF 生成可移植嵌入式 C 源码（流程 7.2-④）
%   面向 STM32 等 ARM Cortex-M：用 Embedded Coder 的 lib 配置 + GenCodeOnly，
%   仅生成 C 源码（不依赖主机编译器），输出至 02_Src_Code/codegen_ekf/。
%   目标函数 ekf_soc_step_cg：单周期调用、persistent 状态保持、定长内存
%   （SOC_bp/OCV_bp 固定 21 点，标量 I/O，无 emxArray/malloc），契合 MCU 实时循环。
%   生成的 ekf_soc_step_cg.c / .h 可直接集成进 STM32 工程（Keil/STM32CubeIDE）。
%
%   定点/优化说明：当前为 double 浮点版（Cortex-M4F/M7 带 FPU 可直接用）；
%   纯整数 MCU 可后续用 Fixed-Point Designer 转定点。
%
%   依赖：需先运行 startup；需 MATLAB Coder + Embedded Coder 许可。
%   PIL 说明：真 PIL 需目标硬件 + 硬件支持包；本脚本只做硬件无关的 C 源生成，
%            数值等价性由 Verify_EKF_Ccode（算法层）佐证。

global BMS_PATHS %#ok<GVMIS>
if isempty(BMS_PATHS); error('请先运行 startup 初始化工程路径。'); end

% 代表性输入类型：标量 I/V/dt/reset + 定长参数结构体（OCV 查表 21 点）
P = load(fullfile(BMS_PATHS.Data,'Pack_Param.mat')).PackParam;
nbp = numel(P.OCV.SOC_bp);
prm = struct('R0_Ohm',P.Cell.R0_Ohm,'R1_Ohm',P.Cell.R1_Ohm,'C1_F',P.Cell.C1_F, ...
    'Cap_Ah',P.Pack.Np*P.Cell.Capacity_Ah,'SOC_bp',P.OCV.SOC_bp(:),'OCV_bp',P.OCV.OCV_bp(:), ...
    'soc0',0.8,'Q',diag([1e-7 1e-6]),'R',4e-6,'P0',diag([1e-2 1e-2]));

% 定长类型定义：查表向量固定 nbp×1（嵌入式静态内存）
prm_t = coder.typeof(prm);
prm_t.Fields.SOC_bp = coder.typeof(0,[nbp 1]);
prm_t.Fields.OCV_bp = coder.typeof(0,[nbp 1]);
args = {0, 0, 0, prm_t, false};             % I_k, V_k, dt, prm, reset

% Embedded Coder lib 配置：仅生成代码，目标 ARM Cortex-M
cfg = coder.config('lib','ecoder',true);
cfg.GenCodeOnly            = true;          % 不调用主机编译器，仅产 C 源
cfg.TargetLang             = 'C';
cfg.GenerateReport         = true;
cfg.SupportNonFinite       = false;         % 嵌入式不支持 Inf/NaN，精简代码
cfg.HardwareImplementation.ProdHWDeviceType = 'ARM Compatible->ARM Cortex-M';

outDir = fullfile(BMS_PATHS.SrcCode,'codegen_ekf');

codegen('ekf_soc_step_cg','-config',cfg, '-args',args, '-d',outDir, '-report');

fprintf('[Build_EKF_Ccode] 嵌入式 C 源码已生成：%s\n', outDir);
fprintf('  主文件：ekf_soc_step_cg.c / .h（单步调用，可集成进 STM32 工程）\n');
fprintf('  特性：persistent 状态保持 | 定长内存(无 malloc) | 标量 I/O\n');
fprintf('  目标：ARM Cortex-M | 浮点 double（M4F/M7 FPU 直接可用）\n');
fprintf('  报告：codegen_ekf/html/report.mldatx\n');
end
