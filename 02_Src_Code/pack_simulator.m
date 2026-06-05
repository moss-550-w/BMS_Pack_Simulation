function out = pack_simulator(I_load, dt, P, opt)
%PACK_SIMULATOR 24 串模组级电-热-故障耦合 PACK 数值仿真器（纯函数）
%   out = PACK_SIMULATOR(I_load, dt, P, opt)
%   每串等效一个单体（12 并集总），串联组成 24S 模组。电气用一阶 Thevenin，
%   热用集总热容 + 相邻串一维热传导 + 散热（风冷/液冷）到环境/冷却液，支持
%   被动/主动均衡、内短路注入与 Arrhenius 热失控。
%
%   电气（每串 j，放电电流 I>0）：
%     V_j = OCV(SOC_j) - I_str*R0_j(T) - Vrc_j
%     Vrc_j(k+1) = a*Vrc_j + R1*(1-a)*I_str,   a = exp(-dt/(R1*C1))
%     SOC_j(k+1) = SOC_j - I_str*dt/(3600*Cap_str)
%   其中 I_str = I_load + I_bal + I_isc；并联组容量 Cap_str = Np*Cap_cell。
%   热（每串 j）：
%     Cth*dT_j/dt = Q_ohm + Q_bal + Q_isc + Q_cond + Q_tr - Q_cool
%   均衡：
%     被动(passive) 高于(均值+阈值)的串投耗散电阻，均衡放电+发热 I_bal^2*R_bal；
%     主动(active)  集中式 DC-DC 电荷转移（见 active_balancing），仅 (1-eff) 损耗发热。
%   散热：
%     风冷(air)   Q_cool = (T-T_amb)/Rth；
%     液冷(liquid) 冷却液沿串号 1->Ns 流动，逐节点吸热升温，下游散热变差呈梯度。
%   内短路：指定串并入短路电阻 R_isc，产生自放电电流与局部发热。
%   热失控：enable_tr 时叠加 Arrhenius 自产热 Q_tr（温度正反馈 + 反应物耗尽自限），
%           热推进用子步保数值稳定。
%
%   输入：
%     I_load - PACK 负载电流序列 (A)，放电为正，长度 N
%     dt     - 步长 (s)，标量
%     P      - PackParam 结构体（含 Cell/OCV/Pack/Thermal/BMS）
%     opt    - 选项结构体，字段（均可缺省，默认保持原行为）：
%                soc0(0.9) 初始SOC标量；T0_C(环境) 初温；
%                enable_balance(true)；soc_spread(0) 初始SOC离散度；
%                k_cond(0.5) 串间热传导W/K；
%                内短路：isc_cell(0=不注入) 串号；isc_start_s(0)；isc_R(0.5)Ohm；
%                均衡：balance_mode('') 'passive'|'active'|'none'（空则由 enable_balance 推断）；
%                      R_bal(33) 被动均衡电阻Ohm；
%                      act_eff(0.9) DC-DC效率；act_Imax(2) 最大均衡电流A；act_deadband(0.005)；
%                散热：cooling('air') 'air'|'liquid'；
%                      cool_Cp(3300) 冷却液比热J/kgK；cool_mdot(0.05) 流量kg/s；
%                      cool_Tin_C(T_amb) 入口温度；Rth_cool(0.3) 串-冷却液热阻K/W；
%                热失控：enable_tr(false)；tr_A(2e10) 频率因子1/s；tr_Ea(1.0e5) 活化能J/mol；
%                      tr_H(1.5e5) 单体总反应热J；tr_m(1) 反应级数；tr_substep(20) 热子步数
%   输出 out（结构体）：
%     t, I_load, V_pack, V_cells(N×Ns), SOC_cells, T_cells,
%     SOC_pack(均值), dV_max(最大压差), bal_active(N×Ns logical),
%     T_coolant(N×Ns 冷却液节点温度,液冷), c_react(N×Ns 反应物浓度,热失控),
%     meta(回显 balance_mode/cooling/enable_tr)
%
%   参考：Plett BMS Vol.1 电-热耦合；一阶 Thevenin；Hatchard/NREL Arrhenius 热失控。

import_check(P);
Ns = P.Pack.Ns;                 % 串数 24
Np = P.Pack.Np;                 % 并数 12
I_load = I_load(:);  N = numel(I_load);

% --- 选项默认值 ---
soc0       = getf(opt,'soc0', 0.9);
T0         = getf(opt,'T0_C', P.Thermal.T_amb_C);
en_bal     = getf(opt,'enable_balance', true);
isc_cell   = getf(opt,'isc_cell', 0);
isc_t0     = getf(opt,'isc_start_s', 0);
isc_R      = getf(opt,'isc_R', 0.5);
soc_spread = getf(opt,'soc_spread', 0);
k_cond     = getf(opt,'k_cond', 0.5);
R_bal      = getf(opt,'R_bal', 33);

