function arch = loadCanonicalArchitecture()
% loadCanonicalArchitecture  Load the shared topology/tag manifest.
%
% The manifest is the phase-1 baseline freeze for both MATLAB and Python.
% Runtime behavior is unchanged; this only centralises architecture facts.

    manifest_path = fullfile(fileparts(mfilename('fullpath')), ...
        'canonical_architecture.json');

    if ~exist(manifest_path, 'file')
        error('loadCanonicalArchitecture:MissingFile', ...
            'Missing architecture manifest: %s', manifest_path);
    end

    arch = jsondecode(fileread(manifest_path));
end
