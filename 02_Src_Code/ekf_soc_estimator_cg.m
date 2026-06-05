function [soc_est, Vrc_est, V_pred] = ekf_soc_estimator_cg(I, V, dt, prm) %#codegen
%EKF_SOC_ESTIMATOR_CG EKF SOC 估算（MATLAB Coder 兼容版，供 STM32 C 代码生成）
%   [soc_est, Vrc_est, V_pred] = EKF_SOC_ESTIMATOR_CG(I, V, dt, prm)
%   与 ekf_soc_estimator 算法一致（一阶 Thevenin EKF，状态 x=[SOC; Vrc]），针对
%   嵌入式 C 代码生成做如下改造：
%     1) OCV 查表用 linear（嵌入式标准），dOCV/dSOC 取当前线段斜率
%        —— interp1 的 'pchip' 在 MATLAB Coder 不支持；
%     2) 参数结构体 prm 字段全部必填（无动态可选字段），类型可静态确定；
%     3) 定步长 dt（标量），符合嵌入式周期采样；
%     4) 仅用 codegen 支持的运算（小矩阵代数 + for 循环 + 一维查表）。
%
%   状态方程（放电 I>0，SOC 下降）：
%     SOC(k+1) = SOC(k) - dt/(3600*Cap)*I(k)
%     Vrc(k+1) = a*Vrc(k) + R1*(1-a)*I(k),   a = exp(-dt/(R1*C1))
%   观测方程：V(k) = OCV(SOC(k)) - R0*I(k) - Vrc(k)
%   雅可比：A=[1 0;0 a]，C=[dOCV/dSOC, -1]
%
%   输入：
%     I   - 电流序列 (A)，列向量，放电为正
%     V   - 端电压观测 (V)，列向量
%     dt  - 采样步长 (s)，标量
%     prm - 参数结构体（字段全部必填）：
%             R0_Ohm, R1_Ohm, C1_F, Cap_Ah, SOC_bp(列), OCV_bp(列),
%             soc0, Q(2x2), R(标量), P0(2x2)
%   输出：
%     soc_est - SOC 估计序列（列向量）
%     Vrc_est - 极化电压估计
%     V_pred  - 预测端电压
%
%   参考：Plett, "Battery Management Systems, Vol.2", Ch.3 EKF。

I = I(:);  V = V(:);
N = numel(I);

R0  = prm.R0_Ohm;
R1  = prm.R1_Ohm;
C1  = prm.C1_F;
Cap = prm.Cap_Ah * 3600;            % As
socbp = prm.SOC_bp(:);
ocvbp = prm.OCV_bp(:);
Q  = prm.Q;
Rn = prm.R;
P  = prm.P0;

x = [prm.soc0; 0];                  % 状态 [SOC; Vrc]
a = exp(-dt/(R1*C1));

soc_est = zeros(N,1);
Vrc_est = zeros(N,1);
V_pred  = zeros(N,1);

for k = 1:N
    % --- 观测预测（linear 查表 + 线段斜率作雅可比）---
    [ocv, dOCV] = lut_linear(socbp, ocvbp, x(1));
    Vhat = ocv - R0*I(k) - x(2);
    Cmat = [dOCV, -1];

    % --- 量测更新 ---
    S = Cmat*P*Cmat' + Rn;
    K = (P*Cmat')/S;
    z = V(k) - Vhat;
    x = x + K*z;
    x(1) = min(max(x(1),0),1);      % SOC 钳位
    P = (eye(2) - K*Cmat)*P;

    soc_est(k) = x(1);
    Vrc_est(k) = x(2);
    V_pred(k)  = Vhat;

    % --- 时间预测（推进到 k+1）---
    A = [1, 0; 0, a];
    x = [x(1) - dt/Cap*I(k); a*x(2) + R1*(1-a)*I(k)];
    x(1) = min(max(x(1),0),1);
    P = A*P*A' + Q;
end
end

%% ===== 局部函数 =====
function [y, slope] = lut_linear(xbp, ybp, xq)
%LUT_LINEAR 一维线性查表 + 当前线段斜率（codegen 兼容，xbp 升序，xq 标量）
%   越界钳位到端点线段。slope 即该线段斜率，用作 dOCV/dSOC。
n = numel(xbp);
if xq <= xbp(1)
    k = 1;
elseif xq >= xbp(n)
    k = n - 1;
else
    k = 1;
    for i = 1:n-1
        if xq >= xbp(i) && xq <= xbp(i+1)
            k = i;
            break;
        end
    end
end
slope = (ybp(k+1) - ybp(k)) / (xbp(k+1) - xbp(k));
y = ybp(k) + slope*(xq - xbp(k));
end
