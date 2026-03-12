function [rho, rho_comp_state] = updateDensity(p, Tgas, rho_comp_prev, cfg)
% updateDensity  Real-gas density using Peng-Robinson equation of state.
%
%   [rho, rho_comp_state] = updateDensity(p, Tgas, rho_comp_prev, cfg)
%
%   Peng-Robinson EOS:
%     P = RT/(V-b) - a(T)/(V(V+b) + b(V-b))
%
%   Solved for compressibility Z iteratively, then:
%     rho = P*M / (Z*R*T)
%
%   Gas composition drift (AR(1)) modifies effective Tc/Pc slightly,
%   representing CH4/C2H6 blend changes from different production wells.
%
%   Parameters from cfg:
%     cfg.pr_Tc, cfg.pr_Pc, cfg.pr_omega  (critical properties)
%     cfg.pr_M, cfg.pr_R                   (molar mass, gas constant)
%     cfg.rho_comp_corr, cfg.rho_comp_std  (composition drift)

    %% Gas composition drift AR(1)
    if nargin >= 4 && ~isempty(rho_comp_prev)
        a_rho = cfg.rho_comp_corr;
        sig   = cfg.rho_comp_std * sqrt(1 - a_rho^2);
        rho_comp_state = a_rho * rho_comp_prev + sig * randn();
    else
        rho_comp_state = 0;
    end

    %% Effective critical properties with composition drift
    Tc = cfg.pr_Tc * (1 + 0.02 * rho_comp_state);   % slight Tc shift
    Pc = cfg.pr_Pc * (1 + 0.01 * rho_comp_state);   % slight Pc shift
    omega = cfg.pr_omega;
    R = cfg.pr_R;
    M = cfg.pr_M;

    %% PR EOS coefficients
    kappa = 0.37464 + 1.54226*omega - 0.26992*omega^2;

    % Compute per node
    rho = zeros(size(p));
    for i = 1:numel(p)
        T_i = Tgas(i);
        P_i = p(i) * 1e5;   % convert bar -> Pa

        alpha = (1 + kappa*(1 - sqrt(T_i/Tc)))^2;
        a_pr  = 0.45724 * R^2 * Tc^2 / (Pc*1e5) * alpha;
        b_pr  = 0.07780 * R * Tc / (Pc*1e5);

        %% Solve cubic Z equation: Z^3 + c2*Z^2 + c1*Z + c0 = 0
        A_eos = a_pr * P_i / (R * T_i)^2;
        B_eos = b_pr * P_i / (R * T_i);

        c2 = B_eos - 1;
        c1 = A_eos - 3*B_eos^2 - 2*B_eos;
        c0 = -(A_eos*B_eos - B_eos^2 - B_eos^3);

        % Find real roots of cubic
        r  = roots([1, c2, c1, c0]);
        rr = real(r(abs(imag(r)) < 1e-6));
        rr = rr(rr > B_eos);   % Z must be > B

        if isempty(rr)
            Z = 1.0;   % fallback to ideal gas
        else
            Z = max(rr);   % gas phase: largest real root
        end

        %% Density from Z
        rho(i) = P_i * M / (Z * R * T_i);   % kg/m^3
    end

    %% Physical bounds [0.01, 150] kg/m^3
    rho = max(0.01, min(rho, 150));
end