function [soc, vrc, vhat] = ekf_soc_step_cg(I_k, V_k, dt, prm, reset) %#codegen
%EKF_SOC_STEP_CG 单步 EKF SOC 估算（嵌入式单周期调用版，供 STM32 部署）
%   [soc, vrc, vhat] = EKF_SOC_STEP_CG(I_k, V_k, dt, prm, reset)
%   每个采样周期调用一次，内部用 persistent 保持状态 x=[SOC;Vrc] 与协方差 P，
%   契合 MCU 实时循环。区别于批处理版 ekf_soc_estimator_cg：
%     - 标量输入/输出，固定大小（OCV 查表 21 点定长），无动态内存(emxArray/malloc)；
%     - persistent 状态跨调用保持；reset=true 时按 prm.soc0 重新初始化。
%   适合 Cortex-M4F/M7（带 FPU）直接集成；生成的 C 为静态内存、可重入到单实例。
%
%   状态方程（放电 I>0）：SOC -= dt/(3600*Cap)*I；Vrc = a*Vrc + R1*(1-a)*I
%   观测方程：V = OCV(SOC) - R0*I - Vrc；雅可比 C=[dOCV/dSOC, -1]
%
%   输入：
%     I_k   - 当前电流 (A)，放电为正
%     V_k   - 当前端电压观测 (V)
%     dt    - 采样步长 (s)
%     prm   - 参数结构体（字段全部必填，OCV_bp/SOC_bp 为 21x1 定长）：
%               R0_Ohm,R1_Ohm,C1_F,Cap_Ah,SOC_bp(21),OCV_bp(21),soc0,Q(2x2),R,P0(2x2)
%     reset - 逻辑标量，true 时用 prm.soc0/P0 重置状态（上电/重启时置 true）
%   输出：
%     soc   - 当前 SOC 估计 [0,1]；vrc - 极化电压；vhat - 预测端电压
%
%   参考：Plett, "Battery Management Systems, Vol.2", Ch.3 EKF。

persistent x P
if isempty(x) || reset
    x = [prm.soc0; 0];
    P = prm.P0;
end

R0  = prm.R0_Ohm;  R1 = prm.R1_Ohm;  C1 = prm.C1_F;
Cap = prm.Cap_Ah * 3600;
a   = exp(-dt/(R1*C1));

% --- 观测预测（linear 查表 + 线段斜率）---
[ocv, dOCV] = lut_linear21(prm.SOC_bp, prm.OCV_bp, x(1));
vhat = ocv - R0*I_k - x(2);
Cmat = [dOCV, -1];

% --- 量测更新 ---
S = Cmat*P*Cmat' + prm.R;
K = (P*Cmat')/S;
z = V_k - vhat;
x = x + K*z;
x(1) = min(max(x(1),0),1);
P = (eye(2) - K*Cmat)*P;

soc = x(1);
vrc = x(2);

% --- 时间预测（推进到下一周期）---
A = [1, 0; 0, a];
x = [x(1) - dt/Cap*I_k; a*x(2) + R1*(1-a)*I_k];
x(1) = min(max(x(1),0),1);
P = A*P*A' + prm.Q;
end

%% ===== 局部函数 =====
function [y, slope] = lut_linear21(xbp, ybp, xq)
%LUT_LINEAR21 21 点一维线性查表 + 线段斜率（定长，codegen 嵌入式友好）
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
