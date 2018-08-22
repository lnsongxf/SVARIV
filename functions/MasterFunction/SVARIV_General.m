function [Plugin, InferenceMSW, Chol, RForm] = SVARIV_General(p,confidence, ydata, z, NWlags, norm, scale, horizons, savdir, columnnames, IRFselect, time, dataset_name, RForm)
% Implements standard and weak-IV robust SVAR-IV inference.
%-Syntax:
%       [Plugin, InferenceMSW, Chol] = SVARIV_Luigi(p,confidence, ydata, z, NWlags, norm, scale, horizons, savdir)
% -Inputs:
%       p:            Number of lags in the VAR model                                                    (1 times 1)                                          
%       confidence:   Value for the standard and weak-IV robust confidence set                           (1 times 1) 
%       ydata:        Endogenous variables from the VAR model                                            (T times n) 
%       z:            External instrumental variable                                                     (T times 1)
%       NWlags:       Newey-West lags                                                                    (1 times 1)
%       norm:         Variable used for normalization                                                    (1 times 1)
%       scale:        Scale of the shock                                                                 (1 times 1)
%       horizons:     Number of horizons for the Impulse Response Functions (IRFs) 
%                     (does not include the impact horizon 0)                                            (1 times 1)
%       savdir:       Directory where the figures generated will be saved                                (String)
%       columnnames:  Vector with the names for the endogenous variables, in the same order as ydata     (1 times n)
%       IRFselect:    Indices for the variables that the user wants separate IRF plots for               (1 times q)
%       time:         Time unit for the dataset (e.g. year, month, etc.)                                 (String)
%       RForm_user:   Structure containing the reduced form estimates (more details below).              (Structure)
%       dataset_name: The name of the dataset used for generating the figures (used in the output label) (String)
%
% -Output:
%       PLugin:       Structure containing standard plug-in inference
%       InferenceMSW: Structure containing the MSW weak-iv robust confidence interval
%       Chol:         Cholesky IRFs
%       RForm:        Structure containing the reduced form parameters
%
% Note: this function calls the functions MSWFunction, RForm_VAR, CovAhat_Sigmahat_Gamma and jbfill
%
% This version: August 14th, 2018
% Comment: We have tested this function on a Macbook Pro 
%         @2.4 GHz Intel Core i7 (8 GB 1600 MHz DDR3)
%         Running Matlab R2016b.
%         This script runs in about 10 seconds.
%
% Note: Note: By default the function estimates the reduced form, but you can
% provide your estimates with a RForm structure. For that, the user must
% provide the input structure RForm. The structure must contain the
% following variables, with the described dimensions:

%   RForm.n :         Number of variables
%   RForm.mu:         The VAR forecast errors                                                 (n times 1)
%   RForm.AL:         Least-squares estimator of the VAR coefficients                         (n times np)
%   RForm.Sigma:      Least-squares estimator of the VAR variance-covariance residuals matrix (n times n)
%   RForm.eta:        VAR model residuals                                                     (n times T)
%   RForm.X:          Matrix of VAR covariates                                                (T times np + 1)
%   RForm.Y:          VAR matrix of endogenous regressors                                     (T times n)
%   RForm.Gamma:      RForm.eta*SVARinp.Z(p+1:end,1)/(size(RForm.eta,2)); Used for the computation of impulse response.
%   RForm.externalIV: SVARinp.Z(p+1:end,1);



%% 1)

olddir = pwd; % Save user's dir in order to return to the user with the same dir

currentcd = mfilename('fullpath');

currentcd = extractBetween(currentcd, '' , '/SVARIV_General');

currentcd = currentcd{1};

cd(currentcd);

cd .. % Now we are back to the functions folder

cd .. % Now we are back to the SVARIV folder

main_d = pwd;

cd(main_d);   %the main dir is the SVARIV folder

disp('-');

disp('The SVARIV_General function reports standard and weak-IV robust confidence sets for IRFs estimated using the SVAR-IV approach described in MSW(18)');

disp('(created by Karel Mertens and Jose Luis Montiel Olea)')

disp('(output saved in the "Inference.MSW" structure)')

disp(strcat('The nominal confidence level is ',num2str(100*confidence),'%'))
 
disp('-')
 
disp('This version: August 2018')
 
disp('-')
 
disp('(We would like to thank Qifan Han and Jianing Zhai for excellent research assistance)')

% Definitions for the next sections

SVARinp.ydata = ydata;

SVARinp.Z = z;

SVARinp.n        = size(ydata,2); %number of columns(variables)

RForm.p          = p; %RForm_user.p is the number of lags in the model

%% 2) Least-squares, reduced-form estimation

addpath(strcat(main_d,'/functions/RForm'));

