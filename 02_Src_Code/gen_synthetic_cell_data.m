function gen_synthetic_cell_data()
%GEN_SYNTHETIC_CELL_DATA 生成 18650 电芯合成标定数据（OCV-SOC + HPPC 脉冲）
%   在无实测数据时打通全链路。输出 CSV 至 03_Data/Cell_Test_Data/：
%     - OCV_SOC_Test.csv ：准静态 OCV-SOC 曲线（含测量噪声）
%     - HPPC_Pulse_Test.csv：1C 放电脉冲响应（用于辨识 R0/R1/C1）
%   电芯模型：一阶 Thevenin 等效电路  V = OCV(SOC) - I*R0 - Vrc
%             dVrc/dt = -Vrc/(R1*C1) + I/C1   （I 放电为正）
%   参考：Plett, "Battery Management Systems, Vol.1", Ch.2-3。
%
%   依赖：需先运行 startup 注册全局路径 BMS_PATHS。

global BMS_PATHS %#ok<GVMIS>
if isempty(BMS_PATHS)
    error('请先运行 startup 初始化工程路径。');
end
outDir = BMS_PATHS.CellTest;
rng(42);   % 固定随机种子，保证可复现

%% 电芯真值参数（18650 NMC 典型，作为合成数据的"真相"）
Cap_Ah = 3.0;      % 标称容量 Ah
R0     = 0.025;    % 欧姆内阻 Ohm
R1     = 0.015;    % 极化电阻 Ohm
C1     = 2000;     % 极化电容 F  => tau = R1*C1 = 30 s
T_amb  = 25;       % 环境温度 degC

% OCV-SOC 真值表（典型 NMC 圆柱电芯）
soc_pts = [0 .05 .1 .2 .3 .4 .5 .6 .7 .8 .9 .95 1].';
ocv_pts = [3.00 3.30 3.45 3.55 3.62 3.67 3.73 3.80 3.87 3.95 4.07 4.13 4.18].';

%% 1) 准静态 OCV-SOC 测试数据（低倍率，叠加 3 mV 测量噪声）
soc_fine = (0:0.01:1).';
ocv_true = interp1(soc_pts, ocv_pts, soc_fine, 'pchip');
ocv_meas = ocv_true + 0.003*randn(size(ocv_true));
T_ocv = table(soc_fine, ocv_meas, 'VariableNames', {'SOC','OCV_V'});
writetable(T_ocv, fullfile(outDir, 'OCV_SOC_Test.csv'));

%% 2) HPPC 脉冲数据：1C 放电脉冲 90s + 长静置（脉冲时长 ≥3×tau 保证可辨识）
dt   = 0.1;                 % 采样步长 s
tEnd = 230;                 % 总时长 s（脉冲 90s + 弛豫 ≥4×tau）
t    = (0:dt:tEnd).';
N    = numel(t);

Ipulse = 1.0 * Cap_Ah;      % 1C = 3.0 A
I = zeros(N,1);
I(t>=10 & t<100) = Ipulse;  % 10~100s 放电脉冲（90s，覆盖 3×tau）

SOC0 = 0.6;                 % 起始 SOC（OCV≈3.80V，曲线中段灵敏）
SOC  = zeros(N,1); SOC(1) = SOC0;
Vrc  = zeros(N,1);          % 极化电压
V    = zeros(N,1);

a = exp(-dt/(R1*C1));       % 一阶离散零阶保持系数
for k = 1:N
    ocv_k = interp1(soc_pts, ocv_pts, SOC(k), 'pchip');
    V(k)  = ocv_k - I(k)*R0 - Vrc(k);
    if k < N
        Vrc(k+1) = a*Vrc(k) + (1-a)*I(k)*R1;
        SOC(k+1) = SOC(k) - I(k)*dt/3600/Cap_Ah;
    end
end
V = V + 0.001*randn(N,1);   % 1 mV 电压测量噪声
Temp = T_amb + zeros(N,1);  % 等温工况（热标定用经验值，见 calibrate 脚本）

T_hppc = table(t, I, V, Temp, ...
    'VariableNames', {'Time_s','Current_A','Voltage_V','Temp_C'});
writetable(T_hppc, fullfile(outDir, 'HPPC_Pulse_Test.csv'));

fprintf('[gen_data] 合成数据已生成至 %s\n', outDir);
fprintf('[gen_data]   OCV_SOC_Test.csv  (%d 点)\n', numel(soc_fine));
fprintf('[gen_data]   HPPC_Pulse_Test.csv (%d 点)\n', N);
fprintf('[gen_data]   真值：R0=%.4f Ω, R1=%.4f Ω, C1=%.0f F, tau=%.1f s\n', ...
    R0, R1, C1, R1*C1);
end
