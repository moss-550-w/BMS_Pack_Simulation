function Show_Runaway(ext)
%SHOW_RUNAWAY 渲染热失控链式蔓延 3D 温度场并录制 GIF 至 asset/（流程 7.2）
%   SHOW_RUNAWAY(ext)  ext 为 Run_Extended_Sim 返回结构；无参时自动运行。
%   用 Arrhenius 热失控工况数据，将 24 串排为 4×6 圆柱阵列，温度蓝(25°C)→
%   红(300°C+)着色，逐帧录制由第 12 串向两端的链式失控蔓延为 GIF（间隔 0.15s，
%   永久循环）。另导出峰值帧静态 PNG。
%
%   依赖：需先运行 startup。

global BMS_PATHS %#ok<GVMIS>
if isempty(BMS_PATHS); error('请先运行 startup 初始化工程路径。'); end
if nargin < 1 || isempty(ext); ext = Run_Extended_Sim(); end
asset = BMS_PATHS.Asset;  font = 'SimSun';

o = ext.tr.runaway;
Ns = size(o.T_cells,2);  nRow = 4; nCol = 6;
T_lo = 25;  T_hi = 300;                 % 热失控色阶范围 (°C)

% 时间下采样：聚焦失控蔓延段（每 10s 一帧）
dt = o.t(2)-o.t(1);
step = max(1, round(10/dt));
frames = 1:step:numel(o.t);
if frames(end) ~= numel(o.t), frames(end+1) = numel(o.t); end

cmap = jet(256);
[xc, yc, zc] = cylinder(0.4, 20);

fig = figure('Visible','off','Color','w','Position',[100 100 780 580]);
ax = axes(fig); hold(ax,'on');
hCyl = gobjects(Ns,1);
for sidx = 1:Ns
    [r,c] = ind2sub([nCol,nRow], sidx);
    hCyl(sidx) = surf(ax, xc+r*1.0, yc+c*1.0, zc, 'EdgeColor','none');
end
view(ax, 35, 30); axis(ax,'equal'); axis(ax,'off');
colormap(ax, cmap);  cb = colorbar(ax);  clim(ax,[T_lo T_hi]);
cb.Label.String = '温度 (°C)';  cb.Label.FontName = font;  cb.Label.FontSize = 11;
camlight(ax,'headlight');  lighting(ax,'gouraud');
ttl = title(ax,'','FontName',font,'FontSize',14);

gifFile = fullfile(asset,'Runaway_Spread_Dynamic.gif');
for fi = 1:numel(frames)
    k = frames(fi);
    Tk = o.T_cells(k,:);
    for sidx = 1:Ns
        cidx = round((Tk(sidx)-T_lo)/(T_hi-T_lo)*255)+1;
        cidx = min(max(cidx,1),256);
        set(hCyl(sidx), 'FaceColor', cmap(cidx,:));
    end
    nHot = sum(Tk>200);
    ttl.String = sprintf('热失控蔓延  t=%.0fs  峰值%.0f°C  失控%d/24', o.t(k), max(Tk), nHot);
    drawnow;
    [A,map] = rgb2ind(frame2im(getframe(fig)), 256);
    if fi == 1
        imwrite(A,map,gifFile,'gif','LoopCount',Inf,'DelayTime',0.15);
    else
        imwrite(A,map,gifFile,'gif','WriteMode','append','DelayTime',0.15);
    end
end

% 峰值帧静态 PNG
[~,kpk] = max(max(o.T_cells,[],2));
Tk = o.T_cells(kpk,:);
for sidx = 1:Ns
    cidx = min(max(round((Tk(sidx)-T_lo)/(T_hi-T_lo)*255)+1,1),256);
    set(hCyl(sidx), 'FaceColor', cmap(cidx,:));
end
ttl.String = sprintf('热失控峰值  t=%.0fs  峰值%.0f°C', o.t(kpk), max(Tk));
exportgraphics(fig, fullfile(asset,'Runaway_Peak.png'), 'Resolution',300);
close(fig);

fprintf('[Show_Runaway] 已导出热失控蔓延动图与峰值帧至 %s\n', asset);
fprintf('  Runaway_Spread_Dynamic.gif (%d 帧) / Runaway_Peak.png\n', numel(frames));
end
