function ekf = updateEKF(ekf, plc_reg_p, plc_reg_q, p, q)
    y = [plc_reg_p; plc_reg_q];
    Ppred = ekf.P + ekf.Qn;
    K_ekf = Ppred*ekf.C'/(ekf.C*Ppred*ekf.C'+ekf.Rk);
    ekf.xhat = ekf.xhat + K_ekf*(y - ekf.C*ekf.xhat);
    ekf.P = (eye(ekf.nx)-K_ekf*ekf.C)*Ppred;
    ekf.xhatP = ekf.xhat(1:numel(p));
    ekf.xhatQ = ekf.xhat(numel(p)+1:end);
    ekf.residP = p - ekf.xhatP;
    ekf.residQ = q - ekf.xhatQ;
end
