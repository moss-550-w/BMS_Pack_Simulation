function [q, dcdt, info] = arrhenius_heat(T_C, c, prm)
%ARRHENIUS_HEAT 锂电热失控单步 Arrhenius 自产热功率与反应物消耗速率
%   [q, dcdt, info] = ARRHENIUS_HEAT(T_C, c, prm)
%   以单步集总放热反应近似热失控链式产热：温度升高 → 反应速率指数增长 →
%   产热增大 → 温度进一步升高（正反馈），由反应物耗尽实现自限。
%
%   模型：
%     反应速率   k(T,c) = A * c^m * exp(-Ea/(Rgas*T_K))     [1/s]
%     产热功率   q       = H_total * k                       [W]
%     反应物消耗 dc/dt   = -k                                [1/s]，c∈[0,1]
%   其中 T_K = T_C + 273.15。低温时 exp 项极小（近零产热），温度越过隐式
%   起始点后 k 暴增触发失控；c 由 1 衰减至 0 后产热自动停止，避免无限产热。
%
%   输入：
%     T_C - 温度 (°C)，标量或向量（逐单体）
%     c   - 归一化反应物浓度 [0,1]，与 T_C 同形
%     prm - 参数结构体：
%             A       频率因子 (1/s)
%             Ea      活化能 (J/mol)
%             H_total 单体（串组）总反应热 (J)
%             m       反应级数，可选，默认 1
%             Rgas    气体常数，可选，默认 8.314 J/(mol*K)
%   输出：
%     q    - 自产热功率 (W)，与 T_C 同形
%     dcdt - 反应物消耗速率 (1/s)，与 T_C 同形
%     info - 结构体：k(反应速率)、T_peak_idx(最热点索引)
%
%   参考：Hatchard/NREL 单步 Arrhenius 热失控产热模型（简化集总）。

T_C = T_C(:);
c   = max(c(:), 0);                    % 浓度非负
m    = getf(prm, 'm', 1);
Rgas = getf(prm, 'Rgas', 8.314);

T_K = T_C + 273.15;
k = prm.A .* (c.^m) .* exp(-prm.Ea ./ (Rgas .* T_K));   % 反应速率 1/s

q    = prm.H_total .* k;               % 产热功率 W
dcdt = -k;                             % 反应物消耗速率

[~, idx] = max(T_C);
info = struct('k', k, 'T_peak_idx', idx);
end

%% ===== 局部函数 =====
function v = getf(s, f, def)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = def; end
end
