function soc = coulomb_counting_soc(I, dt, soc0, Cap_Ah)
%COULOMB_COUNTING_SOC 安时积分法 SOC 估算（对照组）
%   soc = COULOMB_COUNTING_SOC(I, dt, soc0, Cap_Ah)
%   纯电流积分，无反馈修正，存在累计漂移，作为 EKF 的对照基准。
%   公式：SOC(k+1) = SOC(k) - I(k)*dt/(3600*Cap_Ah)   （放电 I>0，SOC 下降）
%
%   输入：
%     I       - 电流序列 (A)，列/行向量，放电为正
%     dt      - 采样步长 (s)，标量（等间隔）或与 I 等长向量
%     soc0    - 初始 SOC，标量 [0,1]
%     Cap_Ah  - 电芯/PACK 容量 (A*hr)
%   输出：
%     soc     - SOC 序列，与 I 同形，取值钳位到 [0,1]
%
%   参考：Plett, "Battery Management Systems, Vol.2", Ch.2 库伦计数。

I = I(:);
N = numel(I);
if isscalar(dt)
    dt = repmat(dt, N, 1);
else
    dt = dt(:);
end

soc = zeros(N, 1);
soc(1) = soc0;
for k = 1:N-1
    soc(k+1) = soc(k) - I(k)*dt(k)/(3600*Cap_Ah);
end
soc = min(max(soc, 0), 1);   % 物理钳位
end
