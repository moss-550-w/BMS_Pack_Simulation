function [bal_cmd, info] = passive_balancing(V_cells, threshold_V, hysteresis_V)
%PASSIVE_BALANCING 被动均衡阈值控制逻辑（单步）
%   [bal_cmd, info] = PASSIVE_BALANCING(V_cells, threshold_V, hysteresis_V)
%   单体电压高于（组内均值 + 阈值）时开启耗散均衡，收敛整包压差。
%   带迟滞避免在阈值附近频繁通断（chattering）。
%
%   策略：以组内单体电压均值为基准，对高于 (mean+threshold) 的单体置位均衡；
%         迟滞下界为 (mean + threshold - hysteresis)，本函数为无状态单步判定，
%         迟滞用于配合上层保持逻辑（见 info.upper/lower 门限）。
%
%   输入：
%     V_cells      - 单体电压向量 (V)，长度 = 串数
%     threshold_V  - 均衡开启阈值（高于均值多少，V），如 PackParam.BMS.balance_threshold_V
%     hysteresis_V - 迟滞带宽 (V)，可选，默认 threshold_V/5
%   输出：
%     bal_cmd      - 逻辑向量，true=该单体开启被动均衡
%     info         - 结构体：mean_V、max_dV(最大压差)、upper/lower 门限、n_active
%
%   参考：被动均衡（耗散式）常见 BMS 控制策略。

V_cells = V_cells(:);
if nargin < 3 || isempty(hysteresis_V)
    hysteresis_V = threshold_V/5;
end

V_mean = mean(V_cells);
upper  = V_mean + threshold_V;                  % 开启门限
lower  = V_mean + threshold_V - hysteresis_V;   % 迟滞下界（上层保持用）

bal_cmd = V_cells > upper;

info = struct( ...
    'mean_V',   V_mean, ...
    'max_dV',   max(V_cells) - min(V_cells), ...
    'upper',    upper, ...
    'lower',    lower, ...
    'n_active', sum(bal_cmd));
end
