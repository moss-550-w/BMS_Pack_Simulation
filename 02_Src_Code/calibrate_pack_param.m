function PackParam = calibrate_pack_param()
%CALIBRATE_PACK_PARAM 从电芯测试数据标定参数并生成 Pack_Param.mat
%   流程：读取 03_Data/Cell_Test_Data/ 的 OCV-SOC 与 HPPC CSV →
%         拟合 OCV-SOC 查表、辨识 R0/R1/C1 → 组装电芯/PACK/热/几何/BMS
%         全局参数结构体 PackParam → 保存至 03_Data/Pack_Param.mat。
%   输出校验图 asset/OCV_SOC_Calibration.png。
%   辨识方法：
%     R0      = ΔV/ΔI（放电阶跃瞬时电压跳变）
%     R0+R1   = Vdrop_ss/I（放电末准稳态压降）
%     tau     = -1/slope（弛豫段 ln(Vinf-V) 线性拟合），C1 = tau/R1
%   参考：Plett, "Battery Management Systems, Vol.1", HPPC 辨识。
%
%   依赖：需先运行 startup 注册全局路径 BMS_PATHS。

global BMS_PATHS %#ok<GVMIS>
if isempty(BMS_PATHS)
    error('请先运行 startup 初始化工程路径。');
end

ocvFile  = fullfile(BMS_PATHS.CellTest, 'OCV_SOC_Test.csv');
hppcFile = fullfile(BMS_PATHS.CellTest, 'HPPC_Pulse_Test.csv');
if ~isfile(ocvFile) || ~isfile(hppcFile)
    error('缺少测试数据 CSV，请先运行 gen_synthetic_cell_data 或放入实测数据。');
end

%% 1) OCV-SOC 拟合：去噪 + 重采样到标准断点
ocvData = readtable(ocvFile);
soc_raw = ocvData.SOC;
ocv_raw = ocvData.OCV_V;
ocv_dn  = smoothdata(ocv_raw, 'movmean', 7);          % 滑动平均去噪
SOC_bp  = (0:0.05:1).';                               % 标准断点 21 点
OCV_bp  = interp1(soc_raw, ocv_dn, SOC_bp, 'pchip');

%% 2) HPPC 辨识 R0 / R1 / C1（拟合完整端电压，自动扣除 OCV 漂移）
%   放电脉冲内 SOC 下降会引起 OCV 漂移，若用固定基线会把漂移计入过电位而高估 R1。
%   故拟合完整模型 V(t)=OCV(SOC(t)) - I*R0 - Vrc，SOC 由安时积分、OCV 用上节查表。
Cap_cell = 3.0;                        % 电芯标称容量 Ah（与下节组装一致）
hppc = readtable(hppcFile);
t = hppc.Time_s;  I = hppc.Current_A;  V = hppc.Voltage_V;

on = find(diff(I > 0.1) == 1, 1);     % 放电阶跃上升沿（on+1 为首个放电点）
if isempty(on)
    error('HPPC 数据中未检测到放电脉冲。');
end
Ip   = I(on+1);
OCV0 = V(on);                          % 脉冲前静置开路电压
SOC0 = interp1(OCV_bp, SOC_bp, OCV0, 'linear', 'extrap');   % 反查初始 SOC

% 拟合区间：脉冲起始 → 数据末（含放电段 + 弛豫段）
idx = (on+1 : numel(t)).';
tf  = t(idx) - t(on);                  % 相对时间 s
If  = I(idx);                          % 对应电流序列
Vf  = V(idx);                          % 实测端电压

% R0 代数初值（阶跃瞬时电压跳变，作为优化初值）
R0_init = (V(on) - V(on+1)) / Ip;

% 完整端电压前向积分模型，对 [R0,R1,C1] 做最小二乘拟合
predict = @(p, tq) thevenin_voltage(p, tq, If, SOC0, Cap_cell, SOC_bp, OCV_bp);
p0  = [R0_init, 0.015, 2000];
lb  = [1e-4, 1e-4, 50];
ub  = [1, 1, 1e5];
opt = optimoptions('lsqcurvefit', 'Display', 'off');
pfit = lsqcurvefit(predict, p0, tf, Vf, lb, ub, opt);

R0_id  = pfit(1);
R1_id  = pfit(2);
C1_id  = pfit(3);
tau_id = R1_id * C1_id;
V_fit  = predict(pfit, tf);            % 拟合电压曲线，供校验图使用

%% 3) 组装全局参数结构体 PackParam
PackParam = struct();

% --- 电芯级 ---
PackParam.Cell.Capacity_Ah = 3.0;
PackParam.Cell.R0_Ohm      = R0_id;
PackParam.Cell.R1_Ohm      = R1_id;
PackParam.Cell.C1_F        = C1_id;
PackParam.Cell.Tau_s       = tau_id;
PackParam.Cell.Vnom_V      = 3.6;
PackParam.Cell.Vmax_V      = 4.2;
PackParam.Cell.Vmin_V      = 2.5;

% --- OCV-SOC 查表 ---
PackParam.OCV.SOC_bp = SOC_bp;
PackParam.OCV.OCV_bp = OCV_bp;

% --- PACK 拓扑（24 串 12 并）---
Ns = 24;  Np = 12;
PackParam.Pack.Ns          = Ns;
PackParam.Pack.Np          = Np;
PackParam.Pack.Capacity_Ah = PackParam.Cell.Capacity_Ah * Np;       % 36 Ah
PackParam.Pack.Vnom_V      = PackParam.Cell.Vnom_V * Ns;            % 86.4 V
PackParam.Pack.Vmax_V      = PackParam.Cell.Vmax_V * Ns;            % 100.8 V
PackParam.Pack.Vmin_V      = PackParam.Cell.Vmin_V * Ns;            % 60.0 V
PackParam.Pack.Energy_Wh   = PackParam.Pack.Vnom_V * PackParam.Pack.Capacity_Ah;

