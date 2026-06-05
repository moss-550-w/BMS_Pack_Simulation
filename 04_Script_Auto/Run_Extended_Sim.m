function ext = Run_Extended_Sim()
%RUN_EXTENDED_SIM 拓展工况批量仿真（流程 7.2 拓展方向）
%   覆盖三类拓展能力，逐个调用增强版 pack_simulator，结果存为 timetable 并写
%   CSV 到 03_Data/Sim_Out_Result/，供 Plot_Extended / Show_Runaway 出图复用。
%   拓展工况：
%     1) Balance  主/被动均衡对比（静置 10h，passive vs active DC-DC）
%     2) Cooling  风冷/液冷散热对比（0.5C 放电 1h，air vs liquid 高/低流量）
%     3) Runaway  热失控蔓延对比（第 12 串内短路，线性 vs Arrhenius 自产热）
%   CSV 命名：SimExt_<工况>_<日期>.csv
%
%   依赖：需先运行 startup 并存在 Pack_Param.mat。
%   与 Run_All_Sim 互不影响（原 4 基础工况仍由 Run_All_Sim 维护）。

global BMS_PATHS %#ok<GVMIS>
if isempty(BMS_PATHS); error('请先运行 startup 初始化工程路径。'); end
P = load(fullfile(BMS_PATHS.Data,'Pack_Param.mat')).PackParam;
outDir = BMS_PATHS.SimOut;
dateStr = char(datetime('now','Format','yyyyMMdd'));
Cap = P.Pack.Capacity_Ah;
ext = struct();

%% 1) 主动 vs 被动均衡（静置 10h，初始 SOC 离散 0.08）
fprintf('\n=== 拓展工况 1/3: 主动 vs 被动均衡（静置 10h）===\n');
dtb=10; Nb=3600; Ib=zeros(Nb,1);
base=struct('soc0',0.85,'soc_spread',0.08);
oPas = pack_simulator(Ib,dtb,P, setfields(base,'balance_mode','passive','R_bal',10));
oAct = pack_simulator(Ib,dtb,P, setfields(base,'balance_mode','active','act_Imax',1.5,'act_eff',0.9));
dSOC = @(o) max(o.SOC_cells,[],2)-min(o.SOC_cells,[],2);
dP = dSOC(oPas);  dA = dSOC(oAct);
fprintf('  被动: 压差 %.0f→%.0f mV | SOC离散 %.4f→%.4f | 峰温 %.2f°C\n', ...
    oPas.dV_max(1)*1000, oPas.dV_max(end)*1000, dP(1), dP(end), max(oPas.T_cells(:)));
fprintf('  主动: 压差 %.0f→%.0f mV | SOC离散 %.4f→%.4f | 峰温 %.2f°C | 损耗致SOC降 %.3f%%\n', ...
    oAct.dV_max(1)*1000, oAct.dV_max(end)*1000, dA(1), dA(end), max(oAct.T_cells(:)), ...
    (mean(oAct.SOC_cells(1,:))-mean(oAct.SOC_cells(end,:)))*100);
ext.bal = struct('passive',oPas,'active',oAct,'dt',dtb);
TTb = timetable(seconds(oPas.t), oPas.dV_max*1000, oAct.dV_max*1000, ...
    mean(oPas.T_cells,2), mean(oAct.T_cells,2), ...
    'VariableNames',{'dV_passive_mV','dV_active_mV','T_passive_C','T_active_C'});
writetimetable(TTb, fullfile(outDir, sprintf('SimExt_Balance_%s.csv',dateStr)));

