function Plot_Result(results)
%PLOT_RESULT 绘制仿真结果曲线并导出 PNG 至 asset/
%   PLOT_RESULT(results)  results 为 Run_All_Sim 的返回结构；无参时自动运行。
%   产出（300 dpi，宋体）：
%     EKF_SOC_Compare.png   恒流工况 EKF/安时积分/真值 SOC 对比 + 误差
%     Cell_dV_Balance.png   静置工况单体压差收敛曲线
%     Thermal_ISC_Rise.png  内短路工况温升（均值/峰值）曲线
%
%   依赖：需先运行 startup。

global BMS_PATHS %#ok<GVMIS>
if isempty(BMS_PATHS); error('请先运行 startup 初始化工程路径。'); end
if nargin < 1 || isempty(results)
    results = Run_All_Sim();
end
asset = BMS_PATHS.Asset;
font = 'SimSun';

%% 图1：EKF SOC 估算对比（恒流工况）
r = results.CC; o = r.out;
fig = figure('Visible','off','Color','w','Position',[100 100 900 520]);
subplot(2,1,1);
plot(o.t/60, o.SOC_pack*100, 'k-', 'LineWidth',2); hold on;
plot(o.t/60, r.soc_ekf*100, 'r--', 'LineWidth',1.5);
plot(o.t/60, r.soc_cc*100, 'b-.', 'LineWidth',1.5);
grid on; box on; set(gca,'FontName',font,'FontSize',11);
ylabel('SOC (%)','FontName',font);
title(sprintf('恒流放电 SOC 估算对比（初值偏置 -10%%，EKF RMSE=%.2f%%）',r.rmse_ekf),'FontName',font,'FontSize',13);
legend({'真值','EKF 估算','安时积分'},'Location','northeast','FontName',font);
subplot(2,1,2);
plot(o.t/60, (r.soc_ekf-o.SOC_pack)*100, 'r-', 'LineWidth',1.5); hold on;
plot(o.t/60, (r.soc_cc-o.SOC_pack)*100, 'b-', 'LineWidth',1.5);
grid on; box on; set(gca,'FontName',font,'FontSize',11);
xlabel('时间 (min)','FontName',font); ylabel('估算误差 (%)','FontName',font);
title('SOC 估算误差对比','FontName',font,'FontSize',12);
legend({'EKF 误差','安时积分误差'},'Location','northeast','FontName',font);
exportgraphics(fig, fullfile(asset,'EKF_SOC_Compare.png'), 'Resolution',300);
close(fig);

%% 图2：单体压差均衡收敛（静置工况）
r = results.Balance; o = r.out;
fig = figure('Visible','off','Color','w','Position',[100 100 900 400]);
plot(o.t/3600, o.dV_max*1000, 'Color',[0.85 0.33 0.1], 'LineWidth',2);
grid on; box on; set(gca,'FontName',font,'FontSize',11);
xlabel('时间 (h)','FontName',font); ylabel('最大单体压差 (mV)','FontName',font);
title(sprintf('静置被动均衡：压差收敛 %.0f→%.0f mV',o.dV_max(1)*1000,o.dV_max(end)*1000),'FontName',font,'FontSize',13);
exportgraphics(fig, fullfile(asset,'Cell_dV_Balance.png'), 'Resolution',300);
close(fig);

%% 图3：内短路温升（均值 vs 峰值）
r = results.ISC; o = r.out;
T_mean = mean(o.T_cells,2); T_max = max(o.T_cells,[],2);
OT = bms_threshold(BMS_PATHS,'OT_C',60);
fig = figure('Visible','off','Color','w','Position',[100 100 900 400]);
plot(o.t/60, T_mean, 'b-', 'LineWidth',1.8); hold on;
plot(o.t/60, T_max, 'r-', 'LineWidth',2);
yline(OT, 'k--', '过温阈值', 'FontName',font,'LineWidth',1.2);
grid on; box on; set(gca,'FontName',font,'FontSize',11);
xlabel('时间 (min)','FontName',font); ylabel('温度 (°C)','FontName',font);
title(sprintf('内短路热蔓延：峰值温度 %.1f°C（第12串@600s 注入）',max(T_max)),'FontName',font,'FontSize',13);
legend({'PACK 均温','峰值单体温度'},'Location','northwest','FontName',font);
exportgraphics(fig, fullfile(asset,'Thermal_ISC_Rise.png'), 'Resolution',300);
close(fig);

fprintf('[Plot_Result] 已导出 3 张曲线图至 %s\n', asset);
fprintf('  EKF_SOC_Compare.png / Cell_dV_Balance.png / Thermal_ISC_Rise.png\n');
end

%% ===== 局部函数 =====
function v = bms_threshold(paths, field, def)
% 从 Pack_Param.mat 取 BMS 阈值，失败用默认
try
    P = load(fullfile(paths.Data,'Pack_Param.mat')).PackParam;
    v = P.BMS.(field);
catch
    v = def;
end
end
