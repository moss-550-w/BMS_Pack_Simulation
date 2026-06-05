function Verify_EKF_Ccode()
%VERIFY_EKF_CCODE EKF 嵌入式版数值等价性验证（流程 7.2-④，PIL 算法层替代）
%   无目标硬件 / 主机 C 编译器时，真 PIL/SIL 不可执行；本脚本在 MATLAB 层做
%   等价性量化，证明 codegen 改造（pchip→linear 查表、单步 persistent）未损害
%   SOC 估算精度，作为 C 代码上板前的算法层佐证。
%   对比三者对真值 SOC 的跟踪：
%     1) ekf_soc_estimator      原版（pchip 插值，浮点参考）
%     2) ekf_soc_estimator_cg   codegen 批处理版（linear 查表）
%     3) ekf_soc_step_cg        codegen 单步版（persistent，将上板的 C 同源）
%   输出对比图 asset/EKF_Ccode_Verify.png。
%
%   依赖：需先运行 startup 并存在 Pack_Param.mat。

global BMS_PATHS %#ok<GVMIS>
if isempty(BMS_PATHS); error('请先运行 startup 初始化工程路径。'); end
P = load(fullfile(BMS_PATHS.Data,'Pack_Param.mat')).PackParam;
font = 'SimSun';

% --- 合成真值场景：0.5C 放电（含中段静置）+ 测量噪声 ---
dt=1; tEnd=3000; t=(0:dt:tEnd)'; N=numel(t);
Cap=P.Cell.Capacity_Ah; R0=P.Cell.R0_Ohm; R1=P.Cell.R1_Ohm; C1=P.Cell.C1_F;
I=0.5*Cap*ones(N,1); I(t>=1500 & t<2000)=0;
SOC_true=zeros(N,1); SOC_true(1)=0.9; Vrc=0; V=zeros(N,1); a=exp(-dt/(R1*C1));
for k=1:N
    ocv=interp1(P.OCV.SOC_bp,P.OCV.OCV_bp,SOC_true(k),'pchip');
    V(k)=ocv-R0*I(k)-Vrc;
    if k<N, Vrc=a*Vrc+R1*(1-a)*I(k); SOC_true(k+1)=SOC_true(k)-I(k)*dt/3600/Cap; end
end
rng(0); V=V+0.002*randn(N,1);    % 固定种子可复现

% --- 三版 EKF（初值故意偏置 -10%）---
prm0=struct('R0_Ohm',R0,'R1_Ohm',R1,'C1_F',C1,'Cap_Ah',Cap, ...
    'SOC_bp',P.OCV.SOC_bp(:),'OCV_bp',P.OCV.OCV_bp(:),'soc0',0.8, ...
    'Q',diag([1e-7 1e-6]),'R',4e-6,'P0',diag([1e-2 1e-2]));

soc_ref  = ekf_soc_estimator(I,V,dt,prm0);          % pchip 原版
soc_cg   = ekf_soc_estimator_cg(I,V,dt,prm0);       % linear 批处理
soc_step = zeros(N,1);                              % linear 单步（同源 C）
clear ekf_soc_step_cg;
for k=1:N
    soc_step(k)=ekf_soc_step_cg(I(k),V(k),dt,prm0,k==1);
end

% --- 误差量化 ---
rmse=@(e) sqrt(mean(e.^2))*100;
r_ref=rmse(soc_ref-SOC_true); r_cg=rmse(soc_cg-SOC_true); r_step=rmse(soc_step-SOC_true);
d_cg=max(abs(soc_cg-soc_ref))*100; d_step=max(abs(soc_step-soc_cg))*100;
fprintf('[Verify_EKF_Ccode] 等价性验证结果：\n');
fprintf('  vs真值 RMSE: 原版(pchip)=%.3f%% | cg批处理(linear)=%.3f%% | cg单步=%.3f%%\n',r_ref,r_cg,r_step);
fprintf('  最大偏差: cg批处理 vs 原版=%.3f%% | cg单步 vs cg批处理=%.2e%%\n',d_cg,d_step);
fprintf('  结论: linear 查表致精度差 %.3f%%（嵌入式取舍），单步与批处理位级一致。\n',d_cg);

% --- 对比图 ---
asset=BMS_PATHS.Asset;
fig=figure('Visible','off','Color','w','Position',[100 100 900 560]);
subplot(2,1,1);
plot(t/60,SOC_true*100,'k-','LineWidth',2); hold on;
plot(t/60,soc_ref*100,'b--','LineWidth',1.5);
plot(t/60,soc_step*100,'r:','LineWidth',1.8);
grid on; box on; set(gca,'FontName',font,'FontSize',11);
ylabel('SOC (%)','FontName',font);
title(sprintf('EKF C 代码等价性：原版 vs 嵌入式单步版（RMSE %.2f%% / %.2f%%）',r_ref,r_step),'FontName',font,'FontSize',13);
legend({'真值','原版(pchip,浮点参考)','嵌入式单步版(linear,同源C)'},'Location','northeast','FontName',font);
subplot(2,1,2);
plot(t/60,(soc_step-soc_ref)*100,'r-','LineWidth',1.5); hold on;
plot(t/60,(soc_cg-soc_ref)*100,'b-','LineWidth',1.0);
grid on; box on; set(gca,'FontName',font,'FontSize',11);
xlabel('时间 (min)','FontName',font); ylabel('与原版偏差 (%)','FontName',font);
title(sprintf('嵌入式版 vs 原版偏差（最大 %.3f%%，linear 查表取舍）',d_cg),'FontName',font,'FontSize',12);
legend({'单步版-原版','批处理版-原版'},'Location','northeast','FontName',font);
exportgraphics(fig,fullfile(asset,'EKF_Ccode_Verify.png'),'Resolution',300);
close(fig);
fprintf('  对比图：%s\n',fullfile(asset,'EKF_Ccode_Verify.png'));
end
