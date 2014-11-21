function varargout = visORICA(varargin)
% VISORICA MATLAB code for visORICA.fig
%      VISORICA, by itself, creates a new VISORICA or raises the existing
%      singleton*.
%
%      H = VISORICA returns the handle to a new VISORICA or the handle to
%      the existing singleton*.
%
%      VISORICA('CALLBACK',hObject,eventData,handles,...) calls the local
%      function named CALLBACK in VISORICA.M with the given input arguments.
%
%      VISORICA('Property','Value',...) creates a new VISORICA or raises the
%      existing singleton*.  Starting from the left, property value pairs are
%      applied to the GUI before visORICA_OpeningFcn gets called.  An
%      unrecognized property name or invalid value makes property application
%      stop.  All inputs are passed to visORICA_OpeningFcn via varargin.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
%
% See also: GUIDE, GUIDATA, GUIHANDLES

% Edit the above text to modify the response to help visORICA

% Last Modified by GUIDE v2.5 14-Nov-2014 13:06:51

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @visORICA_OpeningFcn, ...
                   'gui_OutputFcn',  @visORICA_OutputFcn, ...
                   'gui_LayoutFcn',  [] , ...
                   'gui_Callback',   []);
if nargin && ischar(varargin{1})
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT


% --- Executes just before visORICA is made visible.
function visORICA_OpeningFcn(hObject, eventdata, handles, varargin)
% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% varargin   command line arguments to visORICA (see VARARGIN)
%   1: channel locations


% Parse varargsin 
handles.chanlocs = evalin('base','chanlocs');
handles.ntopo = 8;
handles.nic = length(handles.chanlocs);
handles.ics = 1:handles.nic;
handles.streamName = 'EEGLAB';
handles.curIC = 1;
calibData = varargin{1};

% Start EEG stream
vis_stream_ORICA('figurehandles',handles.figure1,'axishandles',handles.axisEEG);
% vis_stream_ORICA('StreamName',handles.streamName,'figurehandles',handles.figure1,'axishandles',handles.axisEEG);
eegTimer = timerfind('Name','eegTimer');

% Intialize ORICA
initializeORICA(handles,calibData);

% Create ORICA timer
oricaTimer = timer('Period',.1,'ExecutionMode','fixedSpacing','TimerFcn',{@onl_filtered_ORICA,1},'StartDelay',0.1,'Tag','oricaTimer','Name','oricaTimer');

% Populate scalp maps
for it = 1:handles.ntopo
    set(handles.figure1, 'CurrentAxes', handles.(['axesIC' int2str(it)]))
    topoplotFast(rand(size(handles.chanlocs)), handles.chanlocs);
end

% Create scalp map timer
topoTimer = timer('Period',2/handles.ntopo,'ExecutionMode','fixedRate','TimerFcn',{@vis_topo,hObject},'StartDelay',0.2,'Tag','topoTimer','Name','topoTimer');

% Create data timer (starts as power spectrum)
infoTimer = timer('Period',1,'ExecutionMode','fixedRate','TimerFcn',{@icPS,hObject},'StartDelay',0.2,'Tag','infoTimer','Name','infoTimer');

% Set panel and button colors
% names = fieldnames(handles);
% ind = find(any([strncmpi(names,'panel',5),strncmpi(names,'toggle',6),strncmpi(names,'push',4),strncmpi(names,'popup',5)],2));
% for it = 1:length(ind)
%     set(handles.(names{ind(it)}),'BackgroundColor',get(handles.figure1,'Color'))
% end

% Start timers
start(oricaTimer);
start(eegTimer);
start(topoTimer);
start(infoTimer);

% Save timers
handles.pauseTimers = [eegTimer,topoTimer,infoTimer];

% Choose default command line output for visORICA
handles.output = hObject;

% Update handles structure
guidata(hObject, handles);

% UIWAIT makes visORICA wait for user response (see UIRESUME)
% uiwait(handles.figure1);


function initializeORICA(handles,calibData)

run_readlsl('MatlabStream',handles.streamName, ...
    'SelectionProperty','type','SelectionValue','EEG', 'MarkerStreamQuery',[]);

