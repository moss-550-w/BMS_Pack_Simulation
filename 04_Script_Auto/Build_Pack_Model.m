function Build_Pack_Model()
%BUILD_PACK_MODEL 用 Simscape Battery Builder 构建 24S12P 模组级等效电池包库
%   流程：从 Pack_Param.mat 取标定参数 → 配置 Table-Based 电芯（一阶RC+热端口）
%         → ParallelAssembly(12P, Lumped) → Module(24S, Lumped) → buildBattery
%         生成自定义 Simscape 库至 01_Model/Pack_Lib.slx。
%   建模粒度：Lumped（集总等效），整组/整模组等效为单一模型，仿真快，
%             足够支撑 SOC 估算、被动均衡、故障注入的演示需求。
%   热耦合：AmbientThermalPath=CellBasedThermalResistance，电芯经热阻连风冷环境。
%   参考：Simscape Battery, buildBattery / ParallelAssembly / Module (R2025a)。
%
%   依赖：需先运行 startup 注册路径并加载 PackParam。

global BMS_PATHS %#ok<GVMIS>
if isempty(BMS_PATHS)
    error('请先运行 startup 初始化工程路径。');
end

% 加载标定参数
matFile = fullfile(BMS_PATHS.Data, 'Pack_Param.mat');
if ~isfile(matFile)
    error('缺少 Pack_Param.mat，请先运行 calibrate_pack_param（流程第 2 步）。');
end
S = load(matFile, 'PackParam');
P = S.PackParam;

import simscape.battery.builder.*

%% 1) 电芯几何（18650 圆柱）
geo = CylindricalGeometry( ...
    Height   = simscape.Value(P.Geometry.Height_m,   'm'), ...
    Radius   = simscape.Value(P.Geometry.Diameter_m/2,'m'));

%% 2) 电芯模型选项：Table-Based + 一阶 RC + 热端口 + 温度依赖
cellOpts = CellModelBlock;
cellOpts.BlockParameters.thermal_port = 'model';   % 暴露热端口，支持热耦合
cellOpts.BlockParameters.T_dependence = 'yes';     % 内阻/OCV 随温度变化
cellOpts.BlockParameters.prm_dyn      = 'rc1';     % 一阶 RC 动态（R0+R1//C1）

%% 3) 电芯对象
cellObj = Cell( ...
    Geometry         = geo, ...
    CellModelOptions = cellOpts, ...
    Capacity         = simscape.Value(P.Cell.Capacity_Ah, 'A*hr'), ...
    Mass             = simscape.Value(P.Thermal.mass_kg,  'kg'));
cellObj.Name = 'Cell_18650';

%% 4) 并联组：12 并，集总等效，热阻连风冷环境
pSet = ParallelAssembly( ...
    Cell             = cellObj, ...
    NumParallelCells = P.Pack.Np, ...
    ModelResolution  = 'Lumped', ...
    AmbientThermalPath = 'CellBasedThermalResistance');
pSet.Name = 'PSet_12P';

%% 5) 模组：24 串并联组，集总等效，热阻连风冷环境
moduleObj = Module( ...
    ParallelAssembly    = pSet, ...
    NumSeriesAssemblies = P.Pack.Ns, ...
    ModelResolution     = 'Lumped', ...
    AmbientThermalPath  = 'CellBasedThermalResistance');
moduleObj.Name = 'Module_24S12P';

%% 6) 生成自定义 Simscape 库
libName = 'Pack_Lib';
buildBattery(moduleObj, ...
    LibraryName = libName, ...
    Directory   = BMS_PATHS.Model, ...
    MaskParameters = 'VariableNamesByType', ...
    Verbose = 'on');

fprintf('[build] 电池包库已生成：%s\n', fullfile(BMS_PATHS.Model, [libName '_lib.slx']));
fprintf('[build]   主模块：Module_24S12P（拖入顶层模型即可使用）\n');
fprintf('[build]   参数脚本：%s\n', fullfile(BMS_PATHS.Model, [libName '_param.m']));
fprintf('[build]   拓扑：%d 串 %d 并 | 集总等效 | 风冷热阻耦合\n', P.Pack.Ns, P.Pack.Np);
fprintf('[build]   电芯模型：Table-Based 一阶RC，R0=%.4f Ω R1=%.4f Ω C1=%.0f F\n', ...
    P.Cell.R0_Ohm, P.Cell.R1_Ohm, P.Cell.C1_F);
end
