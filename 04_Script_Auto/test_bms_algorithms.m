function tests = test_bms_algorithms()
%TEST_BMS_ALGORITHMS BMS 核心算法单元测试（MATLAB Test 框架）
%   覆盖：安时积分、EKF-SOC 收敛、被动均衡、故障诊断。
%   运行：results = runtests('test_bms_algorithms')
%   依赖：需先运行 startup 并存在 Pack_Param.mat。
tests = functiontests(localfunctions);
end

function setupOnce(tc)
% 加载标定参数供各用例使用
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
run(fullfile(root, 'startup.m'));
S = load(fullfile(root, '03_Data', 'Pack_Param.mat'), 'PackParam');
tc.TestData.P = S.PackParam;
end

function test_coulomb_counting_monotonic(tc)
% 恒流放电下安时积分 SOC 应单调下降且守恒
P = tc.TestData.P;
dt = 1; N = 3600;                       % 1 小时
I  = 0.5*P.Cell.Capacity_Ah*ones(N,1);  % 0.5C
soc = coulomb_counting_soc(I, dt, 1.0, P.Cell.Capacity_Ah);
verifyTrue(tc, all(diff(soc) <= 0), '放电 SOC 应单调不增');
% 0.5C 放电 1h => ΔSOC = 0.5
verifyEqual(tc, soc(1)-soc(end), 0.5, 'AbsTol', 1e-3);
end

function test_coulomb_counting_clamp(tc)
% 过放应钳位到 0，不出现负 SOC
P = tc.TestData.P;
soc = coulomb_counting_soc(P.Cell.Capacity_Ah*ones(7200,1), 1, 0.5, P.Cell.Capacity_Ah);
verifyGreaterThanOrEqual(tc, min(soc), 0);
end

function test_ekf_converges_from_wrong_init(tc)
% EKF 在初值给错 10% 时应收敛到真值（核心能力）
P = tc.TestData.P;
[I, V, SOC_true, dt] = local_synth_discharge(P, 0.9);

prm = struct('R0_Ohm',P.Cell.R0_Ohm,'R1_Ohm',P.Cell.R1_Ohm,'C1_F',P.Cell.C1_F, ...
    'Cap_Ah',P.Cell.Capacity_Ah,'SOC_bp',P.OCV.SOC_bp,'OCV_bp',P.OCV.OCV_bp, ...
    'soc0',0.8,'Q',diag([1e-7 1e-6]),'R',4e-6,'P0',diag([1e-2 1e-2]));
soc_ekf = ekf_soc_estimator(I, V, dt, prm);

rmse = sqrt(mean((soc_ekf - SOC_true).^2));
verifyLessThan(tc, rmse, 0.02, 'EKF RMSE 应 < 2%');
verifyLessThan(tc, abs(soc_ekf(end)-SOC_true(end)), 0.01, 'EKF 末端误差应 < 1%');
end

function test_ekf_beats_coulomb_on_wrong_init(tc)
% 初值错误时，EKF 末端误差应远小于安时积分
P = tc.TestData.P;
[I, V, SOC_true, dt] = local_synth_discharge(P, 0.9);
soc_cc = coulomb_counting_soc(I, dt, 0.8, P.Cell.Capacity_Ah);
prm = struct('R0_Ohm',P.Cell.R0_Ohm,'R1_Ohm',P.Cell.R1_Ohm,'C1_F',P.Cell.C1_F, ...
    'Cap_Ah',P.Cell.Capacity_Ah,'SOC_bp',P.OCV.SOC_bp,'OCV_bp',P.OCV.OCV_bp, ...
    'soc0',0.8,'Q',diag([1e-7 1e-6]),'R',4e-6,'P0',diag([1e-2 1e-2]));
soc_ekf = ekf_soc_estimator(I, V, dt, prm);
verifyLessThan(tc, abs(soc_ekf(end)-SOC_true(end)), abs(soc_cc(end)-SOC_true(end)));
end

function test_passive_balancing_targets_highest(tc)
% 被动均衡应仅对高出均值+阈值的单体置位
P = tc.TestData.P;
Vc = [3.80 3.82 3.95 3.81 3.79 3.83]';
[cmd, info] = passive_balancing(Vc, P.BMS.balance_threshold_V);
verifyTrue(tc, cmd(3));
verifyEqual(tc, info.n_active, 1);
end

function test_passive_balancing_balanced_pack(tc)
% 整包已均衡（压差极小）时不应触发均衡
P = tc.TestData.P;
Vc = 3.80 + 0.001*(1:6)';
cmd = passive_balancing(Vc, P.BMS.balance_threshold_V);
verifyFalse(tc, any(cmd));
end

function test_fault_diagnosis_locates_faults(tc)
% 过压/过温/内短路应分别精确定位
P = tc.TestData.P;
Vc = [3.80 4.30 3.81 3.79 3.20 3.82]';   % 第2过压、第5内短路
Tc = [30   31   32   65   33   30  ]';   % 第4过温
f = fault_diagnosis(Vc, Tc, P.BMS);
verifyTrue(tc, f.OV(2));
verifyTrue(tc, f.OT(4));
verifyTrue(tc, f.ISC(5));
verifyEqual(tc, sum(f.any), 3);
end

function test_fault_diagnosis_healthy_pack(tc)
% 健康整包不应误报
P = tc.TestData.P;
Vc = 3.80 + 0.005*randn(6,1);
Tc = 30*ones(6,1);
f = fault_diagnosis(Vc, Tc, P.BMS);
verifyFalse(tc, any(f.any));
end

