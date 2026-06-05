function [I_bal, info] = active_balancing(SOC_cells, I_max, eff, deadband)
%ACTIVE_BALANCING DC-DC 主动均衡电流分配（集中式电荷转移，单步）
%   [I_bal, info] = ACTIVE_BALANCING(SOC_cells, I_max, eff, deadband)
%   高于组内均值的单体放电（+），能量经 DC-DC 变换器（效率 eff）转移并按缺额
%   比例分配给低于均值的单体充电（-）。区别于被动均衡的耗散发热，主动均衡仅
%   产生 (1-eff) 的变换损耗，能量利用率高、收敛快。
%
%   策略（集中式 buck-boost 母线模型）：
%     dev_j = SOC_j - mean(SOC)
%     放电集合 hi: dev > deadband，放电电流 I_dis_j = min(I_max, kp*dev_j)
%     充电集合 lo: dev < -deadband，可用充电总量 = eff*Σ I_dis，
%       按各低串缺额 |dev| 比例分配为充电电流（负值）
%   能量守恒：放出 ΣI_dis，充入 eff*ΣI_dis，损耗 (1-eff)*ΣI_dis 计入 info。
%
%   输入：
%     SOC_cells - 单体（串组）SOC 向量 [0,1]
%     I_max     - 单体最大均衡电流 (A)，限幅放电电流
%     eff       - DC-DC 变换效率 [0,1]，可选，默认 0.9
%     deadband  - SOC 死区（偏差小于此值不动作），可选，默认 0.005
%   输出：
%     I_bal     - 均衡电流向量 (A)，+放电 / -充电，对 SOC 直接生效
%     info      - 结构体：n_dis/n_chg(放/充电串数)、I_transfer(转移总电流)、
%                 loss_frac(损耗占比)、max_dSOC(最大SOC偏差)
%
%   参考：主动均衡 DC-DC 电荷转移拓扑（cell-to-pack / pack-to-cell）。

SOC_cells = SOC_cells(:);
n = numel(SOC_cells);
if nargin < 3 || isempty(eff),      eff = 0.9;       end
if nargin < 4 || isempty(deadband), deadband = 0.005; end

% 比例增益：偏差 0.1 对应 I_max 放电（线性映射后限幅）
kp = I_max / 0.1;

mSOC = mean(SOC_cells);
dev  = SOC_cells - mSOC;

I_bal = zeros(n,1);
hi = dev >  deadband;     % 高 SOC，放电
lo = dev < -deadband;     % 低 SOC，充电

% 放电电流（正），限幅 I_max
I_bal(hi) = min(I_max, kp*dev(hi));
I_transfer = sum(I_bal(hi));

% 充电电流（负），按缺额比例分配 eff 倍可用电荷
if any(lo) && I_transfer > 0
    w = -dev(lo);  w = w / sum(w);          % 缺额权重
    I_bal(lo) = -eff * I_transfer * w;
end

info = struct( ...
    'n_dis',      sum(hi), ...
    'n_chg',      sum(lo), ...
    'I_transfer', I_transfer, ...
    'loss_frac',  1-eff, ...
    'max_dSOC',   max(SOC_cells) - min(SOC_cells));
end
