function Plot_Extended(ext)
%PLOT_EXTENDED 绘制拓展工况对比曲线并导出 PNG 至 asset/（流程 7.2）
%   PLOT_EXTENDED(ext)  ext 为 Run_Extended_Sim 返回结构；无参时自动运行。
%   产出（300 dpi，宋体）：
%     ActiveBalance_Compare.png  主/被动均衡压差与 SOC 离散收敛对比
%     Cooling_Air_vs_Liquid.png  风冷/液冷沿串温度分布与均温对比
%     Thermal_Runaway.png        线性内短路 vs Arrhenius 热失控温升与蔓延时序
%
%   依赖：需先运行 startup。

global BMS_PATHS %#ok<GVMIS>
if isempty(BMS_PATHS); error('请先运行 startup 初始化工程路径。'); end
if nargin < 1 || isempty(ext); ext = Run_Extended_Sim(); end
asset = BMS_PATHS.Asset;  font = 'SimSun';

%% 图1：主动 vs 被动均衡
oP = ext.bal.passive;  oA = ext.bal.active;
th = oP.t/3600;
dP = max(oP.SOC_cells,[],2)-min(oP.SOC_cells,[],2);
dA = max(oA.SOC_cells,[],2)-min(oA.SOC_cells,[],2);
fig = figure('Visible','off','Color','w','Position',[100 100 900 560]);
subplot(2,1,1);
plot(th, oP.dV_max*1000, 'b-', 'LineWidth',1.8); hold on;
plot(th, oA.dV_max*1000, 'r-', 'LineWidth',1.8);
grid on; box on; set(gca,'FontName',font,'FontSize',11);
ylabel('最大单体压差 (mV)','FontName',font);
title(sprintf('主动 vs 被动均衡（静置 10h）：压差收敛 %.0f→%.0f mV(被动) / %.0f mV(主动)', ...
    oP.dV_max(1)*1000, oP.dV_max(end)*1000, oA.dV_max(end)*1000),'FontName',font,'FontSize',12);
legend({'被动均衡(耗散)','主动均衡(DC-DC)'},'Location','northeast','FontName',font);
subplot(2,1,2);
plot(th, dP*100, 'b-', 'LineWidth',1.8); hold on;
plot(th, dA*100, 'r-', 'LineWidth',1.8);
grid on; box on; set(gca,'FontName',font,'FontSize',11);
xlabel('时间 (h)','FontName',font); ylabel('SOC 离散度 (%)','FontName',font);
title('SOC 离散度收敛（主动均衡显著更快、近乎无发热）','FontName',font,'FontSize',12);
legend({'被动均衡','主动均衡'},'Location','northeast','FontName',font);
exportgraphics(fig, fullfile(asset,'ActiveBalance_Compare.png'), 'Resolution',300);
close(fig);

%% 图2：风冷 vs 液冷
oAir = ext.cool.air;  oLH = ext.cool.liquid_hi;  oLL = ext.cool.liquid_lo;
Ns = size(oAir.T_cells,2);  s = 1:Ns;  tc = oAir.t/60;
fig = figure('Visible','off','Color','w','Position',[100 100 900 560]);
subplot(2,1,1);
plot(s, oAir.T_cells(end,:), 'k-o', 'LineWidth',1.6,'MarkerSize',4); hold on;
plot(s, oLH.T_cells(end,:), 'b-s', 'LineWidth',1.6,'MarkerSize',4);
plot(s, oLL.T_cells(end,:), 'r-^', 'LineWidth',1.6,'MarkerSize',4);
grid on; box on; set(gca,'FontName',font,'FontSize',11);
xlabel('串号（冷却液流向 1→24）','FontName',font); ylabel('末态温度 (°C)','FontName',font);
title('末态沿串温度分布：风冷均匀、液冷呈流向梯度','FontName',font,'FontSize',12);
legend({'风冷','液冷 0.05kg/s','液冷 0.02kg/s'},'Location','northwest','FontName',font);
subplot(2,1,2);
plot(tc, mean(oAir.T_cells,2), 'k-', 'LineWidth',1.8); hold on;
plot(tc, mean(oLH.T_cells,2), 'b-', 'LineWidth',1.8);
plot(tc, oLH.T_coolant(:,end), 'b--', 'LineWidth',1.4);
grid on; box on; set(gca,'FontName',font,'FontSize',11);
xlabel('时间 (min)','FontName',font); ylabel('温度 (°C)','FontName',font);
title('PACK 均温与冷却液出口温升（液冷散热更强）','FontName',font,'FontSize',12);
legend({'风冷 均温','液冷 均温','液冷 出口液温'},'Location','southeast','FontName',font);
exportgraphics(fig, fullfile(asset,'Cooling_Air_vs_Liquid.png'), 'Resolution',300);
close(fig);

%% 图3：热失控蔓延
oLin = ext.tr.linear;  oRun = ext.tr.runaway;  tr = oRun.t/60;
fig = figure('Visible','off','Color','w','Position',[100 100 900 560]);
subplot(2,1,1);
plot(tr, max(oLin.T_cells,[],2), 'b-', 'LineWidth',1.8); hold on;
plot(tr, max(oRun.T_cells,[],2), 'r-', 'LineWidth',2);
yline(60,'k--','过温阈值','FontName',font,'LineWidth',1.0);
grid on; box on; set(gca,'FontName',font,'FontSize',11);
ylabel('峰值单体温度 (°C)','FontName',font);
title(sprintf('线性内短路(峰%.0f°C) vs Arrhenius 热失控(峰%.0f°C，%d/24 串失控)', ...
    max(oLin.T_cells(:)), max(oRun.T_cells(:)), ext.tr.n_runaway),'FontName',font,'FontSize',12);
legend({'线性内短路','Arrhenius 热失控'},'Location','northwest','FontName',font);
subplot(2,1,2);
reps = [12 11 9 7 1];  cmap = lines(numel(reps));
leg = cell(1,numel(reps));
for i = 1:numel(reps)
    plot(tr, oRun.T_cells(:,reps(i)), 'Color',cmap(i,:), 'LineWidth',1.6); hold on;
    leg{i} = sprintf('串%d', reps(i));
end
grid on; box on; set(gca,'FontName',font,'FontSize',11);
xlabel('时间 (min)','FontName',font); ylabel('单体温度 (°C)','FontName',font);
title('热失控链式蔓延：自触发串 12 向两端逐串引燃','FontName',font,'FontSize',12);
legend(leg,'Location','northeast','FontName',font);
exportgraphics(fig, fullfile(asset,'Thermal_Runaway.png'), 'Resolution',300);
close(fig);

fprintf('[Plot_Extended] 已导出 3 张拓展对比图至 %s\n', asset);
fprintf('  ActiveBalance_Compare.png / Cooling_Air_vs_Liquid.png / Thermal_Runaway.png\n');
end