%a) Estimation of (AL, Sigma) and the reduced-form innovations
if (nargin == 13)

    % This essentially checks whether the user provided or not his RForm. If
    % the user didn't, then we calculate it. If the user did, we skip this section and
    % use his/her RForm.
    
    [RForm.mu, ...
     RForm.AL, ...
     RForm.Sigma,...
     RForm.eta,...
     RForm.X,...
     RForm.Y]        = RForm_VAR(SVARinp.ydata, p);

    %b) Estimation of Gammahat (n times 1)

    RForm.Gamma      = RForm.eta*SVARinp.Z(p+1:end,1)/(size(RForm.eta,2));   %sum(u*z)/T. Used for the computation of impulse response.
    %(We need to take the instrument starting at period (p+1), because
    %we there are no reduced-form errors for the first p entries of Y.)

    %c) Add initial conditions and the external IV to the RForm structure

    RForm.Y0         = SVARinp.ydata(1:p,:);

    RForm.externalIV = SVARinp.Z(p+1:end,1);

    RForm.n          = SVARinp.n;

elseif (nargin == 14)

    % We will use the user's RForm

else 

    % Error, not enough inputs.

end

%% 3) Estimation of the asymptotic variance of A,Gamma

% Definitions

n            = RForm.n; % Number of endogenous variables

T            = (size(RForm.eta,2)); % Number of observations (time periods)

d            = ((n^2)*p)+(n);     %This is the size of (vec(A)',Gamma')'

dall         = d+ (n*(n+1))/2;    %This is the size of (vec(A)',vec(Sigma), Gamma')'

%a) Covariance matrix for vec(A,Gammahat). Used
%to conduct frequentist inference about the IRFs. 
 
[RForm.WHatall,RForm.WHat,RForm.V] = ...
    CovAhat_Sigmahat_Gamma(p,RForm.X,SVARinp.Z(p+1:end,1),RForm.eta,NWlags);                
 
%NOTES:
%The matrix RForm.WHatall is the covariance matrix of 
% vec(Ahat)',vech(Sigmahat)',Gamma')'
 
%The matrix RForm.WHat is the covariance matrix of only
% vec(Ahat)',Gamma')' 
 
% The latter is all we need to conduct inference about the IRFs,
% but the former is needed to conduct inference about FEVDs.

%% 4) Compute standard and weak-IV robust confidence set suggested in MSW
 
 %Apply the MSW function
 
tic;
 
addpath(strcat(main_d,'/functions/Inference'));
 
[InferenceMSW,Plugin,Chol] = MSWfunction(confidence,norm,scale,horizons,RForm,1);

%% 5) Plot Results

addpath(strcat(main_d,'/functions/figuresfun'));
 
figure(1)
 
plots.order     = [1:SVARinp.n];
 
caux            = norminv(1-((1-confidence)/2),0,1);


 
for iplot = 1:SVARinp.n
        
    if SVARinp.n > ceil(sqrt(SVARinp.n)) * floor(sqrt(SVARinp.n))
            
        subplot(ceil(sqrt(SVARinp.n)),ceil(sqrt(SVARinp.n)),plots.order(1,iplot));
    
    else
        
        subplot(ceil(sqrt(SVARinp.n)),floor(sqrt(SVARinp.n)),plots.order(1,iplot));
        
    end
    
    plot(0:1:horizons,Plugin.IRF(iplot,:),'b'); hold on
    
    [~,~] = jbfill(0:1:horizons,InferenceMSW.MSWubound(iplot,:),...
        InferenceMSW.MSWlbound(iplot,:),[204/255 204/255 204/255],...
        [204/255 204/255 204/255],0,0.5); hold on
    
    dmub  =  Plugin.IRF(iplot,:) + (caux*Plugin.IRFstderror(iplot,:));
    
    lmub  =  Plugin.IRF(iplot,:) - (caux*Plugin.IRFstderror(iplot,:));
    
    h1 = plot(0:1:horizons,dmub,'--b'); hold on
    
    h2 = plot(0:1:horizons,lmub,'--b'); hold on
    
    clear dmub lmub
    
    h3 = plot([0 horizons],[0 0],'black'); hold off
    
    xlabel(time)
    
    title(columnnames(iplot));
    
    xlim([0 horizons]);

    if iplot == 1
        
        legend('SVAR-IV Estimator',strcat('MSW C.I (',num2str(100*confidence),'%)'),...
            'D-Method C.I.')
        
        set(get(get(h2,'Annotation'),'LegendInformation'),'IconDisplayStyle','off');
        
        set(get(get(h3,'Annotation'),'LegendInformation'),'IconDisplayStyle','off');
        
        legend boxoff
        
        legend('location','southeast')
     
    end
        
end

%% 6) Save the output and plots in ./Output/Mat and ./Output/Figs
 
%Check if the Output File exists, and if not create one.
 
if exist(savdir,'dir')==0
    
    mkdir('savdir')
        
end

mat = strcat(savdir,'/Mat');

if exist(mat,'dir')==0
    
    mkdir(mat)
        
end

figs = strcat(savdir, '/Figs'); 

if exist(figs,'dir')==0
    
    mkdir(figs)
        
end
 
cd(strcat(main_d,'/Output/Mat'));
 
output_label = strcat('_p=',num2str(p),'_',dataset_name,'_', ...
               num2str(100*confidence));
 
save(strcat('IRF_SVAR',output_label,'.mat'),...
     'InferenceMSW','Plugin','RForm','SVARinp');
 
figure(1)
 
