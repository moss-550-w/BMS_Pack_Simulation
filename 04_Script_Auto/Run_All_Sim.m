function results = Run_All_Sim()
%RUN_ALL_SIM 批量多工况 PACK 仿真调度（流程第 5 步）
%   覆盖四类工况，逐个调用 pack_simulator，叠加 EKF / 安时积分 SOC 估算
%   与故障诊断，结果存为 timetable 并写 CSV 到 03_Data/Sim_Out_Result/。
%   工况：
%     1) CC      标准恒流充放电（0.5C 放电）
%     2) WLTC    车载动态工况（变功率充放电剖面）
%     3) ISC     单体内短路热蔓延（第 12 串注入内短路）
%     4) Balance 静置被动均衡（长时间均衡收敛）
%   CSV 命名：Sim_<工况>_<日期>.csv
%
%   依赖：需先运行 startup 并存在 Pack_Param.mat。

global BMS_PATHS %#ok<GVMIS>
if isempty(BMS_PATHS); error('请先运行 startup 初始化工程路径。'); end
P = load(fullfile(BMS_PATHS.Data,'Pack_Param.mat')).PackParam;
outDir = BMS_PATHS.SimOut;
dateStr = char(datetime('now','Format','yyyyMMdd'));

% EKF 估算参数（串组级，与 pack_simulator 自洽：每串端电压用 I_load 配电芯级
% R0/R1/C1，容量为并联组容量 Np*Cap_cell；观测取 V_pack/Ns 的单串端电压）
Cap_str = P.Pack.Np * P.Cell.Capacity_Ah;
ekf_prm = struct('R0_Ohm',P.Cell.R0_Ohm,'R1_Ohm',P.Cell.R1_Ohm,'C1_F',P.Cell.C1_F, ...
    'Cap_Ah',Cap_str,'SOC_bp',P.OCV.SOC_bp,'OCV_bp',P.OCV.OCV_bp, ...
    'Q',diag([1e-7 1e-6]),'R',4e-6,'P0',diag([1e-2 1e-2]));

cases = define_cases(P);
results = struct();

for i = 1:numel(cases)
    c = cases(i);
    fprintf('\n=== 工况 %d/%d: %s ===\n', i, numel(cases), c.name);

    % 运行 PACK 物理仿真
    out = pack_simulator(c.I, c.dt, P, c.opt);

    % SOC 估算：观测=单串端电压 V_pack/Ns，电流=I_load（串联同流），
    % 容量=并联组容量，初值故意偏置 -0.1 看 EKF 修正能力
    Ns = P.Pack.Ns;
    Vstr_obs = out.V_pack / Ns;                      % 单串端电压观测
    Istr = out.I_load;                               % 串组电流 = 负载电流
    soc0_est = out.SOC_pack(1) - 0.1;                % 故意给错初值
    ekf_prm.soc0 = soc0_est;
    soc_ekf = ekf_soc_estimator(Istr, Vstr_obs, c.dt, ekf_prm);
    soc_cc  = coulomb_counting_soc(Istr, c.dt, soc0_est, Cap_str);

    % 故障诊断（逐时刻对 24 串）——统计首次故障时刻
    [fault_flag, first_fault_t] = scan_faults(out, P, c.dt);

    % 汇总指标
    soc_true_end = out.SOC_pack(end);
    rmse_ekf = sqrt(mean((soc_ekf - out.SOC_pack).^2))*100;
    rmse_cc  = sqrt(mean((soc_cc  - out.SOC_pack).^2))*100;
    fprintf('  时长=%.0fs 步长=%.1fs | PACK %.1f→%.1fV | SOC %.2f→%.2f\n', ...
        out.t(end), c.dt, out.V_pack(1), out.V_pack(end), out.SOC_pack(1), soc_true_end);
    fprintf('  温升: %.1f→%.1f°C (峰值%.1f°C) | 最大压差 %.0f→%.0fmV\n', ...
        mean(out.T_cells(1,:)), mean(out.T_cells(end,:)), max(out.T_cells(:)), ...
        out.dV_max(1)*1000, out.dV_max(end)*1000);
    fprintf('  SOC估算RMSE: EKF=%.2f%% 安时积分=%.2f%% (初值偏置-10%%)\n', rmse_ekf, rmse_cc);
    if first_fault_t >= 0
        fprintf('  [故障] 首次触发 @ %.0fs，类型=%s\n', first_fault_t, fault_flag);
    else
        fprintf('  [故障] 无\n');
    end

    % 导出 timetable -> CSV
    TT = timetable(seconds(out.t), out.I_load, out.V_pack, out.SOC_pack, ...
        soc_ekf, soc_cc, mean(out.T_cells,2), max(out.T_cells,[],2), out.dV_max, ...
        'VariableNames', {'I_load_A','V_pack_V','SOC_true','SOC_EKF','SOC_CC', ...
                          'T_mean_C','T_max_C','dV_max_V'});
    csvFile = fullfile(outDir, sprintf('Sim_%s_%s.csv', c.tag, dateStr));
    writetimetable(TT, csvFile);
    fprintf('  已保存: %s\n', csvFile);

    % 保存到返回结构（供绘图脚本复用）
    results.(c.tag) = struct('out',out,'soc_ekf',soc_ekf,'soc_cc',soc_cc, ...
        'rmse_ekf',rmse_ekf,'rmse_cc',rmse_cc,'csv',csvFile);
