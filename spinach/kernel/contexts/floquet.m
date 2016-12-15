% Floquet magic angle spinning context. Generates a Liouvillian super-
% operator and passes it on to the pulse sequence function, which sho-
% uld be supplied as a handle. Syntax:
%
%    answer=floquet(spin_system,pulse_sequence,parameters,assumptions)
%
% where pulse sequence is a function handle to one of the pulse sequences
% located in the experiments directory, assumptions is a string that would
% be passed to assume.m when the Hamiltonian is built and parameters is a
% structure with the following subfields:
%
%   parameters.rate     - spinning rate in Hz
%
%   parameters.axis     - spinning axis, given as a normalized
%                         3-element vector
%
%   parameters.spins    - a cell array giving the spins that 
%                         the pulse sequence involves, e.g. 
%                         {'1H','13C'}
%
%   parameters.offset   - a cell array giving transmitter off-
%                         sets in Hz on each of the spins listed
%                         in parameters.spins array
%
%   parameters.max_rank - maximum harmonic rank to retain in
%                         the solution (increase till conver-
%                         gence is achieved, approximately
%                         equal to the number of spinning si-
%                         debands in the spectrum)
%
%   parameters.grid     - spherical grid file name. See grids
%                         directory in the kernel.
%
% Additional subfields may be required by the pulse sequence. The parameters
% structure is passed to the pulse sequence with the following additional
% parameters set:
%
%   parameters.spc_dim  - matrix dimension for the spatial
%                         dynamics subspace
%
%   parameters.spn_dim  - matrix dimension for the spin 
%                         dynamics subspace
%
% This function returns the powder average of whatever it is that the pulse
% sequence returns.
%
% Note: the choice of the rank depends on the spinning rate (the slower
%       the spinning, the greater ranks are required). The rank is appro-
%       ximately equal to the number of spinning sidebands.
%
% Note: the state projector assumes a powder -- single crystal MAS is not
%       currently supported.
%
% luke.edwards@ucl.ac.uk
% i.kuprov@soton.ac.uk

function answer=floquet(spin_system,pulse_sequence,parameters,assumptions)

% Show the banner
banner(spin_system,'sequence_banner'); 

% Set common defaults
parameters=defaults(spin_system,parameters);

% Check consistency
grumble(spin_system,pulse_sequence,parameters,assumptions);

% Report to the user
report(spin_system,'building the Liouvillian...');

% Get the Hamiltonian
[H,Q]=hamiltonian(assume(spin_system,assumptions));

% Apply frequency offsets
H=frqoffset(spin_system,H,parameters);

% Get relaxation and kinetics
R=relaxation(spin_system); K=kinetics(spin_system);

% Get the averaging grid
sph_grid=load([spin_system.sys.root_dir '/kernel/grids/' parameters.grid '.mat']);

% Get problem dimensions
spc_dim=2*parameters.max_rank+1; spn_dim=size(H,1);
report(spin_system,['lab space problem dimension  ' num2str(spc_dim)]);
report(spin_system,['spin space problem dimension ' num2str(spn_dim)]);
report(spin_system,['Floquet problem dimension    ' num2str(spc_dim*spn_dim)]);
parameters.spc_dim=spc_dim; parameters.spn_dim=spn_dim;