%% 2) 风冷 vs 液冷（0.5C 放电 1h）
fprintf('\n=== 拓展工况 2/3: 风冷 vs 液冷散热（0.5C 放电 1h）===\n');
dtc=1; Nc=3600; Ic=0.5*Cap*ones(Nc,1);
bc=struct('soc0',0.95);
oAir = pack_simulator(Ic,dtc,P, setfields(bc,'cooling','air'));
oLqH = pack_simulator(Ic,dtc,P, setfields(bc,'cooling','liquid','cool_mdot',0.05,'Rth_cool',0.3));
oLqL = pack_simulator(Ic,dtc,P, setfields(bc,'cooling','liquid','cool_mdot',0.02,'Rth_cool',0.3));
grad=@(o) o.T_cells(end,end)-o.T_cells(end,1);
fprintf('  风冷:     峰温 %.1f°C | 沿串梯度 %.1f°C\n', max(oAir.T_cells(end,:)), grad(oAir));
fprintf('  液冷(0.05): 峰温 %.1f°C | 梯度 %.1f°C | 冷却液出口 %.1f°C\n', max(oLqH.T_cells(end,:)), grad(oLqH), oLqH.T_coolant(end,end));
fprintf('  液冷(0.02): 峰温 %.1f°C | 梯度 %.1f°C | 冷却液出口 %.1f°C\n', max(oLqL.T_cells(end,:)), grad(oLqL), oLqL.T_coolant(end,end));
ext.cool = struct('air',oAir,'liquid_hi',oLqH,'liquid_lo',oLqL,'dt',dtc);
TTc = timetable(seconds(oAir.t), mean(oAir.T_cells,2), mean(oLqH.T_cells,2), mean(oLqL.T_cells,2), ...
    oLqH.T_coolant(:,end), oLqL.T_coolant(:,end), ...
    'VariableNames',{'T_air_C','T_liqHi_C','T_liqLo_C','Tout_liqHi_C','Tout_liqLo_C'});
writetimetable(TTc, fullfile(outDir, sprintf('SimExt_Cooling_%s.csv',dateStr)));

%% 3) 热失控蔓延：线性内短路 vs Arrhenius 自产热
fprintf('\n=== 拓展工况 3/3: 热失控蔓延（第 12 串内短路）===\n');
dtr=1; Nr=1500; Ir=0.5*Cap*ones(Nr,1);
br=struct('soc0',0.9,'isc_cell',12,'isc_start_s',60,'isc_R',0.05,'k_cond',2.0,'enable_balance',false);
oLin = pack_simulator(Ir,dtr,P, br);                                   % 线性内短路（无热失控）
oRun = pack_simulator(Ir,dtr,P, setfields(br,'enable_tr',true, ...
    'tr_H',25000,'tr_A',2e10,'tr_Ea',1.0e5,'tr_substep',50));          % Arrhenius 热失控
nRunaway = sum(max(oRun.T_cells,[],1) > 200);
fprintf('  线性内短路:   峰温 %.1f°C（未触发热失控）\n', max(oLin.T_cells(:)));
fprintf('  Arrhenius失控: 峰温 %.0f°C | 失控串 %d/24 | 触发串12反应物耗尽 c=%.3f\n', ...
    max(oRun.T_cells(:)), nRunaway, oRun.c_react(end,12));
ext.tr = struct('linear',oLin,'runaway',oRun,'dt',dtr,'n_runaway',nRunaway);
TTr = timetable(seconds(oRun.t), max(oLin.T_cells,[],2), max(oRun.T_cells,[],2), ...
    mean(oRun.T_cells,2), oRun.c_react(:,12), ...
    'VariableNames',{'Tmax_linear_C','Tmax_runaway_C','Tmean_runaway_C','c_react_cell12'});
writetimetable(TTr, fullfile(outDir, sprintf('SimExt_Runaway_%s.csv',dateStr)));

fprintf('\n[Run_Extended_Sim] 3 类拓展工况完成，CSV 存于 %s\n', outDir);
end

%% ===== 局部函数 =====
function s = setfields(s, varargin)
%SETFIELDS 在结构体 s 上批量设置 name-value 字段，返回副本（不改入参）
for i = 1:2:numel(varargin)
    s.(varargin{i}) = varargin{i+1};
end
end
