function [faults, info] = fault_diagnosis(V_cells, T_cells, bms)
%FAULT_DIAGNOSIS 单体故障诊断（过压/欠压/过温/低温/内短路）
%   [faults, info] = FAULT_DIAGNOSIS(V_cells, T_cells, bms)
%   基于阈值与离群检测，逐单体输出故障标志位（单步）。
%
%   诊断逻辑：
%     OV  过压：V > bms.OV_V
%     UV  欠压：V < bms.UV_V
%     OT  过温：T > bms.OT_C
%     UT  低温：T < bms.UT_C
%     ISC 内短路：电压显著低于组内中位数（鲁棒离群），疑似自放电/内短路。
%         判据：(median(V) - V) > k*1.4826*MAD(V) 且压降超最小绝对阈值。
%
%   输入：
%     V_cells - 单体电压向量 (V)
%     T_cells - 单体温度向量 (degC)，可与 V 等长；标量则广播
%     bms     - BMS 阈值结构体，含 OV_V/UV_V/OT_C/UT_C，
%               可选 ISC_k(默认5)、ISC_min_dV(默认0.1V)
%   输出：
%     faults  - 结构体，各字段为逻辑向量（true=该单体故障）：
%                 OV, UV, OT, UT, ISC, any(任一故障)
%     info    - 结构体：fault_count、first_fault_idx、median_V、mad_V
%
%   参考：BMS 故障诊断阈值法 + MAD 鲁棒离群检测。

V_cells = V_cells(:);
n = numel(V_cells);
T_cells = T_cells(:);
if isscalar(T_cells), T_cells = repmat(T_cells, n, 1); end

% 可选参数默认
ISC_k      = getfield_default(bms, 'ISC_k', 5);
ISC_min_dV = getfield_default(bms, 'ISC_min_dV', 0.1);

% 阈值类故障
OV = V_cells > bms.OV_V;
UV = V_cells < bms.UV_V;
OT = T_cells > bms.OT_C;
UT = T_cells < bms.UT_C;

% 内短路：鲁棒离群（基于中位数 + MAD）
medV = median(V_cells);
madV = median(abs(V_cells - medV));      % 中位绝对偏差
robust_sigma = 1.4826*madV;              % 正态一致估计
if robust_sigma < 1e-6
    ISC = false(n,1);                    % 全同压，无离群
else
    ISC = (medV - V_cells) > ISC_k*robust_sigma & (medV - V_cells) > ISC_min_dV;
end

any_fault = OV | UV | OT | UT | ISC;

faults = struct('OV',OV, 'UV',UV, 'OT',OT, 'UT',UT, 'ISC',ISC, 'any',any_fault);

first_idx = find(any_fault, 1);
if isempty(first_idx), first_idx = 0; end
info = struct( ...
    'fault_count',     sum(any_fault), ...
    'first_fault_idx', first_idx, ...
    'median_V',        medV, ...
    'mad_V',           madV);
end

%% ===== 局部函数 =====
function v = getfield_default(s, f, def)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = def; end
end