opts.lsl.StreamName = handles.streamName;
opts.BCILAB_PipelineConfigFile = 'ORICA_pipeline_config_realtime.mat'; % make sure this file doesn't have 'signal' entry

% define the pipeline configuration
try    fltPipCfg = exp_eval(io_load(opts.BCILAB_PipelineConfigFile));
catch, disp('-- no existing pipeline --'); fltPipCfg = {}; end
fltPipCfg = arg_guipanel('Function',@flt_pipeline, ...
    'Parameters',[{'signal',calibData} fltPipCfg], ...
    'PanelOnly',false);

if ~isempty(fltPipCfg)
    if isfield(fltPipCfg,'signal'); fltPipCfg = rmfield(fltPipCfg,'signal'); end
    save(env_translatepath(['data/' opts.BCILAB_PipelineConfigFile]),...
        '-struct','fltPipCfg');
end

% run pipline on calibration data
cleaned_data = exp_eval(flt_pipeline('signal',calibData,fltPipCfg));

% initialize the pipeline for streaming data
pipeline     = onl_newpipeline(cleaned_data,opts.lsl.StreamName);
assignin('base','pipeline',pipeline);


function icPS(varargin)
secs2samp = 5; % seconds

try
    W = evalin('base','W');
    sphere = evalin('base','sphere');
    handles = guidata(varargin{3});
    
    set(handles.panelInfo,'Title',['Power spectral density of IC' int2str(handles.curIC)])
    
    srate = evalin('base','lsl_visORICA_stream.srate');
    data = evalin('base','lsl_visORICA_stream.data');
    if all(data(:,end)==0)
        mark=1;
        while true
            ind = find(data(1,mark:end)==0,1);
            mark = mark+ind;
            if all(data(:,mark+ind-1)==0)
                break; end
        end
        data = data(:,max(1,mark-srate*secs2samp+1):mark);
    else
        data = data(:,end-srate*secs2samp+1:end);
    end
    
    data = bsxfun(@minus,data,mean(data,2));
    data = W*sphere*data;
    data = data(handles.curIC,:);
    
    [data,f] = pwelch(data,[],[],[],srate);
    
    plot(handles.axisInfo,f,db(data))
    grid(handles.axisInfo,'on');
    xlabel(handles.axisInfo,'Frequency (Hz)')
    ylabel(handles.axisInfo,'Power/Frequency (dB/Hz)')
    % axis(handles.axisInfo,[0 srate/2 -60 40])
    axis(handles.axisInfo,'tight')
    set(handles.axisInfo,'XTick',[0 10:10:f(end)])
end

function vis_topo(varargin)
% get the updated stream buffer
W = evalin('base','W');
sphere = evalin('base','sphere');
Winv = inv(W*sphere);
handles = guidata(varargin{3});

% update topo plot
it = mod(get(varargin{1},'TasksExecuted')-1,handles.ntopo)+1;
set(handles.(['panelIC' int2str(it)]),'Title',['IC' int2str(handles.ics(it))])
hstr = ['axesIC' int2str(it)];
hand = get(handles.(hstr),'children');
[map, cmin, cmax] = topoplotUpdate(Winv(:,handles.ics(it)), handles.chanlocs,'electrodes','off','gridscale',32);
set(hand(end),'CData',map);
set(handles.(hstr),'CLim',[cmin cmax]);


% --- Outputs from this function are returned to the command line.
function varargout = visORICA_OutputFcn(hObject, eventdata, handles) 
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Get default command line output from handles structure
varargout{1} = handles.output;


