%% startup.m - BMS_Pack_Simulation 工程初始化脚本
% 功能：以本文件所在目录为工程根，添加算法/脚本路径，定义全局路径变量，
%       并在存在时自动加载全局参数 Pack_Param.mat。
% 用法：MATLAB 当前文件夹切到工程根后输入 startup 即可。
% 规则：严禁硬编码绝对路径，所有路径基于本文件位置用 fullfile 构建。

function startup()

% 工程根目录 = 本脚本所在目录
projectRoot = fileparts(mfilename('fullpath'));

% 标准目录定义（与 Claude.md / Design.md 目录树一致）
paths = struct();
paths.Root       = projectRoot;
paths.Asset      = fullfile(projectRoot, 'asset');
paths.Model      = fullfile(projectRoot, '01_Model');
paths.SrcCode    = fullfile(projectRoot, '02_Src_Code');
paths.Data       = fullfile(projectRoot, '03_Data');
paths.CellTest   = fullfile(projectRoot, '03_Data', 'Cell_Test_Data');
paths.SimOut     = fullfile(projectRoot, '03_Data', 'Sim_Out_Result');
paths.ScriptAuto = fullfile(projectRoot, '04_Script_Auto');
paths.Doc        = fullfile(projectRoot, '05_doc');

% 加入 MATLAB 搜索路径（算法、脚本、模型目录递归加入）
addpath(genpath(paths.SrcCode));
addpath(genpath(paths.ScriptAuto));
addpath(paths.Model);

% 暴露为全局变量，供脚本统一取用，避免各处重复拼路径
global BMS_PATHS %#ok<GVMIS>
BMS_PATHS = paths;

% 自动加载全局参数（若已标定生成）
paramFile = fullfile(paths.Data, 'Pack_Param.mat');
if isfile(paramFile)
    evalin('base', sprintf('load(''%s'');', paramFile));
    fprintf('[startup] 已加载全局参数：%s\n', paramFile);
else
    fprintf('[startup] 提示：未找到 Pack_Param.mat，请先执行参数标定（流程第 2 步）。\n');
end

fprintf('[startup] BMS_Pack_Simulation 初始化完成，工程根：%s\n', projectRoot);

end