function test_active_balancing_charge_transfer(tc)
% 主动均衡：高 SOC 串放电(+)、低 SOC 串充电(-)，且充入≈eff*放出（电荷守恒）
SOC = [0.9 0.5 0.5 0.5 0.5 0.1]';        % 均值 0.5，串1高、串6低
[I, info] = active_balancing(SOC, 2, 0.9, 0.005);
verifyGreaterThan(tc, I(1), 0);          % 高 SOC 放电
verifyLessThan(tc, I(6), 0);             % 低 SOC 充电
Qout = sum(I(I>0));  Qin = -sum(I(I<0));
verifyEqual(tc, Qin, 0.9*Qout, 'RelTol', 1e-9, '充入应为 eff*放出');
verifyEqual(tc, info.n_dis, 1);
end

function test_active_balancing_deadband(tc)
% 已均衡（SOC 离散在死区内）时主动均衡不动作
SOC = 0.5 + 0.001*(1:6)';
I = active_balancing(SOC, 2, 0.9, 0.005);
verifyTrue(tc, all(I == 0));
end

function test_arrhenius_temperature_sensitivity(tc)
% Arrhenius 产热强温度敏感：高温产热应远大于低温，且非负
prm = struct('A',2e10, 'Ea',1.0e5, 'H_total',1.5e5*12);
q_lo = arrhenius_heat(25,  1, prm);
q_hi = arrhenius_heat(200, 1, prm);
verifyGreaterThanOrEqual(tc, q_lo, 0);
verifyGreaterThan(tc, q_hi, q_lo*1e3, '高温产热应远大于低温');
end

function test_arrhenius_depleted_no_heat(tc)
% 反应物耗尽（c=0）时产热与消耗速率均为零（自限）
prm = struct('A',2e10, 'Ea',1.0e5, 'H_total',1.8e6);
[q, dcdt] = arrhenius_heat(300, 0, prm);
verifyEqual(tc, q, 0);
verifyEqual(tc, dcdt, 0);
end

function test_active_beats_passive_convergence(tc)
% 仿真器层：静置下主动均衡末态压差应优于被动
P = tc.TestData.P;
N=2000; dt=10; I=zeros(N,1);
base = struct('soc0',0.85,'soc_spread',0.08);
oP = pack_simulator(I,dt,P, setf(base,'balance_mode','passive','R_bal',10));
oA = pack_simulator(I,dt,P, setf(base,'balance_mode','active','act_Imax',1.5));
verifyLessThan(tc, oA.dV_max(end), oP.dV_max(end));
end

function test_liquid_cooling_lower_peak_and_gradient(tc)
% 仿真器层：液冷峰温应低于风冷，且沿流向呈梯度（末串>首串）
P = tc.TestData.P;
N=1800; dt=1; I=0.5*P.Pack.Capacity_Ah*ones(N,1);
oair = pack_simulator(I,dt,P, struct('soc0',0.95,'cooling','air'));
olq  = pack_simulator(I,dt,P, struct('soc0',0.95,'cooling','liquid','cool_mdot',0.05));
verifyLessThan(tc, max(olq.T_cells(end,:)), max(oair.T_cells(end,:)));
verifyGreaterThan(tc, olq.T_cells(end,end), olq.T_cells(end,1));
end

function test_thermal_runaway_triggers_and_stable(tc)
% 热失控：应触发(>300°C)、数值稳定(无NaN、不爆炸)、反应物耗尽自限
P = tc.TestData.P;
N=1200; dt=1; I=0.5*P.Pack.Capacity_Ah*ones(N,1);
opt = struct('soc0',0.9,'isc_cell',12,'isc_start_s',60,'isc_R',0.05,'k_cond',2.0, ...
    'enable_balance',false,'enable_tr',true,'tr_H',25000,'tr_A',2e10,'tr_Ea',1.0e5,'tr_substep',50);
o = pack_simulator(I,dt,P,opt);
verifyFalse(tc, any(isnan(o.T_cells(:))), '不应出现 NaN');
verifyGreaterThan(tc, max(o.T_cells(:)), 300, '应触发热失控');
verifyLessThan(tc, max(o.T_cells(:)), 2000, '峰温应物理有界（数值稳定）');
verifyLessThan(tc, o.c_react(end,12), 0.01, '触发串反应物应耗尽');
end

%% ===== 局部辅助函数 =====
function s = setf(s, varargin)
% 在结构体上批量设置 name-value 字段，返回副本
for i = 1:2:numel(varargin), s.(varargin{i}) = varargin{i+1}; end
end

function [I, V, SOC_true, dt] = local_synth_discharge(P, soc_start)
% 生成 0.5C 放电（含中段静置）的合成真值场景，叠加 2mV 测量噪声
dt = 1; tEnd = 3000; t = (0:dt:tEnd)'; N = numel(t);
Cap = P.Cell.Capacity_Ah; R0 = P.Cell.R0_Ohm; R1 = P.Cell.R1_Ohm; C1 = P.Cell.C1_F;
I = 0.5*Cap*ones(N,1); I(t>=1500 & t<2000) = 0;
SOC_true = zeros(N,1); SOC_true(1) = soc_start; Vrc = 0; V = zeros(N,1);
a = exp(-dt/(R1*C1));
for k = 1:N
    ocv = interp1(P.OCV.SOC_bp, P.OCV.OCV_bp, SOC_true(k), 'pchip');
    V(k) = ocv - R0*I(k) - Vrc;
    if k < N
        Vrc = a*Vrc + R1*(1-a)*I(k);
        SOC_true(k+1) = SOC_true(k) - I(k)*dt/3600/Cap;
    end
end
V = V + 0.002*randn(N,1);
end