cd(strcat(main_d,'/Output/Figs'));
 
print(gcf,'-depsc2',strcat('IRF_SVAR',output_label,'.eps'));
 
cd(main_d);
 
%clear plots output_label main_d labelstrs dtype

%cd(olddir);

%% 7) Select the Impulse Response Functions 

figure(2)
 
plots.order     = 1:length(IRFselect);
 
caux            = norminv(1-((1-confidence)/2),0,1);

for i = 1:length(IRFselect) 

    iplot = IRFselect(i);
    
    if length(IRFselect) > ceil(sqrt(length(IRFselect))) * floor(sqrt(length(IRFselect)))
            
        subplot(ceil(sqrt(length(IRFselect))),ceil(sqrt(length(IRFselect))),plots.order(1,i));
    
    else
        
        subplot(ceil(sqrt(length(IRFselect))),floor(sqrt(length(IRFselect))),plots.order(1,i));
        
    end
    
    plot(0:1:horizons,Plugin.IRF(iplot,:),'b'); hold on
    
    [~,~] = jbfill(0:1:horizons,InferenceMSW.MSWubound(iplot,:),...
        InferenceMSW.MSWlbound(iplot,:),[204/255 204/255 204/255],...
        [204/255 204/255 204/255],0,0.5); hold on
    
    dmub  =  Plugin.IRF(iplot,:) + (caux*Plugin.IRFstderror(iplot,:));
    
    lmub  =  Plugin.IRF(iplot,:) - (caux*Plugin.IRFstderror(iplot,:));
    
    h1 = plot(0:1:horizons,dmub,'--b'); hold on
    
    h2 = plot(0:1:horizons,lmub,'--b'); hold on
    
    clear dmub lmub
    
    h3 = plot([0 horizons],[0 0],'black'); hold off
    
    xlabel(time)
    
    title(columnnames(iplot));
    
    xlim([0 horizons]);
    
    if iplot == 1
        
        legend('SVAR-IV Estimator',strcat('MSW C.I (',num2str(100*confidence),'%)'),...
            'D-Method C.I.')
        
        set(get(get(h2,'Annotation'),'LegendInformation'),'IconDisplayStyle','off');
        
        set(get(get(h3,'Annotation'),'LegendInformation'),'IconDisplayStyle','off');
        
        legend boxoff
        
        legend('location','southeast')
     
    end
    
    
end

%% 8) Generating separate IRF plots and saving them to different folder
 
plots.order     = 1:length(IRFselect);
 
caux            = norminv(1-((1-confidence)/2),0,1);

for i = 1:length(IRFselect) 

    iplot = IRFselect(i);
    
    figure(3+i);
    
    plot(0:1:horizons,Plugin.IRF(iplot,:),'b'); hold on
    
    [~,~] = jbfill(0:1:horizons,InferenceMSW.MSWubound(iplot,:),...
        InferenceMSW.MSWlbound(iplot,:),[204/255 204/255 204/255],...
        [204/255 204/255 204/255],0,0.5); hold on
    
    dmub  =  Plugin.IRF(iplot,:) + (caux*Plugin.IRFstderror(iplot,:));
    
    lmub  =  Plugin.IRF(iplot,:) - (caux*Plugin.IRFstderror(iplot,:));
    
    h1 = plot(0:1:horizons,dmub,'--b'); hold on
    
    h2 = plot(0:1:horizons,lmub,'--b'); hold on
    
    clear dmub lmub
    
    h3 = plot([0 horizons],[0 0],'black'); hold off
    
    xlabel(time)
    
    title(columnnames(iplot));
    
    xlim([0 horizons]);
    
    legend('SVAR-IV Estimator',strcat('MSW C.I (',num2str(100*confidence),'%)'),...
            'D-Method C.I.')
        
    set(get(get(h2,'Annotation'),'LegendInformation'),'IconDisplayStyle','off');
        
    set(get(get(h3,'Annotation'),'LegendInformation'),'IconDisplayStyle','off');
        
    legend boxoff
        
    legend('location','southeast')
    
    %Check if the Output File exists, and if not create one.

    MatIRFselect = strcat(savdir, '/MatIRFselect');

    if exist(MatIRFselect,'dir')==0
    
        mkdir(MatIRFselect)
    
    end

    FigsIRFselect = strcat(savdir, '/FigsIRFselect');

    if exist(FigsIRFselect,'dir')==0
    
        mkdir(FigsIRFselect)
    
    end
 
    cd(strcat(main_d,'/Output/MatIRFselect'));
 
    output_label = strcat('_p=',num2str(p),'_',dataset_name,'_',...
                    num2str(100*confidence), '_', num2str(iplot));
 
    save(strcat('IRF_SVAR',output_label,'.mat'),...
        'InferenceMSW','Plugin','RForm','SVARinp');
 
    figure(3+i)
 
    cd(strcat(main_d,'/Output/FigsIRFselect'));
 
    print(gcf,'-depsc2',strcat('IRF_SVAR',output_label,'.eps'));
 
    cd(main_d);
    
    
end

clear plots output_label main_d labelstrs dtype

cd(olddir);


end