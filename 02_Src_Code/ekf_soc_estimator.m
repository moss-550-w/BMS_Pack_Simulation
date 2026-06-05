function [soc_est, info] = ekf_soc_estimator(I, V, dt, prm)
%EKF_SOC_ESTIMATOR 扩展卡尔曼滤波 SOC 估算（一阶 Thevenin 模型）
%   [soc_est, info] = EKF_SOC_ESTIMATOR(I, V, dt, prm)
%   以端电压观测在线修正 SOC，抑制安时积分漂移。状态 x=[SOC; Vrc]。
%
%   状态方程（放电 I>0，SOC 下降）：
%     SOC(k+1) = SOC(k) - dt/(3600*Cap)*I(k)
%     Vrc(k+1) = a*Vrc(k) + R1*(1-a)*I(k),   a = exp(-dt/(R1*C1))
%   观测方程：
%     V(k) = OCV(SOC(k)) - R0*I(k) - Vrc(k)
%   雅可比：A = [1 0; 0 a]，  C = [dOCV/dSOC, -1]
%
%   输入：
%     I    - 电流序列 (A)，放电为正
%     V    - 端电压观测 (V)
%     dt   - 采样步长 (s)，标量或与 I 等长向量
%     prm  - 参数结构体，必含字段：
%              R0_Ohm, R1_Ohm, C1_F, Cap_Ah, SOC_bp, OCV_bp
%            可选字段（缺省给默认）：
%              soc0(0.5), Q(diag([1e-6 1e-5])), R(1e-3), P0(diag([1e-2 1e-2]))
%   输出：
%     soc_est - SOC 估计序列（列向量）
%     info    - 结构体：Vrc 估计、V_pred 预测电压、innov 残差
%
%   参考：Plett, "Battery Management Systems, Vol.2", Ch.3 EKF。

I = I(:);  V = V(:);
N = numel(I);
if isscalar(dt), dt = repmat(dt, N, 1); else, dt = dt(:); end

% 参数提取
R0   = prm.R0_Ohm;
R1   = prm.R1_Ohm;
C1   = prm.C1_F;
Cap  = prm.Cap_Ah * 3600;          % As
socbp = prm.SOC_bp(:);
ocvbp = prm.OCV_bp(:);

% 可选参数默认值
soc0 = getfield_default(prm, 'soc0', 0.5);
Q    = getfield_default(prm, 'Q', diag([1e-6, 1e-5]));   % 过程噪声
Rn   = getfield_default(prm, 'R', 1e-3);                 % 观测噪声
P    = getfield_default(prm, 'P0', diag([1e-2, 1e-2]));  % 初始协方差

% 状态初始化 x=[SOC; Vrc]
x = [soc0; 0];

soc_est = zeros(N,1);
Vrc_est = zeros(N,1);
V_pred  = zeros(N,1);
innov   = zeros(N,1);

for k = 1:N
    a = exp(-dt(k)/(R1*C1));

    % --- 观测预测（用当前状态）---
    ocv  = interp1(socbp, ocvbp, x(1), 'pchip');
    Vhat = ocv - R0*I(k) - x(2);
    dOCV = docv_dsoc(socbp, ocvbp, x(1));   % dOCV/dSOC
    C    = [dOCV, -1];

    % --- 量测更新 ---
    S = C*P*C' + Rn;
    K = (P*C')/S;
    z = V(k) - Vhat;                 % 新息
    x = x + K*z;
    x(1) = min(max(x(1),0),1);       % SOC 钳位
    P = (eye(2) - K*C)*P;

    soc_est(k) = x(1);
    Vrc_est(k) = x(2);
    V_pred(k)  = Vhat;
    innov(k)   = z;

    % --- 时间预测（推进到 k+1）---
    A = [1, 0; 0, a];
    x = [x(1) - dt(k)/Cap*I(k); a*x(2) + R1*(1-a)*I(k)];
    x(1) = min(max(x(1),0),1);
    P = A*P*A' + Q;
end

info = struct('Vrc', Vrc_est, 'V_pred', V_pred, 'innov', innov);
end

%% ===== 局部函数 =====
function d = docv_dsoc(socbp, ocvbp, soc)
%DOCV_DSOC OCV-SOC 查表在 soc 处的数值导数（中心差分）
h  = 1e-3;
s1 = min(max(soc - h, socbp(1)), socbp(end));
s2 = min(max(soc + h, socbp(1)), socbp(end));
d  = (interp1(socbp, ocvbp, s2, 'pchip') - ...
      interp1(socbp, ocvbp, s1, 'pchip')) / (s2 - s1);
end

function v = getfield_default(s, f, def)
%GETFIELD_DEFAULT 取结构体字段，缺失返回默认值
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = def; end
end