% 均衡模式：空则由 enable_balance 推断（向下兼容：默认 passive）
bal_mode = getf(opt,'balance_mode', '');
if isempty(bal_mode)
    if en_bal, bal_mode = 'passive'; else, bal_mode = 'none'; end
end
if ~en_bal, bal_mode = 'none'; end                 % enable_balance=false 强制关闭
act_eff   = getf(opt,'act_eff', 0.9);
act_Imax  = getf(opt,'act_Imax', 2);
act_db    = getf(opt,'act_deadband', 0.005);

% 散热模式
cooling   = getf(opt,'cooling', 'air');
cool_Cp   = getf(opt,'cool_Cp', 3300);
cool_mdot = getf(opt,'cool_mdot', 0.05);
cool_Tin  = getf(opt,'cool_Tin_C', P.Thermal.T_amb_C);
Rth_cool  = getf(opt,'Rth_cool', 0.3);
mCp_cool  = cool_mdot * cool_Cp;                   % 冷却液热容流率 W/K

% 热失控（Arrhenius）
en_tr   = getf(opt,'enable_tr', false);
trp.A       = getf(opt,'tr_A', 2e10);
trp.Ea      = getf(opt,'tr_Ea', 1.0e5);
trp.H_total = getf(opt,'tr_H', 1.5e5) * Np;        % 并联组总反应热
trp.m       = getf(opt,'tr_m', 1);
tr_substep  = getf(opt,'tr_substep', 50);
tr_dc_cap   = getf(opt,'tr_dc_cap', 0.01);         % 单子步反应物消耗上限（数值稳定）

% --- 参数 ---
R0 = P.Cell.R0_Ohm;  R1 = P.Cell.R1_Ohm;  C1 = P.Cell.C1_F;
socbp = P.OCV.SOC_bp(:);  ocvbp = P.OCV.OCV_bp(:);
Cap_str = Np * P.Cell.Capacity_Ah;                 % 并联组容量 A*hr
kR_T  = P.Thermal.kR_perC;                         % 内阻温度系数 1/°C
Tref  = P.Thermal.T_amb_C;
Cth   = P.Thermal.mass_kg * P.Thermal.Cp_JpkgK * Np;   % 并联组热容 J/K
Rth   = P.Thermal.Rth_KpW / Np;                    % 并联组对环境热阻 K/W
bal_thr = P.BMS.balance_threshold_V;
T_amb = P.Thermal.T_amb_C;

% --- 状态初始化（列向量，索引=串号）---
SOC = soc0*ones(Ns,1) + soc_spread*linspace(-1,1,Ns)';
SOC = min(max(SOC,0),1);
Vrc = zeros(Ns,1);
T   = T0*ones(Ns,1);
c_r = ones(Ns,1);                                  % 反应物归一化浓度

% --- 输出预分配 ---
V_cells    = zeros(N,Ns);
SOC_cells  = zeros(N,Ns);
T_cells    = zeros(N,Ns);
bal_active = false(N,Ns);
T_coolant  = zeros(N,Ns);
c_react    = zeros(N,Ns);
V_pack     = zeros(N,1);

a = exp(-dt/(R1*C1));
use_tr   = en_tr;
nsub     = use_tr * (tr_substep-1) + 1;            % 热失控时子步，否则 1
dts      = dt / nsub;

