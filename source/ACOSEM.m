function x_acosem = ACOSEM(options)
%ACOSEM Accelerated Convergent OSEM.
%   Implements the ACOSEM reconstruction on input PET data.
%   See main_nongate.m for options-variables.
%
%   x_acosem = ACOSEM(options) returns the ACOSEM reconstructions for all
%   iterations, including the initial value.

if iscell(options.SinM)
    Sino = options.SinM{1};
    Sino = Sino(:);
else
    Sino = options.SinM;
    Sino = Sino(:);
end

LL = [];
index = [];
pituus = [];
lor = [];

if options.use_raw_data == false && options.subsets > 1
    if options.precompute_lor || options.reconstruction_method == 3
        load([options.machine_name '_lor_pixel_count_' num2str(options.Nx) 'x' num2str(options.Ny) 'x' num2str(options.Nz) '_sino_' num2str(options.Ndist) 'x' num2str(options.Nang) '.mat'],'lor','discard')
        if length(discard) ~= options.TotSinos*options.Nang*options.Ndist
            error('Error: Size mismatch between sinogram and LORs to be removed')
        end
        if options.use_raw_data == false && options.NSinos ~= options.TotSinos
            discard = discard(1:options.NSinos*options.Nang*options.Ndist);
        end
        ind_apu = uint32(find(discard));
        port = ceil((options.Nang-options.subsets+1)/options.subsets);
        over = options.Nang - port*options.subsets;
        index = cell(options.subsets,1);
        pituus = zeros(options.subsets, 1, 'uint32');
        for i=1:options.subsets
            if over>0
                index1 = uint32(sort(sub2ind([options.Nang options.Ndist options.NSinos],repmat(repelem(i:options.subsets:(port + 1)*options.subsets,options.Ndist)',options.NSinos,1),repmat((1:options.Ndist)',(port+1)*options.NSinos,1),repelem((1:options.NSinos)',options.Ndist*(port+1),1))));
                over = over - 1;
            else
                index1 = uint32(sort(sub2ind([options.Nang options.Ndist options.NSinos],repmat(repelem(i:options.subsets:port*options.subsets,options.Ndist)',options.NSinos,1),repmat((1:options.Ndist)',port*options.NSinos,1),repelem((1:options.NSinos)',options.Ndist*port,1))));
            end
            index{i} = index1(ismember(index1, ind_apu));
            pituus(i) = int32(length(index{i}));
        end
        index = cell2mat(index);
        index = index(ismember(index, ind_apu));
        clear index1 ind_apu
    else
        port = ceil((options.Nang-options.subsets+1)/options.subsets);
        over = options.Nang - port*options.subsets;
        index = cell(options.subsets,1);
        pituus = zeros(options.subsets, 1, 'uint32');
        for i=1:options.subsets
            if over>0
                index1 = uint32(sort(sub2ind([options.Nang options.Ndist options.NSinos],repmat(repelem(i:options.subsets:(port + 1)*options.subsets,options.Ndist)',options.NSinos,1),repmat((1:options.Ndist)',(port+1)*options.NSinos,1),repelem((1:options.NSinos)',options.Ndist*(port+1),1))));
                over = over - 1;
            else
                index1 = uint32(sort(sub2ind([options.Nang options.Ndist options.NSinos],repmat(repelem(i:options.subsets:port*options.subsets,options.Ndist)',options.NSinos,1),repmat((1:options.Ndist)',port*options.NSinos,1),repelem((1:options.NSinos)',options.Ndist*port,1))));
            end
            index{i} = uint32(index1);
            pituus(i) = int32(length(index1));
        end
        clear index1
    end
elseif options.subsets > 1
    % for raw list-mode data, take the options.subsets randomly
    % last subset has all the spare indices
    if options.precompute_lor || options.reconstruction_method == 3 || options.reconstruction_method == 2
        load([options.machine_name '_detector_locations_' num2str(options.Nx) 'x' num2str(options.Ny) 'x' num2str(options.Nz) '_raw.mat'],'LL','lor')
        indices = uint32(length(LL));
        index = cell(options.subsets, 1);
        port = uint32(floor(length(LL)/options.subsets));
        if options.use_Shuffle
            apu = Shuffle(indices(end), 'index')';
        else
            apu = uint32(randperm(indices(end)))';
        end
        pituus = zeros(options.subsets, 1, 'uint32');
        for i = 1 : options.subsets
            if i == options.subsets
                index{i} = apu(port*(i-1)+1:end);
            else
                index{i} = apu(port*(i-1)+1:(port*(i)));
            end
            pituus(i) = int32(length(index{i}));
        end
        clear apu
    else
        load([options.machine_name '_detector_locations_' num2str(Nx) 'x' num2str(Ny) 'x' num2str(Nz) '_raw.mat'],'LL')
        indices = uint32(length(LL));
        index = cell(options.subsets, 1);
        port = uint32(floor(length(LL)/options.subsets));
        if options.use_Shuffle
            apu = Shuffle(indices(end), 'index')';
        else
            apu = uint32(randperm(indices(end)))';
        end
        for i = 1 : options.subsets
            if i == options.subsets
                index{i} = apu(port*(i-1)+1:end);
            else
                index{i} = apu(port*(i-1)+1:(port*(i)));
            end
        end
        clear apu
    end
end

if options.precompute_lor && options.subsets > 1
    pituus2 = [0;cumsum(pituus)];
    Sino = Sino(index);
end

epps = options.epps;
N = options.Nx * options.Ny * options.Nz;

x_acosem = zeros(options.Nx,options.Ny,options.Nz, options.Niter + 1);
x_acosem(:,:,:,1) = options.x0;
x_acosem = reshape(x_acosem, options.Nx*options.Ny*options.Nz, options.Niter + 1);

pj = zeros(N,options.subsets);
C_aco = zeros(double(N), options.subsets);

for ll = 1 : options.subsets
    [A] = observation_matrix_formation_nongate(options, ll, index, LL, pituus, lor);
    pj(:,ll) = A'*ones(size(A,1),1,'double');
    if options.precompute_lor == false
        uu = double(Sino(index{ll}));
    else
        uu = double(Sino(pituus2(ll)+1:pituus2(ll + 1)));
    end
    if options.use_fsparse == false
        if options.precompute_lor == false
            C_aco(:,ll) = full(sum(spdiags(uu./(A*x_acosem(:,1)+epps),0,size(A,1),size(A,1))*(A.*(x_acosem(:,1)').^(1/options.h)))');
        else
            C_aco(:,ll) = full(sum(spdiags(uu./(A*x_acosem(:,1)+epps),0,size(A,1),size(A,1))*(A.*(x_acosem(:,1)').^(1/options.h)))');
        end
    else
        [I, ~, VV] = find((uu./(A*x_acosem(:,1)+epps)));
        if options.precompute_lor == false
            C_aco(:,ll) = full(sum(fsparse(I, I, VV, [size(A,1) size(A,1) length(VV)])*(A.*(x_acosem(:,1)').^(1/options.h)))');
        else
            C_aco(:,ll) = full(sum(fsparse(I, I, VV, [size(A,1) size(A,1) length(VV)])*(A.*(x_acosem(:,1)').^(1/options.h)))');
        end
    end
end
D = sum(pj,2);

for ii = 1 : options.Niter
    aco_apu = x_acosem(:,ii);
    for kk = 1 : options.subsets
        [A] = observation_matrix_formation_nongate(options, kk, index, LL, pituus, lor);
        
        if options.precompute_lor == false
            uu = double(Sino(index{kk}));
        else
            uu = double(Sino(pituus2(kk)+1:pituus2(kk + 1)));
        end
        tStart = tic;
        if options.use_fsparse
            [I, ~, VV] = find((uu./(A*aco_apu+epps)));
            if options.precompute_lor == false
                C_aco(:,kk) = full(sum(fsparse(I, I, VV, [size(A,1) size(A,1) length(VV)])*(A.*(aco_apu').^(1/options.h)))');
            else
                C_aco(:,kk) = full(sum(fsparse(I, I, VV, [size(A,1) size(A,1) length(VV)])*(A.*(aco_apu').^(1/options.h)))');
            end
        else
            if options.precompute_lor == false
                C_aco(:,kk) = full(sum(spdiags(uu./(A*aco_apu+epps),0,size(A,1),size(A,1))*(A.*(aco_apu').^(1/options.h)))');
            else
                C_aco(:,kk) = full(sum(spdiags(uu./(A*aco_apu+epps),0,size(A,1),size(A,1))*(A.*(aco_apu').^(1/options.h)))');
            end
        end
        apu = (sum(C_aco,2)./D).^options.h;
        aco_apu = (apu)*sum(uu)/sum(A*apu+epps);
        tElapsed = toc(tStart);
        disp(['ACOSEM sub-iteration ' num2str(kk) ' took ' num2str(tElapsed) ' seconds'])
        disp(['ACOSEM sub-iteration ' num2str(kk) ' finished'])
    end
    x_acosem(:,ii+1) = aco_apu;
end
x_acosem = reshape(x_acosem,options.Nx,options.Ny,options.Nz, options.Niter + 1);

end