function Show_3DPack(results)
%SHOW_3DPACK 渲染 24S12P 电池包 3D 温度场并录制动态 GIF 至 asset/
%   SHOW_3DPACK(results)  results 为 Run_All_Sim 返回结构；无参时自动运行。
%   用内短路工况(ISC)数据，将 24 串排为 4×6 圆柱阵列，按温度蓝(25°C)→红(60°C)
%   着色，逐帧录制热蔓延过程为 GIF（间隔 0.2s，永久循环）。
%   另导出末帧静态 PNG 作 README 封面。
%
%   依赖：需先运行 startup。

global BMS_PATHS %#ok<GVMIS>
if isempty(BMS_PATHS); error('请先运行 startup 初始化工程路径。'); end
if nargin < 1 || isempty(results)
    results = Run_All_Sim();
end
asset = BMS_PATHS.Asset;
font = 'SimSun';

o = results.ISC.out;
Ns = size(o.T_cells,2);            % 24 串
nRow = 4; nCol = 6;               % 阵列布局
T_lo = 25; T_hi = 60;             % 温度色阶范围 (°C)

% 时间下采样：每 30s 一帧
dt = o.t(2)-o.t(1);
step = max(1, round(30/dt));
frames = 1:step:numel(o.t);
if frames(end) ~= numel(o.t), frames(end+1) = numel(o.t); end

% 颜色映射：蓝→青→黄→红
cmap = jet(256);

% 预建圆柱几何
[xc, yc, zc] = cylinder(0.4, 20);   % 半径0.4，便于间距
zc = zc*1.0;                        % 高度1

fig = figure('Visible','off','Color','w','Position',[100 100 760 560]);
ax = axes(fig); hold(ax,'on');
hCyl = gobjects(Ns,1);
for s = 1:Ns
    [r,c] = ind2sub([nCol,nRow], s);   % 列优先排布
    hCyl(s) = surf(ax, xc+r*1.0, yc+c*1.0, zc, 'EdgeColor','none');
end
view(ax, 35, 30); axis(ax,'equal'); axis(ax,'off');
colormap(ax, cmap);
cb = colorbar(ax); clim(ax,[T_lo T_hi]);
cb.Label.String = '温度 (°C)'; cb.Label.FontName = font; cb.Label.FontSize = 11;
camlight(ax,'headlight'); lighting(ax,'gouraud');
ttl = title(ax,'','FontName',font,'FontSize',14);

gifFile = fullfile(asset,'ISC_Temp_Dynamic.gif');
for fi = 1:numel(frames)
    k = frames(fi);
    Tk = o.T_cells(k,:);
    for s = 1:Ns
        cidx = round((Tk(s)-T_lo)/(T_hi-T_lo)*255)+1;
        cidx = min(max(cidx,1),256);
        set(hCyl(s), 'FaceColor', cmap(cidx,:));
    end
    ttl.String = sprintf('24S12P 温度场  t=%.0fs  峰值%.1f°C', o.t(k), max(Tk));
    drawnow;
    frame = getframe(fig);
    [A,map] = rgb2ind(frame2im(frame), 256);
    if fi == 1
        imwrite(A,map,gifFile,'gif','LoopCount',Inf,'DelayTime',0.2);
    else
        imwrite(A,map,gifFile,'gif','WriteMode','append','DelayTime',0.2);
    end
end

% 末帧静态 PNG（README 封面）
exportgraphics(fig, fullfile(asset,'Pack_3D_Thermal.png'), 'Resolution',300);
close(fig);

fprintf('[Show_3DPack] 已导出 3D 温度动图与封面至 %s\n', asset);
fprintf('  ISC_Temp_Dynamic.gif (%d 帧) / Pack_3D_Thermal.png\n', numel(frames));
end