% --- 热参数（18650，工程经验值，待热测试数据替换）---
D = 0.018; H = 0.065;                                  % 直径/高 m
A_surf = pi*D*H + 2*pi*(D/2)^2;                        % 单体外表面积
PackParam.Thermal.mass_kg       = 0.045;              % 单体质量
PackParam.Thermal.Cp_JpkgK      = 900;               % 比热容
PackParam.Thermal.h_conv_Wpm2K  = 25;                % 风冷对流换热系数
PackParam.Thermal.A_surf_m2     = A_surf;
PackParam.Thermal.Rth_KpW       = 1/(25*A_surf);     % 单体-环境热阻
PackParam.Thermal.T_amb_C       = 25;
PackParam.Thermal.kR_perC       = -0.005;            % 内阻温度系数 1/°C
PackParam.Thermal.alpha_cap_perC= 0.001;             % 容量温度系数 1/°C

% --- 几何 ---
PackParam.Geometry.Diameter_m = D;
PackParam.Geometry.Height_m   = H;

% --- BMS 阈值 ---
PackParam.BMS.balance_threshold_V = 0.05;   % 单体高于均值 50mV 开启被动均衡
PackParam.BMS.OV_V = 4.25;                  % 过压保护
PackParam.BMS.UV_V = 2.50;                  % 欠压保护
PackParam.BMS.OT_C = 60;                    % 过温保护
PackParam.BMS.UT_C = -10;                   % 低温保护

%% 4) 保存 Pack_Param.mat
matFile = fullfile(BMS_PATHS.Data, 'Pack_Param.mat');
save(matFile, 'PackParam');

%% 5) 标定校验图（左：OCV-SOC 拟合；右：HPPC 过电位拟合）
fig = figure('Visible','off','Color','w','Position',[100 100 1100 460]);

subplot(1,2,1);
plot(soc_raw*100, ocv_raw, '.', 'Color',[.6 .6 .6], 'MarkerSize',6); hold on;
plot(SOC_bp*100, OCV_bp, '-o', 'Color',[0.85 0.1 0.1], 'LineWidth',1.6, ...
    'MarkerFaceColor',[0.85 0.1 0.1], 'MarkerSize',4);
grid on; box on;
set(gca, 'FontName','SimSun', 'FontSize',11);
xlabel('SOC (%)', 'FontName','SimSun');
ylabel('开路电压 OCV (V)', 'FontName','SimSun');
title('OCV-SOC 标定校验曲线', 'FontName','SimSun', 'FontSize',13);
legend({'测量数据','拟合查表'}, 'Location','southeast', 'FontName','SimSun');

subplot(1,2,2);
plot(tf, Vf, '.', 'Color',[.6 .6 .6], 'MarkerSize',6); hold on;
plot(tf, V_fit, '-', 'Color',[0.1 0.3 0.85], 'LineWidth',1.8);
grid on; box on;
set(gca, 'FontName','SimSun', 'FontSize',11);
xlabel('时间 t (s)', 'FontName','SimSun');
ylabel('端电压 V (V)', 'FontName','SimSun');
title('HPPC 1-RC 辨识拟合', 'FontName','SimSun', 'FontSize',13);
legend({'实测端电压','1-RC 拟合'}, 'Location','northeast', 'FontName','SimSun');

pngFile = fullfile(BMS_PATHS.Asset, 'OCV_SOC_Calibration.png');
exportgraphics(fig, pngFile, 'Resolution', 300);
close(fig);

%% 6) 控制台汇总
fprintf('[calibrate] 参数辨识结果：\n');
fprintf('[calibrate]   R0 = %.4f Ω | R1 = %.4f Ω | tau = %.1f s | C1 = %.0f F\n', ...
    R0_id, R1_id, tau_id, C1_id);
fprintf('[calibrate]   PACK：%d 串 %d 并 | 容量 %.0f Ah | 标称 %.1f V | 能量 %.0f Wh\n', ...
    Ns, Np, PackParam.Pack.Capacity_Ah, PackParam.Pack.Vnom_V, PackParam.Pack.Energy_Wh);
fprintf('[calibrate] 已保存：%s\n', matFile);
fprintf('[calibrate] 校验图：%s\n', pngFile);
end

%% ===== 局部函数 =====
function Vmodel = thevenin_voltage(p, tq, Iseq, SOC0, Cap_Ah, SOC_bp, OCV_bp)
%THEVENIN_VOLTAGE 一阶 Thevenin 完整端电压前向积分模型（含 SOC 引起的 OCV 漂移）
%   V(t) = OCV(SOC(t)) - I*R0 - Vrc
%   dVrc/dt = -Vrc/(R1*C1) + I/C1 ;  SOC(t) 由安时积分（放电 I>0，SOC 下降）
%   p = [R0, R1, C1]，tq 相对时间，Iseq 电流序列；OCV 用标定查表插值。
R0 = p(1);  R1 = p(2);  C1 = p(3);
N   = numel(tq);
Vrc = 0;
SOC = SOC0;
Vmodel = zeros(N,1);
for k = 1:N
    ocv_k = interp1(SOC_bp, OCV_bp, SOC, 'pchip');
    Vmodel(k) = ocv_k - Iseq(k)*R0 - Vrc;
    if k < N
        dt  = tq(k+1) - tq(k);
        a   = exp(-dt/(R1*C1));          % 零阶保持离散
        Vrc = a*Vrc + (1-a)*Iseq(k)*R1;
        SOC = SOC - Iseq(k)*dt/3600/Cap_Ah;
    end
end
end