for k = 1:N
    Iload = I_load(k);

    % 内短路自放电电流：I_isc = OCV/R_isc（触发后）
    I_isc = zeros(Ns,1);
    if isc_cell>=1 && isc_cell<=Ns && (k-1)*dt >= isc_t0
        ocv_f = interp1(socbp, ocvbp, SOC(isc_cell), 'pchip');
        I_isc(isc_cell) = ocv_f / isc_R;
    end

    % 当前端电压（内阻随温度修正，下限钳位避免热失控高温下线性外推为负）
    R0_T = max(R0 .* (1 + kR_T*(T - Tref)), 0.2*R0);
    ocv  = interp1(socbp, ocvbp, SOC, 'pchip');
    Vj   = ocv - Iload*R0_T - Vrc;

    % 均衡判定（被动/主动/无）
    bal    = false(Ns,1);
    I_bal  = zeros(Ns,1);
    Q_bal  = zeros(Ns,1);
    switch bal_mode
        case 'passive'
            bal = Vj > (mean(Vj) + bal_thr);
            I_bal(bal) = Vj(bal)/R_bal;
            Q_bal = I_bal.^2 * R_bal;                 % 耗散发热
        case 'active'
            I_bal = active_balancing(SOC, act_Imax, act_eff, act_db);
            bal = I_bal ~= 0;
            % DC-DC 变换损耗发热（计在放电侧）
            dis = I_bal > 0;
            Q_bal(dis) = (1-act_eff) * I_bal(dis) .* Vj(dis);
        otherwise  % 'none'
    end

    % 记录
    V_cells(k,:)    = Vj';
    SOC_cells(k,:)  = SOC';
    T_cells(k,:)    = T';
    bal_active(k,:) = bal';
    c_react(k,:)    = c_r';
    V_pack(k)       = sum(Vj);

    % 各串总电流（负载串联同流 + 本串均衡 + 本串内短路）
    I_str = Iload + I_bal + I_isc;

    % 与电流相关的恒定发热（步内不变）
    Q_ohm  = I_str.^2 .* R0_T + (Iload.^2)*R1;     % 欧姆 + 极化发热
    Q_isc  = I_isc.^2 * isc_R;                     % 内短路发热
    Q_const = Q_ohm + Q_bal + Q_isc;

    % --- 电气状态推进（单步）---
    if k < N
        Vrc = a*Vrc + R1*(1-a)*I_str;
        SOC = SOC - I_str*dt/3600/Cap_str;
        SOC = min(max(SOC,0),1);
    end

    % --- 热状态推进（子步，重算温度相关项保稳定）---
    Tc_last = T_amb*ones(Ns,1);
    for ss = 1:nsub
        % 相邻串一维热传导
        Q_cond = zeros(Ns,1);
        Q_cond(1)       = k_cond*(T(2)-T(1));
        Q_cond(end)     = k_cond*(T(end-1)-T(end));
        Q_cond(2:end-1) = k_cond*(T(1:end-2)+T(3:end)-2*T(2:end-1));

        % 散热（风冷/液冷）
        if strcmp(cooling,'liquid')
            [Q_cool, Tc_last] = liquid_cooling(T, cool_Tin, mCp_cool, Rth_cool);
        else
            Q_cool = (T - T_amb)/Rth;              % 风冷对流
        end

        % Arrhenius 自产热（以反应物消耗驱动并限幅，保证 ∫释放=H_total、不数值过冲）
        if use_tr
            [~, dcdt] = arrhenius_heat(T, c_r, trp);     % dcdt=-k(T,c)
            dc   = min(min(-dcdt*dts, c_r), tr_dc_cap);  % 消耗量：≤请求、≤剩余、≤单步上限
            dc   = max(dc, 0);
            q_tr = dc * trp.H_total / dts;               % 等效释放功率 W
            c_r  = c_r - dc;
        else
            q_tr = zeros(Ns,1);
        end

        if k < N
            dT = (Q_const + Q_cond + q_tr - Q_cool)/Cth;
            T  = T + dT*dts;
        end
    end
    T_coolant(k,:) = Tc_last';
end

out = struct();
out.t          = (0:N-1)'*dt;
out.I_load     = I_load;
out.V_pack     = V_pack;
out.V_cells    = V_cells;
out.SOC_cells  = SOC_cells;
out.T_cells    = T_cells;
out.SOC_pack   = mean(SOC_cells,2);
out.dV_max     = max(V_cells,[],2) - min(V_cells,[],2);
out.bal_active = bal_active;
out.T_coolant  = T_coolant;
out.c_react    = c_react;
out.meta       = struct('balance_mode',bal_mode,'cooling',cooling,'enable_tr',en_tr);
end

%% ===== 局部函数 =====
function import_check(P)
req = {'Cell','OCV','Pack','Thermal','BMS'};
for i = 1:numel(req)
    if ~isfield(P,req{i}); error('PackParam 缺少字段 %s', req{i}); end
end
end

function [Q_cool, Tc] = liquid_cooling(T, Tin, mCp, Rth_cool)
%LIQUID_COOLING 沿串号 1->Ns 流动的冷却液准稳态换热
%   冷却液从入口 Tin 进入，逐串吸热升温（下游液温更高 → 散热变差呈梯度）。
%   Q_cool_j = (T_j - Tc_up)/Rth_cool ; Tc_j = Tc_up + Q_cool_j/mCp
Ns = numel(T);
Q_cool = zeros(Ns,1);
Tc     = zeros(Ns,1);
Tc_up  = Tin;
for j = 1:Ns
    Q_cool(j) = (T(j) - Tc_up)/Rth_cool;
    Tc(j)     = Tc_up + Q_cool(j)/mCp;
    Tc_up     = Tc(j);
end
end

function v = getf(s, f, def)
if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = def; end
end