% Build the MAS part of the Liouvillian
M=2*pi*parameters.rate*kron(spdiags((parameters.max_rank:-1:-parameters.max_rank)',0,spc_dim,spc_dim),speye(spn_dim));

% Kron up relaxation and kinetics
R=kron(speye(spc_dim),R); K=kron(speye(spc_dim),K);

% Get the rotor orientation
[phi,theta,~]=cart2sph(parameters.axis(1),parameters.axis(2),parameters.axis(3));
theta=pi/2-theta; D_rot2lab=euler2wigner(phi,theta,0); D_lab2rot=D_rot2lab';

% Project states
P=spalloc(spc_dim,1,1); P((spc_dim+1)/2)=1;
if isfield(parameters,'rho0')
    parameters.rho0=kron(P,parameters.rho0);
end
if isfield(parameters,'coil')
    parameters.coil=kron(P,parameters.coil);
end

% Store problem dimension information
parameters.spc_dim=spc_dim; parameters.spn_dim=spn_dim;

% Estimate nonzero count
nnz_est=sum(sum(cellfun(@nnz,Q)));

% Preallocate answer array
ans_array=cell(numel(sph_grid.weights),1);

% Shut up and inform the user
report(spin_system,['powder average being computed over ' num2str(numel(sph_grid.weights)) ' orientations.']);
if ~isfield(parameters,'verbose')||(parameters.verbose==0)
    report(spin_system,'pulse sequence has been silenced to avoid excessive output.');
    spin_system.sys.output='hush';
end

% Powder averaged spectrum
parfor q=1:numel(sph_grid.weights) %#ok<*PFBNS>

    % Set the crystal reference frame
    D_mol2rot=euler2wigner(sph_grid.alphas(q),sph_grid.betas(q),sph_grid.gammas(q))';
    
    % Move into rotor frame
    D_mol2rot=D_rot2lab*D_mol2rot*D_lab2rot;
    
    % Preallocate fourier terms
    fourier_terms=cell(5,1);
    
    % Get Fourier terms of the Hamiltonian
    for n=1:5
        fourier_terms{n}=spalloc(size(H,1),size(H,2),nnz_est);
        D_rotor=zeros(5,5); D_rotor(n,n)=1;
        D=D_rot2lab*D_rotor*D_lab2rot*D_mol2rot;
        for m=1:5
            for k=1:5
                fourier_terms{n}=fourier_terms{n}+Q{k,m}*D(k,m);
            end
        end
    end

    % Add the isotropic part
    fourier_terms{3}=fourier_terms{3}+H;
    
    % Kron up into the Floquet space
    F=spalloc(spc_dim*spn_dim,spc_dim*spn_dim,0);
    for n=1:5
        F=F+kron(spdiags(ones(spc_dim,1),n-3,spc_dim,spc_dim),fourier_terms{n});
    end
    
    % Add the MAS part and clean up
    F=clean_up(spin_system,F+M,spin_system.tols.liouv_zero);
    
    % Report to the user
    report(spin_system,'running the pulse sequence...');
    
    % Run the pulse sequence
    ans_array{q}=pulse_sequence(spin_system,parameters,F,R,K);

end

% Add up structures
answer=sph_grid.weights(1)*ans_array{1};
for n=2:numel(ans_array)
    answer=answer+sph_grid.weights(n)*ans_array{n};
end

end

% Default parameters
function parameters=defaults(spin_system,parameters)
if ~isfield(parameters,'decouple')
    report(spin_system,'parameters.decouple field not set, assuming no decoupling.');
    parameters.decouple={};
end
if ~isfield(parameters,'offset')
    report(spin_system,'parameters.offset field not set, assuming zero offsets.');
    parameters.offset=zeros(size(parameters.spins));
end
if ~isfield(parameters,'verbose')
    report(spin_system,'parameters.verbose field not set, silencing array operations.');
    parameters.verbose=0;
end
end

% Consistency enforcement
function grumble(spin_system,pulse_sequence,parameters,assumptions)

% Rotating frames
if isfield(parameters,'rframes')
    error('numerical rotating frame transformation is not supported by Floquet theory.');
end

% Formalism 
if ~ismember(spin_system.bas.formalism,{'zeeman-liouv','sphten-liouv'})
    error('this function is only available in Liouville space.');
end

% Assumptions
if ~ischar(assumptions)
    error('assumptions argument must be a character string.');
end

% Rotor rank
if ~isfield(parameters,'max_rank')
    error('parameters.max_rank subfield must be present.');
elseif (~isnumeric(parameters.max_rank))||(~isreal(parameters.max_rank))||...
       (mod(parameters.max_rank,1)~=0)||(parameters.max_rank<0)
    error('parameters.max_rank must be a positive real integer.');
end

% Spinning rate
if ~isfield(parameters,'rate')
    error('parameters.rate subfield must be present.');
elseif (~isnumeric(parameters.rate))||(~isreal(parameters.rate))
    error('parameters.rate must be a real number.');
end

% Spinning axis
if ~isfield(parameters,'axis')
    error('parameters.axis subfield must be present.');
elseif (~isnumeric(parameters.axis))||(~isreal(parameters.axis))||...
       (~isrow(parameters.axis))||(numel(parameters.axis)~=3)
    error('parameters.axis must be a row vector of three real numbers.');
end

% Spherical grid
if ~isfield(parameters,'grid')
    error('spherical averaging grid must be specified in parameters.grid variable.');
elseif isempty(parameters.grid)
    error('parameters.grid variable cannot be empty.');
elseif ~ischar(parameters.grid)
    error('parameters.grid variable must be a character string.');
elseif strcmp(parameters.grid,'single_crystal')
    error('this module does not support single crystal simulations, use singlerot() instead.');
end

% Active spins
if isempty(parameters.spins)
    error('parameters.spins variable cannot be empty.');
elseif ~iscell(parameters.spins)
    error('parameters.spins variable must be a cell array.');
elseif ~all(cellfun(@ischar,parameters.spins))
    error('all elements of parameters.spins cell array must be strings.');
elseif any(~ismember(parameters.spins,spin_system.comp.isotopes))
    error('parameters.spins refers to a spin that is not present in the system.');
end

% Offsets
if isempty(parameters.offset)
    error('parameters.offset variable cannot be empty.');
elseif ~isnumeric(parameters.offset)
    error('parameters.offset variable must be an array of real numbers.');
elseif ~isfield(parameters,'spins')
    error('parameters.spins variable must be specified alongside parameters.offset variable.');
elseif numel(parameters.offset)~=numel(parameters.spins)
    error('parameters.offset variable must have the same number of elements as parameters.spins.');
end

% Pulse sequence
if ~isa(pulse_sequence,'function_handle')
    error('pulse_sequence argument must be a function handle.');
end

end

% If you've got a good idea then go ahead and do it. It's always
% easier to ask forgiveness than it is to get permission.
%
% Rear Admiral Grace Hopper

