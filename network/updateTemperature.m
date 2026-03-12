function [Tgas, T_turb] = updateTemperature(params, Tgas, q, p_prev, p_now, T_turb_prev, cfg)
% updateTemperature  Lumped thermal model with Joule-Thomson cooling.
%
%   [Tgas, T_turb] = updateTemperature(params, Tgas, q, p_prev, p_now, T_turb_prev, cfg)
%
%   Physics:
%   Base:  Tgas += -alpha*(Tgas - T_ambient) + beta*(B*q)  [convection + advection]
%   JT:    Tgas += mu_JT * (p_now - p_prev)                [Joule-Thomson; Req 3]
%          mu_JT = cfg.T_jt_coeff (K/bar, typically -0.45)
%
%   Continuous noise (Req 3):
%   Turbulent thermal mixing: AR(1) per node representing enthalpy
%   fluctuations from turbulent eddies and pipe wall heat transfer.
%   Config: cfg.T_turb_corr in [0.80, 0.90]
%           cfg.T_turb_std  in [0.03, 0.10] K
%
%   Bounds (Req 3): temperature clamped to [250, 320] K

    alpha = 0.001;   % convective cooling rate
    beta  = 0.0002;  % advective heat transport coefficient
    T_amb = 285;     % K ambient (buried pipeline)

    %% Base thermal update
    Tgas = Tgas + (-alpha * (Tgas - T_amb) + beta * (params.B * q));

    %% Joule-Thomson cooling (Req 3): dT proportional to pressure drop
    if nargin >= 5 && ~isempty(p_prev)
        dp    = p_now - p_prev;
        dT_JT = cfg.T_jt_coeff * dp;    % negative coeff -> cooling on drop
        Tgas  = Tgas + dT_JT;
    end

    %% Turbulent thermal noise AR(1) per node (Req 3, Req 7, Req 8)
    if nargin >= 7 && ~isempty(T_turb_prev)
        a_T    = cfg.T_turb_corr;                    % [0.80, 0.90] from cfg
        sig    = cfg.T_turb_std * sqrt(1 - a_T^2);  % stationary std (Req 8)
        T_turb = a_T * T_turb_prev + sig * randn(params.nNodes, 1);
    else
        T_turb = zeros(params.nNodes, 1);
    end
    Tgas = Tgas + T_turb;

    %% Physical clamp [250, 320] K (Req 3, Req 12)
    Tgas = max(250, min(Tgas, 320));
end