% --- Executes on selection change in popupmenuEEG.
function popupmenuEEG_Callback(hObject, eventdata, handles)
% hObject    handle to popupmenuEEG (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
eegTimer = timerfind('Name','eegTimer');
stop(eegTimer)
if get(hObject,'value')==1
    set(eegTimer,'UserData',0);
else
    set(eegTimer,'UserData',1);
end
start(eegTimer)

% Hints: contents = cellstr(get(hObject,'String')) returns popupmenuEEG contents as cell array
%        contents{get(hObject,'Value')} returns selected item from popupmenuEEG


% --- Executes during object creation, after setting all properties.
function popupmenuEEG_CreateFcn(hObject, eventdata, handles)
% hObject    handle to popupmenuEEG (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in pushbuttonIC.
function pushbuttonIC_Callback(hObject, eventdata, handles)
% hObject    handle to pushbuttonIC (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% if ~isfield(handles,'figIC')
% else
%     figure('toolbar','none','Menubar','none','Name','IC Select','position',[1 1 990 990])
% tic
% n = length(W);
% rowcols(2) = ceil(sqrt(n));
% rowcols(1) = ceil(n/rowcols(2));
% scaleMatTopo = [1 0 0 0;0 1 0 0;0 0 1 0;0 .2 0 .8];
% scaleMatExclude = [1 0 0 0;0 1 0 0;0 0 .5 0;.5 0 0 .2];
% for it = 1:n
% %     h(it) = axes([.025+.95*mod(it
%     h(it) = subplot(rowcols(1),rowcols(2),it);
% %     set(h(it),'looseinset',get(h(it),'tightinset'))
%     tempPos = get(h(it),'Position');
%     set(h(it),'position',get(h(it),'position')*scaleMat)
%     topoplotFast(W(:,it),chanlocs);
%     title(['IC' int2str(it)])
%     
%     buttonLock(it) = uicontrol('Style', 'togglebutton', 'String', 'Lock','Units','normalize','Position', tempPos.*[1 1 .5 .2],'Callback', '');
%     buttonExclude(it) = uicontrol('Style', 'togglebutton', 'String', 'Exclude','Units','normalize','Position', tempPos*scaleMatExclude,'Callback', '');
% end
% toc
% end


function genICSelectGUI(handles)
figure
rowcols(2) = ceil(sqrt(handles.nic));
rowcols(1) = ceil(handles.nic/rowcols(2));
for it = 1:handles.nic
    subplot(rowcols(1),rowcols(2),it);
    topoplotFast(W(:,it),chanlocs);
    title(['IC' int2str(it)])
end
toc


% --- Executes on button press in togglebuttonLockIC1.
function togglebuttonLockIC1_Callback(hObject, eventdata, handles)
% hObject    handle to togglebuttonLockIC1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of togglebuttonLockIC1


% --- Executes on button press in togglebuttonExcludeIC1.
function togglebuttonExcludeIC1_Callback(hObject, eventdata, handles)
% hObject    handle to togglebuttonExcludeIC1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of togglebuttonExcludeIC1


% --- Executes on selection change in popupmenuInfo.
function popupmenuInfo_Callback(hObject, eventdata, handles)
% hObject    handle to popupmenuInfo (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: contents = cellstr(get(hObject,'String')) returns popupmenuInfo contents as cell array
%        contents{get(hObject,'Value')} returns selected item from popupmenuInfo


% --- Executes during object creation, after setting all properties.
function popupmenuInfo_CreateFcn(hObject, eventdata, handles)
% hObject    handle to popupmenuInfo (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in togglebuttonExcludeIC8.
function togglebuttonExcludeIC8_Callback(hObject, eventdata, handles)
% hObject    handle to togglebuttonExcludeIC8 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of togglebuttonExcludeIC8


% --- Executes on button press in togglebuttonLockIC8.
function togglebuttonLockIC8_Callback(hObject, eventdata, handles)
% hObject    handle to togglebuttonLockIC8 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of togglebuttonLockIC8


% --- Executes on button press in togglebuttonExcludeIC7.
function togglebuttonExcludeIC7_Callback(hObject, eventdata, handles)
% hObject    handle to togglebuttonExcludeIC7 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of togglebuttonExcludeIC7


% --- Executes on button press in togglebuttonLockIC7.
function togglebuttonLockIC7_Callback(hObject, eventdata, handles)
% hObject    handle to togglebuttonLockIC7 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of togglebuttonLockIC7


% --- Executes on button press in togglebuttonExcludeIC6.
function togglebuttonExcludeIC6_Callback(hObject, eventdata, handles)
% hObject    handle to togglebuttonExcludeIC6 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of togglebuttonExcludeIC6


% --- Executes on button press in togglebuttonLockIC6.
function togglebuttonLockIC6_Callback(hObject, eventdata, handles)
% hObject    handle to togglebuttonLockIC6 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of togglebuttonLockIC6


% --- Executes on button press in togglebuttonExcludeIC5.
function togglebuttonExcludeIC5_Callback(hObject, eventdata, handles)
% hObject    handle to togglebuttonExcludeIC5 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
1;
% Hint: get(hObject,'Value') returns toggle state of togglebuttonExcludeIC5


% --- Executes on button press in togglebuttonLockIC5.
function togglebuttonLockIC5_Callback(hObject, eventdata, handles)
% hObject    handle to togglebuttonLockIC5 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of togglebuttonLockIC5


% --- Executes on button press in togglebuttonExcludeIC4.
function togglebuttonExcludeIC4_Callback(hObject, eventdata, handles)
% hObject    handle to togglebuttonExcludeIC4 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of togglebuttonExcludeIC4


% --- Executes on button press in togglebuttonLockIC4.
function togglebuttonLockIC4_Callback(hObject, eventdata, handles)
% hObject    handle to togglebuttonLockIC4 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of togglebuttonLockIC4


% --- Executes on button press in togglebuttonExcludeIC3.
function togglebuttonExcludeIC3_Callback(hObject, eventdata, handles)
% hObject    handle to togglebuttonExcludeIC3 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of togglebuttonExcludeIC3


% --- Executes on button press in togglebuttonLockIC3.
function togglebuttonLockIC3_Callback(hObject, eventdata, handles)
% hObject    handle to togglebuttonLockIC3 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of togglebuttonLockIC3


% --- Executes on button press in togglebuttonExcludeIC2.
function togglebuttonExcludeIC2_Callback(hObject, eventdata, handles)
% hObject    handle to togglebuttonExcludeIC2 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of togglebuttonExcludeIC2


% --- Executes on button press in togglebuttonLockIC2.
function togglebuttonLockIC2_Callback(hObject, eventdata, handles)
% hObject    handle to togglebuttonLockIC2 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of togglebuttonLockIC2


% --- Executes on mouse press over axes background.
function axesIC1_ButtonDownFcn(hObject, eventdata, handles)
% hObject    handle to axesIC1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
handles.curIC = handles.ics(1);
% Update handles structure
guidata(hObject, handles);


% --- Executes on mouse press over axes background.
function axesIC2_ButtonDownFcn(hObject, eventdata, handles)
% hObject    handle to axesIC2 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
handles.curIC = handles.ics(2);
% Update handles structure
guidata(hObject, handles);


% --- Executes on mouse press over axes background.
function axesIC3_ButtonDownFcn(hObject, eventdata, handles)
% hObject    handle to axesIC3 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
handles.curIC = handles.ics(3);
% Update handles structure
guidata(hObject, handles);


% --- Executes on mouse press over axes background.
function axesIC4_ButtonDownFcn(hObject, eventdata, handles)
% hObject    handle to axesIC4 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
handles.curIC = handles.ics(4);
% Update handles structure
guidata(hObject, handles);


% --- Executes on mouse press over axes background.
function axesIC5_ButtonDownFcn(hObject, eventdata, handles)
% hObject    handle to axesIC5 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
handles.curIC = handles.ics(5);
% Update handles structure
guidata(hObject, handles);


% --- Executes on mouse press over axes background.
function axesIC6_ButtonDownFcn(hObject, eventdata, handles)
% hObject    handle to axesIC6 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
handles.curIC = handles.ics(6);
% Update handles structure
guidata(hObject, handles);


% --- Executes on mouse press over axes background.
function axesIC7_ButtonDownFcn(hObject, eventdata, handles)
% hObject    handle to axesIC7 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
handles.curIC = handles.ics(7);
% Update handles structure
guidata(hObject, handles);


% --- Executes on mouse press over axes background.
function axesIC8_ButtonDownFcn(hObject, eventdata, handles)
% hObject    handle to axesIC8 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
handles.curIC = handles.ics(8);
% Update handles structure
guidata(hObject, handles);


% --- Executes on button press in pushbuttonPause.
function pushbuttonPause_Callback(hObject, eventdata, handles)
% hObject    handle to pushbuttonPause (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
if strcmpi(get(handles.pushbuttonPause,'string'),'Pause');
    set(handles.pushbuttonPause,'string','Resume');
    stop(handles.pauseTimers)
else
    set(handles.pushbuttonPause,'string','Pause');
    start(handles.pauseTimers);
end