end

fprintf('\n[Run_All_Sim] 全部 %d 工况完成，数据存于 %s\n', numel(cases), outDir);
end

%% ===== 局部函数 =====
function cases = define_cases(P)
%DEFINE_CASES 定义四类工况的电流剖面与选项
Cap = P.Pack.Capacity_Ah;

% 1) 恒流放电 0.5C，1h
dt1=1; N1=3600; I1=0.5*Cap*ones(N1,1);
c1=struct('name','标准恒流放电(0.5C,1h)','tag','CC','dt',dt1,'I',I1, ...
    'opt',struct('soc0',0.95,'soc_spread',0.02,'enable_balance',true));

% 2) WLTC 动态工况，30min
dt2=1; I2=wltc_current_profile(Cap, dt2);
c2=struct('name','WLTC动态工况(30min)','tag','WLTC','dt',dt2,'I',I2, ...
    'opt',struct('soc0',0.80,'soc_spread',0.02,'enable_balance',true));

% 3) 内短路热蔓延：0.5C 放电中，第12串 600s 注入内短路
dt3=1; N3=1800; I3=0.5*Cap*ones(N3,1);
c3=struct('name','单体内短路热蔓延(第12串@600s)','tag','ISC','dt',dt3,'I',I3, ...
    'opt',struct('soc0',0.90,'isc_cell',12,'isc_start_s',600,'isc_R',0.3, ...
                 'enable_balance',true,'k_cond',1.0));

% 4) 静置被动均衡，10h
dt4=10; N4=3600; I4=zeros(N4,1);
c4=struct('name','静置被动均衡(10h)','tag','Balance','dt',dt4,'I',I4, ...
    'opt',struct('soc0',0.85,'soc_spread',0.08,'enable_balance',true,'R_bal',10));

cases=[c1 c2 c3 c4];
end

function I = wltc_current_profile(Cap, dt)
%WLTC_CURRENT_PROFILE 简化 WLTC 变功率电流剖面（4 段速度 → 充放电）
%   低/中/高/超高速段，正=放电(驱动)，负=回馈充电(制动)。
seg_dur = [589 433 455 323];               % WLTC 四段典型时长 s
seg_amp = [0.3 0.6 0.9 1.2]*Cap;           % 各段放电幅值（倍率×容量）
I = [];
for s = 1:4
    n = round(seg_dur(s)/dt);
    t = (0:n-1)'/n;
    % 段内叠加加减速波动 + 间歇制动回馈（负电流）
    base = seg_amp(s)*(0.5 + 0.5*sin(2*pi*3*t));
    brake = -0.4*seg_amp(s)*(sin(2*pi*7*t)>0.7);   % 偶发制动回馈
    I = [I; base + brake]; %#ok<AGROW>
end
end

function [flag, first_t] = scan_faults(out, P, dt)
%SCAN_FAULTS 逐时刻故障诊断，返回首次故障时刻与类型字符串
N = size(out.V_cells,1);
first_t = -1; flag = 'none';
for k = 1:N
    f = fault_diagnosis(out.V_cells(k,:)', out.T_cells(k,:)', P.BMS);
    if any(f.any)
        first_t = (k-1)*dt;
        types = {};
        if any(f.OV), types{end+1}='过压'; end %#ok<AGROW>
        if any(f.UV), types{end+1}='欠压'; end %#ok<AGROW>
        if any(f.OT), types{end+1}='过温'; end %#ok<AGROW>
        if any(f.UT), types{end+1}='低温'; end %#ok<AGROW>
        if any(f.ISC),types{end+1}='内短路'; end %#ok<AGROW>
        flag = strjoin(types,'+');
        return;
    end
end
end
